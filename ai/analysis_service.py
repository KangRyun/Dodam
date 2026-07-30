"""종합 분석 오케스트레이션 — API_명세서_최종.md §19.3 요청 → §19.4 응답.

`POST /internal/v1/analyses`의 실제 처리부. 정본 명세가 규정한 '객체+시각+행동+대화 종합'
분석을 현재 보유한 자산(YOLO 객체탐지 · VLM 관찰 서술)으로 채우고,
**채우지 못한 부분은 지어내지 않고 unusedInputs/warnings로 명시한다.**

설계 원칙(§24.3 · CLAUDE.md 9절):
- 입력에 없는 아동 정보나 맥락을 추정하지 않는다.
- 검색 근거(RAG)가 없으면 근거 기반 문장을 만들지 않는다 — 지금은 RAG 미구현이므로
  evidenceReferences는 항상 빈 배열이고 그 사실을 unusedInputs에 남긴다.
- 필압 미지원·대화 없음 등 '못 쓴 입력'이 하나라도 있으면 status=PARTIAL_SUCCESS다(§11.4).
- 진단명·질환 확률·원인 단정은 만들지 않는다. 관찰 서술 프롬프트(ai/prompts/)가 1차 방어선이고,
  BE의 안전 필터(A13)가 2차 방어선이다.

가드레일:
- 아동 그림 bytes·signedUrl·아이 발화 원문은 로그에 남기지 않는다. 식별자와 오류 유형만.
"""

import hashlib
import logging
import tempfile
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

import httpx

import config
import htp_labels
import internal_contracts as contracts
import sketch_labels
import vlm_client
import yolo_client

logger = logging.getLogger(__name__)

# 관찰 초안에 반드시 붙는 한계 고지(§2.4 · CLAUDE.md 9절 "진단이 아니라 관찰 참고 자료").
DISCLAIMER = (
    "이 내용은 진단이 아니라 그림과 대화에서 관찰된 정보를 정리한 참고 자료입니다. "
    "개별 아동의 맥락은 전문가 검토가 필요합니다."
)

# 아이가 답변으로 낸 메시지 유형(§4 MessageType).
_ANSWER_TYPES = {"VOICE_ANSWER", "OPTION_ANSWER", "TEXT_ANSWER"}


class AnalysisInputError(RuntimeError):
    """그림을 가져오지 못했거나 무결성 검증에 실패했다 — 재시도해도 같은 입력이면 실패한다."""


class AnalysisUpstreamError(RuntimeError):
    """탐지·서술 등 상류 처리 실패 — 재시도 여지가 있다."""


# ── 그림 입력 ───────────────────────────────────────────────────
def _fetch_drawing(drawing: contracts.DrawingInput) -> bytes:
    """signedUrl에서 그림 bytes를 받아온다. 크기 상한과 checksum을 검증한다.

    reason: 만료·오배포된 URL이 다른 리소스를 가리킬 수 있으므로, BE가 checksum을 준 경우
    반드시 대조한다 — 다른 아이의 그림을 분석하는 사고를 원천 차단(가드레일).

    Raises:
        AnalysisInputError: 응답 오류·크기 초과·checksum 불일치.
    """
    try:
        with httpx.stream(
            "GET",
            drawing.signed_url,
            timeout=config.ANALYSIS_IMAGE_TIMEOUT_SEC,
            follow_redirects=True,
        ) as response:
            if response.status_code != 200:
                # ⚠️ URL 자체는 로그에 남기지 않는다(만료 전 접근 가능한 자격이므로).
                raise AnalysisInputError(
                    f"그림을 가져오지 못했어요(status={response.status_code})."
                )
            chunks: list[bytes] = []
            size = 0
            for chunk in response.iter_bytes():
                size += len(chunk)
                if size > config.ANALYSIS_IMAGE_MAX_BYTES:
                    raise AnalysisInputError("그림 크기가 허용 상한을 넘었어요.")
                chunks.append(chunk)
    except httpx.HTTPError as e:
        logger.error("그림 다운로드 실패: %s", type(e).__name__)
        raise AnalysisInputError("그림을 가져오지 못했어요(네트워크).") from e

    image_bytes = b"".join(chunks)
    if not image_bytes:
        raise AnalysisInputError("그림이 비어 있어요.")

    if drawing.checksum_sha256:
        actual = hashlib.sha256(image_bytes).hexdigest()
        expected = drawing.checksum_sha256.removeprefix("sha256-").strip().lower()
        if actual != expected:
            # 값 자체는 남겨도 개인정보가 아니지만, 어느 자산인지만 식별자로 남긴다.
            logger.error(
                "그림 checksum 불일치: drawingAssetId=%s", drawing.drawing_asset_id
            )
            raise AnalysisInputError("그림 무결성 검증에 실패했어요.")
    return image_bytes


# ── 시각 특징 ───────────────────────────────────────────────────
def _visual_features(
    image_bytes: bytes, detections: list
) -> tuple[dict[str, float | str | None], list[str]]:
    """이미지에서 '객관적 수치'만 계산한다(§11.3 visualFeatures).

    계산하는 것: 잉크 밀도 · 평균 밝기 · 평균 채도 · 탐지 객체의 화면 점유율.
    계산하지 않는 것: 선 굵기 — 획 벡터가 있어야 신뢰할 수 있어 이미지만으로는 추정하지 않는다.

    Returns:
        (특징 dict, 경고 코드 목록)
    """
    import cv2  # 지연 import — 서버 기동에는 필요 없다
    import numpy as np

    warnings: list[str] = []
    array = cv2.imdecode(np.frombuffer(image_bytes, dtype=np.uint8), cv2.IMREAD_COLOR)
    if array is None:
        raise AnalysisInputError("그림을 이미지로 해석하지 못했어요.")

    hsv = cv2.cvtColor(array, cv2.COLOR_BGR2HSV)
    saturation = hsv[:, :, 1]
    value = hsv[:, :, 2]

    # 잉크 밀도: 종이(밝고 채도 낮음)가 아닌 픽셀의 비율 — '얼마나 채워 그렸는지'.
    ink_mask = (value < 240) | (saturation > 25)
    ink_ratio = float(ink_mask.mean())

    # 화면 점유율: 탐지 박스 면적 합(겹침은 보정하지 않으므로 1.0으로 클램프).
    occupancy = sum(max(0.0, d.bbox_norm_xywh[2]) * max(0.0, d.bbox_norm_xywh[3]) for d in detections)
    occupancy_ratio = float(min(1.0, occupancy))
    if occupancy > 1.0:
        # 겹친 객체가 많다는 신호 — 값이 포화됐음을 숨기지 않는다.
        warnings.append("OCCUPANCY_RATIO_CLAMPED")

    features: dict[str, float | str | None] = {
        "inkRatio": round(ink_ratio, 4),
        "meanBrightness": round(float(value.mean()) / 255.0, 4),
        "meanSaturation": round(float(saturation.mean()) / 255.0, 4),
        "occupancyRatio": round(occupancy_ratio, 4),
        "imageWidth": int(array.shape[1]),
        "imageHeight": int(array.shape[0]),
        # 선 굵기는 추정하지 않는다 — null과 0은 의미가 다르다(§3.3).
        "strokeThickness": None,
    }
    return features, warnings


# ── 행동 특징 ───────────────────────────────────────────────────
def _behavior_features(
    behavior: contracts.BehaviorInput | None,
) -> tuple[dict[str, int | bool | None], list[contracts.UnusedInput], list[str]]:
    """BE가 집계해 넘긴 행동 요약을 그대로 특징으로 옮긴다.

    reason: 획 배치(strokeBatchUrls) 원본 해석은 아직 구현하지 않았다. 요약만 쓰고,
    필압 미지원처럼 '없는 데이터'는 0으로 채우지 않고 null + unusedInputs로 남긴다
    (§25 계약 테스트: pressureAvailable=false면 평균 필압은 null).
    """
    unused: list[contracts.UnusedInput] = []
    warnings: list[str] = []

    if behavior is None or behavior.summary is None:
        unused.append(
            contracts.UnusedInput(
                source_type="BEHAVIOR",
                reason_code="BEHAVIOR_SUMMARY_ABSENT",
                reason_detail="행동 요약이 요청에 없어 행동 특징을 만들지 못했습니다.",
                retryable=True,
            )
        )
        return {}, unused, warnings

    summary = behavior.summary
    features: dict[str, int | bool | None] = {
        "drawingDurationMs": summary.drawing_duration_ms,
        "activeDrawingMs": summary.active_drawing_ms,
        "pauseCount": summary.pause_count,
        "undoCount": summary.undo_count,
        "eraseCount": summary.erase_count,
        "toolChangeCount": summary.tool_change_count,
        "colorChangeCount": summary.color_change_count,
        "pressureAvailable": summary.pressure_available,
        # 필압 통계는 지원 기기에서만 만든다 — 미지원이면 null 고정.
        "pressureMean": None,
        "pressureMax": None,
    }

    if not summary.pressure_available:
        warnings.append("PRESSURE_DATA_UNAVAILABLE")
        unused.append(
            contracts.UnusedInput(
                source_type="PRESSURE",
                reason_code="DEVICE_NOT_SUPPORTED",
                reason_detail="입력 기기가 필압을 지원하지 않아 필압 통계를 만들지 않았습니다.",
                retryable=False,
            )
        )

    if behavior.stroke_batch_urls:
        # 받았지만 쓰지 않았다는 사실을 숨기지 않는다.
        warnings.append("STROKE_BATCH_NOT_ANALYZED")
        unused.append(
            contracts.UnusedInput(
                source_type="STROKE_BATCH",
                reason_code="NOT_IMPLEMENTED",
                reason_detail="획 단위 원본 해석은 아직 구현하지 않아 요약만 사용했습니다.",
                retryable=True,
            )
        )
    return features, unused, warnings


# ── 대화 요약 ───────────────────────────────────────────────────
def _conversation_summary(
    conversation: contracts.ConversationInput | None,
) -> tuple[
    contracts.AnalysisConversationSummary | None, list[contracts.UnusedInput], list[str]
]:
    """대화 메시지에서 '세는 것'만 만든다. AI 요약 문장은 만들지 않는다.

    reason: 정본 §11.3은 "실제 발화와 AI 요약을 구분"하도록 요구한다. 지금은 실제 발화
    대표값과 카운트만 신뢰할 수 있으므로 summaryText는 null로 두고 그 사실을 알린다 —
    빈 문자열로 채우면 '요약했는데 내용이 없다'로 오해된다(§3.3).
    """
    unused: list[contracts.UnusedInput] = []
    warnings: list[str] = []

    if conversation is None or not conversation.messages:
        unused.append(
            contracts.UnusedInput(
                source_type="CONVERSATION",
                reason_code="CONVERSATION_ABSENT",
                reason_detail="대화 기록이 없어 대화 요약을 만들지 못했습니다.",
                retryable=True,
            )
        )
        return None, unused, warnings

    messages = conversation.messages
    question_count = sum(1 for m in messages if m.message_type == "QUESTION")
    answers = [m for m in messages if m.message_type in _ANSWER_TYPES]
    response_count = len(answers)
    # 음성 답변인데 텍스트가 비었다 = STT가 내용을 확정하지 못했다는 뜻.
    unrecognized = sum(
        1 for m in answers if m.message_type == "VOICE_ANSWER" and not (m.text or "").strip()
    )
    representative = next(
        (m.text for m in reversed(answers) if (m.text or "").strip()), None
    )

    summary = contracts.AnalysisConversationSummary(
        summary_text=None,
        representative_utterance=representative,
        question_count=question_count,
        response_count=response_count,
        skipped_question_count=max(0, question_count - response_count),
        unrecognized_speech_count=unrecognized,
    )

    warnings.append("CONVERSATION_SUMMARY_NOT_GENERATED")
    unused.append(
        contracts.UnusedInput(
            source_type="CONVERSATION_SUMMARY",
            reason_code="NOT_IMPLEMENTED",
            reason_detail="대화 내용 요약문 생성은 아직 구현하지 않아 실제 발화와 횟수만 제공합니다.",
            retryable=True,
        )
    )
    if unrecognized:
        # 음성 내용을 추정하지 않는다(§11.4 예시).
        warnings.append("SPEECH_NOT_RECOGNIZED")
        unused.append(
            contracts.UnusedInput(
                source_type="SPEECH",
                reason_code="TRANSCRIPTION_EMPTY",
                reason_detail=f"음성 답변 {unrecognized}건의 내용을 확정하지 못해 추정하지 않았습니다.",
                retryable=True,
            )
        )
    return summary, unused, warnings


# ── 클래스 라벨 표 선택 ─────────────────────────────────────────
#   두 가중치는 클래스 집합이 완전히 다르다(HTP 한국어 47종 / 그림일기 영어 100종).
#   모델 Registry Key와 짝을 맞춰 각자의 표를 쓴다 — 한쪽 표로 양쪽을 조회하면
#   맞지 않는 쪽이 통째로 UNKNOWN이 된다(그림일기에서 실제로 그랬다, S15P11B209-711).
_LABELS_BY_MODEL = {"htp": htp_labels, "sketch": sketch_labels}


def _labels_for(model_key: str):
    """모델 Registry Key → 클래스 라벨 표 모듈."""
    try:
        return _LABELS_BY_MODEL[model_key]
    except KeyError:  # pragma: no cover - _model_key_for가 걸러 준다
        raise ValueError(f"알 수 없는 모델 키: {model_key!r}") from None


# ── 객체 탐지 변환 ──────────────────────────────────────────────
def _to_detected_objects(
    detections: list,
    labels,
) -> tuple[list[contracts.AnalysisDetectedObject], list[str]]:
    """yolo_client.Detection → §19.4 detectedObjects[].

    objectCode는 해당 모델의 계약 표를 그대로 쓴다 — 여기서 따로 매핑을 두면 두 표가
    갈라져 BE에 서로 다른 라벨이 저장된다.
    objectName은 내부 클래스명이 아니라 **표시명**이다. 이 값이 질문 LLM 프롬프트와
    보호자 리포트에 그대로 나가므로, '기둥'(TREE_TRUNK) 같은 내부 용어를 흘리면
    LLM이 다른 뜻으로 읽는다(S15P11B209-709 원인 2).
    UNKNOWN이 섞이면 가중치 클래스 집합과 표가 어긋났다는 신호라 경고로 드러낸다.
    """
    warnings: list[str] = []
    objects: list[contracts.AnalysisDetectedObject] = []
    for index, detection in enumerate(detections):
        spec = labels.spec_of(detection.label)
        if (
            spec.contract_label == labels.UNKNOWN_LABEL
            and "OBJECT_CODE_UNMAPPED" not in warnings
        ):
            warnings.append("OBJECT_CODE_UNMAPPED")
        x, y, width, height = detection.bbox_norm_xywh
        objects.append(
            contracts.AnalysisDetectedObject(
                object_code=spec.contract_label,
                object_name=spec.display_name,
                confidence=detection.confidence,
                bounding_box=contracts.BoundingBox(x=x, y=y, width=width, height=height),
                area_ratio=round(max(0.0, width) * max(0.0, height), 6),
                detection_order=index + 1,
            )
        )
    return objects, warnings


# ── 진입점 ──────────────────────────────────────────────────────
def _model_key_for(activity_type: contracts.ActivityType) -> str:
    """확정된 활동 유형을 YOLO 모델 Registry Key로 변환한다."""
    return {"HTP": "htp", "ART_DIARY": "sketch"}[activity_type]


def _format_detections_for_log(detections: list) -> str:
    """탐지 목록을 로그 한 줄로 만든다(S15P11B209-710).

    상세 로그가 꺼져 있으면 개수만 남긴다 — 라벨은 아동 그림 내용을 서술하므로
    운영 기본값에서는 남기지 않는다(가드레일). bbox·이미지는 어느 모드에서도 남기지 않는다.
    """
    if not detections:
        return "(없음)"
    if not config.DETECTION_LOG_DETAIL:
        return f"{len(detections)}건"
    return " ".join(f"{d.label}({d.confidence:.2f})" for d in detections)


# ── 탐지 Metadata 로그 (S15P11B209-610) ─────────────────────────
# 710(사람용 콘솔 한 줄)과 별개로, 611(로그 TTL·집계·피드백, MongoDB 문서+TTL 인덱스)이
# 그대로 import해 저장할 구조화 레코드를 emit한다. 스키마 정본은 contracts.DetectionMetadataLog
# (pydantic), emit은 model_dump_json() 한 줄. 마커로 로그 파이프라인이 이 줄만 골라낸다.
DETECTION_META_MARKER = "[DETECTION_META]"
_KST = timezone(timedelta(hours=9))  # 발생 시각 timezone(한국, S15P11B209-736 KST 통일)


def _detection_metadata(
    req: contracts.AnalysisRequest,
    detected_objects: list,
    model_info: contracts.ModelInfo,
    warnings: list[str],
    processing_time_ms: int,
    occurred_at: str,
) -> contracts.DetectionMetadataLog:
    """객체 탐지 결과를 611이 소비할 구조화 메타데이터 모델로 만든다.

    - TTL: occurred_at(timezone 명시 ISO8601)이 MongoDB TTL 인덱스 기준이 된다.
    - 집계: class_counts·detection_count·object_detection·activity_type·drawing_subject.
    - 피드백 연결: analysis_id(+object_code·detection_order)로 사용자 피드백을 조인한다.
    아동 그림 내용(object_name 표시명·bbox 좌표·이미지)은 담지 않는다(코드·수치만).
    """
    class_counts: dict[str, int] = {}
    objects: list[contracts.DetectionMetadataObject] = []
    for o in detected_objects:
        class_counts[o.object_code] = class_counts.get(o.object_code, 0) + 1
        objects.append(
            contracts.DetectionMetadataObject(
                object_code=o.object_code,
                confidence=round(o.confidence, 4),
                area_ratio=o.area_ratio,
                detection_order=o.detection_order,
            )
        )
    return contracts.DetectionMetadataLog(
        occurred_at=occurred_at,
        analysis_id=req.analysis_id,
        drawing_session_id=req.drawing_session_id,
        activity_type=req.activity_type,
        drawing_subject=req.drawing_subject,
        object_detection=model_info.object_detection,
        image_width=req.drawing.width,
        image_height=req.drawing.height,
        detection_count=len(detected_objects),
        class_counts=class_counts,
        objects=objects,
        warnings=list(warnings),
        processing_time_ms=processing_time_ms,
    )


def _filter_detections_for_activity(
    activity_type: contracts.ActivityType,
    drawing_subject: contracts.DrawingSubject | None,
    detections: list,
    warnings: list[str],
) -> list:
    """HTP 단계 주제에 맞게 탐지를 제한하고 기대 주제 미탐지를 표시한다."""
    if activity_type == "ART_DIARY":
        return detections
    if drawing_subject is None:
        raise ValueError("HTP analysis requires drawingSubject")

    kept = htp_labels.suppress_for_subject(detections, drawing_subject)
    if len(kept) != len(detections):
        warnings.append("CROSS_SUBJECT_PARTS_SUPPRESSED")
    summary = htp_labels.summarize(kept)
    group = summary.groups.get(drawing_subject)
    if group is None or not group.whole_detected:
        warnings.append("HTP_SUBJECT_NOT_DETECTED")
    return kept


def _detect_or_degrade(
    image_path: str,
    image_bytes: bytes,
    warnings: list[str],
    analysis_id: str = "",
    *,
    model_key: str,
) -> tuple[list, bytes]:
    """객체 탐지를 시도하되 실패하면 탐지 없이 진행할 수 있게 degrade한다(S15P11B209-604).

    reason: 가중치 부재·무결성 실패·추론 오류로 탐지가 죽어도 관찰 서술·행동·대화 요약은 낼 수
    있다. 전체 분석을 502로 버리는 대신 탐지만 비우고 원본 이미지로 이어간다. 못 채운 부분은
    지어내지 않고 OBJECT_DETECTION_UNAVAILABLE로 명시한다(모듈 철학). 서버의 구성요소 준비 상태는
    /internal/v1/health의 objectDetection=NOT_READY로 따로 드러난다.

    Returns:
        (탐지 목록, VLM 서술에 쓸 이미지 bytes). 실패 시 ([], 원본 image_bytes).
    """
    try:
        return yolo_client.detect_and_annotate(image_path, model_key=model_key)
    except RuntimeError as error:
        logger.error(
            "객체 탐지 실패 — 탐지 없이 진행(fallback): analysisId=%s type=%s",
            analysis_id,
            type(error).__name__,
        )
        warnings.append("OBJECT_DETECTION_UNAVAILABLE")
        return [], image_bytes


def analyze(req: contracts.AnalysisRequest, request_id: str = "") -> contracts.AnalysisResponse:
    """§19.3 요청 → §19.4 응답.

    Raises:
        AnalysisInputError: 그림을 못 가져왔거나 무결성 검증 실패(422로 매핑).
        AnalysisUpstreamError: 관찰 서술(VLM) 실패(502로 매핑).

    객체 탐지 실패는 502가 아니라 탐지 없이 진행하는 fallback으로 처리한다
    (OBJECT_DETECTION_UNAVAILABLE 경고, S15P11B209-604).
    """
    started = time.monotonic()
    unused: list[contracts.UnusedInput] = []
    warnings: list[str] = []

    image_bytes = _fetch_drawing(req.drawing)
    model_key = _model_key_for(req.activity_type)

    # YOLO는 파일 경로를 받는다 — 임시 파일은 블록을 벗어나면 삭제된다(원본 잔존 방지).
    suffix = ".png" if "png" in (req.drawing.mime_type or "") else ".jpg"
    with tempfile.NamedTemporaryFile(suffix=suffix) as temp:
        temp.write(image_bytes)
        temp.flush()
        detections, annotated_png = _detect_or_degrade(
            temp.name,
            image_bytes,
            warnings,
            req.analysis_id,
            model_key=model_key,
        )

    # 필터 '전' 원시 탐지 — 주제 필터가 무엇을 지웠는지 판별하려면 이 줄이 있어야 한다.
    logger.info(
        "[탐지] analysisId=%s activity=%s subject=%s model=%s raw=%d | %s",
        req.analysis_id,
        req.activity_type,
        req.drawing_subject or "-",
        model_key,
        len(detections),
        _format_detections_for_log(detections),
    )

    # HTP 단계 주제는 영속화된 확정값이다. 전체 객체가 미탐지여도 다른 HTP 그룹은 제거한다.
    raw_count = len(detections)
    warnings_before = len(warnings)
    detections = _filter_detections_for_activity(
        req.activity_type, req.drawing_subject, detections, warnings
    )
    # 필터 '후' — 남은 목록과 이번 필터가 새로 붙인 경고만 보여준다.
    # SCENERY는 의도적으로 남으므로(집 그림의 배경 나무 등) 여기서 그 사실이 드러난다.
    logger.info(
        "[필터] analysisId=%s kept=%d/%d removed=%d warnings=%s | %s",
        req.analysis_id,
        len(detections),
        raw_count,
        raw_count - len(detections),
        warnings[warnings_before:] or "-",
        _format_detections_for_log(detections),
    )

    labels = _labels_for(model_key)
    detected_objects, detection_warnings = _to_detected_objects(detections, labels)
    warnings.extend(detection_warnings)

    visual_features, visual_warnings = _visual_features(image_bytes, detections)
    warnings.extend(visual_warnings)

    behavior_features, behavior_unused, behavior_warnings = _behavior_features(req.behavior)
    unused.extend(behavior_unused)
    warnings.extend(behavior_warnings)

    conversation_summary, conversation_unused, conversation_warnings = _conversation_summary(
        req.conversation
    )
    unused.extend(conversation_unused)
    warnings.extend(conversation_warnings)

    # 관찰 서술: 프롬프트(ai/prompts/drawing_description.txt)가 진단형 표현을 막는 1차 방어선.
    # ⚠️ 주석 이미지는 억제 '전' 박스로 그려져 있다(yolo_client가 탐지와 함께 만든 것).
    #    탐지 목록은 억제 후를 넘기므로 텍스트 근거는 정확하지만, 이미지에는 억제된 박스가
    #    남아 서술에 섞일 수 있다 — CROSS_SUBJECT_PARTS_SUPPRESSED 경고로 드러낸다.
    #    억제 후 재렌더링은 추론을 한 번 더 돌려야 해서 후속 과제로 둔다.
    try:
        description = vlm_client.describe(
            annotated_png, detections, display_name_of=labels.display_name_of
        )
    except RuntimeError as e:
        logger.error(
            "그림 서술 실패: analysisId=%s type=%s", req.analysis_id, type(e).__name__
        )
        raise AnalysisUpstreamError("그림 서술에 실패했어요.") from e

    observation_draft = contracts.AnalysisObservationDraft(
        status="AI_DRAFT",
        overall_summary=description or None,
        observations=[],
        follow_up_questions=[],
        expert_review_required=True,
        disclaimer=DISCLAIMER,
    )

    # RAG 미구현 — 근거 없는 문장을 만들지 않고 '못 했음'만 남긴다(§24.3).
    warnings.append("RAG_NOT_CONFIGURED")
    unused.append(
        contracts.UnusedInput(
            source_type="RAG",
            reason_code="NOT_IMPLEMENTED",
            reason_detail="문헌 검색 파이프라인이 없어 근거를 연결하지 않았습니다.",
            retryable=True,
        )
    )

    # 아이가 고른 감정은 '입력'으로 받아두되 해석하지 않는다 — 해석은 전문가·보호자 몫.
    if req.reflection is None or not req.reflection.selected_emotions:
        unused.append(
            contracts.UnusedInput(
                source_type="REFLECTION",
                reason_code="REFLECTION_ABSENT",
                reason_detail="아이가 선택한 감정이 없어 활동 마무리 정보를 반영하지 못했습니다.",
                retryable=True,
            )
        )

    model_info = contracts.ModelInfo(
        object_detection=contracts.ModelRef(
            name=f"yolo-{model_key}",
            version=Path(
                config.YOLO_MODEL_PATH
                if model_key == "htp"
                else config.SKETCH_MODEL_PATH
            ).name,
        ),
        # GMS 모델은 빌드 버전을 노출하지 않으므로 파이프라인 버전을 기록해 재현 가능하게 한다.
        vision=contracts.ModelRef(name=config.VLM_MODEL, version=config.PIPELINE_VERSION),
        language=None,
        knowledge_base_version=config.RAG_KNOWLEDGE_BASE_VERSION or None,
    )

    elapsed_ms = int((time.monotonic() - started) * 1000)

    logger.info(
        "종합 분석 완료: analysisId=%s objects=%d unused=%d requestId=%s",
        req.analysis_id,
        len(detected_objects),
        len(unused),
        request_id or "-",
    )
    # 구조화 탐지 메타데이터(S15P11B209-610) — 611이 MongoDB 문서로 저장·집계·TTL한다.
    # 마커로 로그 파이프라인이 이 줄만 골라낸다. occurredAt이 TTL 인덱스 기준(KST ISO8601).
    logger.info(
        "%s %s",
        DETECTION_META_MARKER,
        _detection_metadata(
            req,
            detected_objects,
            model_info,
            warnings,
            elapsed_ms,
            datetime.now(_KST).isoformat(),
        ).model_dump_json(by_alias=True),
    )

    return contracts.AnalysisResponse(
        analysis_id=req.analysis_id,
        # 못 쓴 입력이 하나라도 있으면 완전 성공이라고 말하지 않는다(§11.4).
        status="PARTIAL_SUCCESS" if unused else "SUCCESS",
        model_info=model_info,
        detected_objects=detected_objects,
        visual_features=visual_features,
        behavior_features=behavior_features,
        conversation_summary=conversation_summary,
        observation_draft=observation_draft,
        evidence_references=[],
        unused_inputs=unused,
        warnings=warnings,
        processing_time_ms=elapsed_ms,
    )

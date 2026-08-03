"""GMS 관찰 리포트 생성 클라이언트 — 활동 집계·감정·대표 발화 → 보호자용 관찰 초안.

BE 계약(report.dto.ObservationGenerationRequest → ObservationGenerationResult)에 맞춰
최종 분석 요청을 받아 관찰 리포트 결과를 만든다. 실제 소비자는 BE AiObservationClient이며,
지금은 MockAiObservationClient가 고정 fixture를 쓴다 — HTTP 배선은 후속 이슈.

역할 분담:
- LLM(GMS)이 생성하는 것: 정성적 관찰 문구(요약·긍정신호·주의점·근거·안내·후속질문·특징·대화요약·안내·질문).
- 서버가 고정으로 채우는 것: status(AI_DRAFT)·disclaimer·limitations(안전 문구는 LLM에 맡기지 않는다)·
  model 정보·request_id 에코·emotion_source(요청에서 결정)·representative_utterance 에코.

가드레일:
- 진단·점수화 금지는 프롬프트가 강제하고, 안전 문구(disclaimer/limitations)는 코드가 상수로 보장한다.
- 대표 발화·표현 감정 등 아이 표현은 로그로 남기지 않는다(실패 로그에 에러 유형만).
- RAG 근거(S15P11B209-614): 배포된 인덱스에서 관찰 어휘·일반 지식을 검색해 프롬프트 보조
  근거로 싣고, 출처(ragReferences)와 KB Version을 응답에 기록한다. 검색 실패는 차단이
  아니라 기능 저하 — RAG 없이 생성한다(정책: docs/ai/rag-corpus-policy.md).
  ⚠️ RAG는 HTP 리포트에서만 검색한다. 그림일기 프롬프트는 [전문 자료 근거]를 근거 목록에
  두지 않으므로 검색해도 쓰이지 않는다 — RAG_NOT_APPLICABLE로 표시하고 건너뛴다.

프롬프트 구성: 활동 변형(report_htp | report_diary) + 공통(report_common)을 이어붙인다.
활동 판별은 subject_summaries[].drawing_subject 유무로 추론한다(계약에 activityType 없음).

형식 지표(S15P11B209-836): 그리기 소요시간·멈춤·지우기 등은 요청의 behaviorMetrics 로 들어온다.
계약 확장 전에는 전달 수단이 없어 [형식적 분석] 블록이 운영 경로에서 한 번도 실리지 않았다 —
프롬프트는 그 블록을 전제로 쓰여 있는데 데이터가 도착하지 않던 상태였다.
"""

from __future__ import annotations

import json
import logging

from openai import OpenAIError
from prometheus_client import Counter as PrometheusCounter

import config
import internal_contracts as contracts
import prompts_registry  # 프롬프트 파일 로딩·버전 관리 중앙화 (S15P11B209-595)
import report_safety
from gms import get_client
from rag import Chunk, RagUnavailableError, retrieve
from rag import knowledge_base_version as rag_knowledge_base_version

logger = logging.getLogger(__name__)

# ── 활동 유형별 리포트 프롬프트 ─────────────────────────────────
# 하나의 report.txt로 두 활동을 처리하던 것을 갈랐다. 근거 블록 구성이 다르기 때문이다:
#   - HTP: 주제별 [집 그림 관찰]·[집 그림 문답] … + [전문 자료 근거](RAG)
#   - 그림일기: 단일 [그림 관찰](740) 또는 [그림 관찰 서술](레거시 draft 인자). RAG 없음.
# 구 report.txt는 근거 화이트리스트가 "[그림 관찰 서술]·[형식적 분석]·[활동 데이터]만"이라
# 실제로 주입되는 주제별 블록·RAG 블록이 목록에서 빠져 있었다 — 뒤쪽 상세 설명과 정면 모순이라
# 모델이 화이트리스트를 곧이곧대로 읽으면 RAG 근거와 그림 내용을 통째로 버린다.
# 공통 규칙·JSON 스키마는 report_common이 소유하고, 변형 파일 뒤에 이어붙인다
# (JSON 중괄호 때문에 str.format 을 쓸 수 없어 문자열 연결로 조립한다).
_REPORT_COMMON = "report_common"
_REPORT_HTP = "report_htp"
_REPORT_DIARY = "report_diary"

# 활동 변형별 조합 — 라벨은 저장 태그에 그대로 실리는 고정 어휘다(S15P11B209-819).
_COMBOS: dict[str, tuple[str, ...]] = {
    "htp": (_REPORT_COMMON, _REPORT_HTP),
    "diary": (_REPORT_COMMON, _REPORT_DIARY),
}

# 두 변형과 공통부를 함께 담은 통합 버전 — 어떤 파일 조합으로 생성됐는지 한 문자열로 남긴다.
PROMPT_VERSION = prompts_registry.short_version(
    "report-all", _REPORT_COMMON, _REPORT_HTP, _REPORT_DIARY
)


def version_manifest() -> dict[str, str]:
    """축약 태그 → 정본 조합 버전. 저장된 다이제스트를 되짚는 수단이다(S15P11B209-819).

    저장 값은 포인터라, 이 매핑이 로그·버전 엔드포인트로 노출돼야 재현성이 유지된다.
    """
    return {
        prompts_registry.short_version(label, *names): prompts_registry.composite_version(
            *names
        )
        for label, names in _COMBOS.items()
    }

# 그림일기에는 RAG 근거를 싣지 않는다(결정: HTP 전용). 코퍼스는 활동유형 중립이지만,
# 전문 자료 인용이 필요한 쪽은 '검사처럼 읽히기 쉬운' HTP 리포트다 — 거기서만 관찰 어휘를
# 보조받고, 가벼운 그림일기 리포트는 활동 데이터만으로 담백하게 쓴다.
RAG_NOT_APPLICABLE = "RAG_NOT_APPLICABLE"

# 안전 문구는 LLM이 빠뜨리거나 바꾸면 안 되는 필수 고지 — 서버가 상수로 보장한다.
# (BE MockAiObservationClient와 동일 문구를 써서 두 구현의 고지가 일관되게.)
DISCLAIMER = (
    "본 결과는 아동 발달 진단이 아니라 그림 활동 관찰 기록입니다. "
    "우려되는 점이 있으면 전문가와 상담하세요."
)
LIMITATIONS = (
    "본 리포트는 제한된 활동 데이터를 바탕으로 한 관찰 기록이며, "
    "아동의 발달 상태를 단정하지 않습니다."
)
# 대표 발화가 비어 있을 때의 중립 기본값(진단·해석 없는 무난한 문장).
DEFAULT_UTTERANCE = "재미있었어요."

# 후속 질문이 비었거나 진단성 표현이 섞였을 때 대체할 안전 기본값(S15P11B209-601).
# 보호자가 아이에게 그대로 건네도 무해한, 진단이 아닌 '집에서 나눌 대화'용 질문.
DEFAULT_FOLLOW_UP_QUESTION = "오늘 그림에서 어떤 부분이 제일 마음에 들었어?"

_VALID_SCOPES = {"EXPERT_ONLY", "REVIEWED_GUARDIAN"}


def _load(name: str) -> str:
    """프롬프트 로딩은 prompts_registry로 중앙화했다(S15P11B209-595)."""
    return prompts_registry.load(name)


def _is_htp(req: contracts.ObservationGenerationRequest) -> bool:
    """이 요청이 HTP 활동인지 판별한다.

    계약(ObservationGenerationRequest)에 activityType 필드가 없어 subject_summaries로 추론한다 —
    HTP는 drawingSubject가 반드시 채워지고(AnalysisRequest·QuestionRequest와 같은 검증 규칙),
    그림일기는 None, 구 BE(subject_summaries 미전달)는 빈 목록이다. 뒤의 둘은 모두
    '단일 그림 + RAG 없음' 경로라 그림일기 프롬프트가 그대로 맞는다.
    """
    return any(s.drawing_subject is not None for s in req.subject_summaries)


def _prompt_names(is_htp: bool) -> tuple[str, str]:
    """이번 생성이 쓰는 (변형 프롬프트, 공통 프롬프트) 이름."""
    return (_REPORT_HTP if is_htp else _REPORT_DIARY), _REPORT_COMMON


def _system_prompt(is_htp: bool) -> str:
    """리포트 지침 system 프롬프트 — 활동 변형 + 공통 규칙을 이어붙인다.

    변형이 앞(역할·근거 화이트리스트·블록 사용법), 공통이 뒤(사실/해석 분리·작성 규칙·
    출력 JSON 스키마)다. 출력 형식을 맨 끝에 두어야 모델이 형식을 놓치지 않는다.

    ⚠️ 공용 guardrails.txt(대화용)는 append 하지 않는다 — 그 파일은 "정서를 진단·해석하지 마"를
    전제로 한 대화 응답용이라, 리포트의 '요소별 감정 해석' 지침과 충돌한다. 리포트의 안전 기준
    (장애명·진단명·점수·낙인 금지, 과도한 부정 금지, 걱정 신호는 attentionPoints로만)은
    report_common.txt가 자체적으로 담는다.
    JSON 스키마 중괄호 때문에 str.format 을 쓰지 않고 문자열을 그대로 이어붙인다.
    """
    variant, common = _prompt_names(is_htp)
    return f"{_load(variant)}\n\n{_load(common)}"


def _emotion_source(req: contracts.ObservationGenerationRequest) -> str:
    """표현 감정의 출처를 요청 값으로 결정한다(LLM이 아니라 규칙 기반).

    선택 감정 카드가 있으면 SELECTED, 말로 표현했으면 STATED, 둘 다 없으면 INFERRED.
    """
    if req.selected_emotions:
        return "SELECTED"
    if req.expressed_emotion_text and req.expressed_emotion_text.strip():
        return "STATED"
    return "INFERRED"


def _fmt_minutes(ms: int | None) -> str | None:
    """밀리초를 '약 N분' 문구로. None이면 None.

    분 단위로 반올림한다 — 0.1분(6초) 자리까지 적으면 집계가 갖지 않은 정밀도를
    관찰 사실처럼 보이게 한다(구 구현의 "약 10.0분"). 1분 미만은 반올림하면 "약 0분"이 되어
    아예 안 그린 것처럼 읽히므로 따로 적는다.
    """
    if ms is None:
        return None
    if ms < 60_000:
        return "1분 미만"
    return f"약 {round(ms / 60000)}분"


# 블록 머리에 붙는 '이 수치가 무엇의 값인가' 단서 (S15P11B209-838).
#   HTP는 BE가 집·나무·사람 세 단계를 합산해 보낸다 — 한 장 기준으로 읽히면 안 된다.
#   truncated는 배치 상한에 걸려 세션 앞부분만 집계한 값이라 활동 전체로 읽히면 안 된다.
_SCOPE_NOTE_HTP = "집·나무·사람 세 장을 합친 활동 전체 기준"
_SCOPE_NOTE_TRUNCATED = "저장된 캔버스 입력 구간까지만 집계 — 활동 전체가 아닐 수 있어요"


def _format_behavior(
    behavior: contracts.BehaviorMetrics | None, *, is_htp: bool = False
) -> str:
    """형식적 분석 지표를 프롬프트 [형식적 분석] 블록으로. 없으면 빈 문자열.

    None인 항목은 줄 자체를 넣지 않는다 — 0("0번")과 구분하기 위해서다. 집계하지 못한 값을
    0으로 적으면 "멈춤 없이 그렸다"는 관찰 사실로 읽힌다(BE StrokeBehaviorSummary 와 같은 원칙).

    필압은 강약 값(average_pressure)이 있을 때만 적는다. pressure_available 은 기기가 필압을
    측정할 수 있는지일 뿐 아이에 대한 관찰이 아니라서, "측정됨"·"측정 불가(미지원 기기)"를
    적으면 관찰 내용이 0인 줄이 해석 재료처럼 놓인다. BE도 이 필드를 감정 근거로 쓰지 말라고
    명시했다. 현재 average_pressure 는 항상 None이라 실질적으로 필압 줄은 나오지 않는다.

    tool_change_count·color_change_count 는 계약으로 받되 싣지 않는다 — "색을 5번 바꿨다"의
    관찰 의미가 불분명하고, 블록 항목이 늘수록 프롬프트 규칙끼리 충돌해 왔다(788·808).
    실제 값 분포를 본 뒤 후속에서 판단한다.
    """
    if behavior is None:
        return ""

    notes = []
    if is_htp:
        notes.append(_SCOPE_NOTE_HTP)
    if behavior.truncated:
        notes.append(_SCOPE_NOTE_TRUNCATED)
    header = "[형식적 분석]" + (f" ({' / '.join(notes)})" if notes else "")

    lines = [header]
    total = _fmt_minutes(behavior.drawing_duration_ms)
    active = _fmt_minutes(behavior.active_drawing_ms)
    if total:
        lines.append(f"- 총 소요시간: {total}")
    if active:
        lines.append(f"- 실제 그린 시간: {active}")
    if behavior.pause_count is not None:
        # 배치 경계로 세는 추정값이라 상한도 하한도 아니다(BE javadoc) — 단정 표기를 피한다.
        # 0에 "약"을 붙이면 문장이 이상해지므로 그때만 숫자를 그대로 쓴다.
        count = (
            "0번" if behavior.pause_count == 0 else f"약 {behavior.pause_count}번"
        )
        lines.append(f"- 멈춤 횟수: {count} (추정값)")
    if behavior.erase_count is not None:
        lines.append(f"- 지우기 횟수: {behavior.erase_count}회")
    if behavior.undo_count is not None:
        lines.append(f"- 되돌리기 횟수: {behavior.undo_count}회")
    if behavior.average_pressure is not None:
        lines.append(f"- 필압: 평균 {behavior.average_pressure:.2f} (0~1)")

    # 머리말만 남았다면 적을 관찰이 없다는 뜻 — 빈 블록을 실으면 모델이 채우려 든다.
    if len(lines) == 1:
        return ""
    return "\n".join(lines) + "\n\n"


# 주제 코드 → 한국어 라벨. question_service._SUBJECT_KO와 같은 어휘 — 어긋나면 질문과
# 리포트가 같은 그림을 다른 이름으로 부른다.
_SUBJECT_KO = {"HOUSE": "집", "TREE": "나무", "PERSON": "사람"}


def _subject_label(subject: str | None) -> str:
    """주제 라벨. HTP는 '집 그림'·'나무 그림'·'사람 그림', 그림일기(None)는 '그림'."""
    name = _SUBJECT_KO.get(subject or "")
    return f"{name} 그림" if name else "그림"


# ── 탐지 기하 → 관찰 사실 (S15P11B209-839) ─────────────────────
# HTP 임상 리포트의 형식적 분석 1단계가 크기·위치다. 정규화 bbox 에서 바로 계산된다
# (같은 접근: 이은정·황세진, 미술치료연구 2023 — 객체검출 위치·크기로 형식적 해석 산출).
# ⚠️ 여기서 만드는 것은 '관찰 사실'뿐이다. 크기가 작다/크다에 의미를 붙이는 일은 하지 않는다.
_POSITION_COLS = ("왼쪽", "가운데", "오른쪽")
_POSITION_ROWS = ("위쪽", "가운데", "아래쪽")


def _third(value: float) -> int:
    """0~1 좌표를 3분할 인덱스로. 화면을 9칸으로 나눠 위치를 말하기 위한 것."""
    if value < 1 / 3:
        return 0
    if value < 2 / 3:
        return 1
    return 2


def _position_label(obj: contracts.SubjectDetectedObject) -> str:
    """bbox 중심점의 9분할 위치를 한국어로. 중앙이면 '한가운데'."""
    col = _POSITION_COLS[_third(obj.x + obj.width / 2)]
    row = _POSITION_ROWS[_third(obj.y + obj.height / 2)]
    if col == "가운데" and row == "가운데":
        return "화면 한가운데"
    # 한 축만 가운데면 그 축은 말하지 않는다("화면 아래쪽 가운데"보다 "화면 아래쪽"이 자연스럽다).
    return "화면 " + " ".join(part for part in (row, col) if part != "가운데")


def _percent(ratio: float) -> str:
    """비율(0~1)을 '약 N%'로. 반올림이 0%가 되면 '1% 미만'으로 적는다."""
    percent = round(ratio * 100)
    return "1% 미만" if percent < 1 else f"약 {percent}%"


def _whole_object(
    summary: contracts.SubjectSummary,
) -> contracts.SubjectDetectedObject | None:
    """주제 전체를 감싸는 탐지(집 그림의 HOUSE 등). 그림일기(drawing_subject=None)는 없다."""
    if summary.drawing_subject is None:
        return None
    return next(
        (o for o in summary.detected_objects if o.object_code == summary.drawing_subject),
        None,
    )


def _geometry_line(
    obj: contracts.SubjectDetectedObject,
    whole: contracts.SubjectDetectedObject | None,
    subject_name: str,
) -> str:
    """탐지 하나 → 크기·위치 한 줄.

    신뢰도가 확정 구간 미만이면 완화 문구를 앞에 붙인다 — 겨우 통과한 탐지가 확정 사실로
    적혀 보호자에게 나가면 안 된다(BE 요청). confidence 가 아예 없으면 판단할 근거가 없으므로
    완화하지도 제외하지도 않는다(구 detectedObjectCodes 경로와 같은 취급).
    """
    facts = []
    if obj.area_ratio is not None:
        facts.append(f"종이의 {_percent(obj.area_ratio)}")
        # 부위:주제 비율 — '집에 비해 문이 작다' 같은 관계를 수치로 남긴다.
        if whole is not None and whole is not obj and whole.area_ratio:
            facts.append(f"{subject_name} 전체의 {_percent(obj.area_ratio / whole.area_ratio)}")
    facts.append(_position_label(obj))

    hedge = ""
    if (
        obj.confidence is not None
        and obj.confidence < config.REPORT_GEOMETRY_CERTAIN_CONF
    ):
        hedge = "(희미해 확실하지 않아요) "
    return f"- {obj.object_code}: {hedge}{', '.join(facts)}"


def _format_geometry(summary: contracts.SubjectSummary, label: str) -> str:
    """주제 하나의 [OO 크기·위치] 블록. 쓸 탐지가 없으면 빈 문자열.

    신뢰도가 REPORT_GEOMETRY_MIN_CONF 미만인 탐지는 아예 뺀다 — 탐지 임계값(0.20)은
    '박스를 남길지'의 기준이라 리포트 문장의 근거 기준으로 쓰기엔 낮다.
    """
    usable = [
        obj
        for obj in summary.detected_objects
        if obj.confidence is None or obj.confidence >= config.REPORT_GEOMETRY_MIN_CONF
    ]
    if not usable:
        return ""
    whole = _whole_object(summary)
    subject_name = _SUBJECT_KO.get(summary.drawing_subject or "", "그림")
    lines = [f"[{label} 크기·위치]"]
    lines.extend(_geometry_line(obj, whole, subject_name) for obj in usable)
    return "\n".join(lines)


def _format_subject_blocks(req: contracts.ObservationGenerationRequest) -> str:
    """주제별 [OO 관찰]·[OO 문답] 블록 (S15P11B209-740).

    HTP는 집·나무·사람 각 그림의 VLM 서술과 그 그림에서 나눈 문답이 블록으로 실린다.
    문답의 아이 답변은 '관찰된 사실' 근거로만 쓰이도록 활동별 프롬프트가 강제한다.
    탐지 요소 코드는 서술 검증 참고용 — 리포트 문장에 코드 원문 노출 금지(프롬프트 규칙).

    기하 정보(839)가 있으면 [OO 크기·위치] 블록이 뒤따른다. 없으면(구 BE·PIXEL 좌표뿐인
    주제) 지금까지처럼 코드 목록만 실린다.
    """
    parts: list[str] = []
    for summary in req.subject_summaries:
        label = _subject_label(summary.drawing_subject)
        description = (summary.drawing_description or "").strip() or (
            "(관찰 서술이 제공되지 않았어요)"
        )
        lines = [f"[{label} 관찰]", description]
        if summary.detected_object_codes:
            lines.append(
                "- 탐지된 요소 코드(참고용): " + ", ".join(summary.detected_object_codes)
            )
        parts.append("\n".join(lines))
        geometry = _format_geometry(summary, label)
        if geometry:
            parts.append(geometry)
        if summary.qa_pairs:
            qa_lines = [f"[{label} 문답]"]
            for qa in summary.qa_pairs:
                # SKIPPED는 '아이가 스스로 넘겼다'는 관찰 사실이라 무응답과 구분해 표기한다.
                if (qa.answer_type or "").upper() == "SKIPPED":
                    answer = "(건너뛴 질문)"
                else:
                    answer = (qa.answer_text or "").strip() or "(답하지 않았어요)"
                qa_lines.append(f"- 질문: {qa.question}\n  답변: {answer}")
            parts.append("\n".join(qa_lines))
    return "\n\n".join(parts) + "\n\n"


def _format_activity(
    req: contracts.ObservationGenerationRequest,
    drawing_description: str | None,
    behavior: contracts.BehaviorMetrics | None = None,
    rag_chunks: list[Chunk] | None = None,
) -> str:
    """[그림 관찰 서술](VLM) + [형식적 분석] + [전문 자료 근거] + 집계·감정·대표 발화.

    drawing_description 은 vlm_client.describe 산출물(그림 사실 묘사)이며, 있으면
    관찰 특징·요약의 근거가 된다. 없으면 그림 특징은 언급하지 않도록 안내 문구를 넣는다.
    behavior 는 소요시간·필압 등 형식적 지표이며, 있으면 관찰 보조 근거로 반영된다.
    rag_chunks(614)는 검색된 전문 자료 근거 — 있으면 어휘·일반 지식 보조로 실린다.

    subject_summaries(740)가 있으면 단일 [그림 관찰 서술] 대신 주제별 블록을 쓴다 —
    drawing_description(레거시 draft 경로 인자)과 동시에 오면 주제별 블록이 우선한다.
    """
    emotions = ", ".join(req.selected_emotions) if req.selected_emotions else "없음"
    if req.subject_summaries:
        observation_block = _format_subject_blocks(req)
    else:
        description = (drawing_description or "").strip() or (
            "(그림 관찰 서술이 제공되지 않았어요)"
        )
        observation_block = f"[그림 관찰 서술]\n{description}\n\n"
    return (
        f"{observation_block}"
        f"{_format_behavior(behavior, is_htp=_is_htp(req))}"
        f"{_format_rag_block(rag_chunks or [])}"
        "[활동 데이터]\n"
        f"- 질문 난이도: {req.question_difficulty or '정보 없음'}\n"
        f"- 제시한 질문 수: {req.question_count}\n"
        f"- 응답한 답변 수: {req.answered_count}\n"
        f"- 건너뛴 질문 수: {req.skipped_count}\n"
        f"- 음성 인식 실패 수: {req.unrecognized_speech_count}\n"
        f"- 아이가 선택한 감정: {emotions}\n"
        f"- 아이가 말한 감정: {req.expressed_emotion_text or '없음'}\n"
        f"- 대표 발화: {req.representative_utterance or '없음'}\n\n"
        "이 데이터로 규칙에 맞는 관찰 기록 JSON을 만들어줘."
    )


# ── RAG 근거 검색 (S15P11B209-614 — 정책: docs/ai/rag-corpus-policy.md) ──────
def _build_rag_query(
    req: contracts.ObservationGenerationRequest, drawing_description: str | None
) -> str:
    """검색 질의 텍스트 — 관찰 서술·탐지 객체·선택 감정로만 만든다.

    ⚠️ 질의의 본문은 VLM 관찰 서술 원문이다 — 서술 프롬프트(ai/prompts/drawing_description_*.txt)를
    고치면 이 질의가 바뀌고, 따라서 검색되는 청크와 RAG_SCORE_THRESHOLD 통과 여부도 바뀐다.
    서술이 색·크기·위치 같은 구체적 관찰 어휘를 담을수록 코퍼스(관찰 어휘·발달 일반 지식)와
    가까워진다. 서술을 한 문장으로 줄이는 변경은 질의를 죽여 RAG_LOW_SCORE를 상시화한다.

    ⚠️ 아이 발화(qaPairs.answerText·대표 발화·표현 감정 문구)는 넣지 않는다(정책 §1-1) —
    질의는 GMS로 나가는 표면이라 아동 개인 표현의 유출면을 늘리지 않는다.
    선택 감정은 고정 코드(HAPPY 등)라 개인 표현이 아니다.
    """
    parts: list[str] = []
    if req.subject_summaries:
        for summary in req.subject_summaries:
            if summary.drawing_description:
                parts.append(summary.drawing_description)
            parts.extend(summary.detected_object_codes)
    elif drawing_description:
        parts.append(drawing_description)
    # 관찰 재료(그림 서술·탐지 객체)가 없으면 질의를 만들지 않는다 — 감정 코드·난이도만으로
    # 검색하면 그림과 무관한 근거가 붙는다. 둘은 관찰 재료가 있을 때의 보강 신호로만 쓴다.
    if not parts:
        return ""
    if req.selected_emotions:
        parts.append("아이가 선택한 감정: " + ", ".join(req.selected_emotions))
    if req.question_difficulty:
        parts.append(f"연령 난이도: {req.question_difficulty}")
    return "\n".join(parts).strip()


# RAG 검색 결과 카운터 (S15P11B209-615). outcome: used | no_index | unavailable |
#   low_score | no_query | not_applicable. "성공/실패/저점수 비율"을 운영에서 볼 수 있게 한다 —
#   저점수 비율이 높으면 코퍼스가 얇거나 임계값(RAG_SCORE_THRESHOLD)이 높은 것.
#   not_applicable은 그림일기라 검색을 아예 시도하지 않은 경우 — 장애가 아니라 정책이다.
_RAG_SEARCH_COUNTER = PrometheusCounter(
    "dodam_rag_search_total",
    "관찰 리포트 RAG 검색 결과 (outcome별 누적)",
    labelnames=("outcome",),
)


def _search_rag(
    req: contracts.ObservationGenerationRequest, drawing_description: str | None
) -> tuple[list[Chunk], str | None]:
    """근거 청크 검색 → (청크 목록, 건너뛴 사유 코드).

    실패는 '차단'이 아니라 '기능 저하'다(548 폴백 정책과 정합) — 어떤 사유든
    리포트 생성은 계속되고, 사유는 응답(ragSkippedReason)과 메트릭에만 남는다.

    - RAG_NO_QUERY: 관찰 재료(서술·객체)가 없어 검색을 시도하지 않음
    - RAG_NO_INDEX: 인덱스 미배포(운영상 정상일 수 있는 상태)
    - RAG_UNAVAILABLE: 임베딩 호출 실패 등 검색 장애
    - RAG_LOW_SCORE: 검색은 됐지만 전부 임계값 미달 — 억지 근거를 싣지 않음
    """
    query = _build_rag_query(req, drawing_description)
    if not query:
        _RAG_SEARCH_COUNTER.labels(outcome="no_query").inc()
        return [], "RAG_NO_QUERY"
    try:
        chunks = retrieve(query)
    except RagUnavailableError as e:
        reason = "RAG_NO_INDEX" if e.reason == "NO_INDEX" else "RAG_UNAVAILABLE"
        _RAG_SEARCH_COUNTER.labels(outcome=reason.removeprefix("RAG_").lower()).inc()
        logger.info("RAG 근거 없이 리포트 생성 — reason=%s", reason)
        return [], reason
    if not chunks:
        _RAG_SEARCH_COUNTER.labels(outcome="low_score").inc()
        logger.info("RAG 근거 없이 리포트 생성 — reason=RAG_LOW_SCORE")
        return [], "RAG_LOW_SCORE"
    _RAG_SEARCH_COUNTER.labels(outcome="used").inc()
    return chunks, None


def _format_rag_block(chunks: list[Chunk]) -> str:
    """[전문 자료 근거] 블록. 근거가 없으면 빈 문자열(블록 자체를 싣지 않는다)."""
    if not chunks:
        return ""
    lines = ["[전문 자료 근거]"]
    for chunk in chunks:
        lines.append(f"- ({chunk.title}) {chunk.text}")
    return "\n".join(lines) + "\n\n"


def _rag_references(chunks: list[Chunk]) -> list[contracts.RagReference]:
    """청크 → 출처 목록(자료 단위 중복 제거, 검색 순위 순서 유지)."""
    seen: set[str] = set()
    references: list[contracts.RagReference] = []
    for chunk in chunks:
        if chunk.source_id in seen:
            continue
        seen.add(chunk.source_id)
        references.append(
            contracts.RagReference(source_id=chunk.source_id, title=chunk.title)
        )
    return references


def _extract_json(raw: str) -> dict:
    """모델 응답에서 JSON 객체만 뽑아 파싱한다(코드펜스·머리말이 섞여도 견디게).

    첫 '{' 부터 마지막 '}' 까지를 JSON으로 본다. 파싱 실패는 RuntimeError로 올린다.
    """
    text = raw.strip()
    start = text.find("{")
    end = text.rfind("}")
    if start == -1 or end == -1 or end < start:
        raise RuntimeError("리포트 응답을 해석하지 못했어요(형식 오류).")
    try:
        return json.loads(text[start : end + 1])
    except json.JSONDecodeError as e:
        # ⚠️ 응답 본문은 로그로 남기지 않는다 — 에러 유형만.
        logger.error("리포트 JSON 파싱 실패: %s", type(e).__name__)
        raise RuntimeError("리포트 응답을 해석하지 못했어요(형식 오류).") from e


def _scope(value) -> str:
    """visibility_scope 를 계약 허용값으로 강제한다. 모르는 값은 보수적으로 EXPERT_ONLY."""
    return value if value in _VALID_SCOPES else "EXPERT_ONLY"


def _feature(item: dict) -> contracts.ObservedFeatureDraft:
    """LLM이 만든 특징 dict 하나를 계약 모델로. 누락 필드는 빈 문자열로 채운다.

    두 가지를 보호자 노출 전에 규칙으로 걸러 EXPERT_ONLY로 강등한다:
    - 단정적 진단(591)·감정/성격 과잉 추론(592) 표현 → 격리.
    - '근거 없는 해석'(S15P11B209-600): description(AI 해석)이 있는데 evidenceSummary(관찰 사실)가
      비어 있으면, 사실에 근거하지 않은 억측이라 보호자에게 사실처럼 보이면 안 된다 → 격리.
    경향성 우려 소견·근거 있는 해석은 그대로 통과한다.
    """
    title = str(item.get("title", ""))
    description = str(item.get("description", ""))
    evidence = str(item.get("evidenceSummary", ""))
    scope = _scope(item.get("visibilityScope"))
    if scope != "EXPERT_ONLY" and report_safety.has_unsafe_expression(
        title, description, evidence
    ):
        # ⚠️ 원문은 로그로 남기지 않는다 — 격리 사실만.
        logger.warning("리포트 feature 과도 규정·단정 표현 격리 — EXPERT_ONLY 강등")
        scope = "EXPERT_ONLY"
    elif scope != "EXPERT_ONLY" and description.strip() and not evidence.strip():
        # 해석은 있는데 관찰 근거가 없다 — 사실/해석 분리 원칙 위반이라 보호자 노출 불가.
        logger.warning("리포트 feature 해석에 관찰 근거 없음 — EXPERT_ONLY 강등")
        scope = "EXPERT_ONLY"
    return contracts.ObservedFeatureDraft(
        feature_code=str(item.get("featureCode", "")),
        title=title,
        description=description,
        evidence_summary=evidence,
        visibility_scope=scope,
    )


def _generation_version(is_htp: bool) -> str:
    """리포트 재현성 버전 태그 — 프롬프트·파이프라인 버전을 함께 기록한다(S15P11B209-602).

    ObservationGenerationResult 계약엔 prompt/pipeline 전용 필드가 없어(BE 소유), model_version
    문자열에 둘을 함께 실어 재현·재분석에 필요한 버전을 모두 남긴다(모델 ID는 model_name).
    형식: "pipeline=<파이프라인>;prompt=<이번에 쓴 프롬프트 조합 버전>".

    프롬프트가 활동별로 갈린 뒤로는 '이번 생성이 실제로 쓴' 조합만 싣는다 — 두 변형을 모두
    적으면 어느 쪽으로 뽑힌 결과인지 사후에 구분할 수 없다. 전용 필드 분리는 BE 계약 확장 후속.

    프롬프트 조합은 축약 태그로 싣는다(S15P11B209-819) — 정본을 그대로 실으면 파일이 갈릴 때마다
    길어져 BE 컬럼을 넘긴다. 정본은 version_manifest()로 되짚는다.
    """
    label = "htp" if is_htp else "diary"
    prompt = prompts_registry.short_version(label, *_prompt_names(is_htp))
    return f"pipeline={config.PIPELINE_VERSION};prompt={prompt}"


def _safe_follow_up(raw) -> str:
    """보호자용 후속 질문을 안전하게 보장한다(S15P11B209-601).

    비어 있거나 단정 진단·과잉 추론 표현이 섞이면 안전한 기본 질문으로 대체한다. 후속 질문은
    보호자가 아이에게 그대로 건네는 문장이라, 진단성 표현을 그대로 내보내면 안 된다(제거).

    모델이 스키마(문자열)를 벗어나 {questionText, questionPurpose} 객체로 주는 경우가 있어,
    dict면 questionText만 뽑아낸다 — 안 그러면 dict가 통째로 문자열화돼 화면에 새어 나간다.
    """
    if isinstance(raw, dict):
        raw = raw.get("questionText", "")
    text = str(raw or "").strip()
    if not text or report_safety.has_unsafe_expression(text):
        return DEFAULT_FOLLOW_UP_QUESTION
    return text


def _assemble(
    req: contracts.ObservationGenerationRequest,
    data: dict,
    model: str,
    rag_chunks: list[Chunk] | None = None,
    rag_skipped_reason: str | None = None,
    is_htp: bool | None = None,
) -> contracts.ObservationGenerationResult:
    """LLM 정성 결과(data) + 서버 고정 필드를 합쳐 계약 결과를 만든다.

    rag_chunks(614)가 있으면 출처 목록과 KB Version을 함께 싣는다 — 출처 표시는
    라이선스 의무이자 리포트 재현성 재료(어떤 지식 근거로 생성됐나).
    """
    if is_htp is None:
        is_htp = _is_htp(req)
    conv = data.get("conversationSummary") or {}
    features = [_feature(f) for f in data.get("features", []) if isinstance(f, dict)]

    # 단정적 진단(591)이나 감정·성격 과잉 추론(592) 표현이 보호자 노출 문장·특징에 하나라도
    # 있으면 전문가 검토를 강제한다. attentionPoints는 전문가 전용 채널이라 검사 대상에서 제외한다.
    guardian_texts = [
        str(data.get("overallSummary", "")),
        str(data.get("positiveSignals", "")),
        str(data.get("evidenceSummary", "")),
        str(data.get("guardianGuidance", "")),
        str(data.get("followUpQuestion", "")),
        str(conv.get("summaryText", "")),
        str(conv.get("mainTopic", "")),
        str(conv.get("expressedEmotion", "")),
        *(f"{f.title} {f.description} {f.evidence_summary}" for f in features),
    ]
    needs_expert_review = report_safety.has_unsafe_expression(*guardian_texts)

    observation = contracts.ObservationDraft(
        status="AI_DRAFT",
        overall_summary=str(data.get("overallSummary", "")),
        positive_signals=str(data.get("positiveSignals", "")),
        attention_points=str(data.get("attentionPoints", "")),
        evidence_summary=str(data.get("evidenceSummary", "")),
        guardian_guidance=str(data.get("guardianGuidance", "")),
        # 후속 질문은 비었거나 진단성 표현이 섞이면 안전 기본값으로 대체·보장한다(S15P11B209-601).
        # raw를 그대로 넘긴다 — 객체({questionText,...})로 와도 _safe_follow_up이 questionText를 뽑는다.
        follow_up_question=_safe_follow_up(data.get("followUpQuestion", "")),
        expert_review_required=bool(data.get("expertReviewRequired", False))
        or needs_expert_review,
        disclaimer=DISCLAIMER,
        features=features,
    )
    conversation_summary = contracts.ConversationSummaryDraft(
        summary_text=str(conv.get("summaryText", "")),
        main_topic=str(conv.get("mainTopic", "")),
        expressed_emotion=str(conv.get("expressedEmotion", "")),
        emotion_source=_emotion_source(req),
        representative_utterance=(req.representative_utterance or DEFAULT_UTTERANCE),
    )
    return contracts.ObservationGenerationResult(
        request_id=req.request_id,
        # 재현성(S15P11B209-602): model_name=실제 서빙 모델, model_version=프롬프트+파이프라인 버전.
        model_name=model,
        model_version=_generation_version(is_htp),
        confidence=None,  # LLM 서술엔 보정된 신뢰도가 없다 — 지어내지 않고 None.
        observation_draft=observation,
        conversation_summary=conversation_summary,
        activity_notes=[str(n) for n in data.get("activityNotes", [])],
        follow_up_guides=[
            contracts.FollowUpGuideDraft(
                guidance=str(g.get("guidance", "")),
                detail_text=str(g.get("detailText", "")),
            )
            for g in data.get("followUpGuides", [])
            if isinstance(g, dict)
        ],
        guardian_questions=[
            contracts.GuardianQuestionDraft(
                question_text=str(q.get("questionText", "")),
                question_purpose=str(q.get("questionPurpose", "")),
            )
            for q in data.get("guardianQuestions", [])
            if isinstance(q, dict)
        ],
        limitations_text=LIMITATIONS,
        rag_references=_rag_references(rag_chunks or []),
        # 근거를 실제로 썼을 때만 KB Version을 싣는다 — 근거 없는 리포트에 버전이 붙으면
        # "이 지식에 기반했다"는 거짓 신호가 된다.
        knowledge_base_version=(
            rag_knowledge_base_version() if rag_chunks else None
        ),
        rag_skipped_reason=rag_skipped_reason,
    )


def generate(
    req: contracts.ObservationGenerationRequest,
    *,
    drawing_description: str | None = None,
    behavior: contracts.BehaviorMetrics | None = None,
    model: str | None = None,
) -> contracts.ObservationGenerationResult:
    """[그림 관찰 서술] + [형식적 분석] + 활동 요청 → GMS LLM 관찰 리포트 초안(계약 결과).

    Args:
        req: 최종 분석 관찰 생성 요청(집계·감정·대표 발화).
        drawing_description: vlm_client.describe 산출물(그림 사실 묘사). 있으면 관찰 근거로
            쓰인다. None이면 그림 특징은 언급하지 않고 나머지 데이터만으로 생성한다.
        behavior: 소요시간·필압 등 형식적 지표(있으면 관찰 보조 근거로 반영). 생략하면
            req.behavior_metrics 를 쓴다 — 계약으로 들어온 값이 정상 경로이고, 이 인자는
            draft/스모크에서 계약 밖 값을 넣어 보기 위한 덮어쓰기다.
        model: 미지정 시 config.LLM_MODEL(텍스트 전용 — 이미지 자체는 넘기지 않는다).

    Returns:
        ObservationGenerationResult(BE 계약 형태, camelCase 직렬화).

    Raises:
        RuntimeError: GMS 호출 실패 또는 응답 JSON 파싱 실패 시(내용은 감추고 유형만 로그).
    """
    used_model = model or config.LLM_MODEL
    # 계약 값(836)이 기본. 인자로 준 값이 있으면 그쪽이 이긴다(draft/스모크 덮어쓰기).
    behavior = behavior if behavior is not None else req.behavior_metrics
    is_htp = _is_htp(req)
    # RAG 근거 검색(614)은 HTP 리포트에서만 한다 — 그림일기 프롬프트는 [전문 자료 근거]를
    # 근거 목록에 두지 않으므로, 검색해 봐야 프롬프트가 쓰지 않는 블록에 비용만 쓴다.
    # 실패해도 리포트는 생성한다(기능 저하, 차단 아님). 사유(615)는 응답·메트릭으로만 남긴다.
    if is_htp:
        rag_chunks, rag_skipped_reason = _search_rag(req, drawing_description)
    else:
        _RAG_SEARCH_COUNTER.labels(outcome="not_applicable").inc()
        rag_chunks, rag_skipped_reason = [], RAG_NOT_APPLICABLE
    messages = [
        {"role": "system", "content": _system_prompt(is_htp)},
        {
            "role": "user",
            "content": _format_activity(req, drawing_description, behavior, rag_chunks),
        },
    ]
    try:
        resp = get_client().chat.completions.create(
            model=used_model,
            messages=messages,
            temperature=0.4,  # 관찰 기록은 튀지 않게 다소 낮게.
            response_format={"type": "json_object"},
        )
    except OpenAIError as e:
        # ⚠️ 요청 내용(대표 발화 등)은 로그에 남기지 않는다 — 에러 유형만.
        logger.error("GMS 리포트 생성 호출 실패: %s", type(e).__name__)
        raise RuntimeError("리포트 생성에 실패했어요(GMS).") from e

    data = _extract_json(resp.choices[0].message.content or "")
    # 재현성: GMS가 실제 서빙한 모델 ID를 기록한다(예: gpt-4o-mini-2024-07-18). 없으면 요청 모델명.
    served_model = getattr(resp, "model", "") or used_model
    return _assemble(req, data, served_model, rag_chunks, rag_skipped_reason, is_htp)


if __name__ == "__main__":
    # 스모크 테스트:  cd ai && python report_client.py  (GMS 키 필요)
    logging.basicConfig(level=logging.INFO)
    sample = contracts.ObservationGenerationRequest(
        request_id="smoke-1",
        analysis_id=1,
        drawing_session_id=1,
        analysis_type="FINAL",
        question_difficulty="PRESCHOOL",
        question_count=5,
        answered_count=4,
        skipped_count=1,
        unrecognized_speech_count=0,
        selected_emotions=["JOY"],
        expressed_emotion_text=None,
        representative_utterance="이건 우리 집이야. 엄마랑 나 있어.",
    )
    sample_description = "가운데에 집이 크게 그려져 있고, 왼쪽에 나무 한 그루가 있어요. 오른쪽에는 사람 두 명이 나란히 서 있어요."
    sample_behavior = contracts.BehaviorMetrics(
        drawing_duration_ms=600_000,  # 총 10분
        active_drawing_ms=410_000,  # 실제 그린 시간 약 6.8분
        pause_count=4,
        erase_count=3,
        undo_count=2,
        pressure_available=True,
        # BE는 이번 단계에서 항상 None을 보낸다 — 스모크에서만 값을 넣어 표기를 확인한다.
        average_pressure=0.62,
    )
    result = generate(
        sample, drawing_description=sample_description, behavior=sample_behavior
    )
    print(result.model_dump_json(by_alias=True, indent=2))

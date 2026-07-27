"""그림분석 — YOLO(HTP) 객체탐지 래퍼.

노트북(ai/models/baseline_htp_jupyter.ipynb) 안에만 있던 추론을 재사용 가능한 모듈로 뺐다.
서버·CI가 torch 없이도 import되도록 ultralytics·cv2는 함수 안에서 지연 import한다
(실제 탐지를 돌릴 때만 필요). 가중치는 저장소에 커밋하지 않고 별도로 다운로드/학습해 둔다.

가드레일: 이미지 원본·경로를 로그로 남기지 않는다(탐지 개수·에러 유형만).
"""

from __future__ import annotations

import hashlib
import logging
from dataclasses import dataclass
from pathlib import Path

import config

logger = logging.getLogger(__name__)

_models: dict[str, object] = {}  # 모델 키별 지연 로딩 싱글턴 캐시


@dataclass(frozen=True)
class Detection:
    """탐지된 객체 하나. 좌표는 픽셀·정규화 두 형태를 함께 제공한다.

    - bbox_xyxy: 픽셀 (x1, y1, x2, y2) — 원본 이미지 좌표계.
    - bbox_norm_xywh: 정규화 (x, y, w, h), 0~1 — 대화 질문 계약이 쓰는 형식과 호환.
    """

    label: str
    confidence: float
    bbox_xyxy: tuple[float, float, float, float]
    bbox_norm_xywh: tuple[float, float, float, float]


def _model_registry() -> dict[str, tuple[str, str]]:
    """모델 키 → (가중치 경로, 기대 sha256). config에서 조립한다.

    HTP(집-나무-사람)와 그림일기(자유 그림)는 가중치가 다르다. 키로 구분해 각각
    로드·검증한다. 그림일기(sketch) 모델은 현재 등록·검증만 하며, 분석 파이프라인
    라우팅은 후속 계약과 함께 붙인다.
    """
    return {
        "htp": (config.YOLO_MODEL_PATH, config.YOLO_MODEL_SHA256),
        "sketch": (config.SKETCH_MODEL_PATH, config.SKETCH_MODEL_SHA256),
    }


def _sha256_of_file(path: Path) -> str:
    """가중치 파일의 sha256 hex. 대용량이라 청크로 읽어 메모리를 아낀다."""
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _verify_checksum(path: Path, expected: str | None) -> None:
    """가중치 무결성 검증. 불일치면 실패(fail-closed), 미설정이면 경고 후 통과.

    reason: 파일 존재만 보면 전송 중 손상·오배포된 가중치가 조용히 로드돼 분석 결과가
    오염된다. 로드 전에 sha256을 기대값과 대조한다. 해시는 비밀이 아니라 무결성 지문이라
    불일치 시 로그·예외에 남겨도 된다(가드레일: 이미지 원본·경로가 아니다).
    """
    if not expected or not expected.strip():
        logger.warning("가중치 checksum 미설정(%s) — 무결성 검증을 건너뜁니다.", path.name)
        return
    actual = _sha256_of_file(path)
    if actual != expected.strip().lower():
        raise RuntimeError(
            f"YOLO 가중치 무결성 검증 실패: {path.name} "
            f"(기대 {expected.strip().lower()[:12]}…, 실제 {actual[:12]}…). "
            "배포된 가중치가 손상됐거나 기대 해시가 어긋났습니다."
        )


def _get_model(key: str = "htp"):
    """지정 모델 가중치를 한 번만 로드한다(키별 지연 싱글턴). 로드 전 checksum을 검증한다.

    파일이 없거나(RuntimeError) checksum이 어긋나면(RuntimeError) 명확히 실패한다.
    """
    if key not in _models:
        registry = _model_registry()
        if key not in registry:
            raise ValueError(f"알 수 없는 모델 키: {key!r} (가능: {sorted(registry)}).")
        path_str, expected = registry[key]
        path = Path(path_str)
        if not path.exists():
            raise RuntimeError(
                f"YOLO 가중치를 찾을 수 없어요: {path.name} "
                "(경로 env로 지정하거나 모델을 먼저 배포하세요)."
            )
        _verify_checksum(path, expected)
        from ultralytics import YOLO  # 지연 import — torch는 여기서만 필요

        _models[key] = YOLO(str(path))
    return _models[key]


def verify_all_models() -> dict[str, str]:
    """등록된 모든 모델의 존재·checksum을 torch 로드 없이 점검한다(배포 검증·health용).

    각 모델 키에 "ok"(검증 통과) / "unverified"(기대 해시 미설정)를 돌려주고, 파일 부재·
    checksum 불일치는 예외로 즉시 드러낸다(fail-closed). 실제 추론 전에 운영 가중치가
    기대한 것인지 독립적으로 확인하는 경로다(S15P11B209-603 완료조건).
    """
    statuses: dict[str, str] = {}
    for key, (path_str, expected) in _model_registry().items():
        path = Path(path_str)
        if not path.exists():
            raise RuntimeError(f"YOLO 가중치를 찾을 수 없어요: {key}={path.name}")
        _verify_checksum(path, expected)
        statuses[key] = "ok" if (expected and expected.strip()) else "unverified"
    return statuses


def _parse_result(result) -> list[Detection]:
    """ultralytics 결과 1건을 Detection 목록으로 변환한다(torch 없이 단위 테스트 가능하게 분리).

    result.boxes.data 는 (N, 6) 텐서: [x1, y1, x2, y2, conf, cls].
    result.orig_shape 는 (height, width), result.names 는 {id: 한국어 클래스명}.
    """
    height, width = result.orig_shape
    names = result.names
    data = result.boxes.data
    rows = data.tolist() if hasattr(data, "tolist") else list(data)

    detections: list[Detection] = []
    for x1, y1, x2, y2, conf, cls in rows:
        class_id = int(cls)
        label = names.get(class_id, str(class_id)) if isinstance(names, dict) else names[class_id]
        norm = (
            x1 / width,
            y1 / height,
            (x2 - x1) / width,
            (y2 - y1) / height,
        )
        detections.append(
            Detection(
                label=label,
                confidence=float(conf),
                bbox_xyxy=(float(x1), float(y1), float(x2), float(y2)),
                bbox_norm_xywh=tuple(float(v) for v in norm),  # type: ignore[arg-type]
            )
        )
    return detections


def _encode_png(bgr_ndarray) -> bytes:
    """ultralytics plot() 결과(BGR ndarray)를 PNG bytes로 인코딩한다."""
    import cv2  # 지연 import

    ok, buf = cv2.imencode(".png", bgr_ndarray)
    if not ok:
        raise RuntimeError("주석 이미지 인코딩에 실패했어요.")
    return buf.tobytes()


def detect_and_annotate(
    image_path: str, *, conf: float | None = None
) -> tuple[list[Detection], bytes]:
    """이미지 → (탐지 목록, bbox가 그려진 PNG bytes).

    VLM 서술 입력으로 쓸 '주석 이미지'와 구조화된 탐지 목록을 함께 돌려준다.

    Args:
        image_path: 분석할 이미지 파일 경로.
        conf: 신뢰도 하한. 미지정 시 config.YOLO_CONF_THRESHOLD.

    Raises:
        RuntimeError: 가중치 부재·인코딩 실패 시.
    """
    threshold = config.YOLO_CONF_THRESHOLD if conf is None else conf
    model = _get_model()
    result = model.predict(str(image_path), conf=threshold, verbose=False)[0]
    detections = _parse_result(result)
    annotated_png = _encode_png(result.plot())  # BGR ndarray → PNG bytes
    logger.info("YOLO 탐지 %d건", len(detections))
    return detections, annotated_png


if __name__ == "__main__":
    # 스모크 테스트:  cd ai && python yolo_client.py <이미지파일>
    #   가중치·torch가 필요하다(저장소 미커밋 — models/model_download.ipynb 참고).
    #   후처리(교차 주제 오탐 억제·그룹 집계)까지 함께 보여준다 — S15P11B209-376.
    import sys

    import htp_labels

    logging.basicConfig(level=logging.INFO)
    if len(sys.argv) < 2:
        print("사용법: python yolo_client.py <이미지파일>")
        raise SystemExit(1)

    # 가중치의 클래스 집합이 htp_labels 표와 어긋나면 라벨이 전부 UNKNOWN으로 접힌다 —
    # 추론 결과를 보기 전에 먼저 확인한다(재학습 후 표 갱신 누락을 여기서 잡는다).
    model_names = _get_model().names
    unmapped = htp_labels.verify_against_model_names(model_names.values())
    print(f"클래스 {len(model_names)}종 · 매핑 누락: {unmapped or '없음'}")

    raw, png = detect_and_annotate(sys.argv[1])
    dets = htp_labels.suppress_cross_subject_parts(raw)
    print(f"탐지 {len(raw)}건 → 후처리 후 {len(dets)}건 (conf ≥ {config.YOLO_CONF_THRESHOLD})")
    for d in dets:
        xyxy = tuple(round(v, 1) for v in d.bbox_xyxy)
        print(f"- {htp_labels.to_contract_label(d.label)} ({d.confidence:.2f}) xyxy={xyxy}")

    summary = htp_labels.summarize(dets)
    print(f"그린 주제: {summary.subjects_drawn or '판단 불가(전체 박스 없음)'}")
    for group, group_summary in sorted(summary.groups.items()):
        print(
            f"  {group}: 전체={group_summary.whole_detected} "
            f"부위={group_summary.part_labels} maxconf={group_summary.max_confidence:.2f}"
        )

    # 주석 이미지는 후처리 전 원본 결과 기준이다(plot()이 모델 출력에서 그려짐).
    out = Path("yolo_annotated.png")
    out.write_bytes(png)
    print(f"주석 이미지 저장: {out} ({len(png)} bytes)")

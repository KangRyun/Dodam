"""GMS 그림 서술 클라이언트 — 비전 모델로 아동 그림을 한국어로 관찰 서술한다.

입력: YOLO가 bbox를 그린 주석 이미지(PNG bytes) + 구조화된 탐지 목록(list[Detection]).
출력: 대화 첫 질문의 {drawing_analysis} 슬롯 재료가 되는 2~4문장 한국어 서술.

GMS는 OpenAI 호환 게이트웨이라 chat.completions 에 image_url content part를 그대로 넘긴다
(gpt-4o-mini는 이미지 입력 지원). STT/TTS 클라이언트와 같은 형태를 따른다.

가드레일: 이미지·응답 내용을 로그로 남기지 않는다(에러 유형만). 심리 진단·해석 금지는 프롬프트가 강제.
"""

from __future__ import annotations

import base64
import logging

from openai import OpenAIError

import config
import prompts_registry  # 프롬프트 파일 로딩·버전 관리 중앙화 (S15P11B209-595)
from gms import get_client

logger = logging.getLogger(__name__)

# 그림 서술 프롬프트 버전(내용이 바뀌면 자동으로 달라진다) — S15P11B209-595.
PROMPT_VERSION = prompts_registry.version("drawing_description")


def _load(name: str) -> str:
    """프롬프트 로딩은 prompts_registry로 중앙화했다(S15P11B209-595)."""
    return prompts_registry.load(name)


def _position_hint(cx: float, cy: float) -> str:
    """정규화 중심 좌표를 '위/중간/아래 · 왼쪽/가운데/오른쪽' 힌트로."""
    horizontal = "왼쪽" if cx < 0.34 else "오른쪽" if cx > 0.66 else "가운데"
    vertical = "위" if cy < 0.34 else "아래" if cy > 0.66 else "중간"
    return f"{vertical} {horizontal}"


def _size_hint(area_ratio: float) -> str:
    """면적 비율을 대략적인 크기 힌트로."""
    if area_ratio > 0.25:
        return "큼"
    if area_ratio < 0.05:
        return "작음"
    return "보통"


# GMS(OpenAI 호환 게이트웨이)는 요청 본문 크기에 한도가 있어, base64 페이로드가
# 약 100KB를 넘으면 400('Model not found ...')을 돌려준다(실측: 96KB OK · 105KB 실패).
# 그런데 yolo_client의 주석 이미지는 원본 해상도(예: 1280²) PNG라 base64가 1MB에 달해
# 실그림 호출이 항상 실패했다. → 전송 전 축소·JPEG 인코딩으로 한도 안에 넣는다.
#   ⚠️ 토큰은 이미지 '픽셀 크기'와 무관하게 고정이다(gpt-4o-mini 실측: 64px·512px 모두
#      prompt 8,512로 동일). 그래서 축소는 비용을 늘리지 않고 전송량만 줄인다 — 화질만 감수.
_UPLOAD_MAX_SIDE = 512  # 512px·품질 60이면 실측 약 54KB — 한도 대비 여유
_UPLOAD_MAX_B64_KB = 90  # 100KB 한도에 안전 마진
_UPLOAD_JPEG_QUALITIES = (60, 45, 30, 20)  # 그림에 따라 압축률이 달라 한도 초과 시 낮춰 재시도


def _encode_for_upload(png: bytes) -> tuple[str, str]:
    """주석 PNG를 GMS 페이로드 한도 안에 드는 (mime, base64) 로 인코딩한다.

    실제 이미지는 512px로 줄여 JPEG로 인코딩하고, 한도를 넘으면 품질을 낮춰 재시도한다.
    디코드가 안 되는 입력(테스트용 가짜 바이트 등)은 원본 PNG를 그대로 돌려준다 —
    축소는 어디까지나 '전송 가능하게' 하려는 것이지 입력 검증이 아니다.
    """
    import cv2  # 지연 import — yolo_client와 동일(opencv-python-headless)
    import numpy as np

    image = cv2.imdecode(np.frombuffer(png, dtype=np.uint8), cv2.IMREAD_COLOR)
    if image is None:
        return "image/png", base64.b64encode(png).decode()

    height, width = image.shape[:2]
    longest = max(height, width)
    if longest > _UPLOAD_MAX_SIDE:
        scale = _UPLOAD_MAX_SIDE / longest
        image = cv2.resize(
            image, (max(1, round(width * scale)), max(1, round(height * scale))),
            interpolation=cv2.INTER_AREA,
        )

    encoded = ""
    for quality in _UPLOAD_JPEG_QUALITIES:
        ok, buf = cv2.imencode(".jpg", image, [cv2.IMWRITE_JPEG_QUALITY, quality])
        if not ok:
            continue
        encoded = base64.b64encode(buf.tobytes()).decode()
        if len(encoded) / 1024 <= _UPLOAD_MAX_B64_KB:
            break
    # 최저 품질에서도 한도를 넘으면 마지막 결과라도 넘긴다(호출 실패는 상위에서 처리).
    return "image/jpeg", encoded


def _format_detections(detections, display_name_of=None) -> str:
    """탐지 목록을 프롬프트에 넣을 한국어 텍스트로. 없으면 안내 문구.

    display_name_of를 주면 내부 클래스명 대신 표시명을 쓴다(S15P11B209-711).
    '기둥'(TREE_TRUNK)처럼 내부 용어를 그대로 넣으면 서술이 다른 뜻으로 흐른다.
    """
    if not detections:
        return "(탐지된 객체가 없어요)"
    lines = []
    for d in detections:
        x, y, w, h = d.bbox_norm_xywh
        position = _position_hint(x + w / 2, y + h / 2)
        size = _size_hint(w * h)
        name = display_name_of(d.label) if display_name_of else d.label
        lines.append(f"- {name} (신뢰도 {d.confidence:.2f}, {position}, {size})")
    return "\n".join(lines)


def describe(
    annotated_png: bytes,
    detections,
    *,
    model: str | None = None,
    display_name_of=None,
) -> str:
    """주석 이미지 + 탐지 목록 → 한국어 관찰 서술.

    Args:
        annotated_png: bbox가 그려진 PNG bytes(yolo_client.detect_and_annotate 산출물).
        detections: list[Detection]. 프롬프트에 텍스트로도 함께 제공된다.
        model: 미지정 시 config.VLM_MODEL.
        display_name_of: 클래스명 → 표시명 변환 함수. 활동 유형에 맞는 라벨 표의 것을
            넘긴다. 없으면 클래스명을 그대로 쓴다(하위 호환).

    Returns:
        한국어 서술 문자열(빈 응답이면 "").

    Raises:
        RuntimeError: GMS 호출 실패 시(원본 내용은 감추고 에러 유형만 로그).
    """
    used_model = model or config.VLM_MODEL
    mime, image_b64 = _encode_for_upload(annotated_png)
    data_url = f"data:{mime};base64,{image_b64}"
    system = _load("drawing_description").format(
        detections=_format_detections(detections, display_name_of)
    )
    messages = [
        {"role": "system", "content": system},
        {
            "role": "user",
            "content": [
                {"type": "text", "text": "이 그림을 규칙에 맞게 한국어로 서술해줘."},
                {"type": "image_url", "image_url": {"url": data_url}},
            ],
        },
    ]
    try:
        resp = get_client().chat.completions.create(
            model=used_model,
            messages=messages,
            temperature=0.3,  # 서술은 사실 중심 — 낮게.
        )
    except OpenAIError as e:
        # ⚠️ 이미지·응답 내용은 로그에 남기지 않는다 — 에러 유형만.
        logger.error("GMS 그림 서술 호출 실패: %s", type(e).__name__)
        raise RuntimeError("그림 서술 생성에 실패했어요(GMS).") from e

    return (resp.choices[0].message.content or "").strip()


if __name__ == "__main__":
    # 스모크 테스트:  cd ai && python vlm_client.py <이미지파일>
    #   YOLO 탐지 → 주석 이미지 → VLM 서술 왕복(가중치·GMS 키 필요).
    import sys

    import yolo_client

    logging.basicConfig(level=logging.INFO)
    if len(sys.argv) < 2:
        print("사용법: python vlm_client.py <이미지파일>")
        raise SystemExit(1)
    dets, png = yolo_client.detect_and_annotate(sys.argv[1])
    detected = ", ".join(f"{d.label}({d.confidence:.2f})" for d in dets) or "없음"
    print("[탐지]", detected)
    print("[서술]", describe(png, dets))

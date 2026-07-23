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
from functools import lru_cache
from pathlib import Path

from openai import OpenAIError

import config
from gms import get_client

logger = logging.getLogger(__name__)

PROMPT_DIR = Path(__file__).parent / "prompts"

# 프롬프트 파일이 바뀌면 올린다(어떤 프롬프트로 뽑힌 서술인지 추적용).
PROMPT_VERSION = "1.0.0"


@lru_cache(maxsize=None)
def _load(name: str) -> str:
    """ai/prompts/<name>.txt 를 읽어 캐시한다(llm_client와 같은 로딩 방식)."""
    return (PROMPT_DIR / f"{name}.txt").read_text(encoding="utf-8").strip()


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


def _format_detections(detections) -> str:
    """탐지 목록을 프롬프트에 넣을 한국어 텍스트로. 없으면 안내 문구."""
    if not detections:
        return "(탐지된 객체가 없어요)"
    lines = []
    for d in detections:
        x, y, w, h = d.bbox_norm_xywh
        position = _position_hint(x + w / 2, y + h / 2)
        size = _size_hint(w * h)
        lines.append(f"- {d.label} (신뢰도 {d.confidence:.2f}, {position}, {size})")
    return "\n".join(lines)


def describe(annotated_png: bytes, detections, *, model: str | None = None) -> str:
    """주석 이미지 + 탐지 목록 → 한국어 관찰 서술.

    Args:
        annotated_png: bbox가 그려진 PNG bytes(yolo_client.detect_and_annotate 산출물).
        detections: list[Detection]. 프롬프트에 텍스트로도 함께 제공된다.
        model: 미지정 시 config.VLM_MODEL.

    Returns:
        한국어 서술 문자열(빈 응답이면 "").

    Raises:
        RuntimeError: GMS 호출 실패 시(원본 내용은 감추고 에러 유형만 로그).
    """
    used_model = model or config.VLM_MODEL
    data_url = "data:image/png;base64," + base64.b64encode(annotated_png).decode()
    system = _load("drawing_description").format(detections=_format_detections(detections))
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

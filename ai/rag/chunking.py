"""청크 분할 — 문단 단위 300~500자 (S15P11B209-613, 정책 §6).

왜 문단 기준인가: 발달·정서 자료는 문단이 하나의 완결된 지식 단위다(연령대 하나,
어휘 하나). 문장 중간을 자르면 임베딩이 반쪽 의미를 갖고, 리포트 프롬프트에
실렸을 때도 근거로 읽히지 않는다.

- 짧은 문단은 다음 문단과 병합해 MIN 이상으로 만들고,
- 긴 문단은 문장 경계에서 MAX 이하로 나눈다(문장 경계가 없으면 강제 절단).
"""

from __future__ import annotations

import re
from dataclasses import dataclass

MIN_CHARS = 300
MAX_CHARS = 500

# 한국어 평서문 종결 뒤 공백. 약어·소수점 오탐은 이 Corpus(공공 간행물 산문)에선 드물고,
# 오탐의 비용도 "청크 경계가 한 문장 어긋남"에 그친다 — 정교한 문장 분리기는 과투자.
_SENTENCE_END = re.compile(r"(?<=[.!?다요])\s+")


@dataclass(frozen=True)
class TextChunk:
    """인덱스에 들어갈 청크 하나. chunk_id는 같은 자료 안에서의 순번."""

    source_id: str
    chunk_id: str
    text: str


def _split_long(paragraph: str) -> list[str]:
    """MAX를 넘는 문단을 문장 경계에서 나눈다. 한 문장이 MAX를 넘으면 강제 절단."""
    pieces: list[str] = []
    current = ""
    for sentence in _SENTENCE_END.split(paragraph):
        if not sentence:
            continue
        if current and len(current) + 1 + len(sentence) > MAX_CHARS:
            pieces.append(current)
            current = sentence
        else:
            current = f"{current} {sentence}".strip()
        while len(current) > MAX_CHARS:  # 초장문 단일 문장 방어
            pieces.append(current[:MAX_CHARS])
            current = current[MAX_CHARS:]
    if current:
        pieces.append(current)
    return pieces


def split(source_id: str, text: str) -> list[TextChunk]:
    """자료 원문 텍스트를 청크 목록으로 나눈다.

    입력 텍스트는 이미 비진단 선별(excludedSections 제거)이 끝난 상태여야 한다 —
    선별은 텍스트 준비 단계의 책임이고 기록은 매니페스트에 남는다(정책 §6).
    """
    paragraphs = [p.strip() for p in re.split(r"\n\s*\n", text) if p.strip()]

    merged: list[str] = []
    buffer = ""
    for paragraph in paragraphs:
        buffer = f"{buffer}\n{paragraph}".strip() if buffer else paragraph
        if len(buffer) >= MIN_CHARS:
            merged.extend(_split_long(buffer) if len(buffer) > MAX_CHARS else [buffer])
            buffer = ""
    if buffer:  # 꼬리 문단은 MIN 미만이어도 버리지 않는다 — 마지막 지식 단위 유실 방지
        merged.append(buffer)

    return [
        TextChunk(source_id=source_id, chunk_id=f"{source_id}#{index}", text=piece)
        for index, piece in enumerate(merged)
    ]

"""발달 맥락 문장의 검수 출처 등록부 — 그림일기 4층.

**출처가 완비되기 전에는 그 문장을 쓰지 않는다.** 이 모듈이 하는 일은 그 한 줄을 코드로
강제하는 것이다. 사람이 원문을 읽고 한국어 문구와 대조했다는 사실이 기록되기 전까지
:func:`is_enabled` 는 거짓을 돌려주고, 등록부는 그 항목을 건너뛴다.

필드를 둘로 나눈 이유가 있다.

    기계가 채우는 것   source_version · retrieved_at · content_hash
    사람만 채우는 것   reviewed_at · reviewed_by

앞의 셋은 페이지를 실제로 가져오면 자동으로 나온다. 뒤의 둘은 **사람이 원문과 한국어 노출
문구를 대조했다는 증언**이라 자동으로 만들 수 없다. 자동으로 만들 수 있게 두면 언젠가
자동으로 채워지고, 그러면 이 게이트는 아무것도 막지 않는다.

⚠️ ``reviewed_by`` 에 ``CLAUDE``·``CHATGPT``·``SYSTEM``·``AI`` 같은 값을 넣을 수 없다.
   :func:`_assert_reviewer_is_human` 이 import 시점에 막는다.

content_hash 규칙(테스트로 고정한다):

    1. 공식 페이지의 main article 본문만 추출
    2. script·style·navigation·footer 제거
    3. 연속 공백을 한 칸으로, 줄 끝 공백 제거
    4. UTF-8 · LF 로 정규화
    5. 그 결과의 SHA-256 (소문자 16진수)
"""

from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass, field

# 사람이 아닌 것으로 검수를 기록할 수 없다. 이 게이트의 존재 이유가 사라진다.
_NON_HUMAN_REVIEWERS = frozenset(
    {"CLAUDE", "CHATGPT", "GPT", "SYSTEM", "AI", "BOT", "AUTO", "UNKNOWN", ""}
)

# 어떤 출처든 반드시 함께 나가는 제한이다. 하나라도 빠지면 그 출처는 쓸 수 없다.
REQUIRED_LIMITATIONS = (
    "NOT_KOREAN_NORM",
    "NOT_SCREENING",
    "NOT_DIAGNOSTIC",
    "DO_NOT_USE_FOR_PEER_COMPARISON",
    "DO_NOT_USE_FOR_DELAY_CLASSIFICATION",
)


@dataclass(frozen=True)
class SourceProvenance:
    """검수 출처 한 건의 내력.

    ``retrieved_at``·``content_hash`` 는 페이지를 **실제로 가져왔을 때만** 채운다. 가져오지
    않고 적으면 없는 확인을 있는 것처럼 기록하는 것이고, 그건 이 표가 막으려는 바로 그것이다.
    """

    source_id: str
    document_title: str
    url: str
    source_type: str
    locale: str
    limitations: tuple[str, ...]
    source_version: str = ""
    retrieved_at: str = ""
    content_hash: str = ""
    reviewed_at: str = ""
    reviewed_by: str = ""
    # 이 출처에서 실제로 확인한 문장들(원문 그대로). 사람이 검수할 때 한국어 문구와 한 줄씩
    #   맞춰 보라고 남긴다 — 원문을 다시 찾아 읽는 수고를 줄이는 것이 검수를 실제로 일어나게 한다.
    supporting_excerpts: tuple[str, ...] = field(default_factory=tuple)

    def missing_fields(self) -> tuple[str, ...]:
        """게이트를 막고 있는 필드 이름들. 비어 있으면 열린다."""
        missing: list[str] = []
        if not self.url:
            missing.append("url")
        if not self.source_version:
            missing.append("source_version")
        if not self.retrieved_at:
            missing.append("retrieved_at")
        if not self.content_hash:
            missing.append("content_hash")
        if not self.reviewed_at:
            missing.append("reviewed_at")
        if not self.reviewed_by:
            missing.append("reviewed_by")
        if set(REQUIRED_LIMITATIONS) - set(self.limitations):
            missing.append("limitations")
        return tuple(missing)

    @property
    def enabled(self) -> bool:
        """이 출처로 연령 맥락 문장을 내보내도 되는가."""
        return not self.missing_fields()


def normalize_for_hash(article_text: str) -> str:
    """본문을 해시 입력 형태로 정규화한다.

    규칙을 코드 한 곳에 둔다 — 문서에만 적어 두면 다음에 해시를 만드는 사람이 다르게 만든다.
    """
    text = article_text.replace("\r\n", "\n").replace("\r", "\n")
    text = re.sub(r"[ \t ]+", " ", text)
    text = "\n".join(line.strip() for line in text.split("\n"))
    text = re.sub(r"\n{2,}", "\n", text)
    return text.strip()


def content_hash_of(article_text: str) -> str:
    """정규화한 본문의 SHA-256(소문자 16진수)."""
    return hashlib.sha256(normalize_for_hash(article_text).encode("utf-8")).hexdigest()


# ─────────────────────────────────────────────────────────────────────────────
# 등록된 공식 자료.
#
# ⚠️ retrieved_at·content_hash 가 비어 있는 것은 **아직 페이지를 가져오지 않았다**는 뜻이다.
#    reviewed_at·reviewed_by 가 비어 있는 것은 **아직 사람이 대조하지 않았다**는 뜻이다.
#    넷을 채우기 전까지 두 출처는 enabled 가 아니고, 6세 연령 맥락 문장은 나가지 않는다.
#    그동안에도 SESSION_ONLY 관찰은 정상으로 나간다 — 6세 리포트가 비지 않는다.
#
# ⚠️ 웹 페이지에 판번호가 없어 source_version 은 WEB_CURRENT 로 둔다. 판을 지어내지 않는다.
# ─────────────────────────────────────────────────────────────────────────────
ASHA_KINDERGARTEN = "ASHA_KINDERGARTEN_COMMUNICATION_WEB"
ASHA_FIRST_GRADE = "ASHA_FIRST_GRADE_COMMUNICATION_WEB"

REGISTRY: dict[str, SourceProvenance] = {
    ASHA_KINDERGARTEN: SourceProvenance(
        source_id=ASHA_KINDERGARTEN,
        document_title="Your Child's Communication: Kindergarten",
        url="https://www.asha.org/public/speech/development/kindergarten/",
        source_type="PROFESSIONAL_GRADE_LEVEL_GUIDANCE",
        locale="en-US",
        limitations=REQUIRED_LIMITATIONS,
        source_version="WEB_CURRENT",
        # 실제로 페이지를 가져온 시각이다. 짐작해 쓰지 않았다.
        retrieved_at="2026-08-08T16:39:24Z",
        # ⚠️ 비어 있다. 본문 원문을 그대로 확보하지 못했다 — 요약을 해싱하면 페이지의 해시가
        #    아니라 요약의 해시가 되고, 그건 이 필드가 하려는 일(원문이 바뀌었는지 알기)을
        #    못 한다. 원문을 받아 :func:`content_hash_of` 에 넣어 채운다.
        content_hash="",
        # ↓ 사람만 채운다. 원문과 아래 한국어 문구를 눈으로 대조한 사실의 기록이다.
        reviewed_at="",
        reviewed_by="",
        supporting_excerpts=(
            "Retell a story or talk about something they did.",
            "Take turns talking and keep a conversation going.",
            "Draw a picture that tells a story. Write about the picture.",
        ),
    ),
    ASHA_FIRST_GRADE: SourceProvenance(
        source_id=ASHA_FIRST_GRADE,
        document_title="Your Child's Communication: First Grade",
        url="https://www.asha.org/public/speech/development/firstgrade/",
        source_type="PROFESSIONAL_GRADE_LEVEL_GUIDANCE",
        locale="en-US",
        limitations=REQUIRED_LIMITATIONS,
        source_version="WEB_CURRENT",
        retrieved_at="2026-08-08T16:39:24Z",
        content_hash="",
        reviewed_at="",
        reviewed_by="",
        supporting_excerpts=(
            "Tell and retell stories that make sense.",
            "Stay on topic and take turns in conversation.",
            "Share their ideas using complete sentences.",
        ),
    ),
}


def is_enabled(source_id: str) -> bool:
    """이 출처로 연령 맥락 문장을 내보내도 되는가. 모르는 출처는 거짓."""
    entry = REGISTRY.get(source_id)
    return entry is not None and entry.enabled


def gate_status() -> dict[str, tuple[str, ...]]:
    """출처마다 무엇이 비어 게이트가 닫혀 있는지. 운영에서 상태를 확인할 때 쓴다."""
    return {source_id: entry.missing_fields() for source_id, entry in REGISTRY.items()}


def _assert_reviewer_is_human() -> None:
    """검수자 자리에 사람이 아닌 것이 들어오지 못하게 한다."""
    for entry in REGISTRY.values():
        if entry.reviewed_by.strip().upper() in _NON_HUMAN_REVIEWERS and entry.reviewed_by:
            raise ValueError(
                f"{entry.source_id}: reviewed_by 에 사람이 아닌 식별자를 쓸 수 없다"
            )


_assert_reviewer_is_human()

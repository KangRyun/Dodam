"""연령 발달 맥락 등록부 — 그림일기 리포트 전용.

그림일기에서 관찰된 표현을 연령에 맞게 설명하되, **한 번의 활동을 발달검사처럼 채점하지
않는다.** 설명 구조는 늘 같다.

    연령 맥락 → 이번 활동에서 확인된 표현 → 이번에 확인하지 못한 부분

⚠️ 이 표의 문장은 검수된 공개 자료(CDC·ASHA)에서만 온다. **LLM 이 일반 지식으로 발달
   규준을 보충하지 않는다** — 어느 항목이 붙을지는 아래 조건으로 서버가 정하고, 모델은
   그 결과를 받아 쓰기만 한다. 모델에게 맡기면 "또래보다 빠르다" 같은 문장이 곧바로 나온다.

⚠️ 만 6세 이상(72개월~)에는 연령 규준을 붙이지 않는다. 세부 이야기 규준을 자동 판정할 만큼
   검수된 한국 연령 규준이 아직 없다 — 이 구간은 '이번 활동 관찰'만 제공한다.

출처 갱신: 연 1회 이상 또는 주요 가이드 변경 시 재검토한다. 문장을 고치면
:data:`REGISTRY_VERSION` 과 :data:`AS_OF` 를 함께 올린다.
"""

from __future__ import annotations

from dataclasses import dataclass, field

REGISTRY_VERSION = "1.0.0"
AS_OF = "2026-08-07"

# 관찰 도메인. 스키마와 같은 이름을 쓴다.
NARRATIVE_LANGUAGE = "NARRATIVE_LANGUAGE"
EMOTION_EXPRESSION = "EMOTION_EXPRESSION"
SOCIAL_UNDERSTANDING = "SOCIAL_UNDERSTANDING"
COPING_HELP_SEEKING = "COPING_HELP_SEEKING"
SELF_REFLECTION = "SELF_REFLECTION"

# 관찰 상태. **무응답·건너뜀·짧은 답은 발달 결함이 아니다** — 확인하지 못한 것으로 적는다.
OBSERVED = "OBSERVED_THIS_SESSION"
PARTIAL = "PARTIALLY_OBSERVED"
NOT_ASSESSED = "NOT_ASSESSED"

# 이번 활동에 한정된 관찰임을 카드마다 함께 내보낸다. 이 문구가 빠지면 한 회차가 발달 평가로
#   읽힌다.
SCOPE_TEXT = "이번 활동에서 확인된 표현이며, 전체 발달 수준을 평가한 결과가 아니에요."

# 자료가 없어 확인하지 못했을 때. '못했다'와 '못한다'는 다르다 — 아이 문제로 읽히지 않게 쓴다.
NOT_ASSESSED_TEXT = "이번 활동에서는 확인할 만한 이야기가 충분하지 않아 살펴보지 않았어요."


@dataclass(frozen=True)
class AgeContext:
    """한 연령 구간의 발달 맥락 한 줄.

    ``age_min_months``/``age_max_months`` 는 양끝을 포함한다. ``source_ids`` 는 검수 출처
    식별자이며, 화면에서 출처를 밝히는 데 쓴다 — 비어 있으면 그 문장은 쓸 수 없다.
    """

    context_id: str
    age_min_months: int
    age_max_months: int
    domain: str
    parent_context: str
    source_ids: tuple[str, ...] = field(default_factory=tuple)


# config/developmental_context_registry.yaml(V4 패키지)과 1:1로 대응한다. 항목을 고칠 때는
#   그 문서의 출처·검토일을 함께 확인한다.
REGISTRY: tuple[AgeContext, ...] = (
    AgeContext(
        context_id="NARRATIVE_4Y_DAILY_EVENT",
        age_min_months=48,
        age_max_months=59,
        domain=NARRATIVE_LANGUAGE,
        parent_context="이 시기에는 하루 중 있었던 한 가지 일을 말로 풀어보는 경험이 늘어갈 수 있어요.",
        source_ids=("CDC_4Y_MILESTONES", "CDC_MILESTONE_LIMITATION"),
    ),
    AgeContext(
        context_id="NARRATIVE_5Y_TWO_EVENTS",
        age_min_months=60,
        age_max_months=71,
        domain=NARRATIVE_LANGUAGE,
        parent_context="이 시기에는 들었거나 만든 이야기를 두 사건 이상으로 이어 말하는 표현이 발달해 가요.",
        source_ids=("CDC_5Y_MILESTONES", "CDC_MILESTONE_LIMITATION"),
    ),
    AgeContext(
        context_id="STORY_CHARACTER_SETTING_4_5",
        age_min_months=48,
        age_max_months=71,
        domain=SOCIAL_UNDERSTANDING,
        parent_context="이 시기에는 이야기 속 인물과 장소를 함께 말하는 표현이 늘어갈 수 있어요.",
        source_ids=("ASHA_COMM_4_5", "CDC_MILESTONE_LIMITATION"),
    ),
)

# 만 6세 이상. 연령 규준 대신 '이번 활동 관찰'만 제공한다.
SCHOOL_AGE_MIN_MONTHS = 72
SCHOOL_AGE_CONTEXT = AgeContext(
    context_id="SCHOOL_AGE_OBSERVATION_ONLY",
    age_min_months=SCHOOL_AGE_MIN_MONTHS,
    age_max_months=155,
    domain=NARRATIVE_LANGUAGE,
    parent_context="이 나이대는 이번 활동에서 확인된 표현만 적어요. 또래와 견주거나 발달 수준을 판단하지 않아요.",
    source_ids=("AAP_SURVEILLANCE",),
)

# 연령 규준이 없어도 이번 활동에서 볼 수 있는 것들. 도메인마다 문장이 다르다.
#
# ⚠️ 모든 도메인에 한 줄씩 있어야 한다. 빠진 도메인은 나이를 모를 때 **화면에서 통째로
#    사라진다** — 규준을 붙이지 않는 것과 관찰 자체를 지우는 것은 다르다.
_SESSION_ONLY_CONTEXT = {
    NARRATIVE_LANGUAGE: "있었던 일을 어디까지 이어 말했는지 이번 활동에서만 살펴봐요.",
    EMOTION_EXPRESSION: "감정을 말이나 선택으로 표현했는지 이번 활동에서만 살펴봐요.",
    SOCIAL_UNDERSTANDING: "함께 있던 사람의 행동이나 반응을 이야기했는지 이번 활동에서만 살펴봐요.",
    COPING_HELP_SEEKING: "어려운 일이 있었을 때 어떻게 했는지 이번 활동에서만 살펴봐요.",
    SELF_REFLECTION: "바라는 것이나 이유를 말했는지 이번 활동에서만 살펴봐요.",
}


def months_from_years(child_age: int | None) -> int | None:
    """계약이 주는 나이(년)를 개월로 바꾼다. 나이가 없으면 ``None``.

    ⚠️ 생일이 없어 개월 단위 정밀도가 없다. 연 단위를 그대로 12배 하므로 구간 경계에서
       한 해가 통째로 움직인다 — 그래서 이 값은 **어떤 맥락 문장을 붙일지 고르는 데만** 쓰고,
       발달 판정이나 또래 비교에는 절대 쓰지 않는다.
    """
    if child_age is None or child_age < 0:
        return None
    return child_age * 12


def contexts_for(child_age: int | None, domain: str) -> AgeContext | None:
    """이 나이·도메인에 붙일 수 있는 맥락 한 줄. 없으면 ``None``.

    나이를 모르면 아무 맥락도 붙이지 않는다 — 짐작해 붙이는 순간 지어낸 규준이 된다.
    """
    months = months_from_years(child_age)
    if months is None:
        return None
    if months >= SCHOOL_AGE_MIN_MONTHS:
        # 학령기는 규준 대신 '이번 활동 관찰만'을 명시한다.
        return SCHOOL_AGE_CONTEXT
    for entry in REGISTRY:
        if entry.domain == domain and entry.age_min_months <= months <= entry.age_max_months:
            return entry
    return None


def session_only_context(domain: str) -> str | None:
    """연령 규준이 없는 도메인에서 쓸 '이번 활동만 본다'는 문장."""
    return _SESSION_ONLY_CONTEXT.get(domain)

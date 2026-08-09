"""연령 발달 맥락 등록부 — 그림일기 리포트 전용.

그림일기에서 관찰된 표현을 연령에 맞게 설명하되, **한 번의 활동을 발달검사처럼 채점하지
않는다.** 설명 구조는 늘 같다.

    연령 맥락 → 이번 활동에서 확인된 표현 → 이번에 확인하지 못한 부분

⚠️ 이 표의 문장은 검수된 공개 자료(CDC·ASHA)에서만 온다. **LLM 이 일반 지식으로 발달
   규준을 보충하지 않는다** — 어느 항목이 붙을지는 아래 조건으로 서버가 정하고, 모델은
   그 결과를 받아 쓰기만 한다. 모델에게 맡기면 "또래보다 빠르다" 같은 문장이 곧바로 나온다.

⚠️ 만 6세(72~83개월)에는 연령 규준을 붙이지 않는다. 검수된 한국 6세 규준이 아직 없다.
   대신 학령 초기 참고 맥락(EARLY_SCHOOL_COMMUNICATION_CONTEXT)을 붙인다 — 규준을 주장하지
   않으므로 출처를 달지 않는다. 만 7세 이상은 참고 맥락도 없이 "이번 활동 관찰"만 제공한다.

출처 갱신: 연 1회 이상 또는 주요 가이드 변경 시 재검토한다. 문장을 고치면
:data:`REGISTRY_VERSION` 과 :data:`AS_OF` 를 함께 올린다.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from developmental_sources import ASHA_FIRST_GRADE, ASHA_KINDERGARTEN, is_enabled

REGISTRY_VERSION = "2.0.0"
AS_OF = "2026-08-08"

# 관찰 도메인. 스키마와 같은 이름을 쓴다.
NARRATIVE_LANGUAGE = "NARRATIVE_LANGUAGE"
EMOTION_EXPRESSION = "EMOTION_EXPRESSION"
SOCIAL_UNDERSTANDING = "SOCIAL_UNDERSTANDING"
COPING_HELP_SEEKING = "COPING_HELP_SEEKING"
SELF_REFLECTION = "SELF_REFLECTION"
# 2.0.0 에서 늘린 둘. 기존 다섯의 이름은 바꾸지 않았다 — 저장 행이
#   UNIQUE(report_id, domain) 로 묶여 있어 개명하면 지난 리포트의 카드가 고아가 된다.
CONVERSATION_PARTICIPATION = "CONVERSATION_PARTICIPATION"
DRAWING_LANGUAGE_INTEGRATION = "DRAWING_LANGUAGE_INTEGRATION"

# 맥락 문장이 무엇을 주장하는지 값으로 구분한다.
#
#   AGE_MILESTONE_CONTEXT               검수된 연령 이정표. 출처가 반드시 있다.
#   EARLY_SCHOOL_COMMUNICATION_CONTEXT  학령 초기 참고 맥락. **연령 규준이 아니다.**
#   SESSION_ONLY_CONTEXT                규준을 주장하지 않고 이번 활동만 본다.
#
# 이걸 문자열 대신 값으로 두는 이유는, 화면과 로그가 "규준"과 "참고 맥락"을 섞지 않게 하려는
#   것이다. 문구만으로 구분하면 문구를 다듬는 순간 구분이 사라진다.
AGE_MILESTONE_CONTEXT = "AGE_MILESTONE_CONTEXT"
EARLY_SCHOOL_COMMUNICATION_CONTEXT = "EARLY_SCHOOL_COMMUNICATION_CONTEXT"
SESSION_ONLY_CONTEXT = "SESSION_ONLY_CONTEXT"

# 발달 맥락 문장에 절대 들어가면 안 되는 표현. import 시점에 막는다.
#
# ⚠️ 문장을 나중에 누가 고쳐도 이 검사는 남는다. 4층의 위험은 "또래보다 빠르다"가 한 번
#    섞이는 것이고, 그건 리뷰보다 코드가 막는 편이 확실하다.
_FORBIDDEN_PHRASES = ("규준", "또래", "정상 발달", "발달 수준이", "지연", "충족")

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

    ``age_min_months``/``age_max_months`` 는 양끝을 포함한다.

    ``source_ids`` 는 검수 출처 식별자다. **비는 것이 정상인 경우가 있다** — 연령 이정표를
    주장하는 문장(``AGE_MILESTONE_CONTEXT``)은 출처가 반드시 있어야 하지만, 규준을 주장하지
    않는 문장(``EARLY_SCHOOL_COMMUNICATION_CONTEXT``·``SESSION_ONLY_CONTEXT``)은 출처가
    없다. 그 짝이 어긋나면 :func:`_assert_registry_is_safe` 가 import 시점에 막는다.
    """

    context_id: str
    age_min_months: int
    age_max_months: int
    domain: str
    parent_context: str
    source_ids: tuple[str, ...] = field(default_factory=tuple)
    context_type: str = "AGE_MILESTONE_CONTEXT"
    # 이 항목을 쓸 수 있는 교육단계. 비어 있으면 교육단계를 보지 않는다(4~5세 연령 이정표).
    education_stages: tuple[str, ...] = field(default_factory=tuple)


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
    AgeContext(
        context_id="CONVERSATION_4Y_SIMPLE_ANSWER",
        age_min_months=48,
        age_max_months=59,
        domain=CONVERSATION_PARTICIPATION,
        parent_context="이 시기에는 간단한 질문에 답하며 이야기를 주고받는 경험이 늘어갈 수 있어요.",
        source_ids=("ASHA_COMM_4_5", "CDC_MILESTONE_LIMITATION"),
    ),
    AgeContext(
        context_id="CONVERSATION_5Y_MULTI_TURN",
        age_min_months=60,
        age_max_months=71,
        domain=CONVERSATION_PARTICIPATION,
        parent_context="이 시기에는 질문과 답을 여러 차례 이어가는 표현이 발달해 가요.",
        source_ids=("ASHA_COMM_4_5", "CDC_MILESTONE_LIMITATION"),
    ),
    AgeContext(
        context_id="DRAWING_STORY_5Y_LINK",
        age_min_months=60,
        age_max_months=71,
        domain=DRAWING_LANGUAGE_INTEGRATION,
        parent_context="이 시기에는 그림에 담은 장면을 말로 이어 설명하는 표현이 발달해 가요.",
        source_ids=("ASHA_COMM_4_5", "CDC_MILESTONE_LIMITATION"),
    ),
)

# 만 6세(72~83개월) — 학령 초기 참고 맥락.
#
# ⚠️ **연령 규준도 표준화 이정표도 아니다.** 자동 판정할 만큼 검수된 한국 6세 규준은 여전히
#    없다. 그래서 이 문장들은 "이 나이에 이래야 한다"가 아니라 "학령 초기에는 이런 표현이
#    넓어질 수 있다"고만 말한다.
#
# ⚠️ ``source_ids`` 가 비어 있는 것이 **의도**다. 규준을 주장하지 않는 문장이라 출처를 달 수
#    없고, 달면 없는 근거를 있는 것처럼 보이게 한다. 계약도 "출처 없는 것이 정상"인 경우를
#    이미 인정한다. ASHA Kindergarten 자료의 판·검토일이 확정되면 그때 달면 된다.
#
# ⚠️ 5세 문장을 여기에 재사용하지 않는다. 범위만 늘리면 5세 규준을 6세에 적용하는 것이 되고,
#    그건 사실이 아니다.
EARLY_SCHOOL_MIN_MONTHS = 72
EARLY_SCHOOL_MAX_MONTHS = 83

# 어느 교육단계에서 쓸 수 있는 항목인지. **PRESCHOOL·NULL 은 어디에도 없다** — 나이만 맞다고
#   유치원 자료를 적용하면 어린이집에 다니는 아이에게 학년 자료를 씌우는 것이 된다.
_KINDERGARTEN_ONLY = ("KINDERGARTEN",)
_GRADE_1_ONLY = ("GRADE_1",)
_BOTH_SCHOOL_STAGES = ("KINDERGARTEN", "GRADE_1")

EARLY_SCHOOL_REGISTRY: tuple[AgeContext, ...] = (
    AgeContext(
        context_id="EARLY_SCHOOL_EXPERIENCE_RETELL",
        age_min_months=EARLY_SCHOOL_MIN_MONTHS,
        age_max_months=EARLY_SCHOOL_MAX_MONTHS,
        domain=NARRATIVE_LANGUAGE,
        parent_context="학령 초기에는 자신이 한 일을 다시 말하는 표현이 넓어질 수 있어요.",
        context_type=EARLY_SCHOOL_COMMUNICATION_CONTEXT,
        source_ids=(ASHA_KINDERGARTEN, ASHA_FIRST_GRADE),
        education_stages=_BOTH_SCHOOL_STAGES,
    ),
    AgeContext(
        context_id="EARLY_SCHOOL_CONVERSATION_MAINTENANCE",
        age_min_months=EARLY_SCHOOL_MIN_MONTHS,
        age_max_months=EARLY_SCHOOL_MAX_MONTHS,
        domain=CONVERSATION_PARTICIPATION,
        parent_context="학령 초기에는 대화를 주고받으며 같은 주제를 이어가는 표현이 넓어질 수 있어요.",
        context_type=EARLY_SCHOOL_COMMUNICATION_CONTEXT,
        source_ids=(ASHA_KINDERGARTEN, ASHA_FIRST_GRADE),
        education_stages=_BOTH_SCHOOL_STAGES,
    ),
    AgeContext(
        context_id="EARLY_SCHOOL_DRAWING_STORY_LINK",
        age_min_months=EARLY_SCHOOL_MIN_MONTHS,
        age_max_months=EARLY_SCHOOL_MAX_MONTHS,
        domain=DRAWING_LANGUAGE_INTEGRATION,
        parent_context="그림에 담은 장면을 말이나 글자로 연결해 표현하는 경험이 넓어질 수 있어요.",
        context_type=EARLY_SCHOOL_COMMUNICATION_CONTEXT,
        # 그림-이야기 연결은 Kindergarten 자료에만 있다. First Grade 에서는 SESSION_ONLY 로만 본다.
        source_ids=(ASHA_KINDERGARTEN,),
        education_stages=_KINDERGARTEN_ONLY,
    ),
)

# ⚠️ EARLY_SCHOOL_STORY_COMPONENTS 는 여기 없다. 인물·장소·사건·행동·결과 설명은
#    **연령 규준을 붙이지 않고** SESSION_ONLY 로만 관찰한다. 도메인도 SOCIAL_UNDERSTANDING 이
#    아니라 NARRATIVE_LANGUAGE 다 — 이야기의 구성 요소를 말한 것이지, 다른 사람의 마음을
#    이야기한 것이 아니다. SOCIAL_UNDERSTANDING 은 아이가 **다른 사람의 행동·반응·생각**을
#    직접 이야기했을 때만 쓴다.
STORY_COMPONENTS_SESSION_ONLY = (
    "인물·장소·사건·행동·결과를 어떻게 이어 설명했는지 이번 활동에서만 살펴봐요."
)

# 만 7세 이상. 참고 맥락도 붙이지 않고 '이번 활동 관찰'만 제공한다.
SCHOOL_AGE_MIN_MONTHS = 84
SCHOOL_AGE_CONTEXT = AgeContext(
    context_id="SCHOOL_AGE_OBSERVATION_ONLY",
    age_min_months=SCHOOL_AGE_MIN_MONTHS,
    age_max_months=155,
    domain=NARRATIVE_LANGUAGE,
    parent_context="이 나이대는 이번 활동에서 확인된 표현만 적어요.",
    context_type=SESSION_ONLY_CONTEXT,
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
    CONVERSATION_PARTICIPATION: "질문과 답을 어떻게 주고받았는지 이번 활동에서만 살펴봐요.",
    DRAWING_LANGUAGE_INTEGRATION: "그림에 담은 것을 말로 어떻게 이었는지 이번 활동에서만 살펴봐요.",
}

# 교육 단계. 프로필에 있으면 6세 문구를 고르는 데 함께 본다.
#
# ⚠️ 없으면 "학령 초기"라는 일반 표현만 쓴다. 나이만으로 학년을 확정하면 조기 입학·유예를
#    틀리게 단정한다.
EDUCATION_STAGES = ("PRESCHOOL", "KINDERGARTEN", "GRADE_1")


def _assert_registry_is_safe() -> None:
    """등록부가 스스로 지켜야 할 것을 import 시점에 확인한다.

    리뷰가 아니라 코드가 막는다 — 문장을 고치는 사람이 이 파일만 보고도 걸리게.
    """
    for entry in (*REGISTRY, *EARLY_SCHOOL_REGISTRY, SCHOOL_AGE_CONTEXT):
        for phrase in _FORBIDDEN_PHRASES:
            if phrase in entry.parent_context:
                raise ValueError(
                    f"{entry.context_id}: 발달 맥락 문장에 '{phrase}' 를 쓸 수 없다"
                )
        # 규준을 주장하는 문장에는 출처가 반드시 있어야 한다. SESSION_ONLY 는 주장하지 않아
        #   출처가 없는 것이 정상이다 — 달면 없는 근거를 있는 것처럼 보이게 한다.
        if entry.context_type == SESSION_ONLY_CONTEXT and entry.source_ids:
            raise ValueError(
                f"{entry.context_id}: 규준을 주장하지 않는 문장에 출처를 달 수 없다"
            )
        if entry.context_type != SESSION_ONLY_CONTEXT and not entry.source_ids:
            raise ValueError(f"{entry.context_id}: 규준 문장에는 검수 출처가 필요하다")
        # 학령 초기 항목은 어느 교육단계에서 쓰는지 밝혀야 한다. 비면 나이만으로 붙게 된다.
        if entry.context_type == EARLY_SCHOOL_COMMUNICATION_CONTEXT:
            if not entry.education_stages:
                raise ValueError(f"{entry.context_id}: 학령 초기 항목에는 교육단계가 필요하다")
            if "PRESCHOOL" in entry.education_stages:
                raise ValueError(
                    f"{entry.context_id}: PRESCHOOL 에 학년 자료를 적용할 수 없다"
                )
    # 4~5세 연령 이정표가 72개월 이상으로 새지 않는지. 범위 단순 연장을 막는다.
    for entry in REGISTRY:
        if entry.age_max_months >= EARLY_SCHOOL_MIN_MONTHS:
            raise ValueError(
                f"{entry.context_id}: 연령 이정표를 {EARLY_SCHOOL_MIN_MONTHS}개월 이상에 쓸 수 없다"
            )


_assert_registry_is_safe()


# ⚠️ months_from_years 를 없앴다(2.0.0). 연 × 12 는 구간 경계에서 한 해가 통째로 움직여
#    72~83개월 같은 한 해 안의 구간을 가를 수 없었다. BE 가 birth_date 로 계산한 개월을 보낸다.


def contexts_for(
    domain: str,
    *,
    age_months: int | None,
    education_stage: str | None = None,
) -> AgeContext | None:
    """이 나이·도메인에 붙일 수 있는 맥락 한 줄. 없으면 ``None``.

    나이를 모르면 아무 맥락도 붙이지 않는다 — 짐작해 붙이는 순간 지어낸 규준이 된다.

    ``age_months`` 는 BE 가 ``birth_date`` 로 계산해 보낸 값이다. 연 단위를 12배 하던 방식은
    없앴다 — 구간 경계에서 한 해가 통째로 움직여 72~83개월을 가를 수 없었다.
    """
    months = age_months
    if months is None or months < 0:
        return None
    if months >= SCHOOL_AGE_MIN_MONTHS:
        # 만 7세 이상은 참고 맥락도 붙이지 않고 '이번 활동 관찰만'을 명시한다.
        return SCHOOL_AGE_CONTEXT
    if months >= EARLY_SCHOOL_MIN_MONTHS:
        return _early_school_context(domain, education_stage)
    for entry in REGISTRY:
        if entry.domain == domain and entry.age_min_months <= months <= entry.age_max_months:
            return entry
    return None


def _early_school_context(domain: str, education_stage: str | None) -> AgeContext | None:
    """만 6세 구간의 맥락. 조건이 하나라도 안 맞으면 ``None`` — 그러면 SESSION_ONLY 로 간다.

    막는 것이 셋이다.

      교육단계   ``PRESCHOOL`` 과 미입력은 어떤 학년 자료도 적용하지 않는다. 나이만 맞다고
                유치원 자료를 씌우면 어린이집에 다니는 아이에게 학년 기준을 적용하는 것이 된다.
      출처 게이트 사람이 원문과 한국어 문구를 대조하기 전에는 그 문장을 내보내지 않는다.
      도메인     등록되지 않은 도메인에는 아무것도 붙이지 않는다.
    """
    if education_stage not in _BOTH_SCHOOL_STAGES:
        return None
    for entry in EARLY_SCHOOL_REGISTRY:
        if entry.domain != domain or education_stage not in entry.education_stages:
            continue
        # 이 단계에서 실제로 쓸 수 있는 출처만 남긴다.
        usable = tuple(source for source in entry.source_ids if is_enabled(source))
        if not usable:
            return None
        return AgeContext(
            context_id=entry.context_id,
            age_min_months=entry.age_min_months,
            age_max_months=entry.age_max_months,
            domain=entry.domain,
            parent_context=entry.parent_context,
            source_ids=usable,
            context_type=entry.context_type,
            education_stages=entry.education_stages,
        )
    return None


def months_from_birth_date(birth_date: str | None, as_of: str | None) -> int | None:
    """생일과 기준일로 만 나이를 개월로 계산한다. 둘 중 하나라도 없으면 ``None``.

    ``date`` 를 쓰지 않고 문자열을 파싱하는 이유는 계약이 ISO 문자열로 오기 때문이다.
    형식이 어긋나면 짐작하지 않고 ``None`` 을 돌려준다.
    """
    from datetime import date

    def _parse(value: str | None) -> date | None:
        if not value:
            return None
        try:
            return date.fromisoformat(value[:10])
        except ValueError:
            return None

    born, today = _parse(birth_date), _parse(as_of)
    if born is None or today is None or today < born:
        return None
    months = (today.year - born.year) * 12 + (today.month - born.month)
    if today.day < born.day:
        months -= 1
    return max(0, months)


def session_only_context(domain: str) -> str | None:
    """연령 규준이 없는 도메인에서 쓸 '이번 활동만 본다'는 문장."""
    return _SESSION_ONLY_CONTEXT.get(domain)

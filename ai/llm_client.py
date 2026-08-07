"""GMS 대화 LLM 클라이언트 + 질문 생성.

GMS는 OpenAI 호환 게이트웨이라, 공식 `openai` SDK에 base_url만 GMS로 주면 그대로 동작한다.

- chat(): 배선 — messages를 받아 호출하고 응답 텍스트를 돌려준다.
- first_question() / next_question(): ai/prompts/ 템플릿을 채워 아이에게 건넬 말을 받아온다.
  프롬프트 문구 자체는 코드가 아니라 ai/prompts/*.txt에 있다 — 문구만 고칠 땐 txt만 고치면 된다.

흐름:
    그림분석 → first_question()            → 첫 질문
    아이 발화 → next_question(history=...) → 다음 말

가드레일:
- 키는 로그로 남기지 않는다.
- messages에는 아이 발화가 들어올 수 있으므로, 실패 로그에도 원본 내용을 남기지 않는다(에러 유형만).
"""

from __future__ import annotations

import logging
import re
from functools import lru_cache

from openai import OpenAIError

import answer_check  # 생성 답변 사후 검사(LLM 재호출 없이 규칙 기반)
import config
import prompts_registry  # 프롬프트 파일 로딩·버전 관리 중앙화 (S15P11B209-595)
from gms import get_client  # GMS(OpenAI 호환) 공용 클라이언트

logger = logging.getLogger(__name__)

# ── 활동 유형별 대화 프롬프트 (S15P11B209-786) ──────────────────
# 하나의 first_question/conversations로 두 활동을 처리하던 것을 갈랐다. 대화의 '목적'이
# 다르기 때문이다 — 같은 문장으로 두 목적을 시키면 어느 쪽도 제대로 안 된다:
#   - HTP: 그림 자체가 궁금하다. 아이가 그림에 무엇을 담으려 했는지 그림 안에서 좁혀 간다.
#   - ART_DIARY: 그림 속 이야기에서 시작해 실제 경험인지 상상인지 확인한 뒤 그 흐름과 마음으로 넓혀 간다.
# 기반 규칙(목적·이름·분석결과 취급·태도·출력 형식)과 연령별 말투도 활동별 파일이 소유한다.
# 공용 파일(conversation_common·conversation_tone)은 2026-08-07 없앴다(사용자 결정, S15P11B209-993) —
# 한 활동에 맞춘 수정이 다른 활동을 망치는 경로(939·954)를 구조에서 제거한다.
# 활동 간에 남은 공유 파일은 guardrails 하나다. 아동 안전 금지 목록이라 두 벌로 가르면
# 어긋난 채 조용히 벌어진다 — 활동별 '로직'이 아니라 활동 무관 안전 문구라 예외로 남긴다.
_FIRST_BY_ACTIVITY = {
    "HTP": "first_question_htp",
    "ART_DIARY": "first_question_diary",
}
_NEXT_BY_ACTIVITY = {
    "HTP": "conversations_htp",
    "ART_DIARY": "conversations_diary",
}
_RULES_BY_ACTIVITY = {
    "HTP": "conversation_rules_htp",
    "ART_DIARY": "conversation_rules_diary",
}
_TONE_BY_ACTIVITY = {
    "HTP": "conversation_tone_htp",
    "ART_DIARY": "conversation_tone_diary",
}
# 활동 유형을 못 받은 호출(draft 경로·구 BE)은 HTP로 본다 — vlm_client.DEFAULT_ACTIVITY_TYPE과 같은 기준.
DEFAULT_ACTIVITY_TYPE = "HTP"

_GUARDRAILS = "guardrails"
# HTP 주제별 질문 뱅크(S15P11B209-811). 표준 사후질문(PDI)을 아동용으로 포장한 목록이며,
# 현재 주제 구획 하나만 싣는다. 그림일기는 쓰지 않는다 — PDI는 HTP 전용 프로토콜이다.
_HTP_BANK = "htp_question_bank"
# 활동·주제·대상 지시 블록(S15P11B209-832 이관 · 993 활동별 분리). question_service가
# 구획을 골라 조립해 대화 프롬프트에 끼워 넣는다. 원래 코드 안 문자열이라 버전 추적 밖이었다.
_ACTIVITY_BLOCK_BY_ACTIVITY = {
    "HTP": "activity_block_htp",
    "ART_DIARY": "activity_block_diary",
}

# 대화 경로가 쓰는 프롬프트 파일 전체의 통합 버전(내용이 바뀌면 자동으로 달라진다) — S15P11B209-595.
# 축약 태그로 싣는다(S15P11B209-819) — 대화 경로는 파일이 여섯 개라 정본이 193자다. BE가 아직
# promptVersion을 저장하지 않아 리포트 경로처럼 터지지 않았을 뿐, 저장을 시작하면 같은 사고가 난다.
_ALL_NAMES = (
    *_FIRST_BY_ACTIVITY.values(),
    *_NEXT_BY_ACTIVITY.values(),
    *_RULES_BY_ACTIVITY.values(),
    *_TONE_BY_ACTIVITY.values(),
    *_ACTIVITY_BLOCK_BY_ACTIVITY.values(),
    _GUARDRAILS,
    _HTP_BANK,
)
PROMPT_VERSION = prompts_registry.short_version("conv-all", *_ALL_NAMES)

# 라벨은 저장 태그에 그대로 실리는 고정 어휘 — 활동 변형이 태그만으로 구분돼야 한다(786).
_LABEL_BY_ACTIVITY = {"HTP": "conv-htp", "ART_DIARY": "conv-diary"}


def prompt_names_for(activity_type: str | None) -> tuple[str, ...]:
    """이 활동 유형이 실제로 쓰는 프롬프트 파일 이름들. 모르는 값은 기본(HTP)으로 둔다.

    _ACTIVITY_BLOCK도 포함한다(S15P11B209-832) — 내부 계약 경로(question_service)가 활동·주제·
    대상 지시를 이 파일에서 조립해 끼워 넣으므로, 문구가 바뀌면 promptVersion이 움직여야 한다.
    draft 경로는 activity_block을 비워 보내지만, 이 값은 '이 경로가 쓸 수 있는 파일 조합'이라
    양쪽을 같은 태그로 둔다 — 경로별로 태그를 갈라 두면 같은 프롬프트에 두 버전이 생긴다.
    """
    key = activity_type if activity_type in _FIRST_BY_ACTIVITY else DEFAULT_ACTIVITY_TYPE
    names = (
        _FIRST_BY_ACTIVITY[key],
        _NEXT_BY_ACTIVITY[key],
        _RULES_BY_ACTIVITY[key],
        _TONE_BY_ACTIVITY[key],
        _ACTIVITY_BLOCK_BY_ACTIVITY[key],
        _GUARDRAILS,
    )
    return names + (_HTP_BANK,) if key == "HTP" else names


def prompt_version_for(activity_type: str | None) -> str:
    """이번 활동이 '실제로 쓴' 프롬프트 조합의 버전 — 결과 재현·추적용.

    두 활동 변형을 모두 적으면 어느 쪽으로 뽑힌 결과인지 사후에 구분할 수 없다
    (report_client._generation_version과 같은 이유).

    정본은 version_manifest()로 되짚는다(S15P11B209-819).
    """
    key = activity_type if activity_type in _LABEL_BY_ACTIVITY else DEFAULT_ACTIVITY_TYPE
    return prompts_registry.short_version(
        _LABEL_BY_ACTIVITY[key], *prompt_names_for(activity_type)
    )


def version_manifest() -> dict[str, str]:
    """축약 태그 → 정본 조합 버전 — 저장된 다이제스트를 되짚는 수단(S15P11B209-819)."""
    manifest = {
        PROMPT_VERSION: prompts_registry.composite_version(*_ALL_NAMES),
    }
    for activity in _LABEL_BY_ACTIVITY:
        manifest[prompt_version_for(activity)] = prompts_registry.composite_version(
            *prompt_names_for(activity)
        )
    return manifest

# 캐릭터 이름. 프롬프트 txt에도 '도담'으로 적혀 있으니 바꾸려면 양쪽을 같이 고칠 것.
CHARACTER_NAME = "도담"

# 그림분석이 아직 없을 때 템플릿에 넣을 문구(템플릿 규칙상 "오늘은 뭘 그렸어?"로 유도됨).
NO_ANALYSIS = "(아직 그림 분석 결과가 없어요)"

# 아이 이름을 모를 때. 템플릿의 '이름 규칙'이 이걸 보고 "너"로 부르게 한다.
NO_CHILD_NAME = "(이름은 아직 몰라요)"

# draft 경로 기본 연령대. 난이도를 안 넘기면 말투가 DEFAULT_DIFFICULTY(=LOWER_ELEMENTARY,
# 초등 저학년형 만 7~9세)로 떨어지므로 같은 구간으로 맞춘다 — 프롬프트 첫 줄의 나이와
# 말투 블록의 연령대가 어긋나면 모델이 둘을 조율해야 한다.
# 내부 계약 경로는 요청의 childAge·difficulty를 그대로 쓴다(둘 다 BE가 정한다).
DEFAULT_AGE_BAND = "7~9"

# _ask에 넘기는 짧은 트리거(system 하나로 맥락은 충분하지만 chat 모델은 user 1건이 필요하다).
# 내부 계약 경로(question_service)도 같은 프롬프트를 재사용하도록 상수로 공개한다.
FIRST_QUESTION_TRIGGER = "아이에게 건넬 첫 질문을 해줘."
NEXT_QUESTION_TRIGGER = "아이에게 건넬 다음 말을 해줘."


def chat(
    messages: list[dict],
    *,
    model: str | None = None,
    temperature: float = 0.6,
) -> str:
    """대화 LLM 호출. OpenAI 형식 messages를 받아 응답 텍스트를 반환한다.

    Args:
        messages: [{"role": "system"|"user"|"assistant", "content": str}, ...]
        model: 미지정 시 config.LLM_MODEL.
        temperature: 창의성(0~2). 아동 대화는 튀지 않게 다소 낮게(기본 0.6).

    Returns:
        모델 응답 텍스트(빈 응답이면 "").

    Raises:
        RuntimeError: GMS 호출 실패 시(원본 내용은 감추고 에러 유형만 로그).
    """
    used_model = model or config.LLM_MODEL
    try:
        resp = get_client().chat.completions.create(
            model=used_model,
            messages=messages,
            temperature=temperature,
        )
    except OpenAIError as e:
        # ⚠️ messages(아이 발화 포함 가능)를 로그에 남기지 않는다 — 에러 유형만.
        logger.error("GMS chat 호출 실패: %s", type(e).__name__)
        raise RuntimeError("대화 생성에 실패했어요(GMS).") from e

    return resp.choices[0].message.content or ""


# ── 프롬프트 로딩 / 렌더링 ──────────────────────────────────────


def _load(name: str) -> str:
    """프롬프트 로딩은 prompts_registry로 중앙화했다(S15P11B209-595)."""
    return prompts_registry.load(name)


# ── 연령(난이도)별 말하기 규칙 (S15P11B209-786) ──────────────────
# 구조: 활동별 tone 파일 안에 [[PRESCHOOL]] 같은 머리표로 난이도별 구획을 두고, 그중
# 하나만 골라 싣는다. 한 파일에 네 단계를 모아 둬야 어휘·길이 균형을 나란히 볼 수 있고,
# 활동별로 파일을 가른 것(993)은 난이도 축과 활동 축이 서로를 밟지 않게 하기 위해서다 —
# 공용 tone의 "이유를 물어도 된다"가 HTP의 왜·이유·까닭 금지와 충돌하던 것이 실제 사례다.
# ⚠️ 이 규칙은 원래 question_service._DIFFICULTY_RULES 코드 상수였다. 프롬프트 파일로 옮긴 이유:
#   ① 아이에게 그대로 들려줄 문구인데 prompts_registry 버전 추적 밖에 있었다,
#   ② draft 경로(first_question/next_question)에는 아예 안 붙어 연령별 말투가 없었다.
# 알 수 없는 난이도가 오면 저학년 기준으로 둔다(요청은 계약상 검증되지만 방어적으로).
DEFAULT_DIFFICULTY = "LOWER_ELEMENTARY"

TONE_BLOCK_TITLE = "[연령별 말하기 규칙]"
BANK_BLOCK_TITLE = "[이 주제에서 궁금해할 것]"

# [[KEY]] 파싱은 prompts_registry가 소유한다(S15P11B209-832) — question_service의 활동 블록도
# 같은 규약을 쓰게 되면서 private 함수를 여럿이 들여다보는 모양이 됐다.
_sections = prompts_registry.sections


def _tone_sections(activity_type: str | None = None) -> dict[str, str]:
    key = activity_type if activity_type in _TONE_BY_ACTIVITY else DEFAULT_ACTIVITY_TYPE
    return _sections(_TONE_BY_ACTIVITY[key])


def tone_block(difficulty: str | None, activity_type: str | None = None) -> str:
    """난이도에 맞는 길이·어휘·말투 규칙 블록. 대화 프롬프트 뒤에 덧붙는다.

    활동별 tone 파일에서 고른다(993) — 모르는 활동은 기본(HTP)으로 둔다.
    """
    sections = _tone_sections(activity_type)
    body = sections.get(difficulty or "") or sections[DEFAULT_DIFFICULTY]
    return f"{TONE_BLOCK_TITLE}\n{body}"


def question_bank_block(activity_type: str | None, subject: str | None) -> str:
    """HTP 현재 주제의 질문 뱅크 블록(S15P11B209-811). 해당 없으면 빈 문자열.

    - 그림일기는 싣지 않는다 — PDI는 HTP 전용 프로토콜이다.
    - 주제를 모르면(구 BE·주제 미전달) 싣지 않는다. 세 주제를 다 실으면 다른 주제로 새는
      709 계열이 다시 열리므로, 확실할 때만 하나를 싣는다.
    """
    if activity_type != "HTP":
        return ""
    body = _sections(_HTP_BANK).get(subject or "")
    return f"{BANK_BLOCK_TITLE}\n{body}" if body else ""


def _assemble(
    variant: str,
    *,
    activity_block: str,
    difficulty: str | None,
    question_bank: str = "",
    activity_type: str | None = None,
) -> str:
    """대화 system 프롬프트 조립 — 변형 → 질문 뱅크 → 활동 지시 → 가드레일 → 말투 → 기반 규칙.

    말투와 기반 규칙도 활동별 파일에서 고른다(993 — 공용 제거).
    순서 근거: 변형이 앞(역할·대화 목표·재료 블록)이라 모델이 먼저 '무슨 대화인지'를 잡고,
    기반 규칙이 맨 뒤(이름 규칙·출력 형식)라 형식 지시를 놓치지 않는다. 말투는 기반 규칙의
    "문장 수·길이는 [연령별 말하기 규칙]이 정한다"가 가리키는 대상이라 바로 앞에 둔다.
    질문 뱅크는 '무엇을 물을지'(방향)라 '지금 이것만 물어라'(activity_block)보다 앞에 둔다 —
    뒤에 오는 활동 지시가 뱅크에서 고른 방향을 현재 대상으로 좁히는 순서가 된다.
    """
    rules_key = (
        activity_type if activity_type in _RULES_BY_ACTIVITY else DEFAULT_ACTIVITY_TYPE
    )
    parts = [variant]
    if question_bank:
        parts.append(question_bank)
    if activity_block:
        parts.append(activity_block)
    parts += [
        _load(_GUARDRAILS),
        tone_block(difficulty, activity_type),
        _load(_RULES_BY_ACTIVITY[rules_key]),
    ]
    return "\n\n".join(parts)


def _format_history(history: list[dict] | None) -> str:
    """대화 이력을 템플릿에 넣을 여러 줄 텍스트로 만든다.

    Args:
        history: [{"role": "assistant"|"user", "content": str}, ...] 순서대로.
                 role은 OpenAI 형식을 그대로 쓴다(assistant=도담, user=아이).

    Returns:
        "도담: ...\n아이: ..." 형태. 이력이 없으면 안내 문구.
        (라벨이 아이 이름으로 오해되지 않도록 템플릿의 '이름 규칙'이 짝을 이룬다.)
    """
    if not history:
        return "(아직 나눈 대화가 없어요)"

    lines = []
    for turn in history:
        speaker = "아이" if turn.get("role") == "user" else CHARACTER_NAME
        lines.append(f"{speaker}: {turn.get('content', '')}")
    return "\n".join(lines)


def _ask(system_prompt: str, trigger: str, *, temperature: float) -> str:
    """렌더링된 프롬프트로 LLM에 한 문장을 요청하고, 답변을 사후 검사한다.

    템플릿이 이미 맥락을 다 담고 있어서 system 하나로 충분하지만,
    chat 모델은 user 메시지가 하나는 있어야 하므로 짧은 trigger를 붙인다.

    생성 결과는 answer_check.enforce로 한 번 더 거른다(LLM 재호출 없이 규칙 기반).
    프롬프트 가드레일이 뚫린 경우의 마지막 방어선이다.
    """
    messages = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": trigger},
    ]
    raw = chat(messages, temperature=temperature)
    return answer_check.enforce(raw)


# ── 질문 생성 ───────────────────────────────────────────────────


def _variant(by_activity: dict[str, str], activity_type: str | None) -> str:
    """활동 유형 → 변형 프롬프트 본문. 모르는 값은 기본(HTP)으로 둔다."""
    return _load(by_activity.get(activity_type or "", by_activity[DEFAULT_ACTIVITY_TYPE]))


def render_first_question_prompt(
    drawing_analysis: str | None = None,
    *,
    child_name: str | None = None,
    age_band: str = DEFAULT_AGE_BAND,
    activity_block: str = "",
    activity_type: str | None = None,
    difficulty: str | None = None,
    drawing_subject: str | None = None,
) -> str:
    """첫 질문 system 프롬프트를 렌더링한다(GMS 호출 없음).

    draft 경로와 내부 계약 경로(question_service)가 같은 프롬프트를 쓰도록 렌더링만 분리했다.
    activity_block: HTP 주제·대상 객체·반복 금지 지시 블록(S15P11B209-713). draft 경로는
    비우고(""), 내부 계약 경로가 activityType·drawingSubject 기반으로 채운다.
    activity_type: HTP | ART_DIARY. 대화 목표가 다른 변형 프롬프트를 고른다(S15P11B209-786).
    difficulty: BE QuestionDifficulty. 연령별 말투 블록을 고른다. None이면 기본 난이도.
    drawing_subject: HOUSE | TREE | PERSON. HTP 질문 뱅크 구획을 고른다(S15P11B209-811).
    """
    variant = _variant(_FIRST_BY_ACTIVITY, activity_type).format(
        age_band=age_band,
        child_name=child_name or NO_CHILD_NAME,
        drawing_analysis=drawing_analysis or NO_ANALYSIS,
    )
    return _assemble(
        variant,
        activity_block=activity_block,
        difficulty=difficulty,
        question_bank=question_bank_block(activity_type, drawing_subject),
        activity_type=activity_type,
    )


def first_question(
    drawing_analysis: str | None = None,
    *,
    child_name: str | None = None,
    age_band: str = DEFAULT_AGE_BAND,
    activity_type: str | None = None,
    difficulty: str | None = None,
    drawing_subject: str | None = None,
    temperature: float = 0.7,
) -> str:
    """그림 분석 결과를 보고 아이에게 건넬 첫 질문을 만든다.

    Args:
        drawing_analysis: 그림분석 모델 결과 요약. None이면 "뭘 그렸어?"류로 유도된다.
        child_name: 아이 이름(호칭용). None이면 "너"라고 부르게 된다.
        age_band: 연령대 문구(템플릿의 {age_band}에 그대로 들어감).
        activity_type: HTP | ART_DIARY. None이면 기본(HTP) 변형.
        difficulty: BE QuestionDifficulty. None이면 기본 난이도 말투.
        temperature: 첫 질문은 조금 다양해도 좋아 기본 0.7.

    Returns:
        첫 질문 한 문장.

    Raises:
        RuntimeError: GMS 호출 실패 시.
    """
    system = render_first_question_prompt(
        drawing_analysis,
        child_name=child_name,
        age_band=age_band,
        activity_type=activity_type,
        difficulty=difficulty,
        drawing_subject=drawing_subject,
    )
    return _ask(system, FIRST_QUESTION_TRIGGER, temperature=temperature)


def render_next_question_prompt(
    child_utterance: str,
    *,
    drawing_analysis: str | None = None,
    history: list[dict] | None = None,
    child_name: str | None = None,
    age_band: str = DEFAULT_AGE_BAND,
    activity_block: str = "",
    activity_type: str | None = None,
    difficulty: str | None = None,
    drawing_subject: str | None = None,
) -> str:
    """다음 질문 system 프롬프트를 렌더링한다(GMS 호출 없음).

    draft 경로와 내부 계약 경로(question_service)가 같은 프롬프트를 쓰도록 렌더링만 분리했다.
    activity_block: HTP 주제·반복 금지 지시 블록(S15P11B209-713). draft 경로는 비운다.
    activity_type: HTP | ART_DIARY. 대화 목표가 다른 변형 프롬프트를 고른다(S15P11B209-786).
    difficulty: BE QuestionDifficulty. 연령별 말투 블록을 고른다. None이면 기본 난이도.
    drawing_subject: HOUSE | TREE | PERSON. HTP 질문 뱅크 구획을 고른다(S15P11B209-811).
    """
    variant = _variant(_NEXT_BY_ACTIVITY, activity_type).format(
        age_band=age_band,
        child_name=child_name or NO_CHILD_NAME,
        drawing_analysis=drawing_analysis or NO_ANALYSIS,
        history=_format_history(history),
        child_utterance=child_utterance,
    )
    return _assemble(
        variant,
        activity_block=activity_block,
        difficulty=difficulty,
        question_bank=question_bank_block(activity_type, drawing_subject),
        activity_type=activity_type,
    )


def next_question(
    child_utterance: str,
    *,
    drawing_analysis: str | None = None,
    history: list[dict] | None = None,
    child_name: str | None = None,
    age_band: str = DEFAULT_AGE_BAND,
    activity_type: str | None = None,
    difficulty: str | None = None,
    drawing_subject: str | None = None,
    temperature: float = 0.6,
) -> str:
    """아이가 방금 한 말에 반응하고 다음 질문을 이어간다.

    Args:
        child_utterance: STT로 받은 아이의 마지막 발화.
        drawing_analysis: 그림분석 결과(있으면 맥락으로).
        history: 지금까지의 대화(마지막 발화는 제외하고 넘기면 중복이 없다).
        child_name: 아이 이름(호칭용). None이면 "너"라고 부르게 된다.
        age_band: 연령대 문구.
        activity_type: HTP | ART_DIARY. None이면 기본(HTP) 변형.
        difficulty: BE QuestionDifficulty. None이면 기본 난이도 말투.
        temperature: 이어지는 대화는 튀지 않게 기본 0.6.

    Returns:
        아이에게 건넬 다음 말(연령별 말하기 규칙이 정한 길이).

    Raises:
        RuntimeError: GMS 호출 실패 시.
    """
    system = render_next_question_prompt(
        child_utterance,
        drawing_analysis=drawing_analysis,
        history=history,
        child_name=child_name,
        age_band=age_band,
        activity_type=activity_type,
        difficulty=difficulty,
        drawing_subject=drawing_subject,
    )
    return _ask(system, NEXT_QUESTION_TRIGGER, temperature=temperature)


if __name__ == "__main__":
    # 스모크 테스트:  cd ai && python llm_client.py
    logging.basicConfig(level=logging.INFO)

    analysis = "집 1개(가운데, 큼), 나무 1개(왼쪽), 사람 2명(오른쪽)"

    # 이름을 아는 경우 — 아이를 '도담'이라 부르지 않는지 함께 확인한다.
    q1 = first_question(analysis, child_name="지우")
    print("[첫 질문]", q1)

    q2 = next_question(
        "이건 우리 집이야. 여기 엄마랑 나 있어.",
        drawing_analysis=analysis,
        history=[{"role": "assistant", "content": q1}],
        child_name="지우",
    )
    print("[다음 말]", q2)

    # 이름을 모르는 경우 — "너"로 부르는지 확인.
    print("[이름 모를 때]", first_question(analysis))

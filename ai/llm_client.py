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

from openai import OpenAIError

import answer_check  # 생성 답변 사후 검사(LLM 재호출 없이 규칙 기반)
import config
import prompts_registry  # 프롬프트 파일 로딩·버전 관리 중앙화 (S15P11B209-595)
from gms import get_client  # GMS(OpenAI 호환) 공용 클라이언트

logger = logging.getLogger(__name__)

# 질문 생성에 쓰는 프롬프트 파일 조합의 통합 버전(내용이 바뀌면 자동으로 달라진다) — S15P11B209-595.
PROMPT_VERSION = prompts_registry.composite_version(
    "first_question", "conversations", "guardrails"
)

# 캐릭터 이름. 프롬프트 txt에도 '도담'으로 적혀 있으니 바꾸려면 양쪽을 같이 고칠 것.
CHARACTER_NAME = "도담"

# 그림분석이 아직 없을 때 템플릿에 넣을 문구(템플릿 규칙상 "오늘은 뭘 그렸어?"로 유도됨).
NO_ANALYSIS = "(아직 그림 분석 결과가 없어요)"

# 아이 이름을 모를 때. 템플릿의 '이름 규칙'이 이걸 보고 "너"로 부르게 한다.
NO_CHILD_NAME = "(이름은 아직 몰라요)"

DEFAULT_AGE_BAND = "5~7"

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


def render_first_question_prompt(
    drawing_analysis: str | None = None,
    *,
    child_name: str | None = None,
    age_band: str = DEFAULT_AGE_BAND,
) -> str:
    """첫 질문 system 프롬프트를 렌더링한다(GMS 호출 없음).

    draft 경로와 내부 계약 경로(question_service)가 같은 프롬프트를 쓰도록 렌더링만 분리했다.
    """
    return _load("first_question").format(
        age_band=age_band,
        child_name=child_name or NO_CHILD_NAME,
        drawing_analysis=drawing_analysis or NO_ANALYSIS,
        guardrails=_load("guardrails"),
    )


def first_question(
    drawing_analysis: str | None = None,
    *,
    child_name: str | None = None,
    age_band: str = DEFAULT_AGE_BAND,
    temperature: float = 0.7,
) -> str:
    """그림 분석 결과를 보고 아이에게 건넬 첫 질문을 만든다.

    Args:
        drawing_analysis: 그림분석 모델 결과 요약. None이면 "뭘 그렸어?"류로 유도된다.
        child_name: 아이 이름(호칭용). None이면 "너"라고 부르게 된다.
        age_band: 연령대 문구(템플릿의 {age_band}에 그대로 들어감).
        temperature: 첫 질문은 조금 다양해도 좋아 기본 0.7.

    Returns:
        첫 질문 한 문장.

    Raises:
        RuntimeError: GMS 호출 실패 시.
    """
    system = render_first_question_prompt(
        drawing_analysis, child_name=child_name, age_band=age_band
    )
    return _ask(system, FIRST_QUESTION_TRIGGER, temperature=temperature)


def render_next_question_prompt(
    child_utterance: str,
    *,
    drawing_analysis: str | None = None,
    history: list[dict] | None = None,
    child_name: str | None = None,
    age_band: str = DEFAULT_AGE_BAND,
) -> str:
    """다음 질문 system 프롬프트를 렌더링한다(GMS 호출 없음).

    draft 경로와 내부 계약 경로(question_service)가 같은 프롬프트를 쓰도록 렌더링만 분리했다.
    """
    return _load("conversations").format(
        age_band=age_band,
        child_name=child_name or NO_CHILD_NAME,
        drawing_analysis=drawing_analysis or NO_ANALYSIS,
        history=_format_history(history),
        child_utterance=child_utterance,
        guardrails=_load("guardrails"),
    )


def next_question(
    child_utterance: str,
    *,
    drawing_analysis: str | None = None,
    history: list[dict] | None = None,
    child_name: str | None = None,
    age_band: str = DEFAULT_AGE_BAND,
    temperature: float = 0.6,
) -> str:
    """아이가 방금 한 말에 반응하고 다음 질문을 이어간다.

    Args:
        child_utterance: STT로 받은 아이의 마지막 발화.
        drawing_analysis: 그림분석 결과(있으면 맥락으로).
        history: 지금까지의 대화(마지막 발화는 제외하고 넘기면 중복이 없다).
        child_name: 아이 이름(호칭용). None이면 "너"라고 부르게 된다.
        age_band: 연령대 문구.
        temperature: 이어지는 대화는 튀지 않게 기본 0.6.

    Returns:
        아이에게 건넬 다음 말(한두 문장).

    Raises:
        RuntimeError: GMS 호출 실패 시.
    """
    system = render_next_question_prompt(
        child_utterance,
        drawing_analysis=drawing_analysis,
        history=history,
        child_name=child_name,
        age_band=age_band,
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

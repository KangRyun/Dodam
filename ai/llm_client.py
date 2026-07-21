"""GMS 대화 LLM 클라이언트 (얇은 래퍼).

GMS는 OpenAI 호환 게이트웨이라, 공식 `openai` SDK에 base_url만 GMS로 주면 그대로 동작한다.
이 모듈은 '배선'만 담당한다 — messages를 받아 호출하고 응답 텍스트를 돌려줄 뿐,
프롬프트 '내용'은 여기 두지 않는다(그건 ai/prompts/, 편주희 담당).

가드레일:
- 키는 로그로 남기지 않는다.
- messages에는 아이 발화가 들어올 수 있으므로, 실패 로그에도 원본 내용을 남기지 않는다(에러 유형만).
"""

from __future__ import annotations

import logging

from openai import OpenAI, OpenAIError

import config

logger = logging.getLogger(__name__)

# OpenAI 클라이언트는 '지연 생성'한다 — 키가 없어도 import 자체는 실패하지 않게(테스트/부분 실행 대비).
_client: OpenAI | None = None


def _get_client() -> OpenAI:
    global _client
    if _client is None:
        _client = OpenAI(
            api_key=config.require_gms_key(),  # 없으면 여기서 명확히 실패
            base_url=config.GMS_BASE_URL,      # ★ base_url을 GMS로 → GMS 프록시로 호출
            timeout=30.0,                      # 응답 지연 상한(초)
        )
    return _client


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
        resp = _get_client().chat.completions.create(
            model=used_model,
            messages=messages,
            temperature=temperature,
        )
    except OpenAIError as e:
        # ⚠️ messages(아이 발화 포함 가능)를 로그에 남기지 않는다 — 에러 유형만.
        logger.error("GMS chat 호출 실패: %s", type(e).__name__)
        raise RuntimeError("대화 생성에 실패했어요(GMS).") from e

    return resp.choices[0].message.content or ""


if __name__ == "__main__":
    # 스모크 테스트: GMS 배선이 되는지만 확인한다(실제 프롬프트는 편주희 담당).
    #   실행:  cd ai && python llm_client.py
    logging.basicConfig(level=logging.INFO)
    demo_messages = [
        {"role": "system", "content": "너는 아이와 대화하는 따뜻한 곰돌이야. 쉽고 짧게 말해."},
        {"role": "user", "content": "안녕? 한국어로 인사해줘."},
    ]
    print(chat(demo_messages))

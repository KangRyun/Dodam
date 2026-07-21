"""GMS TTS 클라이언트 — gpt-4o-mini-tts(지시형)로 텍스트→음성(mp3 bytes).

gpt-4o-mini-tts는 'instructions'로 말투를 지시(steer)할 수 있다(곰돌이 톤).
※ tts-1/tts-1-hd는 instructions 미지원 — 폴백 시 톤 지시는 빠진다.

가드레일: 키·원본 텍스트는 로그로 남기지 않는다(에러 유형만).
"""

from __future__ import annotations

import logging

from openai import OpenAIError

import config
from gms import get_client

logger = logging.getLogger(__name__)

# 곰돌이 캐릭터 말투 지시(steer). 실제 대사 '내용'은 아니고 '어떻게 말할지'만.
BEAR_INSTRUCTIONS = (
    "너는 아이와 이야기하는 따뜻하고 다정한 곰돌이야. "
    "밝고 부드럽게, 조금 천천히, 쉬운 말로 말해. 과장 없이 친근하게."
)


def synthesize(
    text: str,
    *,
    voice: str | None = None,
    instructions: str | None = None,
) -> bytes:
    """텍스트를 음성(mp3 bytes)으로 변환한다.

    Args:
        text: 읽을 텍스트(캐릭터 대사).
        voice: 미지정 시 config.TTS_VOICE(fable).
        instructions: 말투 지시. 미지정 시 곰돌이 기본(BEAR_INSTRUCTIONS).

    Returns:
        mp3 오디오 bytes.

    Raises:
        RuntimeError: GMS 호출 실패 시.
    """
    used_voice = voice or config.TTS_VOICE
    try:
        resp = get_client().audio.speech.create(
            model=config.TTS_MODEL,
            voice=used_voice,
            input=text,
            instructions=instructions or BEAR_INSTRUCTIONS,  # gpt-4o-mini-tts 전용
            response_format="mp3",
        )
    except OpenAIError as e:
        logger.error("GMS TTS 호출 실패: %s", type(e).__name__)
        raise RuntimeError("음성 합성에 실패했어요(GMS).") from e

    return resp.content  # bytes


if __name__ == "__main__":
    # 스모크 테스트:  cd ai && python tts_client.py  → out.mp3 생성 후 재생해보기
    logging.basicConfig(level=logging.INFO)
    audio = synthesize("안녕? 오늘 그림 그리러 왔구나! 정말 반가워.")
    with open("out.mp3", "wb") as f:
        f.write(audio)
    print(f"out.mp3 생성됨 ({len(audio)} bytes) — 재생해서 목소리 톤을 확인하세요")

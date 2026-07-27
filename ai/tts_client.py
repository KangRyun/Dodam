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

# 서비스 voice 코드 → GMS provider voice id.
#   BE 공개 API는 명세 예시(voice="CHILD_FRIENDLY_01")에 맞춰 대문자 코드를 받는데, GMS는
#   소문자 provider id만 허용해 대문자 값이 그대로 넘어가면 BadRequestError로 전부 실패한다.
#   말투·목소리 정책은 AI 서버 소유(docs/ai/ai-speech-contract.md)이므로 매핑도 여기서 한다.
#   값 자체가 provider id인 경우(fable 등)도 대문자로 정규화해 같은 표에서 찾는다.
SERVICE_VOICE_TO_PROVIDER = {
    "CHILD_FRIENDLY_01": "fable",
    "FABLE": "fable",
    "ALLOY": "alloy",
    "NOVA": "nova",
    "CORAL": "coral",
}


def resolve_voice(voice: str | None) -> str:
    """서비스 voice 코드를 GMS provider voice id로 바꾼다.

    모르는 코드는 서버 기본값으로 폴백한다. 아이와 대화하는 도중 목소리 코드 하나 때문에
    음성이 아예 나오지 않는 쪽보다, 기본 목소리로라도 들려주는 쪽이 낫다고 판단했다.

    Args:
        voice: BE가 전달한 서비스 코드 또는 provider id. 없으면 기본값을 쓴다.

    Returns:
        GMS가 허용하는 provider voice id.
    """
    if not voice or not voice.strip():
        return config.TTS_VOICE
    normalized = voice.strip().upper()
    resolved = SERVICE_VOICE_TO_PROVIDER.get(normalized)
    if resolved is None:
        logger.warning("알 수 없는 voice 코드라 기본 목소리로 대체합니다: %s", normalized)
        return config.TTS_VOICE
    return resolved


def synthesize(
    text: str,
    *,
    voice: str | None = None,
    instructions: str | None = None,
) -> bytes:
    """텍스트를 음성(mp3 bytes)으로 변환한다.

    Args:
        text: 읽을 텍스트(캐릭터 대사).
        voice: 서비스 voice 코드 또는 provider id. 미지정·미지 코드는 config.TTS_VOICE(fable).
        instructions: 말투 지시. 미지정 시 곰돌이 기본(BEAR_INSTRUCTIONS).

    Returns:
        mp3 오디오 bytes.

    Raises:
        RuntimeError: GMS 호출 실패 시.
    """
    used_voice = resolve_voice(voice)
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

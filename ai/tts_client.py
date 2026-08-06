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

TONE_PROFILES = {
    "CHARACTER_DEFAULT_V1",
    "CHARACTER_CELEBRATING_V1",
    "CHARACTER_ENCOURAGING_V1",
}

# 지시는 텍스트나 요청의 자유 입력에서 만들지 않는다. voice는 아래 고정 표의 키 선택에만 쓰고,
# 알 수 없는 값은 BASE로 수렴한다. 그래서 아이 발화나 임의 문자열이 모델 지시가 될 수 없다.
CHARACTER_INSTRUCTIONS = {
    "BASE": "포근하고 믿음직한 도담이 친구처럼, 밝고 부드럽고 쉬운 말로 말해.",
    "PRINCESS": "다정하고 자신감 있는 공주 친구처럼, 반짝이되 차분하게 말해.",
    "DINO": "호기심 많은 공룡 친구처럼, 활기차되 너무 빠르지 않게 말해.",
    "OCTOPUS": "장난스럽고 리듬감 있는 문어 친구처럼, 또렷하고 친근하게 말해.",
    "EXPLORER": "함께 발견하는 탐험가 친구처럼, 기대감을 담아 따뜻하게 말해.",
    "RIBBON": "경쾌하고 사랑스러운 리본 친구처럼, 밝은 격려를 담아 말해.",
    "PRINCE": "차분하고 예의 바른 왕자 친구처럼, 든든하고 부드럽게 말해.",
}

SCENARIO_INSTRUCTIONS = {
    "CHARACTER_DEFAULT_V1": "기본 목소리와 말의 속도를 유지해 자연스럽게 이어 가.",
    "CHARACTER_CELEBRATING_V1": "아이가 발견하거나 해낸 순간에는 기쁜 마음을 조금 더 담되, 들뜨거나 과장하지 마.",
    "CHARACTER_ENCOURAGING_V1": "아이가 망설이거나 생각할 때는 속도를 조금 낮추고, 짧고 안정적으로 응원해.",
}

# 서비스 voice 코드 → GMS provider voice id.
#   BE 공개 API는 명세 예시(voice="CHILD_FRIENDLY_01")에 맞춰 대문자 코드를 받는데, GMS는
#   소문자 provider id만 허용해 대문자 값이 그대로 넘어가면 BadRequestError로 전부 실패한다.
#   말투·목소리 정책은 AI 서버 소유(docs/ai/ai-speech-contract.md)이므로 매핑도 여기서 한다.
#   값 자체가 provider id인 경우(fable 등)도 대문자로 정규화해 같은 표에서 찾는다.
SERVICE_VOICE_TO_PROVIDER = {
    "CHILD_FRIENDLY_01": "fable",
    "FABLE": "fable",
    "ALLOY": "alloy",
    "ASH": "ash",
    "BALLAD": "ballad",
    "NOVA": "nova",
    "CORAL": "coral",
    "ECHO": "echo",
    "SAGE": "sage",
    "VERSE": "verse",
}

SERVICE_VOICE_TO_CHARACTER = {
    "CHILD_FRIENDLY_01": "BASE",
    "FABLE": "BASE",
    "NOVA": "PRINCESS",
    "ASH": "DINO",
    "BALLAD": "OCTOPUS",
    "VERSE": "EXPLORER",
    "SAGE": "RIBBON",
    "ECHO": "PRINCE",
    "ALLOY": "BASE",
    "CORAL": "BASE",
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


def compose_instructions(voice: str | None, tone_profile: str) -> str:
    """서버 고정 캐릭터·상황 표만 조합해 GMS 지시를 만든다."""
    if tone_profile not in TONE_PROFILES:
        raise ValueError("unsupported tone profile")
    voice_code = voice.strip().upper() if voice and voice.strip() else ""
    character = SERVICE_VOICE_TO_CHARACTER.get(voice_code, "BASE")
    return f"{CHARACTER_INSTRUCTIONS[character]} {SCENARIO_INSTRUCTIONS[tone_profile]}"


def synthesize(
    text: str,
    *,
    voice: str | None = None,
    tone_profile: str = "CHARACTER_DEFAULT_V1",
) -> bytes:
    """텍스트를 음성(mp3 bytes)으로 변환한다.

    Args:
        text: 읽을 텍스트(캐릭터 대사).
        voice: 서비스 voice 코드 또는 provider id. 미지정·미지 코드는 config.TTS_VOICE(fable).
        tone_profile: 서버 고정 캐릭터·상황 말투 프로필. 목록 밖의 값은 거절한다.

    Returns:
        mp3 오디오 bytes.

    Raises:
        RuntimeError: GMS 호출 실패 시.
    """
    used_voice = resolve_voice(voice)
    instructions = compose_instructions(voice, tone_profile)
    try:
        resp = get_client().audio.speech.create(
            model=config.TTS_MODEL,
            voice=used_voice,
            input=text,
            instructions=instructions,  # gpt-4o-mini-tts 전용
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

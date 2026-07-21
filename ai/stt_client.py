"""GMS STT 클라이언트 — whisper-1로 음성 파일→텍스트.

가드레일: 인식된 텍스트(아이 발화일 수 있음)와 키는 로그로 남기지 않는다(에러 유형만).
"""

from __future__ import annotations

import logging

from openai import OpenAIError

import config
from gms import get_client

logger = logging.getLogger(__name__)


def transcribe(audio_path: str, *, language: str = "ko") -> str:
    """음성 파일을 텍스트로 변환한다.

    Args:
        audio_path: 음성 파일 경로(mp3/wav/m4a 등).
        language: 인식 언어 힌트. 기본 한국어("ko").

    Returns:
        인식된 텍스트.

    Raises:
        RuntimeError: GMS 호출 실패 시.
    """
    try:
        with open("/home/kr/S15P11B209/ai/out.mp3", "rb") as f:
            resp = get_client().audio.transcriptions.create(
                model=config.STT_MODEL,
                file=f,
                language=language,
            )
    except OpenAIError as e:
        logger.error("GMS STT 호출 실패: %s", type(e).__name__)
        raise RuntimeError("음성 인식에 실패했어요(GMS).") from e

    return resp.text


if __name__ == "__main__":
    # 스모크 테스트:  cd ai && python stt_client.py <음성파일>
    #   팁: tts_client.py로 만든 out.mp3를 넣으면 TTS→STT 왕복 확인이 된다.
    import sys
    
    logging.basicConfig(level=logging.INFO)
    if len(sys.argv) < 2:
        print("사용법: python stt_client.py <음성파일(mp3/wav/m4a)>")
        raise SystemExit(1)
    print(transcribe(sys.argv[1]))

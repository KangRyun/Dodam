"""GMS(OpenAI 호환 게이트웨이) 공용 클라이언트.

LLM/STT/TTS 세 클라이언트가 같은 GMS 접속(키·base_url)을 공유한다.
지연 생성 — 키가 없어도 import 자체는 실패하지 않게(테스트/부분 실행 대비).
"""

from __future__ import annotations

from openai import OpenAI

import config

_client: OpenAI | None = None


def get_client() -> OpenAI:
    """GMS로 향하는 OpenAI 클라이언트(싱글턴). 키가 없으면 여기서 명확히 실패."""
    global _client
    if _client is None:
        _client = OpenAI(
            api_key=config.require_gms_key(),
            base_url=config.GMS_BASE_URL,  # ★ base_url을 GMS로 → GMS 프록시로 호출
            timeout=60.0,                  # STT/TTS는 다소 오래 걸릴 수 있어 여유
        )
    return _client

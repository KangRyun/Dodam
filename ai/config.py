"""GMS · AI 서버 설정 — .env에서 읽어 한 곳에서 제공한다.

GMS = SSAFY의 OpenAI 호환 게이트웨이. 키는 절대 코드/로그에 남기지 않는다(.env만).
로컬 개발에선 .env를 읽고, 컨테이너 배포에선 환경변수로 주입된다(둘 다 os.environ으로 접근).
"""

import os

from dotenv import find_dotenv, load_dotenv

# cwd가 ai/ 여도 상위(repo 루트)의 .env를 찾아 로드한다(find_dotenv가 부모로 거슬러 탐색).
# 이미 환경변수가 있으면 덮어쓰지 않음(override=False) — 컨테이너 주입값 우선.
load_dotenv(find_dotenv(usecwd=True), override=False)

# ── GMS 접속 정보 ───────────────────────────────────────────────
GMS_KEY = os.environ.get("GMS_KEY", "")
GMS_BASE_URL = os.environ.get(
    "GMS_BASE_URL", "https://gms.ssafy.io/gmsapi/api.openai.com/v1"
)

# ── 모델 이름(엔진) ─────────────────────────────────────────────
LLM_MODEL = os.environ.get("LLM_MODEL", "gpt-4o-mini")
STT_MODEL = os.environ.get("STT_MODEL", "whisper-1")
# TTS는 지시형(gpt-4o-mini-tts) — "어떻게 말할지"를 instructions로 지정 가능(곰돌이 톤).
TTS_MODEL = os.environ.get("TTS_MODEL", "gpt-4o-mini-tts")
TTS_VOICE = os.environ.get("TTS_VOICE", "fable")  # fable=만화적·개성 / nova=밝음 / coral=친근

# 파이프라인 버전(분석 결과에 기록 → 재현·재분석용). 프롬프트 버전은 프롬프트 파일 쪽에서 관리.
PIPELINE_VERSION = "0.1.0"


def require_gms_key() -> str:
    """GMS_KEY가 없으면 즉시 명확히 실패시킨다(원인이 빨리 드러나게)."""
    if not GMS_KEY:
        raise RuntimeError(
            "GMS_KEY가 비어 있습니다. 프로젝트 루트 .env에 GMS_KEY를 채워주세요."
        )
    return GMS_KEY

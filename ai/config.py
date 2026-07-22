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

# ── BE 내부 계약(183): 대화 질문 생성 ───────────────────────────
# BE ↔ AI 내부 호출 인증 토큰. BE도 같은 이름(AI_INTERNAL_TOKEN)의 환경변수를 쓴다
# (backend RestClientAiQuestionClient가 X-Internal-Token 헤더로 전송).
# ⚠️ 기본 필수(safety review C-183-1): 미설정이면 서버 '기동' 시점에 실패한다(main.py lifespan).
#    이전의 "비어 있으면 검사 생략" fallback은 compose 미주입 + nginx /ai/ 접두제거 프록시와
#    결합해 내부 계약이 무인증으로 인터넷에 노출되는 사고 경로였다 — 제거.
AI_INTERNAL_TOKEN = os.environ.get("AI_INTERNAL_TOKEN", "")

# 로컬 개발 전용 명시적 opt-out — 정확히 "true"일 때만 토큰 없이 기동·검사 생략을 허용.
# reason: 로컬 편의는 '조용한 기본값'이 아니라 개발자가 의도를 선언한 경우에만(C-183-1).
#         배포 compose에는 이 변수를 절대 주입하지 않는다.
AI_INTERNAL_AUTH_DISABLED = (
    os.environ.get("AI_INTERNAL_AUTH_DISABLED", "").strip().lower() == "true"
)

# GMS 질문 생성 재시도 예산 — BE read timeout 15초(RestClientAiQuestionClient) 안쪽으로 설계.
# 최악 소요: 시도당 4.0s × 3회(최초 1 + 재시도 2) + 백오프(0.5 + 1.0)s = 13.5s < 15s
# reason: 공용 GMS timeout(gms.py, 60s)은 STT/TTS용 여유값이라 이 경로에는 그대로 못 쓴다.
QUESTION_LLM_TIMEOUT_SEC = float(os.environ.get("QUESTION_LLM_TIMEOUT_SEC", "4.0"))
QUESTION_LLM_MAX_RETRIES = int(os.environ.get("QUESTION_LLM_MAX_RETRIES", "2"))
QUESTION_LLM_BACKOFF_BASE_SEC = float(os.environ.get("QUESTION_LLM_BACKOFF_BASE_SEC", "0.5"))


def require_gms_key() -> str:
    """GMS_KEY가 없으면 즉시 명확히 실패시킨다(원인이 빨리 드러나게)."""
    if not GMS_KEY:
        raise RuntimeError(
            "GMS_KEY가 비어 있습니다. 프로젝트 루트 .env에 GMS_KEY를 채워주세요."
        )
    return GMS_KEY

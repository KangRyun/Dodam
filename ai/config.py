"""GMS · AI 서버 설정 — .env에서 읽어 한 곳에서 제공한다.

GMS = SSAFY의 OpenAI 호환 게이트웨이. 키는 절대 코드/로그에 남기지 않는다(.env만).
로컬 개발에선 .env를 읽고, 컨테이너 배포에선 환경변수로 주입된다(둘 다 os.environ으로 접근).
"""

import os
from pathlib import Path

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

# ── 그림분석: YOLO 객체탐지 + VLM 서술 (S15P11B209-176) ──────────
# VLM(그림 서술)도 GMS(OpenAI 호환) 비전 모델을 쓴다 — gpt-4o-mini는 이미지 입력 지원.
VLM_MODEL = os.environ.get("VLM_MODEL", "gpt-4o-mini")

# YOLO HTP 가중치 경로. 가중치는 저장소에 커밋하지 않고 별도 다운로드/학습으로 준비된다.
#   기본은 ai/models/htp_yolo/htp_best.pt. 다른 환경에선 YOLO_MODEL_PATH로 덮어쓴다.
YOLO_MODEL_PATH = os.environ.get(
    "YOLO_MODEL_PATH",
    str(Path(__file__).parent / "models" / "htp_yolo" / "htp_best.pt"),
)

# 탐지 신뢰도 하한 — 이보다 낮은 박스는 버린다(아동 스케치 과탐지 억제).
#   0.20은 실측 근거값(S15P11B209-376): stageB_htp test 80장(집·나무·남자사람·여자사람 각 20장)에서
#   임계값별 '주제 전체 박스' 검출률이 0.20에서 99%, 0.25에서 96%, 0.50에서 91%였다.
#   0.15로 더 내려도 검출률은 99% 그대로인데 장당 부위 탐지만 1.7개 늘어 이득이 없다.
#   과탐지의 주범이던 교차 주제 오탐(나무 그림의 PERSON_EYE 등)은 신뢰도가 아니라
#   htp_labels.suppress_cross_subject_parts로 거른다 — 그래서 임계값을 검출률 쪽에 맞출 수 있다.
YOLO_CONF_THRESHOLD = float(os.environ.get("YOLO_CONF_THRESHOLD", "0.20"))

# YOLO 가중치 무결성 핀(sha256) — 운영 볼륨에 배포된 실제 가중치의 해시다.
#   reason: 파일 존재만 확인하면 전송 중 손상·오배포된 가중치를 못 거른다. 로드 전에
#           sha256을 이 값과 대조해 다르면 로드를 거부한다(fail-closed). 값이 비면(미설정)
#           검증을 생략하고 경고만 남긴다(로컬·CI 편의). 해시는 비밀이 아니라 무결성 지문이다.
#   ⚠️ 가중치를 재학습·교체하면 이 값도 함께 갱신한다(마이그레이션 버전 핀과 같은 성격).
YOLO_MODEL_SHA256 = os.environ.get(
    "YOLO_MODEL_SHA256",
    "2b901729ace2a7199382771770f0a38491f9981713f9453fb0b11b7258c5f5e0",
)

# 그림일기(자유 그림) 객체탐지 모델 — HTP와 별도 가중치. 현재는 등록·checksum 검증만 하고
# 분석 파이프라인 라우팅(활동 유형별 모델 선택)은 후속 계약과 함께 붙인다(603 스코프 밖).
SKETCH_MODEL_PATH = os.environ.get(
    "SKETCH_MODEL_PATH",
    str(Path(__file__).parent / "models" / "htp_yolo" / "sketch_base.pt"),
)
SKETCH_MODEL_SHA256 = os.environ.get(
    "SKETCH_MODEL_SHA256",
    "85c93447e30d19456d7b8c40d4bc566f914df0f7c777eead60e07e86f2e8433b",
)

# ── BE 내부 계약(183): 대화 질문 생성 ───────────────────────────
# BE ↔ AI 내부 호출 인증 토큰. BE도 같은 이름(AI_INTERNAL_TOKEN)의 환경변수를 쓴다
# (backend RestClientAiQuestionClient가 X-Internal-Token 헤더로 전송).
# ⚠️ 기본 필수(safety review C-183-1): 미설정이면 서버 '기동' 시점에 실패한다(main.py lifespan).
#    이전의 "비어 있으면 검사 생략" fallback은 compose 미주입 + nginx /ai/ 접두제거 프록시와
#    결합해 내부 계약이 무인증으로 인터넷에 노출되는 사고 경로였다 — 제거.
AI_INTERNAL_TOKEN = os.environ.get("AI_INTERNAL_TOKEN", "")

# 정본 명세(API_명세서_최종.md §3.2 · §19.2)가 요구하는 내부 인증 헤더는 X-Internal-Api-Key다.
# 이미 배포된 BE 소비자(RestClientAiQuestionClient·RestClientAiSttClient)는 X-Internal-Token을
# 보내므로 두 헤더를 함께 받아야 전환 중에도 연동이 끊기지 않는다.
#   reason: 헤더 이름만 갈아끼우면 BE 호출이 401 → BE는 Type.OTHER로 분류해 폴백 템플릿으로
#     조용히 대체된다(internal_contracts.py 상단 경고와 같은 실패 모드).
# 값을 따로 주지 않으면 기존 토큰과 같은 값으로 본다 — 운영 시크릿을 한 번에 하나만 관리.
AI_INTERNAL_API_KEY = os.environ.get("AI_INTERNAL_API_KEY", "") or AI_INTERNAL_TOKEN

# ── 종합 분석 계약(§19.3/§19.4) ─────────────────────────────────
# BE가 넘긴 signedUrl(짧은 만료·읽기 전용)에서 그림을 받아오는 제한 시간.
#   reason: 만료된 URL이나 저장소 지연에 분석이 무한정 매달리지 않게 한다.
ANALYSIS_IMAGE_TIMEOUT_SEC = float(os.environ.get("ANALYSIS_IMAGE_TIMEOUT_SEC", "10.0"))

# 내려받을 그림 최대 크기. 정본 §3.8의 그림 업로드 상한(10 MiB)과 같은 값.
ANALYSIS_IMAGE_MAX_BYTES = int(
    os.environ.get("ANALYSIS_IMAGE_MAX_BYTES", str(10 * 1024 * 1024))
)

# RAG 지식베이스 버전. 검색 파이프라인이 아직 없어 근거를 만들지 못한다 —
# 그 사실을 응답 unusedInputs로 명시하고 evidenceReferences는 비운다(§24.3).
RAG_KNOWLEDGE_BASE_VERSION = os.environ.get("RAG_KNOWLEDGE_BASE_VERSION", "")

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

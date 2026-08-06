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
# 대화 질문 생성용 LLM. 아이가 화면 앞에서 답을 기다리는 경로라 지연이 곧 UX다
# (BE read timeout 15초 · QUESTION_LLM_TIMEOUT_SEC 4초 예산 — 아래 재시도 설계 참조).
LLM_MODEL = os.environ.get("LLM_MODEL", "gpt-4o-mini")

# 관찰 리포트 생성용 LLM (S15P11B209-972). 대화와 모델을 나눈 이유:
#   리포트 한 건은 그림 서술(VLM) + 탐지 기하 + 대화 전체 + 형식 지표 + RAG 근거를 한 번에
#   종합해 보호자가 읽을 최종 문서를 쓰는, 이 서비스에서 가장 무거운 추론이다. 게다가 그 뒤에
#   자체검토(2-pass)까지 붙어 같은 모델이 판정까지 맡는다 — 품질이 지연보다 중요한 경로다.
#   대화 질문은 정반대로 짧은 한 문장을 빨리 돌려주는 게 전부다. 요구가 서로 반대인 두 경로를
#   한 변수로 묶으면 한쪽을 올릴 때 다른 쪽이 반드시 손해를 본다.
# 미설정이면 LLM_MODEL과 같은 값을 쓴다 — 이 변수를 모르는 환경(로컬·CI·기존 배포)은 종전과
#   똑같이 돈다. ""(빈 값)도 미설정으로 본다(AI_INTERNAL_API_KEY와 같은 규약):
#   빈 모델명으로 GMS를 부르면 원인이 안 드러나는 400으로 떨어진다.
REPORT_LLM_MODEL = os.environ.get("REPORT_LLM_MODEL", "") or LLM_MODEL

STT_MODEL = os.environ.get("STT_MODEL", "whisper-1")

# ── STT 무음·저신뢰 판정 임계값 (2026-08-05) ─────────────────────
# reason: whisper는 무음·잡음 구간에 학습 데이터 정형구("구독, 좋아요 …")를 만들어낸다.
#   그 문장이 아이 답변으로 저장되면 하지 않은 말이 대화 기록과 리포트 근거가 된다(실측).
#   verbose_json 세그먼트 지표로 무음·저신뢰를 걸러 실패로 돌린다(정본 §19.6·§25).
#
# 기준값은 whisper 디코더가 쓰는 관례값과 같다 — no_speech_threshold 0.6 /
#   logprob_threshold -1.0. 우리는 이를 세그먼트 길이 가중 평균에 적용한다(stt_verdict).
#   판정을 두 규칙으로 나눈 이유: 무음 확률과 인식 신뢰도는 서로 다른 실패를 말한다
#   (들을 말이 없었다 vs 들었지만 못 알아들었다). 아이에게 줄 안내도 달라야 한다.
STT_NO_SPEECH_PROB_MAX = float(os.environ.get("STT_NO_SPEECH_PROB_MAX", "0.6"))
STT_AVG_LOGPROB_FAIL_MAX = float(os.environ.get("STT_AVG_LOGPROB_FAIL_MAX", "-1.0"))
# 실패는 아니지만 확정하지도 않는 구간 — 보호자 확인 대상으로 넘긴다(정본 §25).
STT_AVG_LOGPROB_CONFIRM_MAX = float(
    os.environ.get("STT_AVG_LOGPROB_CONFIRM_MAX", "-0.6")
)
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

# 리포트 [탐지 기하] 블록의 신뢰도 구간 (S15P11B209-839).
#   탐지 임계값(YOLO_CONF_THRESHOLD=0.20)은 '박스를 남길지'의 기준이고, 이 둘은
#   '리포트 문장에 어떻게 적을지'의 기준이라 별개다. 같은 값을 쓰면 겨우 통과한 탐지가
#   확정 사실로 적혀 보호자에게 나간다 — BE가 "낮은 신뢰도 탐지를 확정 사실처럼 표현 금지"를
#   명시한 지점이다.
#     conf < REPORT_GEOMETRY_MIN_CONF   → 블록에서 제외(문장의 근거로 쓰지 않는다)
#     min ≤ conf < CERTAIN              → "~로 보이는 것"처럼 완화 표기
#     conf ≥ REPORT_GEOMETRY_CERTAIN_CONF → 그대로 표기
#   ⚠️ 0.5/0.7은 실측이 아니라 초기값이다. 운영 분포를 본 뒤 조정한다 — 그래서 상수로 뺐다.
REPORT_GEOMETRY_MIN_CONF = float(os.environ.get("REPORT_GEOMETRY_MIN_CONF", "0.50"))
REPORT_GEOMETRY_CERTAIN_CONF = float(
    os.environ.get("REPORT_GEOMETRY_CERTAIN_CONF", "0.70")
)

# YOLO 가중치 무결성 핀(sha256) — 운영 볼륨에 배포된 실제 가중치의 해시다.
#   reason: 파일 존재만 확인하면 전송 중 손상·오배포된 가중치를 못 거른다. 로드 전에
#           sha256을 이 값과 대조해 다르면 로드를 거부한다(fail-closed). 값이 비면(미설정)
#           검증을 생략하고 경고만 남긴다(로컬·CI 편의). 해시는 비밀이 아니라 무결성 지문이다.
#   ⚠️ 가중치를 재학습·교체하면 이 값도 함께 갱신한다(마이그레이션 버전 핀과 같은 성격).
YOLO_MODEL_SHA256 = os.environ.get(
    "YOLO_MODEL_SHA256",
    "2b901729ace2a7199382771770f0a38491f9981713f9453fb0b11b7258c5f5e0",
)

# 그림일기(자유 그림) 객체탐지 모델 — HTP와 별도 가중치이며 ART_DIARY 분석에서 선택한다.
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

# (제거됨 — S15P11B209-614) RAG_KNOWLEDGE_BASE_VERSION env 선언은 배포된 인덱스
# 실물 기준(rag.knowledge_base_version())으로 대체했다 — 파일 없이 READY로 읽히는
# 거짓 신호를 막는다. 버전의 정본은 인덱스 메타(index.json) 안에 있다(정책 §7).

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

# 리포트 AI 자체검토(2-pass) 호출의 개별 timeout (2026-08-05).
# reason: 자체검토가 붙으면서 리포트 한 건이 GMS를 **두 번** 부른다. BE read timeout은 30초인데
#   (application.yml AI_OBSERVATION_READ_TIMEOUT), 공용 GMS timeout은 60초라(gms.py) 그대로 두면
#   AI가 아직 검토 중일 때 BE가 먼저 포기해 리포트 생성이 통째로 실패할 수 있다 —
#   생성은 끝났는데 검토 때문에 버리는 셈이라 최악의 실패 모드다.
#   검토 응답은 findings 목록뿐이라 생성보다 훨씬 짧다. 넘기면 '검토 못 함'으로 떨어뜨리고
#   리포트는 그대로 내보낸다(status=AI_DRAFT) — 차단이 아니라 기능 저하.
REPORT_REVIEW_TIMEOUT_SEC = float(os.environ.get("REPORT_REVIEW_TIMEOUT_SEC", "10.0"))

# 질문 프롬프트에 넣는 그림 서술(VLM)의 길이 상한 (S15P11B209-704).
# VLM 프롬프트가 2~4문장을 지시하므로 정상 범위는 그대로 통과한다. 이 값은 모델이
# 길게 답해 프롬프트의 다른 지시가 묻히는 경우만 막는 안전판이다.
# reason: 상한을 두지 않으면 장문 서술이 [그림 분석 결과] 절을 압도해 질문이 산만해진다.
QUESTION_DESCRIPTION_MAX_CHARS = int(
    os.environ.get("QUESTION_DESCRIPTION_MAX_CHARS", "300")
)

# 탐지 진단 로그 상세도(S15P11B209-710). 정확히 "true"일 때만 라벨·신뢰도까지 남긴다.
#   기본(꺼짐)은 개수·주제·warnings 요약만 남긴다 — 탐지 라벨은 아동 그림 내용을 서술하므로
#   운영에서는 필요할 때만 켠다. 이미지 원본·경로·아이 발화는 어느 모드에서도 남기지 않는다.
#   reason: S15P11B209-709를 조사할 때 탐지 결과를 볼 수 없어 학습 라벨을 역집계해야 했다.
#     "무엇이 탐지됐고 그중 무엇이 프롬프트에 들어갔는가"가 이 계열 버그의 유일한 확정 증거다.
DETECTION_LOG_DETAIL = (
    os.environ.get("DETECTION_LOG_DETAIL", "").strip().lower() == "true"
)

# sketch(그림일기) 추론 입력 전처리 모드 (S15P11B209-679).
#   "none"(기본): 컬러 이미지를 그대로 predict — 실측 전엔 동작을 바꾸지 않는다.
#   "ink": image_preprocess.ink_normalize로 흑백 선화 도메인에 맞춘다(색 있는 선 보존).
#   color_ablation_test.ipynb 실측으로 도움이 확인되면 "ink"로 켠다. HTP는 흑백 강제라 무관.
SKETCH_PREPROCESS = os.environ.get("SKETCH_PREPROCESS", "none").strip().lower()

# 추론 입력 해상도 — 학습 imgsz와 일치시킨다 (S15P11B209-761 1단계).
#   ultralytics predict는 imgsz 미지정 시 기본 640으로 letterbox한다. 학습이 960인 모델을
#   640으로 추론하면 작은 객체·가는 선에서 손해다. 두 모델 모두 960으로 통일한다.
#   htp_best=960(학습값 일치), sketch_base_v4=960. ⚠️ 현재 배포 sketch는 v1(학습 640)이라
#   960은 v4 배포를 앞서 반영한 값 — v1로 되돌리려면 env SKETCH_IMGSZ=640.
HTP_IMGSZ = int(os.environ.get("HTP_IMGSZ", "960"))
SKETCH_IMGSZ = int(os.environ.get("SKETCH_IMGSZ", "960"))


# ── RAG 검색 (S15P11B209-613 — 정책: docs/ai/rag-corpus-policy.md) ────────────
# 임베딩도 GMS 단일 키 원칙(AI모델선정.md)을 따른다. 인덱스 구축은 오프라인 스크립트,
# 런타임은 질의 임베딩 1회뿐이라 비용·지연 영향이 작다.
EMBEDDING_MODEL = os.environ.get("EMBEDDING_MODEL", "text-embedding-3-small")
# 인덱스 배포 경로 — 가중치(*.pt)와 같은 ai-models 볼륨. 기본값은 컨테이너 기준이고
# 로컬 개발·테스트는 RAG_INDEX_DIR로 덮어쓴다(YOLO_MODEL_PATH와 같은 규약).
RAG_INDEX_DIR = os.environ.get("RAG_INDEX_DIR", "/models/rag")
RAG_TOP_K = int(os.environ.get("RAG_TOP_K", "5"))
# 임계값 미만 청크는 버린다 — 저점수 근거를 억지로 실으면 리포트가 엉뚱한 지식을
# 인용한다(정책 §1-2). 코퍼스 실측 후 조정 대상(615에서 사유 코드와 함께 다룬다).
RAG_SCORE_THRESHOLD = float(os.environ.get("RAG_SCORE_THRESHOLD", "0.35"))


def require_gms_key() -> str:
    """GMS_KEY가 없으면 즉시 명확히 실패시킨다(원인이 빨리 드러나게)."""
    if not GMS_KEY:
        raise RuntimeError(
            "GMS_KEY가 비어 있습니다. 프로젝트 루트 .env에 GMS_KEY를 채워주세요."
        )
    return GMS_KEY

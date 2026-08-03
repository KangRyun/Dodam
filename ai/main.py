"""도담 AI 분석 서버 — 처리 흐름 배선.

흐름:  아동 발화 STT(E) → 대화 LLM(F: 그림분석+발화→질문) → 질문 TTS(G) → (대화 루프)

배선(엔드포인트 호출)은 이강륜(173). F의 프롬프트 '내용'·칩 생성과 그림분석 모델은 편주희.

대화 루프 위치 확정(183, 2026-07-23 · BE 283 머지 근거):
- 루프(질문 반복·질문 수 상한·세션 잠금·폴백 템플릿)는 BE ConversationQuestionService 소유.
- 이 서버는 stateless '질문 1건 생성' 내부 계약(/internal/ai/v1/conversations/question)만 제공.
- GMS 일시 오류는 이 서버 안에서 지수 백오프로 제한 재시도(question_service.py).
  근거 정리: _workspace/183_ai_loop-decision.md

STT/TTS 경로 정리(179·289, 2026-07-23):
- 공개 초안 /stt·/tts 삭제 — nginx /ai/ 프록시로 무인증 인터넷 노출되던 경로(GMS 비용·아동 음성).
- E(STT)·G(TTS)는 BE 전용 /internal/ai/v1/speech/stt·synthesis 로 제공(X-Internal-Token).
  계약: docs/ai/ai-speech-contract.md.

⚠️ /analyze/* 등 기존 경로의 계약은 '초안'이고, /internal/ai/v1/* 는 BE 코드와 맞춘 내부 계약.
원본 음성·발화는 저장·로그하지 않는다(가드레일).
"""

import base64
import hmac
import os
import tempfile
import time
from contextlib import asynccontextmanager

from fastapi import FastAPI, File, Form, Header, UploadFile
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from prometheus_fastapi_instrumentator import Instrumentator
from pydantic import BaseModel, ValidationError

import analysis_service
import config
import internal_contracts
import llm_client
import question_service
import rag
import report_client
import stt_client
import tts_client
import vlm_client
import yolo_client


def _require_internal_auth_config() -> None:
    """기동 시점 fail-fast: 내부 토큰 미설정이면 서버를 띄우지 않는다(safety review C-183-1).

    reason: '조용히 무인증으로 뜨는 것'이 최악의 실패 모드 — compose의
    ${AI_INTERNAL_TOKEN:?} 검증과 이 검증이 이중 안전장치를 이룬다.
    import 시점이 아닌 lifespan(서버 기동) 시점에 검증하므로 CI의
    import 스모크(`python -c "import main"`)는 깨지지 않는다.
    로컬 전용 opt-out: AI_INTERNAL_AUTH_DISABLED=true 를 명시적으로 설정한 경우에만 허용.
    """
    if config.AI_INTERNAL_TOKEN or config.AI_INTERNAL_AUTH_DISABLED:
        return
    raise RuntimeError(
        "AI_INTERNAL_TOKEN이 설정되지 않았습니다. 배포에선 backend·ai 양쪽 컨테이너에 "
        "같은 값을 주입해야 합니다(infra/docker-compose.yml · 배포 시크릿). "
        "로컬 개발에서 토큰 없이 띄우려면 AI_INTERNAL_AUTH_DISABLED=true 를 명시적으로 설정하세요."
    )


@asynccontextmanager
async def _lifespan(_app: FastAPI):
    _require_internal_auth_config()
    yield


app = FastAPI(title="도담 AI 분석 서버", version="0.1.0", lifespan=_lifespan)

# ── 관측: Prometheus 메트릭 노출 (S15P11B209-351) ─────────────────
#   reason: GMS(LLM/STT/TTS) 호출 지연·에러율을 관측해 모니터링 사각지대를 없앤다.
#     Day2 Prometheus가 내부망에서 ai:8000/metrics 를 스크레이프한다.
#     외부 노출은 nginx가 /ai/metrics 를 404로 차단(infra/nginx/conf.d/default.conf).
#   ⚠️ 기본 설정 유지 — 라벨은 라우트 '템플릿 경로'(예: /analyze/conversation, 고정 문자열)만
#     쓰고 요청 본문·쿼리 값은 넣지 않는다. 아동 발화 텍스트가 메트릭에 실릴 경로를 원천 차단(가드레일).
#     경로 파라미터가 있는 라우트가 없어 카디널리티도 유계 — 커스텀 라벨을 추가하지 않는다.
#   기동 순서: 미들웨어 등록(instrument)은 uvicorn 기동 전 import 시점에 끝나야 하므로 모듈 로드
#     시점인 여기에 둔다. lifespan(_lifespan)은 기동 시 내부 토큰 설정만 검증 — 이 배선과 순서 충돌 없음.
Instrumentator().instrument(app).expose(app, endpoint="/metrics", include_in_schema=False)


@app.exception_handler(RequestValidationError)
async def validation_error_without_echo(_request, exc: RequestValidationError):
    """422 검증 오류에서 입력 값 echo를 제거한다(필드 위치·오류 유형만 반환).

    reason: FastAPI 기본 422 본문은 입력 값을 그대로 되돌려주는데,
    요청에는 아이 발화(recentMessages.text)가 실릴 수 있다 — 가드레일 위반 경로 차단.
    BE는 422 본문의 errorCode만 판별하므로 INVALID_REQUEST는
    Type.OTHER → 폴백 템플릿으로 분류된다(안전 차단과 혼동 없음).
    """
    errors = [
        {"loc": [str(part) for part in err.get("loc", [])], "type": err.get("type", "")}
        for err in exc.errors()
    ]
    return JSONResponse(
        status_code=422, content={"errorCode": "INVALID_REQUEST", "errors": errors}
    )


@app.get("/health")
def health():
    """서버가 살아 있는지 확인."""
    return {"status": "ok"}


# ── 그림분석: YOLO 객체탐지 → VLM 한국어 서술 (S15P11B209-176) ─────
#   ⚠️ 이 /analyze/drawing 은 '초안' 경로다. BE↔AI 정식 객체탐지 계약
#      (/internal/ai/v1/drawings/analysis, 픽셀 bbox·UPPER_SNAKE 라벨)과는 별개.
#      여기 description 은 대화 첫 질문의 {drawing_analysis} 슬롯 재료로 쓰인다.
#   무거운 추론 의존성(ultralytics/torch)은 yolo_client가 지연 import한다.
@app.post("/analyze/drawing")
async def analyze_drawing(file: UploadFile = File(...)):
    """그림 이미지 → YOLO 객체탐지 → (bbox 이미지 + 탐지목록) → VLM 한국어 서술.

    원본 이미지는 임시파일로만 다루고 저장·로그하지 않는다(가드레일).
    """
    ext = ""
    if file.filename and "." in file.filename:
        ext = "." + file.filename.rsplit(".", 1)[-1]
    # Windows에서 추론기가 경로를 다시 열 수 있게 delete=False로 만들고 finally에서 지운다.
    with tempfile.NamedTemporaryFile(suffix=ext or ".png", delete=False) as tmp:
        tmp.write(await file.read())
        tmp_path = tmp.name
    try:
        detections, annotated_png = yolo_client.detect_and_annotate(tmp_path)
        description = vlm_client.describe(annotated_png, detections)
    finally:
        try:
            os.remove(tmp_path)
        except OSError:
            pass
        await file.close()
    return {
        "status": "ok",
        "objects": [
            {
                "label": d.label,
                "confidence": round(d.confidence, 4),
                "bbox": [round(v, 1) for v in d.bbox_xyxy],
            }
            for d in detections
        ],
        "description": description,
        "model_id": config.VLM_MODEL,
        # draft 경로는 활동 유형을 받지 않는다 — 기본 HTP 가중치·HTP 서술 프롬프트를 쓴다.
        "prompt_version": vlm_client.prompt_version_for(None),
        "pipeline_version": config.PIPELINE_VERSION,
    }


# ── F. 대화 LLM — gpt-4o-mini (real) ─────────────────────────────
class ConversationRequest(BaseModel):
    utterance: str | None = None         # STT로 받은 아이 발화. 없으면 첫 질문을 만든다.
    drawing_analysis: str | None = None  # 그림분석 결과(있으면 맥락으로)
    history: list[dict] | None = None    # 지금까지의 대화 [{"role","content"}, ...]
    child_name: str | None = None        # 아이 이름(호칭용). 없으면 "너"라고 부른다.
    speak: bool = True                   # True면 생성한 질문을 TTS(mp3)로 함께 합성
    voice: str | None = None             # TTS 목소리. 미지정 시 config.TTS_VOICE


@app.post("/analyze/conversation")
def analyze_conversation(req: ConversationRequest):
    """아이 발화(+그림분석) → 캐릭터 다음 질문 → (speak면) 곧바로 TTS로 합성.

    질문 문자열은 answer_check로 이미 정화된 상태라 그대로 TTS에 넘겨도 안전하다.
    응답(질문+음성)은 이 AI 서버를 호출한 백엔드로 반환되고, 백엔드가 프런트로 중계한다.
    (질문 생성 후 별도 /tts 왕복 없이 한 번에 받게 하려는 것.)
    """
    if req.utterance:
        question = llm_client.next_question(
            req.utterance,
            drawing_analysis=req.drawing_analysis,
            history=req.history,
            child_name=req.child_name,
        )
    else:
        question = llm_client.first_question(
            req.drawing_analysis, child_name=req.child_name
        )

    # 생성한 질문을 그대로 음성으로 — 백엔드가 질문+음성을 한 번에 받는다.
    audio_base64 = None
    if req.speak:
        audio = tts_client.synthesize(question, voice=req.voice)
        audio_base64 = base64.b64encode(audio).decode()

    return {
        "status": "ok",
        "question": question,
        "audio_base64": audio_base64,  # speak=False면 null
        "tts_model_id": config.TTS_MODEL if req.speak else None,
        "chips": [],  # 선택칩 생성은 편주희 프롬프트 영역
        "model_id": config.LLM_MODEL,
        "prompt_version": llm_client.PROMPT_VERSION,
        "pipeline_version": config.PIPELINE_VERSION,
    }


# ── BE 내부 계약: 대화 질문 1건 생성 (183) ───────────────────────
def _internal_auth_ok(token: str = "", api_key: str = "") -> bool:
    """내부 호출 인증. X-Internal-Token(기존 BE) 또는 X-Internal-Api-Key(정본 §3.2) 중 하나면 통과.

    reason: 정본 명세는 헤더 이름을 X-Internal-Api-Key로 규정하지만, 이미 배포된 BE
    소비자(RestClientAiQuestionClient·RestClientAiSttClient)는 X-Internal-Token을 보낸다.
    한쪽만 받으면 전환 시점에 BE 호출이 401 → BE가 폴백 템플릿으로 조용히 대체된다.
    두 헤더를 함께 받아 BE가 자기 속도로 옮겨오게 하고, 전환 확인 후 구 헤더를 제거한다.
    기본 시크릿은 하나다 — AI_INTERNAL_API_KEY 미설정 시 AI_INTERNAL_TOKEN과 같은 값(config).
    """
    if config.AI_INTERNAL_AUTH_DISABLED:
        return True
    expectations = []
    if config.AI_INTERNAL_TOKEN:
        expectations.append((token, config.AI_INTERNAL_TOKEN))
    if config.AI_INTERNAL_API_KEY:
        expectations.append((api_key, config.AI_INTERNAL_API_KEY))
    if not expectations:
        return False
    # compare_digest: 비교 시간 차이로 시크릿이 유추되지 않게(타이밍 공격 방지).
    return any(
        hmac.compare_digest(received or "", expected)
        for received, expected in expectations
    )


def _safe_stt_suffix(filename: str | None) -> str:
    """원본 이름을 보존하지 않고 OpenAI 형식 판별에 필요한 확장자만 만든다."""
    if not filename or "." not in filename:
        return ".mp3"
    extension = filename.rsplit(".", 1)[-1].lower()
    if not extension.isalnum() or len(extension) > 10:
        return ".mp3"
    return f".{extension}"


@app.post("/internal/ai/v1/speech/stt")
async def internal_speech_stt(
    file: UploadFile = File(...),
    x_internal_token: str = Header(default="", alias="X-Internal-Token"),
    x_internal_api_key: str = Header(default="", alias="X-Internal-Api-Key"),
    x_request_id: str = Header(default="", alias="X-Request-Id"),
):
    """BE 전용 STT adapter: 파일은 임시로만 처리하고 계약 DTO로 정규화한다."""
    if not _internal_auth_ok(x_internal_token, x_internal_api_key):
        return JSONResponse(
            status_code=401, content={"errorCode": "INVALID_INTERNAL_TOKEN"}
        )
    if not x_request_id.strip():
        return JSONResponse(status_code=422, content={"errorCode": "INVALID_REQUEST"})

    started_at = time.monotonic()
    tmp_path = None
    try:
        # transcribe가 경로로 파일을 다시 열기 때문에 delete=False로 만들고 닫은 뒤 넘긴다.
        #   Windows는 NamedTemporaryFile이 열려 있는 동안 같은 파일의 재오픈을 막아
        #   PermissionError가 났다(analyze_report가 이미 같은 이유로 delete=False를 쓴다).
        with tempfile.NamedTemporaryFile(
            suffix=_safe_stt_suffix(file.filename), delete=False
        ) as tmp:
            tmp.write(await file.read())
            tmp_path = tmp.name
        text = stt_client.transcribe(tmp_path)
        return {
            "text": text,
            "confidence": None,
            "modelName": config.STT_MODEL,
            "processingTimeMs": int((time.monotonic() - started_at) * 1000),
        }
    except (RuntimeError, OSError):
        # OSError까지 잡는다. 임시파일·디스크 오류가 500으로 누출되면 BE가 상류 장애로
        # 분류하지 못하고 스택트레이스만 남는다.
        return JSONResponse(status_code=502, content={"errorCode": "AI_UPSTREAM_ERROR"})
    finally:
        if tmp_path is not None:
            try:
                os.remove(tmp_path)
            except OSError:
                pass
        await file.close()


@app.post(
    "/internal/ai/v1/conversations/question",
    response_model=internal_contracts.QuestionResponse,
)
def internal_conversation_question(
    req: internal_contracts.QuestionRequest,
    x_internal_token: str = Header(default="", alias="X-Internal-Token"),
    x_internal_api_key: str = Header(default="", alias="X-Internal-Api-Key"),
    x_request_id: str = Header(default="", alias="X-Request-Id"),
):
    """BE(ConversationQuestionService → RestClientAiQuestionClient)가 호출하는 다음 질문 생성.

    응답 ↔ BE 분류 매핑:
    - 200 + 계약 응답(isContractValidFor 통과) → BE가 질문 저장
    - 422 {"errorCode": "AI_SAFETY_POLICY_BLOCKED"} → BE가 저장 없이 사용자 422로 종료
    - 422 {"errorCode": "INVALID_REQUEST"}(검증 실패) → BE Type.OTHER → 폴백 템플릿
    - 502(GMS 재시도 소진·재시도 불가 오류) → BE Type.OTHER → 폴백 템플릿
    - 401(내부 토큰 불일치) → BE Type.OTHER → 폴백 템플릿(운영 로그로 원인 확인)

    루프·질문 수 상한·폴백 템플릿은 BE 소유 — 여기서는 질문 1건만 생성한다(stateless).
    """
    if not _internal_auth_ok(x_internal_token, x_internal_api_key):
        # ⚠️ 수신 토큰 값은 본문·로그 어디에도 남기지 않는다.
        return JSONResponse(
            status_code=401, content={"errorCode": "INVALID_INTERNAL_TOKEN"}
        )
    try:
        return question_service.generate(req, x_request_id)
    except question_service.SafetyBlockedError as e:
        # BE RestClientAiQuestionClient는 422 본문의 errorCode가 정확히
        # "AI_SAFETY_POLICY_BLOCKED"일 때만 SAFETY_POLICY_BLOCKED로 분류한다.
        return JSONResponse(
            status_code=422,
            content={
                "errorCode": "AI_SAFETY_POLICY_BLOCKED",
                "blockReasonCode": e.block_reason_code,
                "ruleVersion": e.rule_version,
            },
        )
    except question_service.UpstreamError as e:
        # 5xx → BE Type.OTHER → 폴백 템플릿. 원인 유형은 이미 warning 로그로 남았다.
        return JSONResponse(status_code=502, content={"errorCode": e.error_code})


# ── BE 내부 계약: 음성 STT(E) / TTS(G) (179 · A안 2026-07-23) ────
#   공개 초안 /stt·/tts 는 삭제했다: nginx /ai/ 프록시를 타고 무인증으로
#   인터넷에 노출되던 경로였다(GMS 비용 소진 + 아동 음성 경로 공개).
#   /internal/ai/v1/* 로 옮기면 기존 nginx /ai/internal/ 차단(404)이 그대로
#   적용되고, BE 호출도 conversations/question과 같은 토큰 패턴으로 통일된다.
#   계약: docs/ai/ai-speech-contract.md


@app.post(
    "/internal/ai/v1/speech/synthesis",
    response_model=internal_contracts.SynthesisResponse,
)
def internal_speech_synthesis(
    req: internal_contracts.SynthesisRequest,
    x_internal_token: str = Header(default="", alias="X-Internal-Token"),
    x_internal_api_key: str = Header(default="", alias="X-Internal-Api-Key"),
):
    """BE(-299 질문 TTS 생성)가 호출하는 텍스트→음성(mp3 base64) 합성."""
    if not _internal_auth_ok(x_internal_token, x_internal_api_key):
        return JSONResponse(
            status_code=401, content={"errorCode": "INVALID_INTERNAL_TOKEN"}
        )
    started = time.monotonic()
    try:
        audio = tts_client.synthesize(req.text, voice=req.voice)
    except (RuntimeError, OSError):
        # transcription과 동일 — 상류(GMS) 장애와 예상 못한 OS 오류를 502로 매핑한다.
        return JSONResponse(status_code=502, content={"errorCode": "AI_UPSTREAM_ERROR"})
    return internal_contracts.SynthesisResponse(
        audio_base64=base64.b64encode(audio).decode(),
        voice=req.voice or config.TTS_VOICE,
        model_name=config.TTS_MODEL,
        processing_time_ms=int((time.monotonic() - started) * 1000),
    )


# ── 관찰 리포트 생성 — (그림 이미지→YOLO+VLM 서술) + 활동 집계·감정 → 관찰 초안 (S15P11B209-180) ──
#   ⚠️ 이 /analyze/report 는 '초안' 경로다. 정식 소비자는 BE AiObservationClient이고,
#      현재 활성 구현은 MockAiObservationClient(고정 fixture)다. 실제 HTTP 배선(mode=http)과
#      내부 토큰 계약, 그림 서술을 BE가 어떻게 넘길지는 후속 이슈가 같은 경계 뒤에 붙인다.
#   ⚠️ BE 계약(ObservationGenerationRequest)엔 그림 서술이 없다. 그래서 관찰을 그림에 근거하게
#      하려고, 이 draft 경로에서 그림 이미지를 받아 기존 yolo_client+vlm_client로 서술을 만들어
#      리포트 입력에 넣는다. 이미지는 임시파일로만 다루고 저장·로그하지 않는다(가드레일).
# ── 정본 계약: 내부 API v1 (API_명세서_최종.md §19) ──────────────
#   정본은 /internal/v1/* 를 규정한다. 기존 /internal/ai/v1/* 는 이미 배포된 BE 소비자가
#   경로를 하드코딩해 호출 중이라 그대로 둔다 — 두 경로 병행은 정본 §21이 허용한 전환 방식이고,
#   BE가 옮겨온 뒤 구 경로를 제거한다(3단계).
#   ⚠️ 같은 대상에 서로 다른 로직을 두지 않는다(§21) — 아래는 구 경로에 없던 신규 계약이다.


@app.get("/internal/v1/health")
def internal_health():
    """§19.1 AI-05 · §19.8. AI 서버와 구성요소별 모델 준비 상태.

    준비 여부 판정 근거:
    - objectDetection: HTP·그림일기 YOLO 가중치 존재 + checksum 무결성. 하나라도
      손상·부재면 출시 대상 활동 전체가 준비되지 않은 것으로 보고 NOT_READY.
      가중치는 프로세스 동안 불변이라 첫 계산을 캐시해 poll마다 재해시하지 않는다(604).
    - vision·language·stt·tts: GMS 키 설정 여부. 원격 모델이라 실제 호출로 확인하면
      health 조회마다 비용이 발생하므로 설정 유무를 대리 지표로 쓴다.
    - rag: 배포된 인덱스 실물 기준(S15P11B209-614) — env 선언이 아니라 rag.knowledge_base_version()
      (인덱스 파일 로드 성공 + KB Version)로 판정한다. 선언만 있고 파일이 없는 READY를 막는다.

    ⚠️ 가중치 '경로'는 노출하지 않는다(서버 파일 구조 힌트) — 준비 여부만.
    ⚠️ status는 서버 응답 가능 여부이고, 구성요소 상태는 models로 따로 알린다.
       정본 §19.8이 정의한 값은 READY뿐이라 미준비는 NOT_READY로 표기한다.
    """
    from datetime import datetime, timezone

    gms_ready = "READY" if config.GMS_KEY else "NOT_READY"
    detection_readiness = yolo_client.model_readiness()
    # 배포된 인덱스 실물 기준 — 미배포면 None(로드는 retriever가 캐시하므로 poll 비용 없음).
    rag_kb_version = rag.knowledge_base_version()

    def ready(flag: bool) -> str:
        return "READY" if flag else "NOT_READY"

    return {
        "status": "UP",
        "models": {
            "objectDetection": ready(
                all(detection_readiness.get(key, False) for key in ("htp", "sketch"))
            ),
            "vision": gms_ready,
            "language": gms_ready,
            "stt": gms_ready,
            "tts": gms_ready,
            # 근거 검색이 없으면 근거 기반 문장을 만들 수 없다(§24.3) — 준비됨으로 표시하지 않는다.
            "rag": ready(rag_kb_version is not None),
        },
        "knowledgeBaseVersion": rag_kb_version,
        "timestamp": datetime.now(timezone.utc)
        .isoformat(timespec="milliseconds")
        .replace("+00:00", "Z"),
        "pipelineVersion": config.PIPELINE_VERSION,
    }


@app.post(
    "/internal/v1/analyses",
    response_model=internal_contracts.AnalysisResponse,
)
def internal_analyses(
    req: internal_contracts.AnalysisRequest,
    x_internal_token: str = Header(default="", alias="X-Internal-Token"),
    x_internal_api_key: str = Header(default="", alias="X-Internal-Api-Key"),
    x_request_id: str = Header(default="", alias="X-Request-Id"),
):
    """§19.1 AI-01. 객체·시각·행동·대화 종합 분석.

    응답 매핑:
    - 200 + §19.4 계약 → BE가 결과 저장(status=SUCCESS | PARTIAL_SUCCESS)
    - 401 INVALID_INTERNAL_TOKEN → 내부 인증 실패
    - 422 ANALYSIS_INPUT_INVALID → 그림을 못 가져왔거나 checksum 불일치(같은 입력이면 재시도 무의미)
    - 502 AI_UPSTREAM_ERROR → 탐지·서술 실패(재시도 여지 있음)

    ⚠️ 이 서버는 상태를 저장하지 않는다 — 분석 행 생성·상태 전이·재시도 정책은 BE 소유다.
    """
    if not _internal_auth_ok(x_internal_token, x_internal_api_key):
        return JSONResponse(
            status_code=401, content={"errorCode": "INVALID_INTERNAL_TOKEN"}
        )
    try:
        return analysis_service.analyze(req, x_request_id)
    except analysis_service.AnalysisInputError:
        # 사유 문구에 URL·이미지 내용이 들어가지 않도록 코드만 반환한다.
        return JSONResponse(
            status_code=422, content={"errorCode": "ANALYSIS_INPUT_INVALID"}
        )
    except analysis_service.AnalysisUpstreamError:
        return JSONResponse(status_code=502, content={"errorCode": "AI_UPSTREAM_ERROR"})


@app.post(
    "/internal/v1/observations",
    response_model=internal_contracts.ObservationGenerationResult,
)
def internal_observations(
    req: internal_contracts.ObservationGenerationRequest,
    x_internal_token: str = Header(default="", alias="X-Internal-Token"),
    x_internal_api_key: str = Header(default="", alias="X-Internal-Api-Key"),
    x_request_id: str = Header(default="", alias="X-Request-Id"),
):
    """BE(RestClientAiObservationClient)가 호출하는 관찰 리포트 초안 생성.

    같은 생성기를 쓰는 /analyze/report 는 멀티파트에 인증이 없어 nginx /ai/ 프록시로
    노출되는 계열이다. 아동 활동 데이터를 보내는 내부 호출은 다른 BE→AI 계약과 같은 형태
    (JSON 본문 + X-Internal-Token)로 두기 위해 이 경로를 별도로 제공한다.

    응답 매핑:
    - 200 + BE ObservationGenerationResult 계약 → BE가 리포트 저장
    - 401 INVALID_INTERNAL_TOKEN → 내부 인증 실패
    - 422 INVALID_REQUEST → analysisType이 FINAL이 아님(같은 입력이면 재시도 무의미)
    - 502 AI_UPSTREAM_ERROR → 상류(GMS) 장애·응답 형식 오류

    그림 서술은 받지 않는다. 이미지가 필요한 호출은 파일을 함께 보내는 /analyze/report를 쓴다.
    """
    if not _internal_auth_ok(x_internal_token, x_internal_api_key):
        return JSONResponse(
            status_code=401, content={"errorCode": "INVALID_INTERNAL_TOKEN"}
        )
    if req.analysis_type != "FINAL":
        return JSONResponse(status_code=422, content={"errorCode": "INVALID_REQUEST"})
    try:
        return report_client.generate(req, drawing_description=None)
    except (RuntimeError, OSError):
        return JSONResponse(status_code=502, content={"errorCode": "AI_UPSTREAM_ERROR"})


@app.post("/analyze/report", response_model=internal_contracts.ObservationGenerationResult)
async def analyze_report(
    request: str = Form(...),
    file: UploadFile | None = File(default=None),
):
    """활동 요청(JSON) + 선택적 그림 이미지 → 그림 서술 근거 관찰 리포트 초안(BE 계약 형태).

    - request: ObservationGenerationRequest JSON 문자열(멀티파트 form 필드).
    - file: 최종 그림 이미지(선택). 있으면 YOLO+VLM으로 서술을 만들어 관찰 근거로 넣고,
      없으면 활동 데이터(집계·감정·대표 발화)만으로 생성한다.

    analysisType 이 FINAL 이 아니면 422(BE Mock과 동일한 계약 위반 취급).
    GMS 상류 장애·서술 실패·응답 형식 오류는 502로 매핑한다(진단 문구를 지어내 반환하지 않는다).
    """
    try:
        req = internal_contracts.ObservationGenerationRequest.model_validate_json(request)
    except ValidationError:
        return JSONResponse(status_code=422, content={"errorCode": "INVALID_REQUEST"})
    if req.analysis_type != "FINAL":
        return JSONResponse(status_code=422, content={"errorCode": "INVALID_REQUEST"})

    tmp_path = None
    try:
        drawing_description = None
        if file is not None:
            ext = ""
            if file.filename and "." in file.filename:
                ext = "." + file.filename.rsplit(".", 1)[-1]
            # Windows에서 추론기가 경로를 다시 열 수 있게 delete=False로 만들고 finally에서 지운다.
            with tempfile.NamedTemporaryFile(suffix=ext or ".png", delete=False) as tmp:
                tmp.write(await file.read())
                tmp_path = tmp.name
            detections, annotated_png = yolo_client.detect_and_annotate(tmp_path)
            drawing_description = vlm_client.describe(annotated_png, detections)
        return report_client.generate(req, drawing_description=drawing_description)
    except RuntimeError:
        return JSONResponse(status_code=502, content={"errorCode": "AI_UPSTREAM_ERROR"})
    finally:
        if tmp_path is not None:
            try:
                os.remove(tmp_path)
            except OSError:
                pass
        if file is not None:
            await file.close()

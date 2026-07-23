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

from fastapi import FastAPI, File, Header, UploadFile
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from prometheus_fastapi_instrumentator import Instrumentator
from pydantic import BaseModel

import config
import internal_contracts
import llm_client
import question_service
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
        "prompt_version": vlm_client.PROMPT_VERSION,
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
def _internal_token_ok(received: str) -> bool:
    """X-Internal-Token 검사. 기본은 토큰 필수 — 미설정 시 무조건 거부.

    이전의 "미설정이면 검사 생략" fallback은 제거했다(safety review C-183-1):
    compose 미주입 + nginx /ai/ 접두제거 프록시와 결합하면 이 내부 계약이
    무인증으로 인터넷에 노출되는 사고 경로였다. 미설정 상태는 기동 시점에
    이미 실패하지만(_require_internal_auth_config), 어떤 경로로든 떠 있어도
    무인증 통과는 없도록 여기서도 거부한다(심층 방어).
    명시적 opt-out(AI_INTERNAL_AUTH_DISABLED=true, 로컬 개발 전용)일 때만 검사 생략.
    compare_digest: 문자열 비교 시간 차이로 토큰이 유추되지 않게(타이밍 공격 방지).
    """
    if config.AI_INTERNAL_AUTH_DISABLED:
        return True
    if not config.AI_INTERNAL_TOKEN:
        return False
    return hmac.compare_digest(received or "", config.AI_INTERNAL_TOKEN)


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
    x_request_id: str = Header(default="", alias="X-Request-Id"),
):
    """BE 전용 STT adapter: 파일은 임시로만 처리하고 계약 DTO로 정규화한다."""
    if not _internal_token_ok(x_internal_token):
        return JSONResponse(
            status_code=401, content={"errorCode": "INVALID_INTERNAL_TOKEN"}
        )
    if not x_request_id.strip():
        return JSONResponse(status_code=422, content={"errorCode": "INVALID_REQUEST"})

    started_at = time.monotonic()
    try:
        with tempfile.NamedTemporaryFile(suffix=_safe_stt_suffix(file.filename)) as tmp:
            tmp.write(await file.read())
            tmp.flush()
            text = stt_client.transcribe(tmp.name)
        return {
            "text": text,
            "confidence": None,
            "modelName": config.STT_MODEL,
            "processingTimeMs": int((time.monotonic() - started_at) * 1000),
        }
    except RuntimeError:
        return JSONResponse(status_code=502, content={"errorCode": "AI_UPSTREAM_ERROR"})
    finally:
        await file.close()


@app.post(
    "/internal/ai/v1/conversations/question",
    response_model=internal_contracts.QuestionResponse,
)
def internal_conversation_question(
    req: internal_contracts.QuestionRequest,
    x_internal_token: str = Header(default="", alias="X-Internal-Token"),
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
    if not _internal_token_ok(x_internal_token):
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
):
    """BE(-299 질문 TTS 생성)가 호출하는 텍스트→음성(mp3 base64) 합성."""
    if not _internal_token_ok(x_internal_token):
        return JSONResponse(
            status_code=401, content={"errorCode": "INVALID_INTERNAL_TOKEN"}
        )
    started = time.monotonic()
    try:
        audio = tts_client.synthesize(req.text, voice=req.voice)
    except RuntimeError:
        # transcription과 동일 — 상류(GMS) 장애는 502로 매핑.
        return JSONResponse(status_code=502, content={"errorCode": "AI_UPSTREAM_ERROR"})
    return internal_contracts.SynthesisResponse(
        audio_base64=base64.b64encode(audio).decode(),
        voice=req.voice or config.TTS_VOICE,
        model_name=config.TTS_MODEL,
        processing_time_ms=int((time.monotonic() - started) * 1000),
    )


@app.post("/analyze/report")
def analyze_report():
    """그림 + 대화 + 감정 종합 → 관찰 리포트. (mock)"""
    return {
        "status": "ok",
        "observations": [
            "집을 화면 가운데에 크게 그렸어요.",
            "따뜻한 색을 주로 사용했어요.",
        ],
        "key_dialogues": [
            {"speaker": "child", "text": "여기는 우리 집이야."},
            {"speaker": "bear", "text": "누구랑 같이 살아?"},
        ],
        "check_points": [
            "가족을 그릴 때 어떤 이야기를 나눴는지 함께 이야기해 보세요.",
        ],
        "disclaimer": "이 리포트는 의학적 진단이 아니라 아이를 이해하기 위한 관찰 참고 자료예요. 걱정되는 점이 있다면 전문가와 상담해 주세요.",
    }

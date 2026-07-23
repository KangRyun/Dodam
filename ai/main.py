"""도담 AI 분석 서버 — 처리 흐름 배선.

흐름:  아동 발화 STT(E) → 대화 LLM(F: 그림분석+발화→질문) → 질문 TTS(G) → (대화 루프)

배선(엔드포인트 호출)은 이강륜(173). F의 프롬프트 '내용'·칩 생성과 그림분석 모델은 편주희.

대화 루프 위치 확정(183, 2026-07-23 · BE 283 머지 근거):
- 루프(질문 반복·질문 수 상한·세션 잠금·폴백 템플릿)는 BE ConversationQuestionService 소유.
- 이 서버는 stateless '질문 1건 생성' 내부 계약(/internal/ai/v1/conversations/question)만 제공.
- GMS 일시 오류는 이 서버 안에서 지수 백오프로 제한 재시도(question_service.py).
  근거 정리: _workspace/183_ai_loop-decision.md

⚠️ /analyze/* 등 기존 경로의 계약은 '초안'이고, /internal/ai/v1/* 는 BE 코드와 맞춘 내부 계약.
원본 음성·발화는 저장·로그하지 않는다(가드레일).
"""

import base64
import hmac
import tempfile
from contextlib import asynccontextmanager

from fastapi import FastAPI, File, Header, UploadFile
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel

import config
import internal_contracts
import llm_client
import question_service
import stt_client
import tts_client


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


# ── 그림분석 / 리포트: 아직 mock (편주희 모델 연결 전) ─────────────
@app.post("/analyze/drawing")
def analyze_drawing():
    """그림 이미지 분석 → 오브젝트/설명. (mock)"""
    return {
        "status": "ok",
        "objects": [{"label": "집", "confidence": 0.9}],
        "description": "집과 나무가 보이는 그림이에요",
    }


# ── E. 아동 발화 STT — whisper-1 (real) ──────────────────────────
@app.post("/stt")
async def stt(file: UploadFile = File(...)):
    """음성 파일 → 텍스트. (원본 음성은 임시파일로만 다루고 저장·로그 안 함)"""
    ext = ""
    if file.filename and "." in file.filename:
        ext = "." + file.filename.rsplit(".", 1)[-1]
    with tempfile.NamedTemporaryFile(suffix=ext or ".mp3") as tmp:
        tmp.write(await file.read())
        tmp.flush()
        text = stt_client.transcribe(tmp.name)
    return {
        "status": "ok",
        "text": text,
        "confidence": None,  # whisper-1은 단순 신뢰도 미제공(스키마 유지용 null)
        "model_id": config.STT_MODEL,
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


# ── G. 질문/답변 TTS — gpt-4o-mini-tts (real) ────────────────────
class TtsRequest(BaseModel):
    text: str
    voice: str | None = None


@app.post("/tts")
def tts(req: TtsRequest):
    """텍스트 → 음성(mp3, base64)."""
    audio = tts_client.synthesize(req.text, voice=req.voice)
    return {
        "status": "ok",
        "audio_url": None,
        "audio_base64": base64.b64encode(audio).decode(),
        "duration_sec": None,
        "model_id": config.TTS_MODEL,
        "pipeline_version": config.PIPELINE_VERSION,
    }


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

"""내부 대화 질문 생성 서비스 (S15P11B209-183).

역할: BE 내부 계약 요청 → GMS 대화 LLM 호출(제한적 재시도) → 계약 응답 조립.

루프 위치 확정(2026-07-23, BE 283 머지 근거):
- 대화 루프(질문 반복·질문 수 상한·세션 잠금·폴백 템플릿)는 BE
  ConversationQuestionService가 소유한다.
- 이 서버는 상태 없는 '질문 1건 생성기' — 세션 상태를 들고 있지 않고,
  요청에 담긴 문맥(recentMessages·detectedObjects)만 사용한다.
  근거 정리: _workspace/183_ai_loop-decision.md

재시도 예산(BE read timeout 15초 안쪽):
- 시도당 GMS timeout 4s × 최대 3회(최초 1 + 재시도 2) + 지수 백오프(0.5s + 1.0s)
  = 최악 13.5s < 15s. 초과하면 BE가 READ_TIMEOUT으로 끊고 폴백 템플릿을 저장한다.
- 일시 오류(연결 실패·타임아웃·5xx)만 재시도한다. 4xx(키 오류·잘못된 요청·429)는
  즉시 실패. reason: 4xx는 다시 보내도 같은 결과라 예산만 소모하고,
  429는 짧은 백오프 재시도가 오히려 부하를 키운다.
  (대안 검토: 429만 1회 재시도 — 트래픽이 커지면 재검토. 지금은 BE 폴백이 있어 불필요.)

가드레일:
- 로그에는 request_id·에러 유형·시도 횟수만 남긴다.
  프롬프트(아이 발화 포함)·GMS 키·생성된 질문 원문은 절대 로그 금지.
"""

from __future__ import annotations

import logging
import time

from openai import APIConnectionError, APIStatusError, OpenAIError

import config
import llm_client
from gms import get_client
from internal_contracts import (
    DetectedObject,
    QuestionOption,
    QuestionRequest,
    QuestionResponse,
    SafetyResult,
)

logger = logging.getLogger(__name__)

# 내부 계약 경로도 draft 경로(llm_client)와 같은 프롬프트 파일을 쓴다 — 버전도 그대로 따른다.
# 프롬프트 파일 단위 버전 관리 체계는 S15P11B209-595에서 정식화한다.
PROMPT_VERSION = llm_client.PROMPT_VERSION


class UpstreamError(Exception):
    """GMS 최종 실패(재시도 소진 또는 재시도 불가 오류).

    엔드포인트가 502로 매핑 → BE Type.OTHER → 폴백 템플릿 저장 경로.
    """

    def __init__(self, error_code: str, cause_type: str):
        super().__init__(error_code)
        self.error_code = error_code  # AI_UPSTREAM_UNAVAILABLE | AI_UPSTREAM_REJECTED | AI_EMPTY_COMPLETION
        self.cause_type = cause_type  # 원인 예외 클래스명(내용 아님 — 로그 안전)


class SafetyBlockedError(Exception):
    """안전 정책 차단. 엔드포인트가 422 AI_SAFETY_POLICY_BLOCKED로 매핑 →
    BE가 저장 없이 사용자 422로 종료하는 경로."""

    def __init__(self, block_reason_code: str, rule_version: str):
        super().__init__(block_reason_code)
        self.block_reason_code = block_reason_code
        self.rule_version = rule_version


# ── 프롬프트 조립 (S15P11B209-589) ──────────────────────────────
# 이전 placeholder는 무맥락 고정 시스템 프롬프트 + "[상황] 아이가 방금 그림을 그렸어요"
# 고정 문구를 써서 첫 질문이 매번 비슷하게 고정됐다(첫 질문 고정 현상).
# 이제 draft 경로가 이미 검증한 프롬프트(first_question.txt·conversations.txt)를 재사용해
# 그림 탐지 객체·대화 문맥 기반으로 생성한다 — 두 경로를 한 프롬프트로 통일.
# ⚠️ 내부 계약엔 아이 이름이 없다(개인정보 최소화) → 항상 "너"로 부른다.

# 난이도별 말투 가이드. draft 프롬프트에 덧붙여 연령/난이도에 맞는 어투를 유도한다.
# (연령대별 길이·어휘 규칙 세분화·강화는 S15P11B209-590에서 확장.)
_DIFFICULTY_TONE = {
    "PRESCHOOL": "유아에게 말하듯 아주 짧고 쉬운 말",
    "LOWER_ELEMENTARY": "초등 저학년에게 말하듯 쉬운 말",
    "UPPER_ELEMENTARY": "초등 고학년에게 말하듯 또렷하고 쉬운 말",
    "SUPPORT": "천천히, 아주 쉽고 다정한 말",
}


def _tone(req: QuestionRequest) -> str:
    """난이도에 맞는 말투 지침. 알 수 없는 값이면 저학년 기준으로 둔다."""
    return _DIFFICULTY_TONE.get(req.difficulty, _DIFFICULTY_TONE["LOWER_ELEMENTARY"])


def _drawing_analysis_text(req: QuestionRequest) -> str | None:
    """탐지 객체를 첫 질문 프롬프트의 {drawing_analysis} 재료(쉼표 목록)로 만든다."""
    if not req.detected_objects:
        return None
    return ", ".join(o.object_name or o.object_code for o in req.detected_objects)


def _last_child_index(req: QuestionRequest) -> int | None:
    """가장 최근 아이 발화(텍스트 있는 것)의 인덱스. 없으면 None(=첫 질문)."""
    for index in range(len(req.recent_messages) - 1, -1, -1):
        message = req.recent_messages[index]
        if (message.sender_type or "").upper() == "CHILD" and (message.text or "").strip():
            return index
    return None


def _history_dicts(messages: list) -> list[dict]:
    """recent_messages → llm_client._format_history가 받는 [{"role","content"}] 형태로."""
    turns: list[dict] = []
    for m in messages:
        if not (m.text or "").strip():
            continue
        role = "user" if (m.sender_type or "").upper() == "CHILD" else "assistant"
        turns.append({"role": role, "content": m.text})
    return turns


def _build_messages(req: QuestionRequest) -> list[dict]:
    """요청 문맥 → GMS messages. draft 프롬프트를 재사용해 컨텍스트 기반으로 생성한다.

    - 아이 발화가 아직 없으면: 첫 질문 프롬프트(그림 탐지 객체 기반).
    - 아이 발화가 있으면: 다음 질문 프롬프트(마지막 발화 + 그 이전 이력).
    연령대는 아이 나이를 넘기고, 난이도별 말투 지침을 덧붙인다.
    """
    age_band = str(req.child_age)
    drawing = _drawing_analysis_text(req)
    last_child = _last_child_index(req)

    if last_child is None:
        system = llm_client.render_first_question_prompt(drawing, age_band=age_band)
        trigger = llm_client.FIRST_QUESTION_TRIGGER
    else:
        utterance = req.recent_messages[last_child].text or ""
        history = _history_dicts(req.recent_messages[:last_child])
        system = llm_client.render_next_question_prompt(
            utterance, drawing_analysis=drawing, history=history, age_band=age_band
        )
        trigger = llm_client.NEXT_QUESTION_TRIGGER

    system = f"{system}\n\n[말투 지침] {_tone(req)}"
    return [
        {"role": "system", "content": system},
        {"role": "user", "content": trigger},
    ]


def _pick_question_purpose(req: QuestionRequest) -> str:
    """질문 목적 결정. (placeholder — 계약 통과용 최소 규칙)

    TODO(편주희): 프롬프트 설계와 함께 목적 분류(EXPRESSION 포함)를 확정.
    """
    if any((m.sender_type or "").upper() == "CHILD" for m in req.recent_messages):
        return "FOLLOW_UP"
    if req.detected_objects:
        return "OBJECT_DESCRIPTION"
    return "DRAWING_CONTEXT"


# TODO(편주희): 질문 내용과 연동된 실제 선택칩 생성 규칙. 아래는 계약 통과용 placeholder
#  (OPTION 허용 시 options가 비어 있으면 BE가 스키마 위반으로 보고 폴백 템플릿을 쓴다).
#  칩 문구는 아동 화면에 그대로 노출되므로 쉽고 따뜻한 말만 사용한다.
_PLACEHOLDER_OPTIONS = [
    QuestionOption(code="CHIP_YES", label="응, 맞아!"),
    QuestionOption(code="CHIP_NO", label="음, 아니야"),
    QuestionOption(code="CHIP_TELL_MORE", label="더 이야기해 줄래"),
]


def _pick_target_object(req: QuestionRequest) -> DetectedObject | None:
    """질문이 가리키는 객체 선택. (placeholder: 신뢰도 최고 객체)

    요청의 detectedObjects는 BE가 이미 검증(objectCode·confidence·정규화 bbox)한
    값이라 그대로 되돌려도 응답 계약을 통과한다.
    TODO(편주희): 질문 내용과 실제로 연결되는 객체를 고르도록 프롬프트와 함께 확정.
    """
    if not req.detected_objects:
        return None
    return max(req.detected_objects, key=lambda o: o.confidence)


def _evaluate_safety(question_text: str, rule_version: str) -> SafetyResult:
    """생성된 질문의 안전 규칙 판단. (통과 스텁)

    TODO(편주희): 금지 표현·위험 신호 판단 규칙(ai/prompts/의 안전 규칙 버전과 연동).
    차단으로 판단되면 여기서 SafetyBlockedError를 던진다 →
    엔드포인트가 422 AI_SAFETY_POLICY_BLOCKED로 매핑(BE는 저장 없이 사용자 422).
    ⚠️ 차단 시에도 질문 원문을 로그에 남기지 않는다 — reason 코드만.
    """
    return SafetyResult(status="PASSED", rule_version=rule_version, block_reason_code=None)


# ── GMS 호출 + 제한적 재시도 ────────────────────────────────────
def _is_retryable(error: OpenAIError) -> bool:
    """일시 오류(재시도 가치 있음)인지 분류.

    - APIConnectionError: 연결 실패·타임아웃(APITimeoutError는 하위 클래스) → 재시도
    - APIStatusError 5xx: 게이트웨이/서버 일시 장애 → 재시도
    - 그 외(4xx: 인증·요청 오류·429 포함): 재시도해도 같은 결과 → 즉시 실패
    """
    if isinstance(error, APIConnectionError):
        return True
    if isinstance(error, APIStatusError):
        return error.status_code >= 500
    return False


def _call_gms_with_retry(messages: list[dict], request_id: str) -> tuple[str, str]:
    """GMS 질문 생성 호출. 성공 시 (질문 텍스트, 실제 서빙 모델명)을 반환한다.

    - with_options(timeout=4s, max_retries=0):
      공용 클라이언트의 60s timeout과 SDK 자체 재시도(기본 2회)를 이 경로에서만 끈다.
      reason: SDK 내부 재시도가 살아 있으면 우리 백오프와 겹쳐 BE 15s 예산을 넘는다.
    - 백오프: base × 2^(재시도 차수-1) → 0.5s, 1.0s.
    """
    client = get_client().with_options(
        timeout=config.QUESTION_LLM_TIMEOUT_SEC,
        max_retries=0,
    )
    total_attempts = config.QUESTION_LLM_MAX_RETRIES + 1
    last_error: OpenAIError | None = None
    for attempt in range(1, total_attempts + 1):
        if attempt > 1:
            time.sleep(config.QUESTION_LLM_BACKOFF_BASE_SEC * (2 ** (attempt - 2)))
        try:
            resp = client.chat.completions.create(
                model=config.LLM_MODEL,
                messages=messages,
                temperature=0.6,  # 아동 대화는 튀지 않게 다소 낮게(llm_client와 동일 기준)
            )
            text = resp.choices[0].message.content or ""
            served_model = getattr(resp, "model", "") or ""
            return text, served_model
        except OpenAIError as e:
            # ⚠️ messages(아이 발화 포함 가능)는 로그 금지 — 유형·시도 횟수·request_id만.
            logger.warning(
                "GMS 질문 생성 실패: type=%s attempt=%d/%d request_id=%s",
                type(e).__name__,
                attempt,
                total_attempts,
                request_id,
            )
            if not _is_retryable(e):
                raise UpstreamError("AI_UPSTREAM_REJECTED", type(e).__name__) from e
            last_error = e
    raise UpstreamError(
        "AI_UPSTREAM_UNAVAILABLE",
        type(last_error).__name__ if last_error else "Unknown",
    ) from last_error


# ── 진입점 ──────────────────────────────────────────────────────
def generate(req: QuestionRequest, request_id: str) -> QuestionResponse:
    """질문 1건 생성 — BE isContractValidFor를 통과하는 응답을 조립한다.

    Raises:
        UpstreamError: GMS 최종 실패(→ 502, BE 폴백 템플릿 경로).
        SafetyBlockedError: 안전 정책 차단(→ 422, BE 사용자 422 경로).
    """
    started = time.monotonic()
    messages = _build_messages(req)
    text, served_model = _call_gms_with_retry(messages, request_id)
    text = text.strip()
    if not text:
        # 빈 질문은 아동 화면에 내보낼 수 없다 → 실패로 취급해 BE 폴백 템플릿에 맡긴다.
        raise UpstreamError("AI_EMPTY_COMPLETION", "EmptyCompletion")

    safety = _evaluate_safety(text, req.safety_rule_version)
    if safety.status != "PASSED":
        raise SafetyBlockedError(
            safety.block_reason_code or "UNSPECIFIED", req.safety_rule_version
        )

    option_allowed = "OPTION" in req.allowed_response_modes
    return QuestionResponse(
        question_text=text,
        question_purpose=_pick_question_purpose(req),
        # OPTION 비허용이면 반드시 null — 빈 배열도 계약 위반이다(isContractValidFor).
        options=list(_PLACEHOLDER_OPTIONS) if option_allowed else None,
        target_object=_pick_target_object(req),
        fallback_used=False,  # AI 서버 자체 폴백 없음 — 폴백 템플릿은 BE 소유
        safety_result=safety,
        model_name=config.LLM_MODEL,
        # modelVersion: GMS가 실제 서빙한 모델 ID(예: gpt-4o-mini-2024-07-18) — 재현성 기록.
        model_version=served_model or config.LLM_MODEL,
        prompt_version=PROMPT_VERSION,
        processing_time_ms=int((time.monotonic() - started) * 1000),
    )

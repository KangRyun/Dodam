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
# 버전은 prompts_registry가 중앙 관리하는 통합 버전이다(S15P11B209-595).
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

# 연령(난이도)별 질문 규칙 — 길이·어휘·말투 세 축으로 나눠 draft 프롬프트에 덧붙인다
# (S15P11B209-590). BE QuestionDifficulty enum과 키를 맞춘다. 아이에게 그대로 들려줄
# 질문이므로 길이·어휘를 연령에 맞춰 통제하는 것이 품질의 핵심이다.
_DIFFICULTY_RULES = {
    "PRESCHOOL": {
        "length": "한 문장, 아주 짧게(대략 10자 안팎). 한 번에 한 가지만 물어봐.",
        "vocabulary": "유아도 아는 아주 쉬운 말만. 어려운 낱말·한자어·추상어는 쓰지 마.",
        "tone": "다정하고 밝게. '우와' 같은 반가운 반응으로 시작해도 좋아.",
    },
    "LOWER_ELEMENTARY": {
        "length": "한 문장, 짧고 간결하게. 한 번에 한 가지만.",
        "vocabulary": "일상에서 자주 쓰는 쉬운 말.",
        "tone": "따뜻하고 친근하게, 칭찬을 살짝 섞어.",
    },
    "UPPER_ELEMENTARY": {
        "length": "한두 문장까지 괜찮지만 그래도 간결하게.",
        "vocabulary": "조금 더 구체적인 낱말도 좋지만 어렵지 않게.",
        "tone": "또렷하고 아이를 존중하는 말투.",
    },
    "SUPPORT": {
        "length": "아주 짧은 한 문장. 천천히, 한 번에 한 가지만.",
        "vocabulary": "가장 쉬운 말만. 낯선 낱말은 피해.",
        "tone": "아주 다정하고 차분하게. 재촉하거나 다그치지 마.",
    },
}

# 알 수 없는 난이도가 오면 저학년 기준으로 둔다(요청은 계약상 검증되지만 방어적으로).
_DEFAULT_DIFFICULTY = "LOWER_ELEMENTARY"


def _difficulty_guidance(req: QuestionRequest) -> str:
    """난이도에 맞는 길이·어휘·말투 규칙 블록. draft 프롬프트 뒤에 덧붙는다."""
    rule = _DIFFICULTY_RULES.get(req.difficulty, _DIFFICULTY_RULES[_DEFAULT_DIFFICULTY])
    return (
        "[연령별 말하기 규칙]\n"
        f"- 문장 길이: {rule['length']}\n"
        f"- 어휘: {rule['vocabulary']}\n"
        f"- 말투: {rule['tone']}"
    )


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
    연령대는 아이 나이를 넘기고, 난이도별 길이·어휘·말투 규칙을 덧붙인다.
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

    system = f"{system}\n\n{_difficulty_guidance(req)}"
    return [
        {"role": "system", "content": system},
        {"role": "user", "content": trigger},
    ]


# ── 질문 목적 ↔ 대상 객체 ↔ 선택 Chip 정합성 (S15P11B209-594) ────
# 세 값이 서로 어긋나면 아동 화면에 엉뚱한 칩·객체가 붙는다. 목적을 먼저 정하고
# 대상 객체·칩을 그 목적에 맞춰 파생시켜 항상 일관되게 만든다.
#   - OBJECT_DESCRIPTION: 특정 객체를 묻는다 → 대상 객체 있음, 예/아니오/더 말하기 칩.
#   - DRAWING_CONTEXT: 그림 전체 맥락을 묻는다 → 대상 객체 없음, 실제/상상 칩.
#   - EXPRESSION: 마음·느낌을 묻는다 → 대상 객체 없음, 감정 칩.
#   - FOLLOW_UP: 아이 발화에 이어 묻는다 → 대상 객체 없음, 예/아니오/더 말하기 칩.
VALID_PURPOSES = {"OBJECT_DESCRIPTION", "DRAWING_CONTEXT", "EXPRESSION", "FOLLOW_UP"}

# 목적별 선택 Chip. 아동 화면에 그대로 노출되므로 쉽고 따뜻한 말만. code는 응답 안에서 유일.
_OPTIONS_BY_PURPOSE: dict[str, list[QuestionOption]] = {
    "OBJECT_DESCRIPTION": [
        QuestionOption(code="CHIP_YES", label="응, 맞아!"),
        QuestionOption(code="CHIP_NO", label="음, 아니야"),
        QuestionOption(code="CHIP_TELL_MORE", label="더 이야기해 줄래"),
    ],
    "DRAWING_CONTEXT": [
        QuestionOption(code="CHIP_REAL", label="진짜 있었던 일이야"),
        QuestionOption(code="CHIP_IMAGINE", label="상상해서 그렸어"),
        QuestionOption(code="CHIP_TELL_MORE", label="더 이야기해 줄래"),
    ],
    "EXPRESSION": [
        QuestionOption(code="CHIP_GOOD", label="좋아!"),
        QuestionOption(code="CHIP_SOSO", label="그냥 그래"),
        QuestionOption(code="CHIP_NOT_SURE", label="잘 모르겠어"),
    ],
    "FOLLOW_UP": [
        QuestionOption(code="CHIP_YES", label="응, 맞아!"),
        QuestionOption(code="CHIP_NO", label="음, 아니야"),
        QuestionOption(code="CHIP_TELL_MORE", label="더 이야기해 줄래"),
    ],
}


def _pick_question_purpose(req: QuestionRequest) -> str:
    """질문 목적 결정.

    아이가 이미 말했으면 그 말에 이어가는 FOLLOW_UP, 첫 질문이면 탐지 객체가 있을 때
    그 객체를 묻는 OBJECT_DESCRIPTION, 없으면 그림 전체를 묻는 DRAWING_CONTEXT.
    (EXPRESSION은 질문 내용 기반 분류가 필요해 후속 프롬프트 구조화 과제로 둔다.)
    """
    if any((m.sender_type or "").upper() == "CHILD" for m in req.recent_messages):
        return "FOLLOW_UP"
    if req.detected_objects:
        return "OBJECT_DESCRIPTION"
    return "DRAWING_CONTEXT"


def _options_for_purpose(purpose: str) -> list[QuestionOption]:
    """목적에 맞는 선택 Chip. 모르는 목적이면 무난한 예/아니오/더 말하기."""
    return list(_OPTIONS_BY_PURPOSE.get(purpose, _OPTIONS_BY_PURPOSE["FOLLOW_UP"]))


def _target_for_purpose(req: QuestionRequest, purpose: str) -> DetectedObject | None:
    """대상 객체는 특정 객체를 묻는 OBJECT_DESCRIPTION일 때만 붙인다(목적과 정합).

    요청의 detectedObjects는 BE가 이미 검증(objectCode·confidence·정규화 bbox)한 값이라
    그대로 되돌려도 계약을 통과한다. 신뢰도 최고 객체를 대상으로 고른다.
    """
    if purpose != "OBJECT_DESCRIPTION" or not req.detected_objects:
        return None
    return max(req.detected_objects, key=lambda o: o.confidence)


def _is_consistent(
    purpose: str,
    target: DetectedObject | None,
    options: list[QuestionOption] | None,
    option_allowed: bool,
) -> bool:
    """목적·대상·칩·응답 방식이 서로 정합한지 검증한다(BE isContractValidFor 사전 방어).

    - 목적은 계약 허용값이어야 한다.
    - 대상 객체는 OBJECT_DESCRIPTION일 때만 허용(다른 목적엔 붙지 않는다).
    - OPTION 허용 시 칩은 비어 있지 않고 code가 유일해야 하며, 비허용 시 칩은 None.
    """
    if purpose not in VALID_PURPOSES:
        return False
    if target is not None and purpose != "OBJECT_DESCRIPTION":
        return False
    if option_allowed:
        if not options:
            return False
        codes = [o.code for o in options]
        if len(codes) != len(set(codes)):
            return False
    elif options is not None:
        return False
    return True


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

    # 목적을 먼저 정하고 대상 객체·칩을 그 목적에 맞춰 파생 — 셋을 항상 정합하게 만든다.
    option_allowed = "OPTION" in req.allowed_response_modes
    purpose = _pick_question_purpose(req)
    target = _target_for_purpose(req, purpose)
    # OPTION 비허용이면 반드시 null — 빈 배열도 계약 위반이다(isContractValidFor).
    options = _options_for_purpose(purpose) if option_allowed else None
    if not _is_consistent(purpose, target, options, option_allowed):
        # 정합성이 깨진 조합은 아동 화면에 내보내지 않는다 → 실패로 돌려 BE 폴백에 맡긴다.
        raise UpstreamError("AI_INCONSISTENT_RESPONSE", "Consistency")

    return QuestionResponse(
        question_text=text,
        question_purpose=purpose,
        options=options,
        target_object=target,
        fallback_used=False,  # AI 서버 자체 폴백 없음 — 폴백 템플릿은 BE 소유
        safety_result=safety,
        model_name=config.LLM_MODEL,
        # modelVersion: GMS가 실제 서빙한 모델 ID(예: gpt-4o-mini-2024-07-18) — 재현성 기록.
        model_version=served_model or config.LLM_MODEL,
        prompt_version=PROMPT_VERSION,
        processing_time_ms=int((time.monotonic() - started) * 1000),
    )

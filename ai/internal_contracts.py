"""BE 내부 대화 질문 계약 모델 (S15P11B209-183).

Spring Boot의 RestClientAiQuestionClient(283에서 머지)가 호출하는 내부 계약
`POST /internal/ai/v1/conversations/question`의 요청/응답을
BE record DTO(AiQuestionRequest · AiQuestionResponse)와 필드 단위로 일치시킨다.

⚠️ 계약 소유자는 BE(backend/src/main/java/com/ssafy/b209/conversation/dto).
   여기서 필드를 임의로 바꾸지 말 것 — 변경은 BE와 합의 후 양쪽 동시 반영.
   응답이 BE의 `AiQuestionResponse.isContractValidFor` 검증에 실패하면 BE는
   폴백 템플릿으로 조용히 대체하므로, 스키마 위반 = 눈에 안 띄는 품질 저하다.

가드레일:
- recentMessages.text에는 아이 발화가 들어온다 → `repr=False`로 감춰
  모델 객체가 통째로 로그에 찍혀도 원문이 노출되지 않게 한다.
- 계약에 아이 실명·생년월일 등 식별 정보는 없다(나이·ID만) — 추가 금지.
"""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field
from pydantic.alias_generators import to_camel


class _CamelModel(BaseModel):
    """BE(Jackson) camelCase JSON ↔ 파이썬 snake_case 필드 변환 공통 설정."""

    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True)


# ── 공용 (요청·응답 양쪽에서 사용) ───────────────────────────────
class BoundingBox(_CamelModel):
    """캔버스 크기에 대해 0~1로 정규화한 사각형 좌표(BE BoundingBox와 동일).

    reason: 그림분석 계약(docs/api/ai-drawing-analysis-contract.md)의 픽셀 좌표와
    형식이 달라 서로 대체할 수 없다 — 문서에도 같은 경고가 있다.
    """

    x: float
    y: float
    width: float
    height: float


class DetectedObject(_CamelModel):
    """그림에서 탐지된 객체(BE DetectedObject와 동일)."""

    object_code: str
    object_name: str | None = None
    confidence: float
    bounding_box: BoundingBox


# ── 요청 (BE AiQuestionRequest) ─────────────────────────────────
class RecentMessage(_CamelModel):
    """최소 대화 문맥. text는 아이 발화일 수 있어 repr에서 감춘다(로그 유출 방지)."""

    message_id: int | None = None
    sender_type: str
    message_type: str
    text: str | None = Field(default=None, repr=False)


# BE enum과 이름을 일치시킨다: QuestionDifficulty · ResponseMode.
# 알 수 없는 값이 오면 422(INVALID_REQUEST) → BE가 폴백 템플릿으로 분류한다.
Difficulty = Literal["PRESCHOOL", "LOWER_ELEMENTARY", "UPPER_ELEMENTARY", "SUPPORT"]
ResponseMode = Literal["VOICE", "OPTION"]


class QuestionRequest(_CamelModel):
    """BE AiQuestionRequest와 1:1 대응하는 질문 생성 요청."""

    conversation_id: int
    drawing_session_id: int
    basis_analysis_id: int | None = None
    child_age: int
    difficulty: Difficulty
    allowed_response_modes: list[ResponseMode]
    current_question_count: int
    max_question_count: int
    detected_objects: list[DetectedObject] = Field(default_factory=list)
    recent_messages: list[RecentMessage] = Field(default_factory=list)
    safety_rule_version: str


# ── 응답 (BE AiQuestionResponse) ────────────────────────────────
class QuestionOption(_CamelModel):
    """선택형 답변 칩(BE QuestionOption). code는 한 응답 안에서 유일해야 한다."""

    code: str
    label: str


class SafetyResult(_CamelModel):
    """안전 필터 결과(BE SafetyResult).

    BE에 저장되려면 status="PASSED"·blockReasonCode=null이어야 한다.
    차단(BLOCKED)은 이 모델로 응답하지 않고 422 AI_SAFETY_POLICY_BLOCKED로 반환한다
    (BE가 저장 없이 사용자 422로 종료하는 경로).
    """

    status: Literal["PASSED", "BLOCKED"]
    rule_version: str
    block_reason_code: str | None = None


# ── 음성 STT/TTS 계약 (S15P11B209-179 — 제안 상태) ──────────────
# ⚠️ conversations/question과 달리 BE 소비자(-289 STT 처리기 · -299 질문 TTS)가
#    아직 미착수라 이 계약은 AI 쪽 '제안'이다. BE 착수 시 함께 확정하고,
#    변경은 양쪽 동시 반영한다. 문서: docs/ai/ai-speech-contract.md


class TranscriptionResponse(_CamelModel):
    """음성→텍스트(STT) 응답. text는 아이 발화 원문 — repr에서 감춘다(로그 유출 방지)."""

    text: str = Field(repr=False)
    confidence: float | None = None  # whisper-1은 신뢰도 미제공 — null 고정(스키마 유지용)
    model_name: str
    processing_time_ms: int


class SynthesisRequest(_CamelModel):
    """텍스트→음성(TTS) 합성 요청. text는 아이에게 들려줄 캐릭터 대사(질문 등)."""

    text: str
    voice: str | None = None  # 미지정 시 서버 기본(config.TTS_VOICE)


class SynthesisResponse(_CamelModel):
    """텍스트→음성(TTS) 합성 응답(mp3 base64)."""

    audio_base64: str = Field(repr=False)  # 큰 바이너리 — repr 오염 방지
    audio_format: Literal["mp3"] = "mp3"
    voice: str
    model_name: str
    processing_time_ms: int


class QuestionResponse(_CamelModel):
    """BE AiQuestionResponse와 1:1 대응. isContractValidFor 통과 조건 요약:

    - questionText·questionPurpose·modelName·modelVersion·promptVersion 비어 있지 않음
    - questionPurpose ∈ {OBJECT_DESCRIPTION, DRAWING_CONTEXT, EXPRESSION, FOLLOW_UP}
    - OPTION 허용 시 options는 비어 있지 않고 code 중복 없음 / 비허용 시 options는 null
    - targetObject가 있으면 objectCode 비어 있지 않고 confidence 0~1·boundingBox 정규화
    - safetyResult.status == "PASSED" 그리고 blockReasonCode == null
    - processingTimeMs >= 0
    """

    question_text: str
    question_purpose: Literal[
        "OBJECT_DESCRIPTION", "DRAWING_CONTEXT", "EXPRESSION", "FOLLOW_UP"
    ]
    options: list[QuestionOption] | None = None
    target_object: DetectedObject | None = None
    fallback_used: bool = False
    safety_result: SafetyResult
    model_name: str
    model_version: str
    prompt_version: str
    processing_time_ms: int

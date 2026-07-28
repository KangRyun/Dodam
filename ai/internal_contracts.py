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

from pydantic import BaseModel, ConfigDict, Field, model_validator
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


# ── 관찰 리포트 생성 계약 (S15P11B209-180) ──────────────────────
# BE report.dto.ObservationGenerationRequest / ObservationGenerationResult(+중첩 record)와
# 1:1 대응한다. BE 경계는 infrastructure.ai.observation.AiObservationClient 이고,
# 현재 활성 구현은 MockAiObservationClient(고정 fixture)다.
# ⚠️ 계약 소유자는 BE. 실제 HTTP 배선(app.ai.observation.mode=http)은 후속 이슈가
#    같은 AiObservationClient 경계 뒤에 붙인다 — 이 AI 서버는 draft 경로로 같은 결과 형태만 제공.
# ⚠️ 요청엔 그림 서술·대화 원문·탐지 객체가 없다(개인정보 최소화 계약) — 임의로 추가하지 말 것.


class ObservationGenerationRequest(_CamelModel):
    """BE ObservationGenerationRequest와 1:1. 집계 수치·비민감 맥락만 담는다.

    representative_utterance·expressed_emotion_text 에는 아이 표현이 들어올 수 있어
    repr에서 감춘다(로그 유출 방지). 이미지·음성 원문·식별 개인정보는 계약에 없다.
    """

    request_id: str
    analysis_id: int
    drawing_session_id: int
    analysis_type: str  # 최종 분석은 "FINAL"
    question_difficulty: str | None = None
    question_count: int = 0
    answered_count: int = 0
    skipped_count: int = 0
    unrecognized_speech_count: int = 0
    selected_emotions: list[str] = Field(default_factory=list)
    expressed_emotion_text: str | None = Field(default=None, repr=False)
    representative_utterance: str | None = Field(default=None, repr=False)


class ObservedFeatureDraft(_CamelModel):
    """관찰 특징 초안(BE ObservedFeatureDraft). visibility_scope로 노출 범위를 나눈다."""

    feature_code: str
    title: str
    description: str
    evidence_summary: str
    visibility_scope: Literal["EXPERT_ONLY", "REVIEWED_GUARDIAN"]


class ObservationDraft(_CamelModel):
    """전문가 검토 전 관찰 초안(BE ObservationDraft). status는 항상 AI_DRAFT.

    attention_points는 전문가 내부 검토용 — 보호자에게 바로 노출하지 않는다.
    disclaimer(진단 아님)는 필수.
    """

    status: str = "AI_DRAFT"
    overall_summary: str
    positive_signals: str
    attention_points: str
    evidence_summary: str
    guardian_guidance: str
    follow_up_question: str
    expert_review_required: bool = False
    disclaimer: str
    features: list[ObservedFeatureDraft] = Field(default_factory=list)


class ConversationSummaryDraft(_CamelModel):
    """대화 요약 초안(BE ConversationSummaryDraft).

    representative_utterance는 아이 발화일 수 있어 repr에서 감춘다.
    집계 수치(질문/응답/건너뜀 수)는 여기 없다 — BE가 요청 값으로 채운다.
    """

    summary_text: str
    main_topic: str
    expressed_emotion: str
    emotion_source: Literal["SELECTED", "STATED", "INFERRED"]
    representative_utterance: str = Field(repr=False)


class FollowUpGuideDraft(_CamelModel):
    """보호자 후속 안내 초안(BE FollowUpGuideDraft)."""

    guidance: str
    detail_text: str


class GuardianQuestionDraft(_CamelModel):
    """보호자 질문 초안(BE GuardianQuestionDraft)."""

    question_text: str
    question_purpose: str


class ObservationGenerationResult(_CamelModel):
    """BE ObservationGenerationResult와 1:1. disclaimer·limitations_text는 필수.

    confidence는 0~1 또는 None. model_name/model_version은 생성 주체 표기.
    """

    request_id: str
    model_name: str
    model_version: str
    confidence: float | None = None
    observation_draft: ObservationDraft
    conversation_summary: ConversationSummaryDraft
    activity_notes: list[str] = Field(default_factory=list)
    follow_up_guides: list[FollowUpGuideDraft] = Field(default_factory=list)
    guardian_questions: list[GuardianQuestionDraft] = Field(default_factory=list)
    limitations_text: str


# ── 종합 분석 계약 (API_명세서_최종.md §19.3 · §19.4) ────────────
# `POST /internal/v1/analyses`. 정본이 규정한 '객체+시각+행동+대화 종합' 계약이다.
#
# ⚠️ 위 두 계약과 소유권이 다르다. 질문·관찰 리포트 계약은 BE 코드가 정본이지만,
#    이 계약의 정본은 문서(API_명세서_최종.md §19)다. BE 소비자
#    (RestClientDrawingAnalysisClient)는 아직 구 계약을 보고 있어 현재 소비자가 없다 —
#    그래서 이 경로 신설은 기존 연동을 깨지 않는다. BE 전환은 application.yml의
#    AI_DRAWING_ANALYSIS_ENDPOINT_PATH 교체와 응답 DTO 수정이 필요하다.
#
# ⚠️ 이름 충돌 주의: 위 관찰 리포트 계약에도 ObservationDraft가 있고 형태가 다르다.
#    여기서는 AnalysisObservationDraft로 구분한다 — 같은 이름을 재사용하면
#    한쪽 계약이 조용히 덮여 BE에 잘못된 형태가 나간다.
#
# 가드레일:
# - 아이 발화가 실리는 필드는 전부 repr=False — 모델이 통째로 로그에 찍혀도 원문이 새지 않는다.
# - 요청에 아이 실명·생년월일은 없다(나이·연령대만). 추가 금지(§19.2).
# - 진단명·질환 확률·원인 단정은 만들지 않는다(§24.3). 근거 없는 문장 대신
#   unusedInputs/warnings로 '못 했음'을 명시한다.

AnalysisType = Literal["INTERMEDIATE", "FINAL"]
ActivityType = Literal["HTP", "ART_DIARY"]
DrawingSubject = Literal["HOUSE", "TREE", "PERSON"]

# §4 AnalysisTriggerReason 전체 값.
TriggerReason = Literal[
    "PAUSE",
    "INTERVAL",
    "STROKE_COUNT",
    "CHANGE_RATIO",
    "USER_REQUEST",
    "DRAWING_COMPLETE",
    "ACTIVITY_COMPLETE",
    "RETRY",
]

# §4 EmotionType. 아이가 직접 고른 값만 들어온다(AI 추정 아님).
EmotionType = Literal["HAPPY", "SAD", "ANGRY", "SCARED", "CALM", "UNKNOWN"]


# ── 요청 (§19.3) ────────────────────────────────────────────────
class ChildContext(_CamelModel):
    """분석에 필요한 최소 아동 맥락. 이름·생년월일은 계약에 없다(§19.2)."""

    age: int
    age_group: Difficulty
    question_difficulty: Difficulty


class DrawingInput(_CamelModel):
    """분석 대상 그림. signedUrl은 짧은 만료의 읽기 전용 URL이다(§19.2)."""

    drawing_asset_id: int
    signed_url: str = Field(repr=False)  # 만료 전 접근 자격 — 로그에 남기지 않는다
    mime_type: str
    width: int | None = None
    height: int | None = None
    checksum_sha256: str | None = None


class BehaviorSummary(_CamelModel):
    """캔버스 과정 데이터 요약. BE가 stroke 배치에서 집계해 넘긴다.

    pressure_available=False면 필압 통계를 만들지 않는다 — 0으로 대체 금지(§25 계약 테스트).
    """

    drawing_duration_ms: int | None = None
    active_drawing_ms: int | None = None
    pause_count: int | None = None
    undo_count: int | None = None
    erase_count: int | None = None
    tool_change_count: int | None = None
    color_change_count: int | None = None
    pressure_available: bool = False


class BehaviorInput(_CamelModel):
    """행동 입력. strokeBatchUrls가 비면 summary만으로 특징을 만든다."""

    stroke_batch_urls: list[str] = Field(default_factory=list, repr=False)
    summary: BehaviorSummary | None = None


class ConversationMessage(_CamelModel):
    """대화 한 건. text는 아이 발화일 수 있어 repr에서 감춘다."""

    message_id: int | None = None
    sender_type: str
    message_type: str
    text: str | None = Field(default=None, repr=False)


class ConversationInput(_CamelModel):
    messages: list[ConversationMessage] = Field(default_factory=list)


class ReflectionInput(_CamelModel):
    """활동 종료 시 아이가 고른 감정(복수 선택)과 자유 서술."""

    selected_emotions: list[EmotionType] = Field(default_factory=list)
    expressed_emotion_text: str | None = Field(default=None, repr=False)


class RagInput(_CamelModel):
    """RAG 검색 조건. 검색 파이프라인 미구현 — 응답에서 unusedInputs로 알린다."""

    knowledge_base_version: str | None = None
    allowed_source_types: list[str] = Field(default_factory=list)
    max_references: int = 5


class AnalysisRequest(_CamelModel):
    """§19.3 종합 분석 요청."""

    analysis_id: int
    drawing_session_id: int
    activity_type: ActivityType
    drawing_subject: DrawingSubject | None = None
    analysis_type: AnalysisType
    trigger_reason: TriggerReason | None = None
    child_context: ChildContext | None = None
    drawing: DrawingInput
    behavior: BehaviorInput | None = None
    conversation: ConversationInput | None = None
    reflection: ReflectionInput | None = None
    rag: RagInput | None = None

    @model_validator(mode="after")
    def validate_activity_context(self) -> "AnalysisRequest":
        """HTP 주제 유무가 활동 유형과 일치하는지 검증한다."""
        if self.activity_type == "HTP" and self.drawing_subject is None:
            raise ValueError("HTP analysis requires drawingSubject")
        if self.activity_type == "ART_DIARY" and self.drawing_subject is not None:
            raise ValueError("ART_DIARY analysis must not include drawingSubject")
        return self


# ── 응답 (§19.4) ────────────────────────────────────────────────
class ModelRef(_CamelModel):
    """구성요소별 모델 식별. 재현·재분석을 위해 결과마다 기록한다."""

    name: str
    version: str


class ModelInfo(_CamelModel):
    """§19.4 modelInfo — 객체탐지·Vision·LLM·RAG 버전을 분리해 기록한다.

    reason: 하나로 뭉치면 어느 구성요소가 바뀌어 결과가 달라졌는지 추적할 수 없다(§26.2).
    """

    object_detection: ModelRef | None = None
    vision: ModelRef | None = None
    language: ModelRef | None = None
    knowledge_base_version: str | None = None


class AnalysisDetectedObject(_CamelModel):
    """§19.4 detectedObjects[]. boundingBox는 0~1 정규화.

    object_code는 htp_labels의 계약 라벨(UPPER_SNAKE), object_name은 한국어 표시명.
    """

    object_code: str
    object_name: str | None = None
    confidence: float
    bounding_box: BoundingBox
    area_ratio: float | None = None
    detection_order: int


class AnalysisConversationSummary(_CamelModel):
    """§19.4 conversationSummary. 실제 발화와 AI 요약을 필드로 분리한다(§11.3).

    representative_utterance는 아이 '실제' 발화 원문이므로 repr에서 감춘다.
    """

    summary_text: str | None = None
    representative_utterance: str | None = Field(default=None, repr=False)
    question_count: int = 0
    response_count: int = 0
    skipped_question_count: int = 0
    unrecognized_speech_count: int = 0


class AnalysisObservationDraft(_CamelModel):
    """§19.4 observationDraft — 전문가 검토 전 초안. 보호자에게 그대로 노출 금지(§2.4).

    status는 §4 ObservationReviewStatus. AI가 만든 것은 항상 AI_DRAFT다.
    """

    status: Literal[
        "AI_DRAFT", "EXPERT_REVIEW_REQUIRED", "EXPERT_REVIEWED", "REJECTED"
    ] = "AI_DRAFT"
    overall_summary: str | None = None
    observations: list[str] = Field(default_factory=list)
    follow_up_questions: list[str] = Field(default_factory=list)
    expert_review_required: bool = True
    disclaimer: str


class UnusedInput(_CamelModel):
    """§19.4 unusedInputs[] — 쓰지 못한 입력과 사유.

    reason: '왜 이 정보가 결과에 없는지'를 남겨야 보호자·전문가가 결과를 과신하지 않는다.
    retryable=True면 조건이 바뀌면 재분석으로 채울 수 있다는 뜻이다.
    """

    source_type: str
    reason_code: str
    reason_detail: str | None = None
    retryable: bool = False


class AnalysisResponse(_CamelModel):
    """§19.4 종합 분석 응답.

    status는 §4 AnalysisStatus 중 AI가 낼 수 있는 값만 쓴다.
    PARTIAL_SUCCESS는 일부 입력을 못 썼다는 뜻이며, 이때 unusedInputs는 비어 있지 않다(§11.4).
    """

    analysis_id: int
    status: Literal["SUCCESS", "PARTIAL_SUCCESS", "FAILED"]
    model_info: ModelInfo
    detected_objects: list[AnalysisDetectedObject] = Field(default_factory=list)
    visual_features: dict[str, float | str | None] = Field(default_factory=dict)
    behavior_features: dict[str, int | bool | None] = Field(default_factory=dict)
    conversation_summary: AnalysisConversationSummary | None = None
    observation_draft: AnalysisObservationDraft | None = None
    evidence_references: list[dict] = Field(default_factory=list)
    unused_inputs: list[UnusedInput] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)
    processing_time_ms: int

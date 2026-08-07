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

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator
from pydantic.alias_generators import to_camel


class _CamelModel(BaseModel):
    """BE(Jackson) camelCase JSON ↔ 파이썬 snake_case 필드 변환 공통 설정."""

    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True)


def _evidence_id_to_str(value):
    """근거 식별자를 문자열로 정규화한다 (2026-08-05 운영 결함 수정).

    BE는 이 값들이 **DB 행 ID(Long)** 라 JSON 숫자로 보낸다. 계약 타입만 str 로 적어 둔 탓에
    906 배포본에서 `detectedObjects[].evidenceSourceId: 10` 이 422로 튕겼다.
    숫자를 거부할 이유가 없다 — AI는 이 값을 **되돌려 줄 참조 문자열로만** 쓴다.

    ⚠️ 문자열로 정규화하는 것이 검증 통과보다 중요하다. `report_client._allowed_evidence_refs`
       가 (kind, id) 튜플로 대조하는데, 한쪽이 int 로 남으면 형식은 통과해도 대조에서 어긋나
       **그 근거가 조용히 사라진다**(422보다 알아채기 어려운 실패다).
    bool 은 int 의 하위 타입이라 따로 막는다 — True 가 "True" 가 되면 안 된다.
    """
    if isinstance(value, bool):
        return value  # 타입 검증에서 걸리게 그대로 넘긴다
    if isinstance(value, int):
        return str(value)
    return value


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
    selected_option_codes: list[str] | None = None


# BE enum과 이름을 일치시킨다: QuestionDifficulty · ResponseMode.
# 알 수 없는 값이 오면 422(INVALID_REQUEST) → BE가 폴백 템플릿으로 분류한다.
Difficulty = Literal["PRESCHOOL", "LOWER_ELEMENTARY", "UPPER_ELEMENTARY", "SUPPORT"]
ResponseMode = Literal["VOICE", "OPTION"]

# HTP/그림일기 활동 맥락 — 질문 경로(QuestionRequest)와 분석 경로(AnalysisRequest)가 함께 쓴다.
# BE enum(DrawingAnalysisActivityType · DrawingAnalysisSubject)과 이름을 정확히 맞춘다.
ActivityType = Literal["HTP", "ART_DIARY"]
DrawingSubject = Literal["HOUSE", "TREE", "PERSON"]


class PreviousSubjectNote(_CamelModel):
    """같은 HTP 활동의 앞 주제에서 아이가 들려준 이야기 (S15P11B209-989).

    주제마다 대화 세션이 따로 열려 다음 주제는 앞 주제 발화를 모른다 — 그 단절을 잇는
    압축 재료다. child_utterances 는 아이 표현이라 repr 에서 감춘다(로그 유출 방지).
    """

    drawing_subject: str  # HOUSE | TREE | PERSON
    child_utterances: list[str] = Field(default_factory=list, repr=False)


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
    # 그림 서술(VLM) — 분석에서 만든 2~4문장 한국어 관찰 서술(S15P11B209-704).
    #   출처: AnalysisResponse.observationDraft.overallSummary
    #        (BE 저장 위치: analysis_observation_results.overall_summary)
    #   왜 필요한가: 객체 이름 목록만으로는 색·표정·구도·크기 관계를 물을 수 없다.
    #   ⚠️ 선택 필드다. BE 가 보내지 않으면 기존 객체 기반 질문으로 그대로 동작한다.
    drawing_description: str | None = None
    recent_messages: list[RecentMessage] = Field(default_factory=list)
    safety_rule_version: str
    # ── HTP 주제 맥락 (S15P11B209-712) ──────────────────────────
    # 질문 경로도 '지금 무슨 HTP 단계(주제)인지'를 받아야 주제를 벗어난 질문을 막을 수 있다
    # (버그 S15P11B209-709 원인 3). 주제는 BE가 세션→HTP 단계로 서버에서 확정해 넘긴다.
    # 롤아웃 안전: 구 BE가 아직 안 보내도 요청이 깨지지 않게 optional·기본값을 둔다
    # (basis_analysis_id와 같은 방식). 실제 프롬프트 반영은 후속 S15P11B209-713이 한다.
    activity_type: ActivityType | None = None
    drawing_subject: DrawingSubject | None = None
    # 이 대화에서 이미 질문한 대상 objectCode 목록(반복 질문 방지용). 713이 프롬프트에서 소비한다.
    asked_object_codes: list[str] = Field(default_factory=list)
    # 앞 주제에서 아이가 한 말 (S15P11B209-989). 롤아웃 안전: 구 BE가 안 보내면 빈 목록 —
    #   첫 주제·그림일기와 같은 경로로 떨어져 기존 동작 그대로다.
    previous_subject_notes: list[PreviousSubjectNote] = Field(default_factory=list)

    @model_validator(mode="after")
    def validate_activity_context(self) -> "QuestionRequest":
        """활동 유형이 주어졌으면 주제 유무가 유형과 일치하는지 검증한다.

        분석 경로(AnalysisRequest.validate_activity_context)와 같은 규칙이되, 질문 경로는
        롤아웃 중 activity_type이 아직 없을 수 있어(구 BE) 유형이 주어졌을 때만 검사한다.
        """
        if self.activity_type == "HTP" and self.drawing_subject is None:
            raise ValueError("HTP question requires drawingSubject")
        if self.activity_type == "ART_DIARY" and self.drawing_subject is not None:
            raise ValueError("ART_DIARY question must not include drawingSubject")
        return self


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
    """음성→텍스트(STT) 응답. text는 아이 발화 원문 — repr에서 감춘다(로그 유출 방지).

    status·failure_reason·needs_confirmation은 정본 §19.6이 요구하는 필드다(2026-08-05 추가).
    무음·저신뢰를 추측 문장 대신 실패로 알려 BE가 텍스트를 저장하지 않게 하고, 앱이 대신
    선택지를 띄우게 한다(§25). 실패면 text는 **빈 문자열**이다 — null로 바꾸면 처음부터
    non-null이던 이 필드의 계약이 깨져 구 BE 파서가 schema 오류로 떨어진다.
    """

    text: str = Field(repr=False)
    confidence: float | None = None  # whisper-1은 신뢰도 미제공 — null 고정(스키마 유지용)
    model_name: str
    processing_time_ms: int
    status: Literal["SUCCESS", "FAILED"] = "SUCCESS"
    failure_reason: (
        Literal["NO_SPEECH", "LOW_CONFIDENCE", "UNSUPPORTED_AUDIO", "TIMEOUT"] | None
    ) = None
    needs_confirmation: bool = False


class SynthesisRequest(_CamelModel):
    """텍스트→음성(TTS) 합성 요청. 말투 문구는 서버 고정 표에서만 선택한다."""

    text: str
    voice: str | None = None  # 미지정 시 서버 기본(config.TTS_VOICE)
    tone_profile: Literal[
        "CHARACTER_DEFAULT_V1",
        "CHARACTER_CELEBRATING_V1",
        "CHARACTER_ENCOURAGING_V1",
    ] = "CHARACTER_DEFAULT_V1"


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
    - confirmedStopTarget가 있으면 질문이 아니라 맺음말이므로 OPTION 허용이어도 options 없음 가능

    confirmedStopTarget(S15P11B209-951)는 **명령이 아니라 관찰 보고**다. "아이가 그만하겠다고
    확인했다"는 사실만 싣고, 실제 종료는 지금과 같이 FE가 수행한다 — AI는 턴·활동을 제어하지
    않는다는 786 원칙은 그대로다.
    """

    question_text: str
    question_purpose: Literal[
        "OBJECT_DESCRIPTION", "DRAWING_CONTEXT", "EXPRESSION", "FOLLOW_UP"
    ]
    options: list[QuestionOption] | None = None
    # 아이가 되묻기에 말로 그만하겠다고 확인한 대상. 확인이 없으면 None이다(S15P11B209-951).
    #   CONVERSATION — 대화만 끝낸다. 그림은 계속 그릴 수 있어 되돌리기 쉽다.
    #   ACTIVITY     — 그림 활동까지 끝낸다. 회고 저장·다음 단계로 이어져 되돌릴 수 없다.
    confirmed_stop_target: Literal["CONVERSATION", "ACTIVITY"] | None = None
    target_object: DetectedObject | None = None
    fallback_used: bool = False
    safety_result: SafetyResult
    model_name: str
    model_version: str
    prompt_version: str
    processing_time_ms: int
    # 아이가 대화를 그만하겠다고 확인해 준 턴이면 true (S15P11B209-947).
    #
    # ⚠️ AI는 대화를 끝내지 않는다 — 세션 상태의 주인은 BE다. 이 값은 '아이가 확인했다'는
    #    사실을 전할 뿐이고, 실제 종료(CHILD_REQUEST)는 BE가 한다. 786이 정한 "턴 제어는
    #    AI 소유가 아니다"를 지키면서 말로 끝낼 길을 여는 유일한 방법이다.
    # ⚠️ BE가 이 필드를 아직 안 읽어도 안전하다. 그때는 questionText(되묻기)가 그대로
    #    전달되어 아이는 지금과 똑같이 칩을 누르면 된다 — 회귀가 없다. 그래서 AI를 먼저
    #    배포할 수 있다(BE의 AiQuestionResponse는 모르는 필드를 무시한다).
    # ⚠️ 그림 활동 완료에는 쓰지 않는다. BE가 대신할 수 없는 일이라(회고 저장·다음 단계는
    #    FE가 쥔다) 그쪽은 화면 버튼을 누르도록 안내한다.
    conversation_end_confirmed: bool = False


# ── 관찰 리포트 생성 계약 (S15P11B209-180) ──────────────────────
# BE report.dto.ObservationGenerationRequest / ObservationGenerationResult(+중첩 record)와
# 1:1 대응한다. BE 경계는 infrastructure.ai.observation.AiObservationClient 이고,
# 현재 활성 구현은 MockAiObservationClient(고정 fixture)다.
# ⚠️ 계약 소유자는 BE. 실제 HTTP 배선(app.ai.observation.mode=http)은 후속 이슈가
#    같은 AiObservationClient 경계 뒤에 붙인다 — 이 AI 서버는 draft 경로로 같은 결과 형태만 제공.
# ⚠️ 개인정보 최소화 계약 — 식별 정보(실명·생년월일 등)는 없다. 임의 추가 금지.
#    그림 서술·문답은 S15P11B209-740에서 합의 확장(subjectSummaries) — 리포트가 그림·문답
#    내용을 근거로 쓸 수 있게 한다. 정본: docs/ai/ai-observation-report-contract.md


class SubjectQaPair(_CamelModel):
    """주제별 문답 한 쌍 (S15P11B209-740).

    answer_text는 아이 발화(STT 텍스트·선택 칩 라벨)라 repr에서 감춘다(로그 유출 방지).
    answer_type은 BE 어휘(VOICE·OPTION·SKIPPED 등). AI는 SKIPPED만 "(건너뛴 질문)"으로
    구분 표기하고(아이가 스스로 넘긴 관찰 사실 — 무응답과 다르다) 그 외 값은 해석하지 않는다.
    """

    question: str
    answer_text: str | None = Field(default=None, repr=False)
    answer_type: str | None = None
    # ── 근거 식별자 (S15P11B209-886) ─────────────────────────────
    # 경향 해석의 근거는 BE가 발급한 식별자만 참조할 수 있다(875 §4). AI가 조립하면 서버가
    # 독립성을 검증할 수 없어 게이트가 자기 신고로 무력해진다.
    #   answer_message_id → sourceRef {kind: "QA_ANSWER", id: <이 값>}
    # 롤아웃 안전: optional 이라 구 BE가 안 보내도 200으로 동작한다. 다만 **식별자가 없는 문답은
    #   공개 해석의 근거로 쓸 수 없다** — 관찰 서술·문답 블록에는 계속 실려 리포트 본문은 유지된다.
    answer_message_id: int | None = None
    question_message_id: int | None = None
    # 음성 인식 확인이 필요한 답변인지(BE만 아는 값). True면 **표시는 유지**하되 근거·대표 발화로는
    #   쓰지 않는다(875 §6-1) — 오인식 문장이 해석의 근거가 되면 잘못된 해석에 확정 근거가 붙는다.
    stt_needs_confirmation: bool = False


class SubjectDetectedObject(_CamelModel):
    """관찰 리포트용 탐지 객체 하나의 정규화 기하 정보 (S15P11B209-836).

    ⚠️ 위 DetectedObject(그림 분석 계약, BoundingBox 중첩)와 다른 모델이다. 이름을 갈라 둔 것은
       의도다 — 같은 이름을 쓰면 뒤 정의가 앞 모델의 forward ref 를 가로채 그림 분석 계약이
       통째로 깨진다(실제로 겪음). 여기 좌표는 평면 x·y·width·height 다.

    좌표계는 항상 NORMALIZED(0~1)다 — BE가 PIXEL 행은 싣지 않고, PIXEL 결과뿐인 주제는
    빈 목록으로 보낸다. AI는 캔버스 원본 크기를 모르므로 픽셀 좌표로는 용지 점유율을
    계산할 수 없다(계약 합의 사항).

    ⚠️ area_ratio 가 None이면 그대로 둔다 — width*height 로 대체 계산하지 않는다(BE 명시).
       추정값을 관찰 사실로 적으면 근거가 아닌 것이 근거 자리에 들어간다.

    ⚠️ 기하 4필드는 **전부 optional** 이다(2026-08-05 운영 결함 수정). 836이 이 넷을 기본값 없는
       필수 필드로 둔 탓에, 906 배포본이 {evidenceSourceId, objectCode} 만 실어 보내자
       POST /internal/v1/observations 가 **422로 100% 실패**했다(운영 2건 중 2건).
       탐지 객체가 하나라도 있으면 전량 실패라 리포트 파이프라인이 통째로 멈췄다.

       이건 단순 버그가 아니라 **원칙 위반**이었다. 이 계약은 곳곳에서 롤아웃 안전 패턴을 쓴다 —
       "구 BE가 안 보내면 빈 목록이라 기존 경로가 그대로 동작한다"(740·836 주석). 836이 자기
       모델에서만 그 원칙을 어겨, BE·AI 배포 순서가 어긋나는 순간 파이프라인이 멈추게 만들었다.
       → 없는 값은 None 으로 받고, **없는 값으로 관찰 사실을 지어내지 않는다**
         (report_client._geometry_facts 가 좌표 없는 항목을 블록에서 건너뛴다).
    """

    object_code: str
    x: float | None = None
    y: float | None = None
    width: float | None = None
    height: float | None = None
    area_ratio: float | None = None
    confidence: float | None = None
    # 근거 식별자 (S15P11B209-886) — sourceRef {kind: "DETECTED_OBJECT", id: <이 값>}.
    #   없으면 이 탐지 결과는 공개 해석의 근거로 쓸 수 없다(관찰 서술 재료로는 계속 쓰인다).
    evidence_source_id: str | None = None

    _normalize_id = field_validator("evidence_source_id", mode="before")(
        _evidence_id_to_str
    )


class SubjectSummary(_CamelModel):
    """주제(집/나무/사람 또는 그림일기 단일 그림) 하나의 관찰 서술·문답 묶음 (S15P11B209-740).

    drawing_description은 해당 그림의 VLM 관찰 서술(analysis_observation_results.overall_summary).
    detected_object_codes는 내부 코드 — 프롬프트 참고용이며 리포트 문장에 원문 노출 금지.
    """

    drawing_subject: DrawingSubject | None = None  # 그림일기는 None
    drawing_description: str = ""
    detected_object_codes: list[str] = Field(default_factory=list)
    # 탐지 기하 (S15P11B209-836). detected_object_codes 와 병렬로 실린다 — 구 BE가 안 보내면
    #   빈 목록이라 기존 코드 목록 경로가 그대로 동작한다(740 롤아웃 패턴과 동일).
    detected_objects: list[SubjectDetectedObject] = Field(default_factory=list)
    qa_pairs: list[SubjectQaPair] = Field(default_factory=list)
    # 근거 식별자 (S15P11B209-886) — 이 그림의 VLM 관찰 서술 레코드 ID.
    #   sourceRef {kind: "VLM_OBSERVATION", id: <이 값>}. 없으면 서술을 근거로 쓸 수 없다.
    observation_evidence_source_id: str | None = None

    # BE가 DB 행 ID(Long)를 숫자로 보낸다 — detectedObjects 에서 실제로 422를 낸 것과 같은 값이다.
    _normalize_id = field_validator("observation_evidence_source_id", mode="before")(
        _evidence_id_to_str
    )


class SubjectDuration(_CamelModel):
    """HTP 한 주제(집·나무·사람)에 머문 시간 (S15P11B209-975).

    ⚠️ **이 목록은 비교 관찰의 재료다.** "어느 그림에 시간을 더 썼는가"는 세 주제가 모두
       있을 때만 참이다. 그래서 BE는 behavior_metrics 전체를 채울 수 있을 때만 — 즉 세 단계가
       전부 캔버스이고 전부 집계 가능할 때만 — 이 목록을 보낸다. 한 단계라도 UPLOAD 이거나
       집계 불가면 behavior_metrics 자체가 None 이 되어 이 목록도 함께 사라진다.
       부분 목록으로 순위를 매기면 아이에 대한 없는 관찰이 만들어진다(§2.3, BE 837 규칙).

    그림일기는 주제 구분이 없어 빈 목록이다.
    """

    drawing_subject: str | None = None
    drawing_duration_ms: int | None = None
    active_drawing_ms: int | None = None


class BehaviorMetrics(_CamelModel):
    """그리기 과정의 형식 지표 (S15P11B209-836). BE StrokeBehaviorSummary 와 필드 1:1.

    ⚠️ None 과 0 은 다른 뜻이다 — None은 '집계하지 못함'이라 프롬프트 블록에서 항목을 빼고,
       0은 '0회'라는 관찰 사실이라 그대로 적는다. 멈춤 없이 몰입해 그린 활동(pause_count=0)과
       집계 실패(None)가 같은 문장이 되면 안 된다(BE javadoc과 같은 원칙).

    HTP는 집·나무·사람 세 단계를 **합산**한 값이다. 한 단계라도 집계할 수 없거나 UPLOAD가
    섞이면 BE가 전체를 None으로 보낸다 — 부분 집계를 전체 활동으로 오인시키지 않기 위해서다.

    truncated=True 면 배치 상한에 걸려 세션 앞부분만 집계한 값이라, 활동 전체를 완전히
    집계한 것처럼 표현하면 안 된다.
    average_pressure 는 이번 단계에서 항상 None이다(BE 확정) — pressure_available 은
    측정 가능 여부일 뿐 필압의 강약도 감정 근거도 아니다.

    stroke_count·colors_used_count·subject_durations 는 S15P11B209-975 확장이다.
    ⚠️ stroke_count 는 **지우개 획도 포함한** 전체 획 수라 erase_count 와 세는 대상이 겹친다.
       두 값으로 '지우기 비율' 같은 파생 수치를 만들면 안 된다 — 계약이 파생 필드를 싣지 않는
       이유가 이것이고, 프롬프트도 같은 규칙을 건다(report_common).
    ⚠️ colors_used_count 는 실제로 획을 그린 색의 **가짓수**(합집합 크기)다. color_change_count
       (색을 바꾼 횟수)와 다른 값이며, HTP 합산에서도 세 단계의 색을 합집합으로 세므로
       같은 색을 두 번 세지 않는다.
    """

    drawing_duration_ms: int | None = None
    active_drawing_ms: int | None = None
    stroke_count: int | None = None
    pause_count: int | None = None
    undo_count: int | None = None
    erase_count: int | None = None
    tool_change_count: int | None = None
    color_change_count: int | None = None
    colors_used_count: int | None = None
    pressure_available: bool = False
    average_pressure: float | None = None
    truncated: bool = False
    # 롤아웃 안전: 구 BE가 안 보내면 빈 목록이라 주제별 시간 줄이 실리지 않는다(§2.5 필드 단위
    #   optional — 836이 이 원칙을 어겨 2026-08-05 운영 전량 422를 냈다).
    subject_durations: list[SubjectDuration] = Field(default_factory=list)


class SelectedEmotionRef(_CamelModel):
    """아이가 고른 감정 하나와 그 레코드 식별자 (S15P11B209-886).

    selected_emotions(코드 목록)와 병렬로 실린다 — 코드만으로는 어느 행에서 왔는지 알 수 없어
    sourceRef 를 만들 수 없다. sourceRef {kind: "EMOTION_SELECTION", id: evidence_source_id}.
    """

    emotion_code: str
    evidence_source_id: str

    # BE가 DB 행 ID(Long)를 숫자로 보낸다 — detectedObjects 에서 실제로 422를 낸 것과 같은 값이다.
    _normalize_id = field_validator("evidence_source_id", mode="before")(
        _evidence_id_to_str
    )


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
    # 활동 시점 기준 아동 만 나이 (S15P11B209-1001). 관찰을 연령 발달 문맥으로 설명하는
    # 축(Lowenfeld 규준 — 982에서 계약 부재로 보류)의 재료다.
    #   롤아웃 안전: 구 BE가 안 보내면 None — 프롬프트가 연령 언급 자체를 금지한다.
    child_age: int | None = None
    selected_emotions: list[str] = Field(default_factory=list)
    expressed_emotion_text: str | None = Field(default=None, repr=False)
    representative_utterance: str | None = Field(default=None, repr=False)
    # 주제별 그림 서술·문답 (S15P11B209-740). HTP=최대 3건(집·나무·사람), 그림일기=1건.
    #   롤아웃 안전: 구 BE가 안 보내도 기존 동작 유지 — 기본 빈 목록(QuestionRequest.activity_type 패턴).
    subject_summaries: list[SubjectSummary] = Field(default_factory=list)
    # 그리기 형식 지표 (S15P11B209-836). 구 BE가 안 보내면 None이라 [형식적 분석] 블록이
    #   실리지 않는다 — 확장 전과 동일 동작.
    behavior_metrics: BehaviorMetrics | None = None
    # ── 근거 식별자 (S15P11B209-886) ─────────────────────────────
    # 문답·탐지 객체·VLM 서술의 식별자는 각 하위 모델에 있고, 아래 둘은 요청 단위다.
    # 전부 optional — 없으면 그 종류는 공개 해석의 근거가 되지 못한다(관찰 재료로는 계속 쓰인다).
    selected_emotion_refs: list[SelectedEmotionRef] = Field(default_factory=list)
    # 활동 지표 스냅샷 식별자 — sourceRef {kind: "ACTIVITY_METRIC", id: <이 값>}.
    #   지표가 여러 개여도 스냅샷 하나가 원본이다(게이트도 계열 전체를 1건으로 센다).
    activity_metric_source_id: str | None = None
    # ⚠️ PRIOR_ACTIVITY(이전 활동)는 이번 계약에 재료가 없다 — 이전 활동의 원본 관찰·발화가
    #    요청에 실리지 않으므로 LONGITUDINAL 근거는 만들 수 없다. 확장은 후속.


class ObservedFeatureDraft(_CamelModel):
    """관찰 특징 초안(BE ObservedFeatureDraft). visibility_scope로 노출 범위를 나눈다.

    ⚠️ 어휘는 그대로지만 **뜻이 재정의됐다**(2026-08-05). DB 마이그레이션을 피하려 값 이름을
    유지했을 뿐, 사람 전문가 독자는 존재한 적이 없다:
    - REVIEWED_GUARDIAN = AI 자체검토를 통과해 **보호자에게 열리는** 카드.
    - EXPERT_ONLY = 보호자에게 바로 열지 않고 **사람 상담 권유·안전 경로 전용**으로 보내는 카드.
    """

    feature_code: str
    title: str
    description: str
    evidence_summary: str
    visibility_scope: Literal["EXPERT_ONLY", "REVIEWED_GUARDIAN"]


class ObservationDraft(_CamelModel):
    """관찰 초안(BE ObservationDraft). disclaimer(진단 아님)는 필수.

    status(2026-08-05):
    - "AI_DRAFT" — 자체검토를 통과하지 못했거나 검토하지 못한 초안. 보호자 경로를 열지 않는다.
    - "AI_REVIEWED" — 자체검토를 통과했다. 관찰 카드가 visibility_scope 대로 노출된다.
    ⚠️ BE ObservationReviewStatus enum 에 AI_REVIEWED 가 추가되고 AnalysisObservationResult 가
       하드코딩 대신 이 값을 받아야 실효가 생긴다. 그 전까지는 BE가 AI_DRAFT 로 저장하므로
       동작이 지금과 같다 — 배포 순서 무관.

    attention_points 는 **보호자가 다음에 더 지켜볼 점**이다(구: 전문가가 추가 확인할 것).
    expert_review_required 는 **사람 상담을 권할 신호**다 — 리포트 품질 실패는 status 로 간다.
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

    ⚠️ representative_utterance 는 **아이가 실제로 한 말**이다. 없으면 None 이고, 무난한
       문장으로 채우지 않는다. 예전에는 비면 "재미있었어요."로 채웠는데, 운영 실측 결과
       analysis_conversation_summaries 51건 중 34건(67%)이 그 문장이었다 — 아이가 한 적
       없는 말이 대표 발화로 저장돼 있었다는 뜻이다. 같은 이유로 confidence 도 None 이다
       (지어내지 않는다). BE 컬럼은 nullable 이고 검증 애너테이션도 없다.
    """

    summary_text: str
    main_topic: str
    expressed_emotion: str
    emotion_source: Literal["SELECTED", "STATED", "INFERRED"]
    representative_utterance: str | None = Field(default=None, repr=False)


class FollowUpGuideDraft(_CamelModel):
    """보호자 후속 안내 초안(BE FollowUpGuideDraft)."""

    guidance: str
    detail_text: str


class GuardianQuestionDraft(_CamelModel):
    """보호자 질문 초안(BE GuardianQuestionDraft)."""

    question_text: str
    question_purpose: str


class RagReference(_CamelModel):
    """리포트가 근거로 참조한 전문 자료 출처 (S15P11B209-614).

    출처 표시는 라이선스 의무(KOGL-1)이자 보호자 신뢰 재료다 — 정책 §1-4.
    청크 텍스트는 싣지 않는다(응답 비대 방지) — sourceId·제목이면 추적에 충분.
    """

    source_id: str
    title: str


# ── 경향 해석 (S15P11B209-887) ───────────────────────────────────
# 정본: docs/S15P11B209-875-report-api-contract.md (정본 v1.1) + 안전 예외는
#   docs/api/report-detail-guardian-contract.md §4-1~§4-4 (S15P11B209-885).
#
# ⚠️ 필드명은 875 계약을 **그대로** 쓴다. FE가 이미 그 이름으로 DTO·화면을 구현해 병합했고
#    (report_dtos.dart), 중간에 매핑 계층을 두면 그 표가 틀릴 때 필드가 조용히 사라진다.
#    그래서 여기 이름은 다른 계약(camelCase 별칭)과 달리 875 문구를 1:1로 따른다.
# ⚠️ 전 필드 optional·기본 빈 목록/None — 구 BE는 unknown 필드를 무시하므로 배포 순서 무관.


class EvidenceSourceRef(_CamelModel):
    """근거의 원본 참조 (875 §4). id는 **BE가 발급한 식별자**만 쓴다.

    AI가 조합키(analysisId+objectCode+detectionOrder 같은)를 조립하면 서버가 독립성을 검증할 수
    없어 게이트가 자기 신고로 무력해진다 — 그래서 받은 것만 참조한다.

    kind: QA_ANSWER | DETECTED_OBJECT | VLM_OBSERVATION | EMOTION_SELECTION |
          ACTIVITY_METRIC | PRIOR_ACTIVITY
    ⚠️ PRIOR_ACTIVITY 는 이전 **AI 해석 결과**를 가리킬 수 없다(순환 추론 차단) — 이전 활동의
       원본 관찰 레코드나 확인된 아동 표현 메시지만.
    """

    kind: str
    id: str


class ReportEvidenceItem(_CamelModel):
    """근거 풀 한 건 (875 §4). 카드가 evidence_refs 로 참조한다.

    evidence_id 는 **이 응답 안에서만 유일한 로컬 정수**다(1,2,3…). BE가 저장 시 최종 ID로
    재매핑하고 evidence_refs 도 함께 갱신한다 — 외부 키로 쓰지 않는다(재생성 시 값이 달라진다).

    배타 규칙: source_ref(원본 근거)와 derived_from(파생 근거) 중 **정확히 하나**만 갖는다.
    파생 근거는 REPEATED_SUBJECT·LONGITUDINAL 처럼 자체 원본이 없는 경우다.

    text 는 아이 발화 인용이 섞일 수 있어 repr에서 감춘다(로그 유출 방지).
    """

    evidence_id: int
    source_type: str
    text: str = Field(repr=False)
    source_ref: EvidenceSourceRef | None = None
    derived_from: list[EvidenceSourceRef] | None = None


class PublicInterpretation(_CamelModel):
    """보호자에게 공개하는 경향 해석 카드 (875 §3).

    tendency_text 는 반드시 가능성 어조("~일 수 있습니다")다 — 단정·진단 어조 금지.
    scope_text·home_observation_guide 가 비면 공개 조건 미달이라 카드가 제외된다(875 §4-1).
    evidence_refs 는 ReportEvidenceItem.evidence_id 참조.

    ⚠️ confidence 는 **LLM이 채우는 자리가 아니다**(S15P11B209-982). 값이 무엇이든 조립 단계에서
       버려지고, interpretation_gate 가 근거의 '종류'로 다시 계산해 덮어쓴다. 모델에게 등급
       판정권을 주면 근거가 약한 해석도 STRONG 이라 주장해 등급 체계 전체가 장식이 된다 —
       근거를 대는 것(evidence_refs)까지가 모델의 몫이고, 그 근거가 얼마나 센지는 코드가 정한다.
       프롬프트도 이 필드를 요구하지 않는다(어휘 자체를 주지 않는 것이 1차 방어다).
    """

    category: str
    title: str
    tendency_text: str
    scope_text: str
    home_observation_guide: str
    evidence_refs: list[int] = Field(default_factory=list)
    # STRONG | MODERATE | WEAK. 기본 None — 구 BE는 unknown 필드를 무시하므로 배포 순서 무관하고,
    #   게이트를 거치지 않은 카드(테스트·중간 조립)는 등급이 '아직 없음'으로 남는다(875 §3-1).
    confidence: str | None = None


class SubjectReportDraft(_CamelModel):
    """주제(집·나무·사람) 하나의 관찰 묶음 (875 §5 SubjectReport의 **부분**).

    HTP는 그림 세 장을 그리는데 지금까지 응답에는 주제 구분이 남지 않았다 — overall_summary
    하나·evidence_summary 하나로 뭉개져, BE·FE가 '주제별 관찰 사실과 문답' 섹션(875 §11-5)을
    조립할 재료가 없었다. 이 모델이 그 자리다.

    ⚠️ 875 §5 의 다섯 필드 중 **셋만** 싣는다. 나머지 둘은 BE가 채운다:
    - image_url — BE가 가진 자산 URL이다. AI가 만들 수 있는 값이 아니다.
    - qa_pairs — 요청에 실려 온 아이 발화 그대로다. LLM을 통과시켜 되돌려 받으면 아이 말이
      바뀔 여지만 생긴다(원문 보존이 인용의 전제다). BE가 자기 데이터를 그대로 쓴다.
    필드명은 875 문구를 1:1로 따른다(subject_type → "subjectType") — 887이 정한 규칙과 같다.
    ⚠️ DrawnItem 은 같은 개념을 drawing_subject 로 부른다. 그쪽은 BE가 activityFacts 로
       옮겨 담는 값이라 이름이 갈렸다. 이 모델은 subjectReports[] 로 **그대로 나가는** 자리라
       875 이름을 쓴다.

    subject_type: HOUSE | TREE | PERSON | None(주제가 나뉘지 않는 활동)
    vision_observations: 그 그림에서 눈으로 확인된 **사실** 문장. 해석은 담지 않는다.
    interpretation_refs: 이 그림의 관찰이 근거가 된 public_interpretations 의 **배열 인덱스**
        (0-based). category 값이 아니다(875 §5-1). 리포트 스냅샷 안에서 카드 배열을 재정렬하면
        참조가 조용히 다른 카드를 가리키므로, 카드가 빠질 때마다 서버가 다시 매핑한다
        (report_client._subject_reports · _apply_findings).
    """

    subject_type: str | None = None
    vision_observations: list[str] = Field(default_factory=list)
    interpretation_refs: list[int] = Field(default_factory=list)


class ReportParentGuide(_CamelModel):
    """보호자 가이드 (875 §7). guide_type 별로 문장을 묶어 낸다.

    guide_type: DRAWING_CONVERSATION | DAILY_PARENTING | HOME_OBSERVATION | PROFESSIONAL_SUPPORT
    ⚠️ PROFESSIONAL_SUPPORT 는 상시 노출되는 **일반 상담 안내**이며 고정 템플릿을 쓴다 —
       crisis_guidance 의 문구·연락처를 재사용하지 않고 신고·긴급 번호를 담지 않는다(875 §7-1).
    """

    guide_type: str
    items: list[str] = Field(default_factory=list)


class CrisisResource(_CamelModel):
    """위기 안내에 함께 싣는 공식 상담·신고 자원 (crisis_guidance.CrisisResource와 1:1)."""

    name: str
    contact: str
    note: str = ""


class CrisisAlert(_CamelModel):
    """위기 대응 안내 (875 §7-1). 보호자 가이드와 **다른 필드**다.

    전부 사전 검토 템플릿이며 LLM이 생성하지 않는다(crisis_guidance 소유).
    None 이 기본값이고 "위기 신호 없음"을 뜻한다 — 별도 플래그를 두지 않는다.

    ⚠️ ABUSE_DISCLOSURE 는 이 값을 만들지 않는다(항상 None). 가해자가 보호자일 수 있어 자동
       통지가 아이를 더 위험하게 한다 — EXPERT_ONLY 보존 + expert_review_required 로 돌린다
       (S15P11B209-890에서 crisis_guidance 반영 완료).
    """

    reason_code: str
    severity: str  # HIGH | ELEVATED
    title: str
    message: str
    action_steps: list[str] = Field(default_factory=list)
    resources: list[CrisisResource] = Field(default_factory=list)


class DrawnItem(_CamelModel):
    """'그린 것' 한 건 (S15P11B209-911).

    ⚠️ 출처는 **VLM 관찰 서술**이다. 탐지 라벨(YOLO)은 근거가 아니다 — 탐지 임계값
       (config.YOLO_CONF_THRESHOLD=0.20)은 '박스를 남길지'의 기준이라, 그 라벨을 확정 사실로
       보호자에게 적을 수 없다. 서술은 실제 이미지를 보고 쓰며 "목록에 있어도 이미지에서
       안 보이면 쓰지 마"가 강제된다(prompts/drawing_description_htp.txt).
       report_client._drawn_items 가 name 이 서술 원문에 실제로 있는지 대조해 걸러낸다.

    drawing_subject: HOUSE | TREE | PERSON | None(그림일기)
    name: 보호자 화면에 그대로 나가는 한국어 표현.
    """

    drawing_subject: str | None = None
    name: str


class DiaryStorySnapshot(_CamelModel):
    """그림일기 한 회차의 핵심 이야기 요약.

    reality_status/time_scope 는 아이가 직접 말한 표현으로만 서버가 확정한다. 그림을 그린
    날짜나 LLM의 추측만으로 값을 올리지 않는다.
    """

    headline: str
    summary: str
    reality_status: Literal["REAL", "IMAGINED", "MIXED", "UNKNOWN"] = "UNKNOWN"
    time_scope: Literal["TODAY", "YESTERDAY", "RECENT", "PAST", "UNKNOWN"] = "UNKNOWN"
    main_event: str | None = None
    evidence_refs: list[EvidenceSourceRef] = Field(default_factory=list)


class DiaryNarrativeStep(_CamelModel):
    """그림일기 이야기 흐름의 한 단계."""

    step_type: Literal[
        "EVENT",
        "CHILD_ACTION",
        "OTHER_RESPONSE",
        "EMOTION",
        "WISH",
        "OUTCOME",
    ]
    text: str
    evidence_refs: list[EvidenceSourceRef] = Field(default_factory=list)


class DiaryChildVoiceItem(_CamelModel):
    """보호자에게 보여 줄 아이의 실제 표현과 질문 유도 방식."""

    text: str = Field(repr=False)
    elicitation_type: Literal[
        "SPONTANEOUS",
        "OPEN_INVITATION",
        "CUED_INVITATION",
        "FOCUSED_WH",
        "YES_NO",
        "MULTIPLE_CHOICE",
        "CORRECTION",
        "UNKNOWN",
    ] = "UNKNOWN"
    answer_type: str | None = None
    source_ref: EvidenceSourceRef | None = None
    stt_needs_confirmation: bool = False


class DiarySessionObservation(_CamelModel):
    """한 회차에 한정해 근거를 붙여 보여 주는 관찰 카드."""

    observation_code: str
    title: str
    description: str
    scope_text: str = "이번 활동에서 확인된 모습이에요."
    evidence_refs: list[EvidenceSourceRef] = Field(default_factory=list)


class DiaryCaregiverQuestion(_CamelModel):
    """보호자가 활동 내용에 이어서 그대로 물어볼 수 있는 질문."""

    question: str
    purpose: str
    evidence_refs: list[EvidenceSourceRef] = Field(default_factory=list)


class DiaryDataQuality(_CamelModel):
    """해석 점수가 아니라 이번 리포트의 원자료 구성을 알려 주는 메타데이터."""

    confirmed_voice_count: int = 0
    option_answer_count: int = 0
    skipped_count: int = 0
    stt_confirmation_count: int = 0
    evidence_count: int = 0
    vision_summary_available: bool = False


class DiaryInsights(_CamelModel):
    """그림일기 전용 보호자 리포트 V2.

    전부 optional 확장이라 구 BE는 무시할 수 있다. HTP 응답에서는 None 이다.
    """

    story_snapshot: DiaryStorySnapshot | None = None
    narrative_flow: list[DiaryNarrativeStep] = Field(default_factory=list)
    child_voice_items: list[DiaryChildVoiceItem] = Field(default_factory=list)
    session_observations: list[DiarySessionObservation] = Field(default_factory=list)
    caregiver_questions: list[DiaryCaregiverQuestion] = Field(default_factory=list)
    listening_tip: str | None = None
    data_quality: DiaryDataQuality = Field(default_factory=DiaryDataQuality)


class ObservationGenerationResult(_CamelModel):
    """BE ObservationGenerationResult와 1:1. disclaimer·limitations_text는 필수.

    confidence는 0~1 또는 None. model_name/model_version은 생성 주체 표기.
    rag_references·knowledge_base_version은 optional 확장(S15P11B209-614) —
    구 BE는 unknown 필드를 무시하므로 하위호환(Jackson 기본 설정), BE record
    반영은 후속. RAG 미사용 시 빈 목록/None으로 기존 응답과 동일하다.
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
    rag_references: list[RagReference] = Field(default_factory=list)
    knowledge_base_version: str | None = None
    # ── 경향 해석 (S15P11B209-887, 875 계약 정본 v1.1) ─────────────
    # 전부 optional·기본 빈 목록/None → 구 BE는 무시하고, 빈 목록이면 현행 동작과 동일하다.
    # 빈 배열은 오류가 아니라 정상이다(875 §10) — 근거가 부족하면 억지로 채우지 않는다.
    public_interpretations: list[PublicInterpretation] = Field(default_factory=list)
    evidence_items: list[ReportEvidenceItem] = Field(default_factory=list)
    parent_guides: list[ReportParentGuide] = Field(default_factory=list)
    # 주제별 관찰 (875 §5). public_interpretations 와 **형제**로 둔다 — 875 §2 에서 셋 다
    #   ReportDetail 최상위 필드이고, 하나만 observation_draft 안에 넣으면 BE가 같은 계층의
    #   데이터를 두 곳에서 꺼내게 된다. 비면 지금과 같은 동작이다(구 BE는 무시).
    subject_reports: list[SubjectReportDraft] = Field(default_factory=list)
    # '그린 것' 목록 (S15P11B209-911) — VLM 관찰 서술 기반. BE가 이 값으로
    #   activityFacts.detectedObjects 를 채운다(S15P11B209-912). 지금 그 줄은 탐지 라벨을
    #   그대로 나열해 신뢰도 필터 없이 보호자에게 나간다. 비면 구 동작과 같다.
    drawn_items: list[DrawnItem] = Field(default_factory=list)
    # 위기 안내는 S15P11B209-889이 채운다. 여기서는 자리만 두고 항상 None으로 둔다 —
    #   문구는 crisis_guidance 의 검토된 템플릿 소유이고 LLM이 만들지 않는다.
    crisis_alert: CrisisAlert | None = None
    # RAG 근거를 싣지 못한 사유 (S15P11B209-615, optional — 구 BE 무시).
    #   RAG_NO_INDEX(인덱스 미배포) | RAG_UNAVAILABLE(임베딩 등 검색 장애) |
    #   RAG_LOW_SCORE(전부 임계값 미달) | RAG_NO_QUERY(관찰 재료 없음).
    #   근거가 실렸으면 None — "왜 없는가"의 설명이므로 있을 때는 침묵한다.
    rag_skipped_reason: str | None = None
    # 그림일기 전용 V2. HTP는 None, 구 BE는 unknown 필드로 무시한다.
    diary_insights: DiaryInsights | None = None


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
# ActivityType · DrawingSubject 는 질문 경로와 공용이라 위(QuestionRequest 앞)에서 정의한다.

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
    # 입력 출처(S15P11B209-762): CANVAS=앱 캔버스 직접 그림, UPLOAD=촬영·스캔·갤러리 등 외부 파일.
    # 사진 보정 분기의 게이트로 쓴다(761). UPLOAD는 사진만이 아니라 스캔·디지털 파일도 포함하므로
    # 무조건 보정하지 않고, 촬영 흔적이 감지될 때만 선택 적용한다(761 2단계).
    input_method: Literal["CANVAS", "UPLOAD"] = "CANVAS"

    @field_validator("input_method", mode="before")
    @classmethod
    def _default_input_method(cls, value: object) -> str:
        """하위호환(순차 배포): 필드가 없거나 null·미지의 값이면 CANVAS로 간주한다(S15P11B209-762)."""
        return value if value in ("CANVAS", "UPLOAD") else "CANVAS"


class BehaviorSummary(_CamelModel):
    """캔버스 과정 데이터 요약. BE가 stroke 배치에서 집계해 넘긴다.

    pressure_available=False면 필압 통계를 만들지 않는다 — 0으로 대체 금지(§25 계약 테스트).

    ⚠️ BehaviorMetrics(리포트 경로)와 **같은 BE record(StrokeBehaviorSummary)의 두 번째
       거울**이다. 한쪽에만 필드를 더하면 같은 집계값이 경로에 따라 다르게 보인다 —
       stroke_count·colors_used_count 를 함께 넣는 이유가 이것이다(S15P11B209-975).
       주제별 시간(subject_durations)은 리포트 전용이라 여기 없다. 이 경로는 세션 하나를
       분석하므로 주제 간 비교가 성립하지 않는다.
    """

    drawing_duration_ms: int | None = None
    active_drawing_ms: int | None = None
    stroke_count: int | None = None
    pause_count: int | None = None
    undo_count: int | None = None
    erase_count: int | None = None
    tool_change_count: int | None = None
    color_change_count: int | None = None
    colors_used_count: int | None = None
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


# ── 객체 탐지 Metadata 로그 스키마 (S15P11B209-610) ─────────────
# 710(사람이 읽는 진단 콘솔 한 줄)과 별개의, 기계가 읽는 구조화 레코드다. 611(로그 TTL·집계·
# 사용자 피드백 연결)이 이 모델을 그대로 import해 MongoDB 문서로 저장한다(문서 + TTL 인덱스).
# 그래서 스키마 정본은 dict가 아니라 이 pydantic 모델이고, emit은 model_dump_json() 한 줄이다.
# ⚠️ 아동 그림 내용은 담지 않는다 — 표시명(한국어)·bbox 좌표·이미지 원본 제외, 계약 코드·수치·집계만.
#    bbox는 그림 구도를 서술하는 내용이라 710 가드레일(어느 모드에서도 미기록)을 그대로 따른다.
class DetectionMetadataObject(_CamelModel):
    """탐지 객체 1건의 집계용 메타. 코드·수치만 — bbox·표시명은 담지 않는다(610/710 가드레일)."""

    object_code: str
    confidence: float
    area_ratio: float | None = None
    detection_order: int


class DetectionMetadataLog(_CamelModel):
    """객체 탐지 구조화 메타데이터 로그(S15P11B209-610). 611이 import해 MongoDB에 저장한다.

    소비자(611)와의 최소 계약:
    - analysis_id: 사용자 피드백 연결의 조인 키
    - occurred_at: TTL 인덱스 기준 발생 시각. timezone 명시 ISO8601(KST +09:00, S15P11B209-736)
    - schema_version: 611이 집계 시 스키마 변화를 구분하는 유일한 수단
    """

    schema_version: str = "1"
    event: Literal["object_detection"] = "object_detection"
    occurred_at: str
    analysis_id: int
    drawing_session_id: int
    activity_type: ActivityType | None = None
    drawing_subject: DrawingSubject | None = None
    object_detection: ModelRef | None = None
    image_width: int | None = None
    image_height: int | None = None
    detection_count: int
    class_counts: dict[str, int] = Field(default_factory=dict)
    objects: list[DetectionMetadataObject] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)
    processing_time_ms: int

"""GMS 관찰 리포트 생성 클라이언트 — 활동 집계·감정·대표 발화 → 보호자용 관찰 초안.

BE 계약(report.dto.ObservationGenerationRequest → ObservationGenerationResult)에 맞춰
최종 분석 요청을 받아 관찰 리포트 결과를 만든다. 실제 소비자는 BE AiObservationClient이며,
지금은 MockAiObservationClient가 고정 fixture를 쓴다 — HTTP 배선은 후속 이슈.

역할 분담:
- LLM(GMS)이 생성하는 것: 정성적 관찰 문구(요약·긍정신호·주의점·근거·안내·후속질문·특징·대화요약·안내·질문).
- 서버가 고정으로 채우는 것: status(AI_DRAFT)·disclaimer·limitations(안전 문구는 LLM에 맡기지 않는다)·
  model 정보·request_id 에코·emotion_source(요청에서 결정)·representative_utterance 에코.

가드레일:
- 진단·점수화 금지는 프롬프트가 강제하고, 안전 문구(disclaimer/limitations)는 코드가 상수로 보장한다.
- 대표 발화·표현 감정 등 아이 표현은 로그로 남기지 않는다(실패 로그에 에러 유형만).
- RAG(학술 근거 문헌 evidence_references)는 이번 범위 밖 — evidence_summary 수준의 요약만 생성한다(후속 이슈).
"""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass

from openai import OpenAIError

import config
import internal_contracts as contracts
import prompts_registry  # 프롬프트 파일 로딩·버전 관리 중앙화 (S15P11B209-595)
import report_safety
from gms import get_client

logger = logging.getLogger(__name__)

# 리포트 프롬프트 버전(내용이 바뀌면 자동으로 달라진다) — S15P11B209-595.
PROMPT_VERSION = prompts_registry.version("report")

# 안전 문구는 LLM이 빠뜨리거나 바꾸면 안 되는 필수 고지 — 서버가 상수로 보장한다.
# (BE MockAiObservationClient와 동일 문구를 써서 두 구현의 고지가 일관되게.)
DISCLAIMER = (
    "본 결과는 아동 발달 진단이 아니라 그림 활동 관찰 기록입니다. "
    "우려되는 점이 있으면 전문가와 상담하세요."
)
LIMITATIONS = (
    "본 리포트는 제한된 활동 데이터를 바탕으로 한 관찰 기록이며, "
    "아동의 발달 상태를 단정하지 않습니다."
)
# 대표 발화가 비어 있을 때의 중립 기본값(진단·해석 없는 무난한 문장).
DEFAULT_UTTERANCE = "재미있었어요."

_VALID_SCOPES = {"EXPERT_ONLY", "REVIEWED_GUARDIAN"}


@dataclass
class DrawingBehaviorMetrics:
    """(AI 보조 입력) 그리기의 형식/행동 지표 — 스펙 §13.4 activityFacts / §19.3 behavior.summary.

    리포트의 '형식적 분석'(소요시간·필압 등)을 관찰 근거로 반영하기 위한 입력이다.
    ⚠️ BE ObservationGenerationRequest 엔 아직 없다(개인정보 최소화 계약). 정식 전달(계약 확장)은
    후속 이슈 — 지금은 draft/데모 경로에서 별도 인자로 넘긴다. 수치 자체는 심리 단정 근거가 아니라
    관찰 보조 근거로만 쓴다(프롬프트가 강제).
    """

    drawing_duration_ms: int | None = None
    active_drawing_duration_ms: int | None = None
    pause_count: int | None = None
    erase_count: int | None = None
    undo_count: int | None = None
    pressure_available: bool = False
    average_pressure: float | None = None


def _load(name: str) -> str:
    """프롬프트 로딩은 prompts_registry로 중앙화했다(S15P11B209-595)."""
    return prompts_registry.load(name)


def _system_prompt() -> str:
    """리포트 지침 system 프롬프트.

    ⚠️ 공용 guardrails.txt(대화용)는 append 하지 않는다 — 그 파일은 "정서를 진단·해석하지 마"를
    전제로 한 대화 응답용이라, 리포트의 '요소별 감정 해석' 지침과 충돌한다. 리포트의 안전 기준
    (장애명·진단명·점수·낙인 금지, 과도한 부정 금지, 걱정 신호는 attentionPoints로만)은 report.txt가
    자체적으로 담는다. JSON 스키마 중괄호 때문에 str.format 을 쓰지 않고 문자열을 그대로 쓴다.
    """
    return _load("report")


def _emotion_source(req: contracts.ObservationGenerationRequest) -> str:
    """표현 감정의 출처를 요청 값으로 결정한다(LLM이 아니라 규칙 기반).

    선택 감정 카드가 있으면 SELECTED, 말로 표현했으면 STATED, 둘 다 없으면 INFERRED.
    """
    if req.selected_emotions:
        return "SELECTED"
    if req.expressed_emotion_text and req.expressed_emotion_text.strip():
        return "STATED"
    return "INFERRED"


def _fmt_minutes(ms: int | None) -> str | None:
    """밀리초를 '약 N분' 문구로. None이면 None."""
    if ms is None:
        return None
    return f"약 {round(ms / 60000, 1)}분"


def _format_behavior(behavior: DrawingBehaviorMetrics | None) -> str:
    """형식적 분석 지표를 프롬프트 [형식적 분석] 블록으로. 없으면 빈 문자열."""
    if behavior is None:
        return ""
    lines = ["[형식적 분석]"]
    total = _fmt_minutes(behavior.drawing_duration_ms)
    active = _fmt_minutes(behavior.active_drawing_duration_ms)
    if total:
        lines.append(f"- 총 소요시간: {total}")
    if active:
        lines.append(f"- 실제 그린 시간: {active}")
    if behavior.pause_count is not None:
        lines.append(f"- 멈춤 횟수: {behavior.pause_count}회")
    if behavior.erase_count is not None:
        lines.append(f"- 지우기 횟수: {behavior.erase_count}회")
    if behavior.undo_count is not None:
        lines.append(f"- 되돌리기 횟수: {behavior.undo_count}회")
    if behavior.pressure_available:
        if behavior.average_pressure is not None:
            lines.append(f"- 필압: 평균 {behavior.average_pressure:.2f} (0~1)")
        else:
            lines.append("- 필압: 측정됨")
    else:
        lines.append("- 필압: 측정 불가(미지원 기기)")
    return "\n".join(lines) + "\n\n"


def _format_activity(
    req: contracts.ObservationGenerationRequest,
    drawing_description: str | None,
    behavior: DrawingBehaviorMetrics | None = None,
) -> str:
    """[그림 관찰 서술](VLM) + [형식적 분석] + 요청의 집계·감정·대표 발화를 프롬프트 user 메시지로.

    drawing_description 은 vlm_client.describe 산출물(그림 사실 묘사)이며, 있으면
    관찰 특징·요약의 근거가 된다. 없으면 그림 특징은 언급하지 않도록 안내 문구를 넣는다.
    behavior 는 소요시간·필압 등 형식적 지표이며, 있으면 관찰 보조 근거로 반영된다.
    """
    emotions = ", ".join(req.selected_emotions) if req.selected_emotions else "없음"
    description = (drawing_description or "").strip() or "(그림 관찰 서술이 제공되지 않았어요)"
    return (
        "[그림 관찰 서술]\n"
        f"{description}\n\n"
        f"{_format_behavior(behavior)}"
        "[활동 데이터]\n"
        f"- 질문 난이도: {req.question_difficulty or '정보 없음'}\n"
        f"- 제시한 질문 수: {req.question_count}\n"
        f"- 응답한 답변 수: {req.answered_count}\n"
        f"- 건너뛴 질문 수: {req.skipped_count}\n"
        f"- 음성 인식 실패 수: {req.unrecognized_speech_count}\n"
        f"- 아이가 선택한 감정: {emotions}\n"
        f"- 아이가 말한 감정: {req.expressed_emotion_text or '없음'}\n"
        f"- 대표 발화: {req.representative_utterance or '없음'}\n\n"
        "이 데이터로 규칙에 맞는 관찰 기록 JSON을 만들어줘."
    )


def _extract_json(raw: str) -> dict:
    """모델 응답에서 JSON 객체만 뽑아 파싱한다(코드펜스·머리말이 섞여도 견디게).

    첫 '{' 부터 마지막 '}' 까지를 JSON으로 본다. 파싱 실패는 RuntimeError로 올린다.
    """
    text = raw.strip()
    start = text.find("{")
    end = text.rfind("}")
    if start == -1 or end == -1 or end < start:
        raise RuntimeError("리포트 응답을 해석하지 못했어요(형식 오류).")
    try:
        return json.loads(text[start : end + 1])
    except json.JSONDecodeError as e:
        # ⚠️ 응답 본문은 로그로 남기지 않는다 — 에러 유형만.
        logger.error("리포트 JSON 파싱 실패: %s", type(e).__name__)
        raise RuntimeError("리포트 응답을 해석하지 못했어요(형식 오류).") from e


def _scope(value) -> str:
    """visibility_scope 를 계약 허용값으로 강제한다. 모르는 값은 보수적으로 EXPERT_ONLY."""
    return value if value in _VALID_SCOPES else "EXPERT_ONLY"


def _feature(item: dict) -> contracts.ObservedFeatureDraft:
    """LLM이 만든 특징 dict 하나를 계약 모델로. 누락 필드는 빈 문자열로 채운다.

    단정적 진단 표현(S15P11B209-591)이 든 보호자 노출 feature는 EXPERT_ONLY로 강등해
    전문가 검토로 격리한다 — 경향성 우려 소견은 그대로 통과한다.
    """
    title = str(item.get("title", ""))
    description = str(item.get("description", ""))
    evidence = str(item.get("evidenceSummary", ""))
    scope = _scope(item.get("visibilityScope"))
    if scope != "EXPERT_ONLY" and report_safety.has_definitive_diagnosis(
        title, description, evidence
    ):
        # ⚠️ 원문은 로그로 남기지 않는다 — 격리 사실만.
        logger.warning("리포트 feature 단정 진단 표현 격리 — EXPERT_ONLY 강등")
        scope = "EXPERT_ONLY"
    return contracts.ObservedFeatureDraft(
        feature_code=str(item.get("featureCode", "")),
        title=title,
        description=description,
        evidence_summary=evidence,
        visibility_scope=scope,
    )


def _assemble(
    req: contracts.ObservationGenerationRequest, data: dict, model: str
) -> contracts.ObservationGenerationResult:
    """LLM 정성 결과(data) + 서버 고정 필드를 합쳐 계약 결과를 만든다."""
    conv = data.get("conversationSummary") or {}
    features = [_feature(f) for f in data.get("features", []) if isinstance(f, dict)]

    # 단정적 진단 표현이 보호자 노출 문장·특징에 하나라도 있으면 전문가 검토를 강제한다
    # (S15P11B209-591). attentionPoints는 전문가 전용 채널이라 검사 대상에서 제외한다.
    guardian_texts = [
        str(data.get("overallSummary", "")),
        str(data.get("positiveSignals", "")),
        str(data.get("evidenceSummary", "")),
        str(data.get("guardianGuidance", "")),
        str(data.get("followUpQuestion", "")),
        str(conv.get("summaryText", "")),
        str(conv.get("mainTopic", "")),
        str(conv.get("expressedEmotion", "")),
        *(f"{f.title} {f.description} {f.evidence_summary}" for f in features),
    ]
    needs_expert_review = report_safety.has_definitive_diagnosis(*guardian_texts)

    observation = contracts.ObservationDraft(
        status="AI_DRAFT",
        overall_summary=str(data.get("overallSummary", "")),
        positive_signals=str(data.get("positiveSignals", "")),
        attention_points=str(data.get("attentionPoints", "")),
        evidence_summary=str(data.get("evidenceSummary", "")),
        guardian_guidance=str(data.get("guardianGuidance", "")),
        follow_up_question=str(data.get("followUpQuestion", "")),
        expert_review_required=bool(data.get("expertReviewRequired", False))
        or needs_expert_review,
        disclaimer=DISCLAIMER,
        features=features,
    )
    conversation_summary = contracts.ConversationSummaryDraft(
        summary_text=str(conv.get("summaryText", "")),
        main_topic=str(conv.get("mainTopic", "")),
        expressed_emotion=str(conv.get("expressedEmotion", "")),
        emotion_source=_emotion_source(req),
        representative_utterance=(req.representative_utterance or DEFAULT_UTTERANCE),
    )
    return contracts.ObservationGenerationResult(
        request_id=req.request_id,
        model_name=model,
        model_version=PROMPT_VERSION,
        confidence=None,  # LLM 서술엔 보정된 신뢰도가 없다 — 지어내지 않고 None.
        observation_draft=observation,
        conversation_summary=conversation_summary,
        activity_notes=[str(n) for n in data.get("activityNotes", [])],
        follow_up_guides=[
            contracts.FollowUpGuideDraft(
                guidance=str(g.get("guidance", "")),
                detail_text=str(g.get("detailText", "")),
            )
            for g in data.get("followUpGuides", [])
            if isinstance(g, dict)
        ],
        guardian_questions=[
            contracts.GuardianQuestionDraft(
                question_text=str(q.get("questionText", "")),
                question_purpose=str(q.get("questionPurpose", "")),
            )
            for q in data.get("guardianQuestions", [])
            if isinstance(q, dict)
        ],
        limitations_text=LIMITATIONS,
    )


def generate(
    req: contracts.ObservationGenerationRequest,
    *,
    drawing_description: str | None = None,
    behavior: DrawingBehaviorMetrics | None = None,
    model: str | None = None,
) -> contracts.ObservationGenerationResult:
    """[그림 관찰 서술] + [형식적 분석] + 활동 요청 → GMS LLM 관찰 리포트 초안(계약 결과).

    Args:
        req: 최종 분석 관찰 생성 요청(집계·감정·대표 발화).
        drawing_description: vlm_client.describe 산출물(그림 사실 묘사). 있으면 관찰 근거로
            쓰인다. None이면 그림 특징은 언급하지 않고 나머지 데이터만으로 생성한다.
        behavior: 소요시간·필압 등 형식적 지표(있으면 관찰 보조 근거로 반영).
        model: 미지정 시 config.LLM_MODEL(텍스트 전용 — 이미지 자체는 넘기지 않는다).

    Returns:
        ObservationGenerationResult(BE 계약 형태, camelCase 직렬화).

    Raises:
        RuntimeError: GMS 호출 실패 또는 응답 JSON 파싱 실패 시(내용은 감추고 유형만 로그).
    """
    used_model = model or config.LLM_MODEL
    messages = [
        {"role": "system", "content": _system_prompt()},
        {"role": "user", "content": _format_activity(req, drawing_description, behavior)},
    ]
    try:
        resp = get_client().chat.completions.create(
            model=used_model,
            messages=messages,
            temperature=0.4,  # 관찰 기록은 튀지 않게 다소 낮게.
            response_format={"type": "json_object"},
        )
    except OpenAIError as e:
        # ⚠️ 요청 내용(대표 발화 등)은 로그에 남기지 않는다 — 에러 유형만.
        logger.error("GMS 리포트 생성 호출 실패: %s", type(e).__name__)
        raise RuntimeError("리포트 생성에 실패했어요(GMS).") from e

    data = _extract_json(resp.choices[0].message.content or "")
    return _assemble(req, data, used_model)


if __name__ == "__main__":
    # 스모크 테스트:  cd ai && python report_client.py  (GMS 키 필요)
    logging.basicConfig(level=logging.INFO)
    sample = contracts.ObservationGenerationRequest(
        request_id="smoke-1",
        analysis_id=1,
        drawing_session_id=1,
        analysis_type="FINAL",
        question_difficulty="PRESCHOOL",
        question_count=5,
        answered_count=4,
        skipped_count=1,
        unrecognized_speech_count=0,
        selected_emotions=["JOY"],
        expressed_emotion_text=None,
        representative_utterance="이건 우리 집이야. 엄마랑 나 있어.",
    )
    sample_description = "가운데에 집이 크게 그려져 있고, 왼쪽에 나무 한 그루가 있어요. 오른쪽에는 사람 두 명이 나란히 서 있어요."
    sample_behavior = DrawingBehaviorMetrics(
        drawing_duration_ms=600_000,  # 총 10분
        active_drawing_duration_ms=410_000,  # 실제 그린 시간 약 6.8분
        pause_count=4,
        erase_count=3,
        undo_count=2,
        pressure_available=True,
        average_pressure=0.62,
    )
    result = generate(
        sample, drawing_description=sample_description, behavior=sample_behavior
    )
    print(result.model_dump_json(by_alias=True, indent=2))

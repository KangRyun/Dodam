"""그림일기 리포트 V2 구조화 신호 검증기.

LLM이 만든 문장을 그대로 신뢰하지 않고, BE가 발급한 근거 식별자와 원본 요청을 기준으로
보호자용 :class:`internal_contracts.DiaryInsights`를 조립한다. 이 모듈은 문장 생성보다
근거 정합성·출처 구분·단일 회차 범위 제한을 책임진다.
"""

from __future__ import annotations

import re
from collections.abc import Iterable, Mapping

import internal_contracts as contracts
import report_safety

_ALLOWED_REF_KINDS = frozenset(
    {
        "QA_ANSWER",
        "VLM_OBSERVATION",
        "EMOTION_SELECTION",
        "ACTIVITY_METRIC",
    }
)
_ALLOWED_STEP_TYPES = frozenset(
    {"EVENT", "CHILD_ACTION", "OTHER_RESPONSE", "EMOTION", "WISH", "OUTCOME"}
)
_REAL_MARKERS = (
    "실제로 있었",
    "진짜 있었",
    "내가 겪은 일이",
    "내가 했던 일이",
    "있었던 일이야",
    "있었던 일이에요",
)
_IMAGINED_MARKERS = (
    "상상한 이야기",
    "상상 이야기",
    "내가 만든 이야기",
    "만든 이야기야",
    "지어낸 이야기",
    "가짜 이야기",
)
_FIRST_PERSON_DAILY_EVENT = re.compile(
    r"(?:오늘|어제|지난주|예전에|전에).{0,50}"
    r"(?:나|내가|나는|우리|엄마(?:랑|와)|아빠(?:랑|와)|친구(?:랑|와)|선생님(?:이|과|랑)).{0,60}"
    r"(?:했어|했어요|갔어|갔어요|왔어|왔어요|봤어|봤어요|받았어|받았어요|"
    r"맞았어|맞았어요|먹었어|먹었어요|놀았어|놀았어요|말했어|말했어요|"
    r"그렸어|그렸어요|샀어|샀어요|잃어버렸어|잃어버렸어요|다쳤어|다쳤어요)"
)

_CORRECTION_MARKERS = ("아니고", "아니야", "그게 아니라", "아니라")
_OPEN_INVITATION_MARKERS = (
    "무슨 일이",
    "어떤 일이",
    "이야기해",
    "이야기를 들려",
    "무슨 이야기",
)
_CUED_INVITATION_MARKERS = ("그다음", "그러고 나서", "그 뒤", "다음에는")
_WH_MARKERS = (
    "무슨",
    "어떤",
    "어떻게",
    "어땠",
    "뭐",
    "누가",
    "누구",
    "어디",
    "언제",
)
_YES_NO_ENDINGS = (
    "했어?",
    "였어?",
    "맞아?",
    "좋아?",
    "싫어?",
    "있어?",
    "없어?",
    "했니?",
    "였니?",
)
_PSYCHOLOGICAL_SCORE_CONTEXT = re.compile(
    r"(불안|우울|정서|심리|발달|자존감|사회성|애착|공격성|충동성|집중력|ADHD|장애|척도|지수)",
    re.IGNORECASE,
)
_ACHIEVEMENT_SCORE_CONTEXT = re.compile(
    r"(시험|퀴즈|문제|과제|성적|수학|국어|영어|과학|체육|"
    r"(?:\d+|백|만)\s*점(?:을|를)?\s*(?:받|맞|얻|달성|기록|나오))"
)


def has_unsafe_diary_expression(*texts: str) -> bool:
    """그림일기 보호자 문장의 안전성을 문맥에 맞게 검사한다.

    일반 리포트 점수 차단기는 ``100점을 받았어요`` 같은 학교 성취 사건까지 심리 점수화로
    오인할 수 있다. 그림일기에서는 진단·낙인·금지 축은 그대로 막되, 심리·발달 문맥이 없는
    실제 시험/과제 점수 표현만 허용한다.
    """

    for raw in texts:
        text = _clean_text(raw)
        if not text:
            continue
        if (
            report_safety.find_definitive_diagnosis(text)
            or report_safety.find_overinference(text)
            or report_safety.find_forbidden_axis(text)
        ):
            return True
        scored = report_safety.find_scored_claim(text)
        if scored:
            if _PSYCHOLOGICAL_SCORE_CONTEXT.search(text):
                return True
            if not _ACHIEVEMENT_SCORE_CONTEXT.search(text):
                return True
    return False



def _clean_text(value: object, *, max_len: int | None = None) -> str:
    text = " ".join(str(value or "").split()).strip()
    if max_len is not None:
        text = text[:max_len].rstrip()
    return text


def classify_elicitation(question: str, answer_type: str | None, answer_text: str) -> str:
    """질문 방식의 대략적인 출처를 보수적으로 분류한다.

    이 값은 진단·점수가 아니라 보호자에게 "어떤 방식으로 나온 말인지"를 알려 주기 위한
    메타데이터다. 정확히 분류할 수 없으면 UNKNOWN으로 둔다.
    """

    kind = (answer_type or "").upper()
    if kind == "OPTION":
        return "MULTIPLE_CHOICE"
    if kind == "SKIPPED":
        return "UNKNOWN"
    answer = _clean_text(answer_text)
    if any(marker in answer for marker in _CORRECTION_MARKERS):
        return "CORRECTION"
    q = _clean_text(question)
    if any(marker in q for marker in _CUED_INVITATION_MARKERS):
        return "CUED_INVITATION"
    if any(marker in q for marker in _OPEN_INVITATION_MARKERS):
        return "OPEN_INVITATION"
    if any(marker in q for marker in _WH_MARKERS):
        return "FOCUSED_WH"
    if q.endswith(_YES_NO_ENDINGS):
        return "YES_NO"
    return "UNKNOWN"


def _iter_qas(req: contracts.ObservationGenerationRequest):
    for summary in req.subject_summaries:
        for qa in summary.qa_pairs:
            yield qa


def _behavior_fact(req: contracts.ObservationGenerationRequest) -> str | None:
    behavior = req.behavior_metrics
    if behavior is None or not req.activity_metric_source_id:
        return None
    parts: list[str] = []
    fields = (
        ("총 소요시간", behavior.drawing_duration_ms, "ms"),
        ("실제 그린 시간", behavior.active_drawing_ms, "ms"),
        ("전체 획 수", behavior.stroke_count, "회"),
        ("멈춤", behavior.pause_count, "회"),
        ("지우기", behavior.erase_count, "회"),
        ("되돌리기", behavior.undo_count, "회"),
    )
    for label, value, suffix in fields:
        if value is not None:
            parts.append(f"{label} {value}{suffix}")
    return ", ".join(parts) if parts else None


def raw_evidence_texts(
    req: contracts.ObservationGenerationRequest,
) -> dict[tuple[str, str], str]:
    """BE가 발급한 근거 참조 → 원본 요청에서 확인한 사실 텍스트."""

    facts: dict[tuple[str, str], str] = {}
    for summary in req.subject_summaries:
        if summary.observation_evidence_source_id and summary.drawing_description.strip():
            facts[("VLM_OBSERVATION", summary.observation_evidence_source_id)] = (
                summary.drawing_description.strip()
            )
        for qa in summary.qa_pairs:
            if (
                qa.answer_message_id is None
                or qa.stt_needs_confirmation
                or not (qa.answer_text or "").strip()
                or (qa.answer_type or "").upper() == "SKIPPED"
            ):
                continue
            answer = (qa.answer_text or "").strip()
            elicitation = classify_elicitation(qa.question, qa.answer_type, answer)
            if (qa.answer_type or "").upper() == "OPTION":
                answer = f"선택지에서 '{answer}'를 골랐어요."
            question = _clean_text(qa.question)
            facts[("QA_ANSWER", str(qa.answer_message_id))] = (
                f"[질문 방식: {elicitation}] 질문: {question} / 아이 답변: {answer}"
            )
    for emotion in req.selected_emotion_refs:
        facts[("EMOTION_SELECTION", emotion.evidence_source_id)] = (
            f"감정 카드에서 {emotion.emotion_code}를 골랐어요."
        )
    behavior_fact = _behavior_fact(req)
    if req.activity_metric_source_id and behavior_fact:
        facts[("ACTIVITY_METRIC", req.activity_metric_source_id)] = behavior_fact
    return facts


def raw_review_facts(
    req: contracts.ObservationGenerationRequest,
    *,
    drawing_description: str | None = None,
) -> list[str]:
    """자체검토의 사실 풀. 생성된 리포트 문장은 절대 포함하지 않는다.

    ``drawing_description``은 레거시 멀티파트 경로에서 요청 모델 밖으로 전달되는 원본 VLM
    관찰이다. 생성된 ``subjectReports``를 사실로 재사용하지 않고 이 원문을 직접 싣는다.
    """

    facts = list(raw_evidence_texts(req).values())
    if drawing_description and drawing_description.strip():
        facts.append(f"그림 관찰 원문: {drawing_description.strip()}")
    if req.representative_utterance and req.representative_utterance.strip():
        facts.append(f"아이 대표 발화: {req.representative_utterance.strip()}")
    if req.expressed_emotion_text and req.expressed_emotion_text.strip():
        facts.append(f"아이가 말로 표현한 감정: {req.expressed_emotion_text.strip()}")
    # 식별자가 아직 없는 레거시 요청에서도 선택 감정 자체는 원자료다. 다만 공개 카드 근거로는
    # 쓰이지 않고, 검토자가 요약 문장이 원자료와 맞는지만 확인하는 데 사용한다.
    if req.selected_emotions:
        facts.append("아이가 고른 감정: " + ", ".join(req.selected_emotions))
    # 순서를 지키면서 중복 제거.
    return list(dict.fromkeys(_clean_text(f) for f in facts if _clean_text(f)))


def _allowed_refs(
    req: contracts.ObservationGenerationRequest,
) -> frozenset[tuple[str, str]]:
    return frozenset(raw_evidence_texts(req))


def _parse_refs(
    raw_refs: object, allowed: frozenset[tuple[str, str]]
) -> list[contracts.EvidenceSourceRef]:
    refs: list[contracts.EvidenceSourceRef] = []
    seen: set[tuple[str, str]] = set()
    if not isinstance(raw_refs, list):
        return refs
    for raw in raw_refs:
        if not isinstance(raw, Mapping):
            continue
        kind = _clean_text(raw.get("kind")).upper()
        ref_id = _clean_text(raw.get("id"))
        key = (kind, ref_id)
        if kind not in _ALLOWED_REF_KINDS or not ref_id or key not in allowed or key in seen:
            continue
        seen.add(key)
        refs.append(contracts.EvidenceSourceRef(kind=kind, id=ref_id))
    return refs


def _child_texts(req: contracts.ObservationGenerationRequest) -> list[str]:
    texts: list[str] = []
    for qa in _iter_qas(req):
        if qa.stt_needs_confirmation or (qa.answer_type or "").upper() == "SKIPPED":
            continue
        text = _clean_text(qa.answer_text)
        if text:
            texts.append(text)
    if req.representative_utterance:
        texts.append(_clean_text(req.representative_utterance))
    return list(dict.fromkeys(t for t in texts if t))


def _derive_reality_and_time(
    req: contracts.ObservationGenerationRequest,
) -> tuple[str, str]:
    text = " ".join(_child_texts(req))
    explicit_imagined = any(marker in text for marker in _IMAGINED_MARKERS)
    explicit_real = any(marker in text for marker in _REAL_MARKERS)
    heuristic_real = bool(_FIRST_PERSON_DAILY_EVENT.search(text))
    # "상상한 이야기야. 나는 우주에 갔어"처럼 상상 선언 뒤의 1인칭 사건을
    # 실제 경험 휴리스틱이 덮어쓰지 않게 한다. MIXED는 아이가 실제와 상상을 둘 다
    # 명시했을 때만 올린다.
    if explicit_imagined and explicit_real:
        reality = "MIXED"
    elif explicit_imagined:
        reality = "IMAGINED"
    elif explicit_real or heuristic_real:
        reality = "REAL"
    else:
        reality = "UNKNOWN"

    if "오늘" in text:
        time_scope = "TODAY"
    elif "어제" in text:
        time_scope = "YESTERDAY"
    elif any(marker in text for marker in ("요즘", "최근")):
        time_scope = "RECENT"
    elif any(marker in text for marker in ("지난주", "지난달", "옛날", "예전에", "전에")):
        time_scope = "PAST"
    else:
        time_scope = "UNKNOWN"
    return reality, time_scope


def _child_voice_items(
    req: contracts.ObservationGenerationRequest,
) -> list[contracts.DiaryChildVoiceItem]:
    items: list[contracts.DiaryChildVoiceItem] = []
    for qa in _iter_qas(req):
        answer_type = (qa.answer_type or "").upper()
        text = _clean_text(qa.answer_text)
        if (
            not text
            or answer_type == "SKIPPED"
            or qa.stt_needs_confirmation
            or qa.answer_message_id is None
        ):
            continue
        items.append(
            contracts.DiaryChildVoiceItem(
                text=text,
                elicitation_type=classify_elicitation(qa.question, qa.answer_type, text),
                answer_type=qa.answer_type,
                source_ref=contracts.EvidenceSourceRef(
                    kind="QA_ANSWER", id=str(qa.answer_message_id)
                ),
                stt_needs_confirmation=False,
            )
        )
        if len(items) >= 4:
            break
    return items


def _safe_public_text(value: object, *, max_len: int) -> str:
    text = _clean_text(value, max_len=max_len)
    # 학교 성취 점수는 허용하되 심리·발달 점수화, 진단, 낙인, 금지 축은 구조화
    # 필드에 들어오기 전에 제거한다. 최종 rule_flag만 믿으면 AI_DRAFT 응답 안에 위험
    # 문장이 남을 수 있으므로 필드 단위에서도 같은 문맥 검사를 적용한다.
    if not text or has_unsafe_diary_expression(text):
        return ""
    return text


def _story_snapshot(
    raw: object,
    allowed: frozenset[tuple[str, str]],
    reality: str,
    time_scope: str,
) -> contracts.DiaryStorySnapshot | None:
    if not isinstance(raw, Mapping):
        return None
    refs = _parse_refs(raw.get("evidenceRefs"), allowed)
    headline = _safe_public_text(raw.get("headline"), max_len=120)
    summary = _safe_public_text(raw.get("summary"), max_len=320)
    main_event = _safe_public_text(raw.get("mainEvent"), max_len=180) or None
    if not refs or not headline or not summary:
        return None
    return contracts.DiaryStorySnapshot(
        headline=headline,
        summary=summary,
        reality_status=reality,
        time_scope=time_scope,
        main_event=main_event,
        evidence_refs=refs,
    )


def _narrative_flow(
    raw: object, allowed: frozenset[tuple[str, str]]
) -> list[contracts.DiaryNarrativeStep]:
    if not isinstance(raw, list):
        return []
    steps: list[contracts.DiaryNarrativeStep] = []
    seen: set[str] = set()
    for item in raw:
        if not isinstance(item, Mapping):
            continue
        step_type = _clean_text(item.get("stepType")).upper()
        text = _safe_public_text(item.get("text"), max_len=180)
        refs = _parse_refs(item.get("evidenceRefs"), allowed)
        if step_type not in _ALLOWED_STEP_TYPES or not text or not refs or text in seen:
            continue
        seen.add(text)
        steps.append(
            contracts.DiaryNarrativeStep(
                step_type=step_type, text=text, evidence_refs=refs
            )
        )
        if len(steps) >= 5:
            break
    return steps


def _elicitation_by_ref(
    req: contracts.ObservationGenerationRequest,
) -> dict[tuple[str, str], str]:
    result: dict[tuple[str, str], str] = {}
    for qa in _iter_qas(req):
        if qa.answer_message_id is None or qa.stt_needs_confirmation:
            continue
        answer = _clean_text(qa.answer_text)
        if not answer or (qa.answer_type or "").upper() == "SKIPPED":
            continue
        result[("QA_ANSWER", str(qa.answer_message_id))] = classify_elicitation(
            qa.question, qa.answer_type, answer
        )
    for emotion in req.selected_emotion_refs:
        result[("EMOTION_SELECTION", emotion.evidence_source_id)] = "MULTIPLE_CHOICE"
    return result


def _session_observations(
    raw: object,
    allowed: frozenset[tuple[str, str]],
    req: contracts.ObservationGenerationRequest,
) -> list[contracts.DiarySessionObservation]:
    if not isinstance(raw, list):
        return []
    observations: list[contracts.DiarySessionObservation] = []
    for item in raw:
        if not isinstance(item, Mapping):
            continue
        refs = _parse_refs(item.get("evidenceRefs"), allowed)
        unique = {(ref.kind, ref.id) for ref in refs}
        elicitation = _elicitation_by_ref(req)
        has_independent_child_expression = any(
            elicitation.get(key)
            in {
                "OPEN_INVITATION",
                "CUED_INVITATION",
                "FOCUSED_WH",
                "CORRECTION",
            }
            for key in unique
        )
        # 서로 다른 참조가 두 개여도 둘 다 선택형·예/아니오라면 같은 유도 프레임 안의
        # 답일 수 있다. 최소 한 건은 아이가 자기 말로 내용을 구성한 응답이어야 한다.
        if len(unique) < 2 or not has_independent_child_expression:
            continue
        code = re.sub(r"[^A-Z0-9_]", "", _clean_text(item.get("observationCode")).upper())
        title = _safe_public_text(item.get("title"), max_len=160)
        description = _safe_public_text(item.get("description"), max_len=360)
        if not code or not title or not description:
            continue
        observations.append(
            contracts.DiarySessionObservation(
                observation_code=code,
                title=title,
                description=description,
                evidence_refs=refs,
            )
        )
        if len(observations) >= 2:
            break
    return observations


def _caregiver_questions(
    raw: object, allowed: frozenset[tuple[str, str]]
) -> list[contracts.DiaryCaregiverQuestion]:
    if not isinstance(raw, list):
        return []
    questions: list[contracts.DiaryCaregiverQuestion] = []
    for item in raw:
        if not isinstance(item, Mapping):
            continue
        refs = _parse_refs(item.get("evidenceRefs"), allowed)
        question = _safe_public_text(item.get("question"), max_len=160)
        purpose = _safe_public_text(item.get("purpose"), max_len=100)
        if not refs or not question or not purpose:
            continue
        # 화면에서 그대로 읽는 질문이다. 문장 중간에 여러 질문을 섞지 않는다.
        if question.count("?") > 1:
            continue
        if not question.endswith("?"):
            question += "?"
        questions.append(
            contracts.DiaryCaregiverQuestion(
                question=question, purpose=purpose, evidence_refs=refs
            )
        )
        if len(questions) >= 2:
            break
    return questions


def _data_quality(
    req: contracts.ObservationGenerationRequest,
    *,
    evidence_count: int,
    vision_available: bool,
) -> contracts.DiaryDataQuality:
    confirmed_voice = option_count = stt_confirmation = 0
    skipped = req.skipped_count
    for qa in _iter_qas(req):
        kind = (qa.answer_type or "").upper()
        if qa.stt_needs_confirmation:
            stt_confirmation += 1
            continue
        if kind == "OPTION" and (qa.answer_text or "").strip():
            option_count += 1
        elif kind in {"VOICE", "VOICE_ANSWER", "TEXT", "TEXT_ANSWER"} and (
            qa.answer_text or ""
        ).strip():
            confirmed_voice += 1
    return contracts.DiaryDataQuality(
        confirmed_voice_count=confirmed_voice,
        option_answer_count=option_count,
        skipped_count=skipped,
        stt_confirmation_count=stt_confirmation,
        evidence_count=evidence_count,
        vision_summary_available=vision_available,
    )


def build_diary_insights(
    raw: object,
    req: contracts.ObservationGenerationRequest,
    *,
    vision_available: bool,
) -> contracts.DiaryInsights | None:
    """LLM의 `diarySignals`를 원본 근거로 검증해 보호자용 V2 구조로 만든다."""

    raw = raw if isinstance(raw, Mapping) else {}
    allowed = _allowed_refs(req)
    reality, time_scope = _derive_reality_and_time(req)
    snapshot = _story_snapshot(raw.get("storySnapshot"), allowed, reality, time_scope)
    flow = _narrative_flow(raw.get("narrativeFlow"), allowed)
    observations = _session_observations(
        raw.get("sessionObservations"), allowed, req
    )
    questions = _caregiver_questions(raw.get("caregiverQuestions"), allowed)
    listening_tip = _safe_public_text(raw.get("listeningTip"), max_len=260) or None
    child_voice = _child_voice_items(req)
    # 새 FE는 diaryInsights 존재 여부로 V2 화면을 선택할 수 있다. 원자료나 검증된
    # 신호가 하나도 없는데 dataQuality 기본값만 담긴 객체를 보내면 빈 V2 화면이 열리므로
    # 의미 있는 내용이 없으면 레거시 화면으로 폴백하도록 None을 반환한다.
    if not any(
        (
            snapshot is not None,
            bool(flow),
            bool(child_voice),
            bool(observations),
            bool(questions),
        )
    ):
        return None
    return contracts.DiaryInsights(
        story_snapshot=snapshot,
        narrative_flow=flow,
        child_voice_items=child_voice,
        session_observations=observations,
        caregiver_questions=questions,
        listening_tip=listening_tip,
        data_quality=_data_quality(
            req, evidence_count=len(allowed), vision_available=vision_available
        ),
    )


def evidence_texts_for_ids(
    req: contracts.ObservationGenerationRequest,
    refs: Iterable[contracts.EvidenceSourceRef],
) -> list[str]:
    """구조화 근거 참조를 검토용 원본 문장으로 해석한다."""

    catalog = raw_evidence_texts(req)
    result: list[str] = []
    for ref in refs:
        text = catalog.get((ref.kind, ref.id))
        if text and text not in result:
            result.append(text)
    return result

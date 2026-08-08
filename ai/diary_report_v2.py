"""그림일기 리포트 V2 구조화 신호 검증기.

LLM이 만든 문장을 그대로 신뢰하지 않고, BE가 발급한 근거 식별자와 원본 요청을 기준으로
보호자용 :class:`internal_contracts.DiaryInsights`를 조립한다. 이 모듈은 문장 생성보다
근거 정합성·출처 구분·단일 회차 범위 제한을 책임진다.
"""

from __future__ import annotations

import re
from collections.abc import Iterable, Mapping

import developmental_context
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


# BE 는 대화 메시지 유형을 그대로 실어 보낸다 — DB enum 이 `OPTION_ANSWER`·`VOICE_ANSWER` 다.
#   계약 문서에는 `OPTION`·`VOICE` 로 적혀 있어 한동안 짧은 쪽만 보고 있었다. 그 결과
#   **고른 답이 아이의 자발 발화로 세어졌다**(994 가 막으려던 바로 그것) — 2026-08-07 실호출로
#   드러났다. 두 표기를 모두 받는다.
_OPTION_ANSWER_TYPES = frozenset({"OPTION", "OPTION_ANSWER", "CHOICE"})
_SPOKEN_ANSWER_TYPES = frozenset({"VOICE", "VOICE_ANSWER", "TEXT", "TEXT_ANSWER"})


def is_option_answer(answer_type: str | None) -> bool:
    """선택지에서 고른 답인가. 아이가 자기 말로 만든 문장과 구분하기 위한 판정이다."""
    return (answer_type or "").upper() in _OPTION_ANSWER_TYPES


def is_spoken_answer(answer_type: str | None) -> bool:
    """아이가 말이나 글로 직접 답했는가."""
    return (answer_type or "").upper() in _SPOKEN_ANSWER_TYPES


def classify_elicitation(question: str, answer_type: str | None, answer_text: str) -> str:
    """질문 방식의 대략적인 출처를 보수적으로 분류한다.

    이 값은 진단·점수가 아니라 보호자에게 "어떤 방식으로 나온 말인지"를 알려 주기 위한
    메타데이터다. 정확히 분류할 수 없으면 UNKNOWN으로 둔다.
    """

    if is_option_answer(answer_type):
        return "MULTIPLE_CHOICE"
    if (answer_type or "").upper() in {"SKIPPED", "SKIPPED_ANSWER"}:
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
            if is_option_answer(qa.answer_type):
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


# 아이가 자기 말로 내용을 구성한 응답. 선택형·예/아니오는 여기 없다 — AI 가 제시한 틀 안의
#   답이라 아이의 표현으로 세면 유도한 답이 근거가 된다.
_CHILD_COMPOSED = frozenset(
    {"OPEN_INVITATION", "CUED_INVITATION", "FOCUSED_WH", "CORRECTION"}
)

_INSIGHT_TYPES = frozenset(
    {"CONFIRMED_EXPRESSION", "SESSION_HYPOTHESIS", "EXPLORE_NEXT"}
)
_INSIGHT_DOMAINS = frozenset(
    {"STORY", "EMOTION", "RELATIONSHIP", "SELF_EXPRESSION", "COPING", "ACTIVITY_STYLE"}
)

# 다음에 확인할 단서(EXPLORE_NEXT)에 심리 특성을 적으면 근거 없는 진단이 된다. 단서는
#   "무엇을 더 들어볼지"까지만 말한다.
_TRAIT_LANGUAGE = re.compile(
    r"성향|기질|성격|경향이|편이에요|아이는 늘|평소에도|원래|내향|외향|불안정|공격적"
)


def _session_observations(
    raw: object,
    allowed: frozenset[tuple[str, str]],
    req: contracts.ObservationGenerationRequest,
) -> list[contracts.DiarySessionObservation]:
    """이번 회차 인사이트를 종류별 게이트로 걸러 조립한다.

    세 종류는 요구하는 근거가 다르다. 한 게이트로 묶으면 강한 주장과 약한 단서가 같은 조건으로
    통과한다.

      CONFIRMED_EXPRESSION  아이가 자기 말로 한 근거 1건 이상. 추측을 적지 않는다.
      SESSION_HYPOTHESIS    자기 말 1건 + 독립 근거 1건 이상, **그리고 다른 설명 1개 이상.**
                            다른 설명이 없으면 가설이 아니라 단정이라 통과시키지 않는다.
      EXPLORE_NEXT          근거 1건이면 된다(그림·선택 감정만으로도 가능). 대신 다음 확인
                            질문이 있어야 하고, 심리 특성을 말하면 버린다.
    """
    if not isinstance(raw, list):
        return []
    elicitation = _elicitation_by_ref(req)
    observations: list[contracts.DiarySessionObservation] = []
    for item in raw:
        if not isinstance(item, Mapping):
            continue
        refs = _parse_refs(item.get("evidenceRefs"), allowed)
        unique = {(ref.kind, ref.id) for ref in refs}
        if not unique:
            continue
        domain = _clean_text(item.get("domain")).upper()
        if domain not in _INSIGHT_DOMAINS:
            domain = "STORY"

        code = re.sub(r"[^A-Z0-9_]", "", _clean_text(item.get("observationCode")).upper())
        title = _safe_public_text(item.get("title"), max_len=160)
        description = _safe_public_text(item.get("description"), max_len=360)
        if not code or not title or not description:
            continue

        hypothesis = _safe_public_text(item.get("hypothesis"), max_len=300) or None
        alternatives = [
            text
            for text in (
                _safe_public_text(value, max_len=300)
                for value in (item.get("alternativeExplanations") or [])
            )
            if text
        ][:3]
        question = (
            _safe_public_text(item.get("clarificationQuestion"), max_len=200) or None
        )

        has_child_composed = any(
            elicitation.get(key) in _CHILD_COMPOSED for key in unique
        )
        insight_type = _clean_text(item.get("insightType")).upper()
        if insight_type not in _INSIGHT_TYPES:
            # 모델이 종류를 안 적었으면 **가진 근거의 모양**에서 읽는다. 무조건 가장 약한 쪽으로
            #   내리면 V2 가 이미 통과시키던 정상 카드가 통째로 사라진다.
            if alternatives:
                insight_type = "SESSION_HYPOTHESIS"
            elif has_child_composed and len(unique) >= 2:
                insight_type = "CONFIRMED_EXPRESSION"
            else:
                insight_type = "EXPLORE_NEXT"

        if insight_type == "CONFIRMED_EXPRESSION":
            # V2 게이트를 그대로 지킨다(참조 2건 + 아이가 자기 말로 한 근거 1건). 이미 배포된
            #   기준이라 여기서 느슨하게 하면 근거가 약한 카드가 새로 통과한다.
            if len(unique) < 2 or not has_child_composed:
                continue
            # 확인된 표현에는 추측을 싣지 않는다. 가설을 쓰려면 종류를 올려야 한다.
            hypothesis = None
            alternatives = []
        elif insight_type == "SESSION_HYPOTHESIS":
            # 다른 설명이 없으면 가설이 아니라 단정이다. 그 한 줄이 가설을 가설로 남긴다.
            if len(unique) < 2 or not has_child_composed or not alternatives:
                continue
        else:  # EXPLORE_NEXT — 근거가 약한 대신 주장도 약하다.
            if not question:
                continue
            if _TRAIT_LANGUAGE.search(f"{title} {description} {hypothesis or ''}"):
                continue
            hypothesis = None

        observations.append(
            contracts.DiarySessionObservation(
                observation_code=code,
                insight_type=insight_type,
                domain=domain,
                title=title,
                description=description,
                hypothesis=hypothesis,
                alternative_explanations=alternatives,
                clarification_question=question,
                evidence_refs=refs,
            )
        )
        if len(observations) >= 3:
            break
    return observations


# 확인하지 못한 것의 이름표. 문구까지 서버가 정한다 — 모델에게 맡기면 '모르는 것'조차 지어낸다.
_UNKNOWN_TEMPLATES: tuple[tuple[str, str], ...] = (
    ("NO_VOICE_ANSWER", "아이가 음성으로 들려준 이야기가 없어 사건의 흐름은 확인하지 않았어요."),
    ("ONLY_CHOICE_ANSWERS", "고른 답만 있어 아이가 자기 말로 표현한 내용은 확인하지 않았어요."),
    ("SKIPPED_QUESTIONS", "아이가 넘긴 질문이 있어 그 부분은 이번에 확인하지 않았어요."),
    ("STT_UNCONFIRMED", "음성 인식 확인이 필요한 답이 있어 그 내용은 근거로 쓰지 않았어요."),
    ("NO_EMOTION", "아이가 고르거나 말한 감정이 없어 마음은 이번에 확인하지 않았어요."),
    ("NO_VISION_SUMMARY", "그림 관찰 서술이 없어 그림 내용은 이번에 확인하지 않았어요."),
    ("REALITY_UNKNOWN", "실제로 있었던 일인지 상상한 이야기인지는 아이가 말하지 않았어요."),
    ("TIME_UNKNOWN", "언제 있었던 일인지는 아이가 말하지 않았어요."),
)


def _is_backed_by_child_answer(step: contracts.DiaryNarrativeStep) -> bool:
    """이 흐름 단계가 아이가 **질문에 준 답**에 기대고 있는가.

    흐름 단계는 아이의 답에서만 오지 않는다. 그림 관찰(``VLM_OBSERVATION``·
    ``DETECTED_OBJECT``)에서 만들어진 단계도 있고, 감정 선택(``EMOTION_SELECTION``)만으로
    만들어진 단계도 있다. 그것들을 아이가 이야기한 것으로 세면 **아이가 하지 않은 말을 했다고
    적게 된다** — 2026-08-09 실측에서 "가운데에 집 모양을 그렸어요"(그림에서 나온 문장) 하나로
    "있었던 일 한 가지를 자기 말로 이야기했어요"가 붙었다.

    근거가 아예 없는 단계도 세지 않는다. 무엇에 기대고 있는지 모르는 문장을 아이의 표현으로
    올릴 수는 없다.
    """
    return any(
        (ref.kind or "").strip().upper() == "QA_ANSWER"
        for ref in (step.evidence_refs or [])
    )


def _developmental_observations(
    req: contracts.ObservationGenerationRequest,
    *,
    flow: list[contracts.DiaryNarrativeStep],
    child_voice: list[contracts.DiaryChildVoiceItem],
) -> list[contracts.DiaryDevelopmentalObservation]:
    """연령 발달 맥락 + 이번 활동에서 확인된 표현을 조립한다(4층).

    **서버가 정한다.** 어떤 맥락 문장이 붙을지는 등록부(검수 출처)와 나이가 정하고, 무엇이
    확인됐는지는 검증된 신호가 정한다 — 모델은 관여하지 않는다. 모델에게 맡기면 "또래보다
    빠르다" 같은 문장이 곧바로 나온다.

    한 번의 활동을 발달검사처럼 채점하지 않는다. 확인하지 못한 도메인은 ``NOT_ASSESSED`` 로
    남기고, 그것을 발달 지연으로 읽지 않도록 범위 문구를 항상 함께 보낸다.
    """
    spoken = [item for item in child_voice if item.elicitation_type in _CHILD_COMPOSED]
    # 도메인별로 '이번 활동에서 무엇이 확인됐는가'만 본다. 판정이 아니라 관찰이다.
    events = [step for step in flow if step.step_type in {"EVENT", "CHILD_ACTION"}]
    others = [step for step in flow if step.step_type == "OTHER_RESPONSE"]
    emotions = [step for step in flow if step.step_type == "EMOTION"]
    wishes = [step for step in flow if step.step_type in {"WISH", "OUTCOME"}]
    said_emotion = bool((req.expressed_emotion_text or "").strip())
    chose_emotion = bool(req.selected_emotion_refs)

    findings: list[tuple[str, str, str, list]] = []

    # ① 이야기·언어 — 사건을 몇 단계나 이어 말했는가.
    #
    # ⚠️ 흐름 단계가 있다는 것과 아이가 이야기했다는 것은 다르다. 단계는 그림 관찰에서도,
    #    고른 답에서도 만들어진다. 그래서 세 갈래로 나눈다.
    #
    #        아이가 직접 문장을 만든 답이 있다   → "자기 말로 이야기했어요"
    #        고른 답만 있다                      → "보기에서 골라 알려줬어요"
    #        둘 다 없다(그림에서만 나온 단계)     → 확인하지 않음
    #
    #    셋을 섞으면 리포트가 아이가 하지 않은 말을 했다고 적는다(2026-08-09 실측).
    answered_events = [step for step in events if _is_backed_by_child_answer(step)]
    if spoken and len(events) >= 2:
        findings.append(
            (
                developmental_context.NARRATIVE_LANGUAGE,
                developmental_context.OBSERVED,
                "이번 활동에서 아이는 있었던 일과 그다음 행동을 이어서 이야기했어요.",
                events[:2],
            )
        )
    elif spoken:
        findings.append(
            (
                developmental_context.NARRATIVE_LANGUAGE,
                developmental_context.PARTIAL,
                "이번 활동에서 아이는 있었던 일 한 가지를 자기 말로 이야기했어요.",
                events[:1],
            )
        )
    elif answered_events:
        findings.append(
            (
                developmental_context.NARRATIVE_LANGUAGE,
                developmental_context.PARTIAL,
                "이번 활동에서 아이는 보기에서 골라 있었던 일을 알려줬어요. 자기 말로 풀어 이야기하지는 않았어요.",
                answered_events[:1],
            )
        )
    else:
        findings.append(
            (
                developmental_context.NARRATIVE_LANGUAGE,
                developmental_context.NOT_ASSESSED,
                developmental_context.NOT_ASSESSED_TEXT,
                [],
            )
        )

    # ② 감정 표현 — 말한 것과 고른 것을 구분한다. 고른 것만으로 '표현했다'고 쓰지 않는다.
    #
    # ⚠️ 흐름의 EMOTION 단계는 **고른 감정에서도 만들어진다.** 그래서 단계가 있다는 것만으로
    #    OBSERVED 로 올리면, 한 마디도 하지 않고 표정을 고르기만 한 아이에게 "자기 말로
    #    이야기했어요"가 붙는다(2026-08-09 실측 — 같은 화면 아래에 "감정을 고른 기록만 있으니"가
    #    함께 떠서 서로 어긋났다). 근거가 감정 선택뿐인 단계는 말한 것으로 세지 않는다.
    spoken_emotions = (
        [step for step in emotions if _is_backed_by_child_answer(step)] if spoken else []
    )
    if spoken_emotions or said_emotion:
        findings.append(
            (
                developmental_context.EMOTION_EXPRESSION,
                developmental_context.OBSERVED,
                "이번 활동에서 아이는 그때의 마음을 자기 말로 이야기했어요.",
                spoken_emotions[:1],
            )
        )
    elif emotions or chose_emotion:
        findings.append(
            (
                developmental_context.EMOTION_EXPRESSION,
                developmental_context.PARTIAL,
                "이번 활동에서 아이는 감정을 보기에서 골랐어요. 말로 설명하지는 않았어요.",
                [],
            )
        )
    else:
        findings.append(
            (
                developmental_context.EMOTION_EXPRESSION,
                developmental_context.NOT_ASSESSED,
                developmental_context.NOT_ASSESSED_TEXT,
                [],
            )
        )

    # ③ 사회적 이해 — 함께 있던 사람의 행동·반응을 이야기했는가.
    findings.append(
        (
            developmental_context.SOCIAL_UNDERSTANDING,
            developmental_context.OBSERVED if others else developmental_context.NOT_ASSESSED,
            "이번 활동에서 아이는 함께 있던 사람이 한 행동도 이야기했어요."
            if others
            else developmental_context.NOT_ASSESSED_TEXT,
            others[:1],
        )
    )

    # ④ 자기 표현 — 바라는 것이나 이야기의 끝을 말했는가.
    findings.append(
        (
            developmental_context.SELF_REFLECTION,
            developmental_context.OBSERVED if wishes else developmental_context.NOT_ASSESSED,
            "이번 활동에서 아이는 바라는 것이나 이야기의 끝을 이야기했어요."
            if wishes
            else developmental_context.NOT_ASSESSED_TEXT,
            wishes[:1],
        )
    )

    # ⑤ 대화 참여 — 질문과 답을 몇 차례 주고받았는가.
    #
    # ⚠️ 세는 것은 **아이가 자기 말로 만든 답**뿐이다. 고른 답과 STT 미확인 발화는 빼는데,
    #    앞의 것은 아이가 만든 문장이 아니고 뒤의 것은 무슨 말인지 확정되지 않아서다.
    if len(spoken) >= 2:
        findings.append(
            (
                developmental_context.CONVERSATION_PARTICIPATION,
                developmental_context.OBSERVED,
                f"이번 활동에서 아이는 질문과 답을 {len(spoken)}차례 자기 말로 이어갔어요.",
                events[:1],
            )
        )
    elif spoken:
        findings.append(
            (
                developmental_context.CONVERSATION_PARTICIPATION,
                developmental_context.PARTIAL,
                "이번 활동에서 아이는 질문에 한 번 자기 말로 답했어요.",
                events[:1],
            )
        )
    else:
        findings.append(
            (
                developmental_context.CONVERSATION_PARTICIPATION,
                developmental_context.NOT_ASSESSED,
                developmental_context.NOT_ASSESSED_TEXT,
                [],
            )
        )

    # ⑥ 그림과 말의 연결 — 그림에 담은 것을 말로 이었는가.
    #
    # ⚠️ 그림 서술이 있는 것만으로는 부족하다. **아이가 말로 그것을 이어야** 연결이다.
    #    그림만 보고 "그림과 말을 연결했다"고 쓰면 아이가 하지 않은 일을 적는 것이 된다.
    has_drawing_description = any(
        summary.drawing_description.strip() for summary in req.subject_summaries
    )
    drew_and_told = has_drawing_description and bool(spoken)
    findings.append(
        (
            developmental_context.DRAWING_LANGUAGE_INTEGRATION,
            developmental_context.OBSERVED
            if drew_and_told
            else developmental_context.NOT_ASSESSED,
            "이번 활동에서 아이는 그림에 담은 장면을 자기 말로 이어 설명했어요."
            if drew_and_told
            else developmental_context.NOT_ASSESSED_TEXT,
            events[:1],
        )
    )

    observations: list[contracts.DiaryDevelopmentalObservation] = []
    for domain, status, text, steps in findings:
        # ⚠️ 근거가 없으면 카드를 만들지 않는다. 예전에는 NOT_ASSESSED 카드를 내보내
        #    "이 나이대에서는 확인하지 않아요"만 줄줄이 남았다 — 보호자에게는 아무것도 아닌
        #    화면이었고, 자칫 아이가 못 한 것으로도 읽혔다. 확인하지 못한 것은
        #    unknown_items 가 이름을 붙여 따로 돌려준다.
        if status == developmental_context.NOT_ASSESSED:
            continue

        # 감정을 고르기만 한 경우는 연령 맥락을 붙이지 않는다. 보기에서 고른 것을 언어·정서
        #   발달과 잇는 순간, 고른 답이 말한 답이 된다.
        emotion_choice_only = (
            domain == developmental_context.EMOTION_EXPRESSION
            and status == developmental_context.PARTIAL
            and not (emotions or said_emotion)
        )
        if emotion_choice_only:
            context = None
        else:
            context = developmental_context.contexts_for(
                domain,
                age_months=req.age_months,
                education_stage=req.education_stage,
            )

        if context is not None:
            age_context = context.parent_context
            source_ids = list(context.source_ids)
            context_type = context.context_type
        elif emotion_choice_only:
            # 맥락 문장 자체를 비운다. 붙일 수 있는 말이 없는 것이 사실이다.
            age_context = ""
            source_ids = []
            context_type = developmental_context.SESSION_ONLY_CONTEXT
        else:
            # 나이를 모르거나, 그 도메인·교육단계에 쓸 수 있는 검수 자료가 없다. 규준을
            #   주장하지 않고 이번 활동만 적는다 — 짐작해 붙이면 지어낸 규준이 된다.
            fallback = developmental_context.session_only_context(domain)
            if fallback is None:
                continue
            age_context = fallback
            source_ids = []
            context_type = developmental_context.SESSION_ONLY_CONTEXT

        refs = [ref for step in steps for ref in step.evidence_refs]
        observations.append(
            contracts.DiaryDevelopmentalObservation(
                domain=domain,
                status=status,
                age_context=age_context,
                observation=text,
                scope_text=developmental_context.SCOPE_TEXT,
                source_ids=source_ids,
                evidence_refs=refs[:2],
                context_type=context_type,
                caregiver_question=_DEVELOPMENTAL_QUESTIONS.get(domain),
            )
        )
    return observations


# 보호자가 활동에 이어 그대로 물어볼 수 있는 질문. 도메인마다 하나씩 고정한다.
#
# ⚠️ 모델이 만들지 않는다. 맡기면 "왜 그렇게 했어?"처럼 아이를 추궁하는 문장이 섞인다.
_DEVELOPMENTAL_QUESTIONS = {
    "NARRATIVE_LANGUAGE": "그 일에서 가장 기억나는 순간은 언제였어?",
    "CONVERSATION_PARTICIPATION": "그 이야기 더 해 줄 수 있어?",
    "DRAWING_LANGUAGE_INTEGRATION": "그림에서 이 부분은 무슨 이야기야?",
    "EMOTION_EXPRESSION": "그때 마음이 어땠는지 조금 더 말해 줄래?",
    "SOCIAL_UNDERSTANDING": "그 사람은 그때 어떤 마음이었을까?",
    "COPING_HELP_SEEKING": "그럴 때 누구한테 도와 달라고 하면 좋을까?",
    "SELF_REFLECTION": "다음에는 어떻게 해 보고 싶어?",
}


def _unknown_items(
    req: contracts.ObservationGenerationRequest,
    *,
    reality: str,
    time_scope: str,
    vision_available: bool,
) -> list[contracts.DiaryUnknownItem]:
    """이번 활동에서 확인하지 못한 것을 원자료에서 결정한다.

    빈칸을 해석으로 메우지 않으려면 침묵이 아니라 **이름**이 필요하다. 근거가 없어 카드를
    비우면 보호자에게는 '문제가 없었다'로 읽힌다 — 무엇을 알 수 없었는지 적어 돌려준다.
    """
    quality = _data_quality(req, evidence_count=0, vision_available=vision_available)
    no_voice = quality.confirmed_voice_count == 0
    flags: dict[str, bool] = {
        # 둘은 배타다. 음성이 없는데 고른 답도 없으면 '이야기가 없음', 고른 답만 있으면
        #   '자기 말이 없음'이다 — 같이 나가면 같은 사실을 두 줄로 말하게 된다.
        "NO_VOICE_ANSWER": no_voice and quality.option_answer_count == 0,
        "ONLY_CHOICE_ANSWERS": no_voice and quality.option_answer_count > 0,
        "SKIPPED_QUESTIONS": quality.skipped_count > 0,
        "STT_UNCONFIRMED": quality.stt_confirmation_count > 0,
        "NO_EMOTION": not (req.selected_emotion_refs or [])
        and not (req.expressed_emotion_text or "").strip(),
        "NO_VISION_SUMMARY": not vision_available,
        "REALITY_UNKNOWN": reality == "UNKNOWN",
        "TIME_UNKNOWN": time_scope == "UNKNOWN",
    }
    return [
        contracts.DiaryUnknownItem(code=code, text=text)
        for code, text in _UNKNOWN_TEMPLATES
        if flags.get(code)
    ]


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
        if qa.stt_needs_confirmation:
            stt_confirmation += 1
            continue
        if is_option_answer(qa.answer_type) and (qa.answer_text or "").strip():
            option_count += 1
        elif is_spoken_answer(qa.answer_type) and (qa.answer_text or "").strip():
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
    # ⚠️ child_voice 는 세지 않는다. 그 목록은 모델이 만든 것이 아니라 **요청의 문답에서 그대로
    #    파생**되므로 문답이 하나라도 있으면 언제나 채워진다. 세는 순간 이 방어가 늘 참이 되어
    #    "빈 V2 를 만들지 않는다"가 무력해진다 — 2026-08-07 실호출에서 핵심 이야기도 흐름도 없이
    #    발화 목록만 있는 V2 가 실제로 열렸다. 근거로 검증된 구조가 하나는 있어야 한다.
    #
    # ⚠️ 발달 맥락(4층)은 **모델이 만들지 않는다.** 서버가 검증된 신호로 조립한다. 그래서
    #    이 판정에 함께 세운다 — 모델이 아무것도 못 만든 활동에서도 서버가 확인한 것이 있으면
    #    그건 보호자에게 보여 줄 값어치가 있는 내용이고, 그걸 버리면 화면이 통째로 옛 레이아웃으로
    #    떨어진다. 2026-08-09 실측: 아이가 보기로만 답한 활동에서 모델이 빈 신호를 돌려주자
    #    이야기·인사이트·4층이 한꺼번에 사라졌다. 4층은 그 활동에서도 적을 것이 있었다.
    #
    #    "빈 V2 를 만들지 않는다"는 그대로 지켜진다 — 확인된 것이 하나도 없으면 4층 카드는
    #    NOT_ASSESSED 로 전부 걸러져 빈 목록이 되고, 이 판정도 함께 거짓이 된다.
    developmental = _developmental_observations(
        req, flow=flow, child_voice=child_voice
    )
    if not any(
        (
            snapshot is not None,
            bool(flow),
            bool(observations),
            bool(questions),
            bool(developmental),
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
        # 연령 발달 맥락(4층). 어떤 맥락 문장이 붙을지는 검수 등록부와 나이가 정하고,
        #   무엇이 확인됐는지는 검증된 신호가 정한다 — 모델은 관여하지 않는다.
        developmental_observations=developmental,
        # 확인하지 못한 것은 모델이 아니라 원자료가 정한다. 카드가 비어 나가는 것과
        #   "무엇을 알 수 없었는지"를 적어 보내는 것은 보호자에게 전혀 다르게 읽힌다.
        unknown_items=_unknown_items(
            req,
            reality=reality,
            time_scope=time_scope,
            vision_available=vision_available,
        ),
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

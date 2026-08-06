"""경향 해석 카드의 구조적 판정 — 공개 게이트(S15P11B209-888) + 확신도 등급(S15P11B209-982).

보호자에게 경향 해석을 내보내려면 "근거 2건 이상"을 **결정적으로** 판정해야 한다. 규칙이 모호하면
LLM이 스스로 "근거 2건입니다"라고 주장하는 것과 다를 바 없어져 게이트가 무력해진다.
정본: docs/S15P11B209-875-report-api-contract.md §4-1·§3-1 · 보호자 계약 §4-1~§4-4(S15P11B209-885).

이 모듈이 소유하는 것은 **근거의 구조로 결정되는 모든 판정**이다. 두 가지가 여기 함께 있다:

    공개 여부(888)   근거가 충분한가 → 부족하면 카드를 뺀다.
    확신도 등급(982) 근거가 어느 통로에서 왔나 → 등급을 매겨 보호자에게 그대로 보여 준다.

둘을 한 모듈에 둔 이유: 같은 입력(카드 + 근거 풀)에 같은 '말단 참조 펼치기'(_leaf_refs)를 쓴다.
나눠 두면 펼치기 구현이 둘로 갈리고, 한쪽만 고쳐졌을 때 등급과 공개 판정이 조용히 어긋난다.

이 모듈이 report_safety와 다른 점 — 섞으면 안 되는 이유:

    report_safety(591·592)   문장 '표현'을 본다. 실패 → EXPERT_ONLY 강등(내용 보존).
    이 모듈(888)             근거의 '구조'를 본다. 실패 → 미공개(제외). 강등이 아니다.

강등은 "표현을 다듬으면 공개할 수 있다"는 뜻이다. 구조 게이트 실패는 근거 자체가 없다는 뜻이라
문장을 고쳐도 공개 대상이 아니다. 그래서 실패 처리가 다르고, 값싼 결정적 검사인 이쪽을 먼저 돌린다.

계수 규칙(§4-1):

1. 카드의 evidence_refs가 가리키는 근거를 모은다.
2. 각 근거를 **말단 원본 참조**로 펼친다 — source_ref는 그 자체가 말단이고, 파생 근거
   (REPEATED_SUBJECT·LONGITUDINAL)는 derived_from의 원본 목록이 말단이다.
3. 말단 (kind, id) **합집합의 크기**가 독립 근거 수다. 파생 근거와 그 원본이 함께 실려도
   같은 말단은 한 번만 센다.
4. 병합 상한을 적용한다 — 감정 근거 계열은 합쳐 1건, 활동 지표는 합쳐 1건.
5. 그 결과가 2건 이상이고, 그중 아이 자신의 표현이 1건 이상이어야 공개한다.

⚠️ 감정 근거를 합치는 이유: 선택 감정은 코드고 말한 감정은 자유 텍스트라 "같은 감정인지"를
   서버가 값 비교로 판정할 수 없다. AI에게 판정을 맡기면 자기 신고로 되돌아간다. 그래서
   보수적으로 계열 전체를 1건으로 본다 — 감정 근거만으로는 통과할 수 없다.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field

import internal_contracts as contracts

logger = logging.getLogger(__name__)

# 공개에 필요한 최소 독립 근거 수 (§4-1).
MIN_INDEPENDENT_EVIDENCE = 2

# 아이 자신의 표현으로 인정하는 근거 유형 (§4-1 조건 2).
CHILD_EXPRESSION_SOURCE_TYPES = frozenset(
    {"CHILD_ANSWER", "SELECTED_EMOTION", "STATED_EMOTION"}
)
# 말단 참조만 남은 파생 근거는 원본의 kind로 판단한다 — 아이 답변 메시지와 아이가 고른 감정.
CHILD_EXPRESSION_REF_KINDS = frozenset({"QA_ANSWER", "EMOTION_SELECTION"})

# 병합 계열: 같은 계열의 근거가 여러 건이어도 합쳐 1건으로 센다 (§4-1 조건 3).
_EMOTION_FAMILY = frozenset({"SELECTED_EMOTION", "STATED_EMOTION"})
_METRIC_FAMILY = frozenset({"ACTIVITY_METRIC"})
_MERGED_FAMILIES = (_EMOTION_FAMILY, _METRIC_FAMILY)

# 미공개 사유 코드 — 로그·unusedInputs에 남긴다. 원문은 남기지 않는다.
NO_EVIDENCE = "NO_EVIDENCE"  # 참조가 없거나 전부 해석 불가
NOT_ENOUGH_INDEPENDENT_EVIDENCE = "NOT_ENOUGH_INDEPENDENT_EVIDENCE"
NO_CHILD_EXPRESSION = "NO_CHILD_EXPRESSION"
BLOCKED_EVIDENCE = "BLOCKED_EVIDENCE"  # 미확정 STT·위기 발화를 근거로 씀

# 근거로 쓸 수 없는 참조 (kind, id) 집합의 별칭. 886(미확정 STT)·889(위기 발화)가 채운다.
BlockedRefs = frozenset


# ── 확신도 등급 (S15P11B209-982) ─────────────────────────────────
# 등급은 **근거의 종류로만** 정한다. LLM은 "무엇을 근거로 삼았는지"(evidence_refs)까지만 대고,
# 얼마나 센 근거인지는 여기서 계산한다. 모델에게 등급 판정권을 주면 근거가 약한 해석도
# STRONG 이라 주장해 체계 전체가 장식이 된다 — 그래서 모델이 보낸 값은 읽지도 않는다.
CONFIDENCE_STRONG = "STRONG"
CONFIDENCE_MODERATE = "MODERATE"
CONFIDENCE_WEAK = "WEAK"

# 근거가 들어온 '통로'. 등급은 어느 통로가 섞였는지로 갈리고, **몇 건인지는 보지 않는다.**
#   개수를 세면 약한 근거를 여러 개 모아 등급을 올리는 길이 열린다 — HTP 해석이 실제로 무너진
#   경로가 지표 합산이라, 이 함수는 집합만 보고 크기를 보지 않는다(규칙 2).
_UTTERANCE = "UTTERANCE"  # 아이가 말이나 문장으로 표현한 것 — 최상위 근거
_CHOICE = "CHOICE"  # 아이가 고른 것(감정 칩). 아이 자신의 표현이지만 발화는 아니다
_DRAWING = "DRAWING"  # 그림에서 확인된 것
_BEHAVIOR = "BEHAVIOR"  # 활동 지표(행동 기록)

# source_type → 통로. 파생 근거(REPEATED_SUBJECT·LONGITUDINAL)는 자체 통로가 없어 여기 없다 —
#   말단 원본의 kind 로 판단한다(아래 _REF_KIND_CHANNELS).
_SOURCE_TYPE_CHANNELS = {
    "CHILD_ANSWER": _UTTERANCE,
    "STATED_EMOTION": _UTTERANCE,
    "SELECTED_EMOTION": _CHOICE,
    "VISION": _DRAWING,
    "ACTIVITY_METRIC": _BEHAVIOR,
}
_REF_KIND_CHANNELS = {
    "QA_ANSWER": _UTTERANCE,
    "EMOTION_SELECTION": _CHOICE,
    "DETECTED_OBJECT": _DRAWING,
    "VLM_OBSERVATION": _DRAWING,
    "ACTIVITY_METRIC": _BEHAVIOR,
    # PRIOR_ACTIVITY 는 이전 활동의 원본 관찰·확인된 발화를 가리킨다. 어느 쪽인지 kind 만으로는
    #   알 수 없어 통로를 주지 않는다 — 통로가 없으면 등급을 올리지 못하고 WEAK 쪽으로 남는다.
}

# 그림·행동은 '아이가 말하지 않은 것'이다. 발화와 함께 쓰이면 교차 추론이라 한 등급 낮춘다.
_INFERRED_CHANNELS = frozenset({_DRAWING, _BEHAVIOR})


@dataclass(frozen=True)
class GateResult:
    """카드 한 건의 판정 결과. 실패 사유는 코드로만 남긴다(원문 비노출)."""

    passed: bool
    independent_count: int = 0
    reason: str | None = None
    child_expression: bool = False
    blocked: tuple[tuple[str, str], ...] = field(default_factory=tuple)


def _leaf_refs(item: contracts.ReportEvidenceItem) -> set[tuple[str, str]]:
    """근거 한 건의 말단 원본 참조 집합.

    source_ref는 그 자체가 말단이다. 파생 근거는 derived_from의 원본들이 말단이다.
    모델이 배타 규칙(정확히 하나)을 이미 보장하므로 한 단계 펼치면 말단에 닿는다 —
    파생이 파생을 가리키는 형태는 계약에 없다(derived_from은 원본 참조 목록이다).
    """
    if item.source_ref is not None:
        return {(item.source_ref.kind, item.source_ref.id)}
    return {(ref.kind, ref.id) for ref in item.derived_from or ()}


def _is_child_expression(item: contracts.ReportEvidenceItem) -> bool:
    """아이 자신의 표현에서 온 근거인지. 파생 근거는 말단 원본의 kind로 판단한다."""
    if item.source_type in CHILD_EXPRESSION_SOURCE_TYPES:
        return True
    return any(kind in CHILD_EXPRESSION_REF_KINDS for kind, _ in _leaf_refs(item))


def _channels(item: contracts.ReportEvidenceItem) -> set[str]:
    """근거 한 건이 지나온 통로. 원본 근거는 source_type, 파생 근거는 말단 kind 로 정한다."""
    channel = _SOURCE_TYPE_CHANNELS.get(item.source_type)
    if channel is not None:
        return {channel}
    return {
        c
        for kind, _ in _leaf_refs(item)
        if (c := _REF_KIND_CHANNELS.get(kind)) is not None
    }


def confidence_for(
    card: contracts.PublicInterpretation,
    evidence_by_id: dict[int, contracts.ReportEvidenceItem],
) -> str | None:
    """카드의 확신도 등급. 근거가 하나도 해석되지 않으면 None(등급을 매길 수 없다).

    판정(계약 §3-1 · CLAUDE.md 2절):

        발화만(감정 선택이 함께여도)        → STRONG    아이가 직접 말한 것 위에 얹힌 해석
        발화 + 그림/행동                    → MODERATE  교차 추론이라 한 걸음 멀다
        발화 없음(그림·행동·감정 선택만)     → WEAK      아이 말이 없으면 그 이상 올릴 수 없다

    ⚠️ 등급 표에는 "아이 발화가 포함되면 STRONG"과 "그림+발화면 MODERATE"가 나란히 적혀 있어
       그대로 읽으면 뒤 줄이 영영 안 걸린다. 표의 '직접 근거'(STRONG)와 '교차 일치'(MODERATE)
       쪽을 정본으로 삼아 위처럼 갈랐다 — 아이가 말하지 않은 것을 그림에서 미뤄 짐작한 해석은
       아이가 말한 것을 그대로 옮긴 해석보다 약하다.
    ⚠️ 감정 선택(칩 탭)이 발화와 함께 있어도 등급을 낮추지 않는다. 둘 다 아이 자신의 표현이라
       추론 단계가 늘지 않는다. 반대로 감정 선택'만'으로는 STRONG 이 될 수 없다 — 칩 하나는
       문장만큼 말해 주지 않는다.
    ⚠️ 근거 **개수는 보지 않는다.** 약한 근거를 아무리 모아도 등급이 오르지 않게 하는 장치다.
    ⚠️ 카드가 들고 온 confidence 값은 읽지 않는다 — 모델이 무엇을 적었든 여기 계산이 정답이다.
    """
    items = [evidence_by_id[ref] for ref in card.evidence_refs if ref in evidence_by_id]
    channels = {channel for item in items for channel in _channels(item)}
    if not channels:
        return None
    if _UTTERANCE not in channels:
        return CONFIDENCE_WEAK
    if channels & _INFERRED_CHANNELS:
        return CONFIDENCE_MODERATE
    return CONFIDENCE_STRONG


def _merge_families(
    items: list[contracts.ReportEvidenceItem],
) -> list[contracts.ReportEvidenceItem]:
    """병합 계열(감정·활동 지표)은 첫 건만 남긴다 — 계열 전체가 합쳐 1건이다.

    첫 건 기준은 결정적이어야 해서 입력 순서를 그대로 쓴다(값 비교로는 같은 감정인지 알 수 없다).
    """
    kept: list[contracts.ReportEvidenceItem] = []
    seen_families: list[frozenset[str]] = []
    for item in items:
        family = next(
            (f for f in _MERGED_FAMILIES if item.source_type in f), None
        )
        if family is not None:
            if family in seen_families:
                continue
            seen_families.append(family)
        kept.append(item)
    return kept


def evaluate(
    card: contracts.PublicInterpretation,
    evidence_by_id: dict[int, contracts.ReportEvidenceItem],
    blocked_refs: frozenset[tuple[str, str]] = frozenset(),
) -> GateResult:
    """카드 한 건을 판정한다. 통과하면 공개, 아니면 그 카드만 제외한다.

    blocked_refs: 근거로 쓸 수 없는 말단 참조(미확정 STT·위기 발화). 하나라도 걸리면 미공개다 —
        오인식 문장이나 위기 발화가 해석의 근거가 되면 안 된다(875 §6-1).
    """
    items = [
        evidence_by_id[ref] for ref in card.evidence_refs if ref in evidence_by_id
    ]
    if not items:
        return GateResult(passed=False, reason=NO_EVIDENCE)

    # 배제 대상을 근거로 썼는지 먼저 본다 — 개수를 세기 전에 걸러야 "2건이니 통과"가 되지 않는다.
    hit = sorted(
        {leaf for item in items for leaf in _leaf_refs(item) if leaf in blocked_refs}
    )
    if hit:
        return GateResult(
            passed=False, reason=BLOCKED_EVIDENCE, blocked=tuple(hit)
        )

    counted = _merge_families(items)
    leaves = {leaf for item in counted for leaf in _leaf_refs(item)}
    child_expression = any(_is_child_expression(item) for item in counted)

    if len(leaves) < MIN_INDEPENDENT_EVIDENCE:
        return GateResult(
            passed=False,
            independent_count=len(leaves),
            reason=NOT_ENOUGH_INDEPENDENT_EVIDENCE,
            child_expression=child_expression,
        )
    if not child_expression:
        # 그림 관찰·활동 지표만으로 심리 경향을 만드는 경로를 막는다(상징 단독 해석 방지).
        return GateResult(
            passed=False,
            independent_count=len(leaves),
            reason=NO_CHILD_EXPRESSION,
        )
    return GateResult(
        passed=True, independent_count=len(leaves), child_expression=True
    )


def apply(
    cards: list[contracts.PublicInterpretation],
    evidence_items: list[contracts.ReportEvidenceItem],
    blocked_refs: frozenset[tuple[str, str]] = frozenset(),
) -> tuple[list[contracts.PublicInterpretation], list[str]]:
    """카드 목록에 게이트를 적용하고, 통과한 카드에 확신도를 **찍어서** 돌려준다.

    반환: (공개할 카드, 미공개 사유 코드 목록). 리포트 전체를 실패시키지 않고 문제 카드만 뺀다.
    ⚠️ 실패한 카드를 EXPERT_ONLY로 강등하지 않는다 — 근거가 없는 것이라 표현을 다듬어도
       공개 대상이 아니다. 강등은 report_safety(표현 필터)의 처리다.
    ⚠️ 확신도를 여기서 찍는 것이 요점이다(982). 이 함수를 통과하지 않고 공개되는 카드는 없으므로,
       '등급이 비어 있는 공개 카드'라는 상태가 원리적으로 생기지 않는다. 모델이 보낸 값이
       남아 있었더라도 여기서 계산 결과로 덮인다 — 등급을 흔들 수 있는 경로가 없다.
    """
    evidence_by_id = {item.evidence_id: item for item in evidence_items}
    passed: list[contracts.PublicInterpretation] = []
    reasons: list[str] = []
    for card in cards:
        result = evaluate(card, evidence_by_id, blocked_refs)
        if result.passed:
            # 게이트를 통과한 카드는 근거가 2건 이상 해석된 상태라 등급이 None 일 수 없다.
            # ⚠️ **제자리에서** 찍는다(model_copy 로 새 객체를 만들지 않는다). 호출부의
            #    _kept_positions 가 카드 배열의 앞뒤를 **동일성(is)** 으로 맞춰 주제별 관찰의
            #    interpretationRefs 를 다시 매핑하는데, 사본을 돌려주면 그 매핑이 전부 실패해
            #    참조가 조용히 사라진다(875 §5-1). 값은 같고 아무 테스트도 깨지지 않는 종류의 사고라
            #    여기 못 박아 둔다.
            card.confidence = confidence_for(card, evidence_by_id)
            passed.append(card)
            continue
        reasons.append(result.reason or NO_EVIDENCE)
        # ⚠️ 카드 문장·아이 발화는 로그로 남기지 않는다 — 사유 코드와 관점 라벨만.
        logger.warning(
            "경향 카드 미공개(구조 게이트): reason=%s category=%s independent=%d",
            result.reason,
            card.category,
            result.independent_count,
        )
    return passed, reasons

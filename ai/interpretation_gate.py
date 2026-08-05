"""경향 해석 카드의 구조적 공개 게이트 (S15P11B209-888).

보호자에게 경향 해석을 내보내려면 "근거 2건 이상"을 **결정적으로** 판정해야 한다. 규칙이 모호하면
LLM이 스스로 "근거 2건입니다"라고 주장하는 것과 다를 바 없어져 게이트가 무력해진다.
정본: docs/S15P11B209-875-report-api-contract.md §4-1 · 보호자 계약 §4-1~§4-4(S15P11B209-885).

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
    """카드 목록에 게이트를 적용한다.

    반환: (공개할 카드, 미공개 사유 코드 목록). 리포트 전체를 실패시키지 않고 문제 카드만 뺀다.
    ⚠️ 실패한 카드를 EXPERT_ONLY로 강등하지 않는다 — 근거가 없는 것이라 표현을 다듬어도
       공개 대상이 아니다. 강등은 report_safety(표현 필터)의 처리다.
    """
    evidence_by_id = {item.evidence_id: item for item in evidence_items}
    passed: list[contracts.PublicInterpretation] = []
    reasons: list[str] = []
    for card in cards:
        result = evaluate(card, evidence_by_id, blocked_refs)
        if result.passed:
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

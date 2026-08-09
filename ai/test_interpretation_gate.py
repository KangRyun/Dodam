"""interpretation_gate 단위 테스트 — 경향 카드 구조적 공개 게이트 (S15P11B209-888).

정본: docs/S15P11B209-875-report-api-contract.md §4-1.

여기서 못 박는 것:
- 독립 근거는 **말단 원본 참조의 합집합 크기**다. 근거 항목 개수가 아니다.
- 같은 sourceType이라도 원본이 다르면 독립이다(집 답변 + 사람 답변 = 2건).
- 파생 근거와 그 원본이 함께 실리면 1건이다.
- 감정 근거 계열·활동 지표는 각각 합쳐 1건이다.
- 아이 표현 근거가 없으면 공개하지 않는다.
- 실패는 **제외**이고 EXPERT_ONLY 강등이 아니다.
"""

from __future__ import annotations

import unittest

import internal_contracts as contracts
import interpretation_gate as gate


def _ref(kind="QA_ANSWER", ref_id="202"):
    return contracts.EvidenceSourceRef(kind=kind, id=ref_id)


def _item(evidence_id, source_type="CHILD_ANSWER", ref=None, derived=None):
    return contracts.ReportEvidenceItem(
        evidence_id=evidence_id,
        source_type=source_type,
        text=f"근거 {evidence_id}",
        source_ref=None if derived else (ref or _ref()),
        derived_from=derived,
    )


def _card(refs):
    return contracts.PublicInterpretation(
        category="RELATIONSHIP",
        title="가족과의 정서적 연결",
        tendency_text="가족에게 의지하려는 경향이 보일 수 있습니다.",
        scope_text="이번 그림 활동에서 나타난 가능성입니다.",
        home_observation_guide="새로운 상황에서도 비슷한지 살펴봐 주세요.",
        evidence_refs=refs,
    )


def _evaluate(items, refs, blocked=frozenset()):
    return gate.evaluate(_card(refs), {i.evidence_id: i for i in items}, blocked)


class IndependentCountTest(unittest.TestCase):
    def test_two_different_origins_pass(self):
        """같은 sourceType이라도 원본이 다르면 독립이다 — 대표 예시가 통과해야 한다."""
        items = [
            _item(1, ref=_ref(ref_id="202")),  # 집 그림 답변
            _item(2, ref=_ref(ref_id="318")),  # 사람 그림 답변
        ]
        result = _evaluate(items, [1, 2])
        self.assertTrue(result.passed)
        self.assertEqual(result.independent_count, 2)

    def test_same_origin_counts_once(self):
        """같은 메시지를 두 번 인용해도 1건이다."""
        items = [_item(1, ref=_ref(ref_id="202")), _item(2, ref=_ref(ref_id="202"))]
        result = _evaluate(items, [1, 2])
        self.assertFalse(result.passed)
        self.assertEqual(result.independent_count, 1)
        self.assertEqual(result.reason, gate.NOT_ENOUGH_INDEPENDENT_EVIDENCE)

    def test_single_evidence_fails(self):
        result = _evaluate([_item(1)], [1])
        self.assertFalse(result.passed)
        self.assertEqual(result.reason, gate.NOT_ENOUGH_INDEPENDENT_EVIDENCE)

    def test_no_reference_fails(self):
        self.assertEqual(_evaluate([_item(1)], []).reason, gate.NO_EVIDENCE)

    def test_unknown_reference_does_not_pad_the_count(self):
        """존재하지 않는 근거는 셈에서 빠진다 — 없는 근거로 2건을 채우지 못한다."""
        result = _evaluate([_item(1)], [1, 99])
        self.assertEqual(result.independent_count, 1)  # 유효한 1건만
        self.assertFalse(result.passed)
        self.assertEqual(result.reason, gate.NOT_ENOUGH_INDEPENDENT_EVIDENCE)

    def test_derived_and_its_origin_count_once(self):
        """파생 근거와 그 원본이 함께 실려도 같은 말단은 한 번만 센다."""
        origin_a, origin_b = _ref(ref_id="202"), _ref(ref_id="318")
        items = [
            _item(1, source_type="REPEATED_SUBJECT", derived=[origin_a, origin_b]),
            _item(2, ref=origin_a),  # 파생의 원본 중 하나
        ]
        result = _evaluate(items, [1, 2])
        self.assertTrue(result.passed)
        self.assertEqual(result.independent_count, 2)  # 3이 아니다

    def test_derived_alone_can_pass_with_two_origins(self):
        """파생 근거 하나가 서로 다른 원본 둘을 담으면 2건이다(그게 파생의 뜻이다)."""
        items = [
            _item(
                1,
                source_type="REPEATED_SUBJECT",
                derived=[_ref(ref_id="202"), _ref(ref_id="318")],
            )
        ]
        result = _evaluate(items, [1])
        self.assertTrue(result.passed)
        self.assertEqual(result.independent_count, 2)


class MergeFamilyTest(unittest.TestCase):
    def test_emotion_family_merges_to_one(self):
        """고른 감정 + 말한 감정은 합쳐 1건 — 감정 근거만으로는 통과할 수 없다."""
        items = [
            _item(1, source_type="SELECTED_EMOTION", ref=_ref("EMOTION_SELECTION", "5")),
            _item(2, source_type="STATED_EMOTION", ref=_ref(ref_id="202")),
        ]
        result = _evaluate(items, [1, 2])
        self.assertFalse(result.passed)
        self.assertEqual(result.independent_count, 1)
        self.assertEqual(result.reason, gate.NOT_ENOUGH_INDEPENDENT_EVIDENCE)

    def test_emotion_plus_other_origin_passes(self):
        items = [
            _item(1, source_type="SELECTED_EMOTION", ref=_ref("EMOTION_SELECTION", "5")),
            _item(2, source_type="CHILD_ANSWER", ref=_ref(ref_id="202")),
        ]
        self.assertTrue(_evaluate(items, [1, 2]).passed)

    def test_activity_metrics_merge_to_one(self):
        items = [
            _item(1, source_type="ACTIVITY_METRIC", ref=_ref("ACTIVITY_METRIC", "m1")),
            _item(2, source_type="ACTIVITY_METRIC", ref=_ref("ACTIVITY_METRIC", "m2")),
            _item(3, source_type="ACTIVITY_METRIC", ref=_ref("ACTIVITY_METRIC", "m3")),
        ]
        result = _evaluate(items, [1, 2, 3])
        self.assertEqual(result.independent_count, 1)
        self.assertFalse(result.passed)


class ChildExpressionRequiredTest(unittest.TestCase):
    def test_vision_and_metric_only_is_blocked(self):
        """그림 관찰과 활동 지표만으로 심리 경향을 만들지 못한다(상징 단독 해석 방지)."""
        items = [
            _item(1, source_type="VISION", ref=_ref("DETECTED_OBJECT", "d1")),
            _item(2, source_type="ACTIVITY_METRIC", ref=_ref("ACTIVITY_METRIC", "m1")),
        ]
        result = _evaluate(items, [1, 2])
        self.assertFalse(result.passed)
        self.assertEqual(result.reason, gate.NO_CHILD_EXPRESSION)
        self.assertEqual(result.independent_count, 2)  # 개수는 찼지만 종류가 모자라다

    def test_vision_plus_child_answer_passes(self):
        items = [
            _item(1, source_type="VISION", ref=_ref("DETECTED_OBJECT", "d1")),
            _item(2, source_type="CHILD_ANSWER", ref=_ref(ref_id="202")),
        ]
        self.assertTrue(_evaluate(items, [1, 2]).passed)

    def test_derived_from_child_origin_counts_as_child_expression(self):
        """파생 근거는 말단 원본이 아이 표현이면 충족으로 본다(§4-1 조건 2)."""
        items = [
            _item(
                1,
                source_type="REPEATED_SUBJECT",
                derived=[_ref(ref_id="202"), _ref(ref_id="318")],
            )
        ]
        result = _evaluate(items, [1])
        self.assertTrue(result.passed)
        self.assertTrue(result.child_expression)

    def test_derived_from_vision_only_is_not_child_expression(self):
        items = [
            _item(
                1,
                source_type="LONGITUDINAL",
                derived=[_ref("DETECTED_OBJECT", "d1"), _ref("VLM_OBSERVATION", "v1")],
            )
        ]
        result = _evaluate(items, [1])
        self.assertFalse(result.passed)
        self.assertEqual(result.reason, gate.NO_CHILD_EXPRESSION)


class BlockedEvidenceTest(unittest.TestCase):
    """미확정 STT·위기 발화는 근거가 될 수 없다 (875 §6-1). 886·889가 목록을 채운다."""

    def test_blocked_origin_fails_before_counting(self):
        items = [_item(1, ref=_ref(ref_id="202")), _item(2, ref=_ref(ref_id="318"))]
        result = _evaluate(items, [1, 2], blocked=frozenset({("QA_ANSWER", "318")}))
        self.assertFalse(result.passed)
        self.assertEqual(result.reason, gate.BLOCKED_EVIDENCE)
        self.assertIn(("QA_ANSWER", "318"), result.blocked)

    def test_blocked_origin_inside_derived_evidence_also_fails(self):
        items = [
            _item(
                1,
                source_type="REPEATED_SUBJECT",
                derived=[_ref(ref_id="202"), _ref(ref_id="318")],
            )
        ]
        result = _evaluate(items, [1], blocked=frozenset({("QA_ANSWER", "318")}))
        self.assertEqual(result.reason, gate.BLOCKED_EVIDENCE)

    def test_unrelated_block_does_not_affect(self):
        items = [_item(1, ref=_ref(ref_id="202")), _item(2, ref=_ref(ref_id="318"))]
        result = _evaluate(items, [1, 2], blocked=frozenset({("QA_ANSWER", "999")}))
        self.assertTrue(result.passed)


class ApplyTest(unittest.TestCase):
    def test_only_failing_card_is_removed(self):
        """리포트 전체를 실패시키지 않고 문제 카드만 뺀다."""
        items = [_item(1, ref=_ref(ref_id="202")), _item(2, ref=_ref(ref_id="318"))]
        good, bad = _card([1, 2]), _card([1])
        passed, reasons = gate.apply([good, bad], items)
        self.assertEqual(passed, [good])
        self.assertEqual(reasons, [gate.NOT_ENOUGH_INDEPENDENT_EVIDENCE])

    def test_all_failing_yields_empty_list(self):
        """통과가 없으면 빈 목록이다 — 그것이 정상이다(875 §10)."""
        passed, reasons = gate.apply([_card([1])], [_item(1)])
        self.assertEqual(passed, [])
        self.assertEqual(len(reasons), 1)

    def test_no_cards_is_fine(self):
        self.assertEqual(gate.apply([], []), ([], []))


class GateIsNotADowngradeTest(unittest.TestCase):
    """구조 게이트 실패는 제외이고 강등이 아니다 — 두 검사의 성질이 다르다.

    강등(EXPERT_ONLY)은 "표현을 다듬으면 공개할 수 있다"는 뜻인데, 근거가 없는 카드는
    문장을 고쳐도 공개 대상이 아니다. 이 모듈이 visibility 값을 다루지 않는 것으로 못 박는다.
    """

    def test_gate_result_carries_no_visibility_scope(self):
        result = _evaluate([_item(1)], [1])
        self.assertFalse(hasattr(result, "visibility_scope"))
        self.assertNotIn("EXPERT_ONLY", str(result.reason))


# ── 확신도 등급 (S15P11B209-982) ─────────────────────────────────


def _confidence(items, refs, **card_overrides):
    card = _card(refs)
    for key, value in card_overrides.items():
        setattr(card, key, value)
    return gate.confidence_for(card, {i.evidence_id: i for i in items})


def _vision(evidence_id, ref_id="d1"):
    return _item(
        evidence_id,
        source_type="VISION",
        ref=_ref(kind="DETECTED_OBJECT", ref_id=ref_id),
    )


def _metric(evidence_id, ref_id="m1"):
    return _item(
        evidence_id,
        source_type="ACTIVITY_METRIC",
        ref=_ref(kind="ACTIVITY_METRIC", ref_id=ref_id),
    )


def _chosen_emotion(evidence_id, ref_id="e5"):
    return _item(
        evidence_id,
        source_type="SELECTED_EMOTION",
        ref=_ref(kind="EMOTION_SELECTION", ref_id=ref_id),
    )


class ConfidenceGradeTest(unittest.TestCase):
    """등급은 근거의 **종류**로 정해진다 — 정본: 875 §3-1 · CLAUDE.md 2절.

    여기서 못 박는 것:
    - 아이 발화만 → STRONG / 발화 + 그림·행동 → MODERATE / 발화 없음 → WEAK
    - 감정 선택은 아이 표현이지만 발화가 아니다 — 단독으로는 STRONG 이 될 수 없다.
    - 등급은 근거 **개수와 무관하다**(약한 근거를 모아 올릴 수 없다).
    """

    def test_child_utterance_only_is_strong(self):
        items = [_item(1, ref=_ref(ref_id="202")), _item(2, ref=_ref(ref_id="318"))]
        self.assertEqual(_confidence(items, [1, 2]), gate.CONFIDENCE_STRONG)

    def test_utterance_with_drawing_is_moderate(self):
        """그림과 발화를 이어 붙인 해석은 교차 추론이라 한 등급 낮다."""
        self.assertEqual(
            _confidence([_item(1), _vision(2)], [1, 2]), gate.CONFIDENCE_MODERATE
        )

    def test_utterance_with_activity_metric_is_moderate(self):
        self.assertEqual(
            _confidence([_item(1), _metric(2)], [1, 2]), gate.CONFIDENCE_MODERATE
        )

    def test_drawing_only_is_weak(self):
        self.assertEqual(
            _confidence([_vision(1), _vision(2, "d2")], [1, 2]), gate.CONFIDENCE_WEAK
        )

    def test_activity_metric_only_is_weak(self):
        self.assertEqual(
            _confidence([_metric(1), _metric(2, "m2")], [1, 2]), gate.CONFIDENCE_WEAK
        )

    def test_selected_emotion_alone_is_weak(self):
        """칩 하나는 문장만큼 말해 주지 않는다 — 아이 표현이어도 발화가 아니다."""
        self.assertEqual(
            _confidence([_chosen_emotion(1), _vision(2)], [1, 2]), gate.CONFIDENCE_WEAK
        )

    def test_selected_emotion_does_not_downgrade_utterance(self):
        """둘 다 아이 자신의 표현이라 추론 단계가 늘지 않는다 — STRONG 을 유지한다."""
        self.assertEqual(
            _confidence([_item(1), _chosen_emotion(2)], [1, 2]), gate.CONFIDENCE_STRONG
        )

    def test_chip_answer_is_choice_not_utterance(self):
        """선택형(OPTION) 대화 답변은 발화가 아니라 '고른 것'이다 (S15P11B209-994).

        AI가 쓴 보기 문장을 아이가 탭한 것이 '아이가 직접 말한 것'(STRONG)으로 세어지면
        확신도가 부풀려진다 — 실측에서 답변의 25.7%가 칩이었다. 감정 칩과 같은 원리로
        _CHOICE 통로가 되어, 칩만으로는 STRONG·MODERATE 에 닿을 수 없다.
        """
        chips = frozenset({("QA_ANSWER", "202")})
        # 칩 답변 + 그림 → 발화 없음 → WEAK (재분류 전에는 MODERATE 였다)
        self.assertEqual(
            gate.confidence_for(
                _card([1, 2]),
                {1: _item(1, ref=_ref(ref_id="202")), 2: _vision(2)},
                chip_answer_refs=chips,
            ),
            gate.CONFIDENCE_WEAK,
        )
        # 칩 답변끼리만 → WEAK
        self.assertEqual(
            gate.confidence_for(
                _card([1, 2]),
                {
                    1: _item(1, ref=_ref(ref_id="202")),
                    2: _item(2, ref=_ref(ref_id="318")),
                },
                chip_answer_refs=frozenset(
                    {("QA_ANSWER", "202"), ("QA_ANSWER", "318")}
                ),
            ),
            gate.CONFIDENCE_WEAK,
        )

    def test_chip_answer_does_not_downgrade_spoken_answer(self):
        """말한 답과 칩 답이 함께면 말한 답이 등급을 정한다 — 칩이 끌어내리지 않는다(994)."""
        chips = frozenset({("QA_ANSWER", "318")})
        self.assertEqual(
            gate.confidence_for(
                _card([1, 2]),
                {
                    1: _item(1, ref=_ref(ref_id="202")),  # 말한 답
                    2: _item(2, ref=_ref(ref_id="318")),  # 칩 답
                },
                chip_answer_refs=chips,
            ),
            gate.CONFIDENCE_STRONG,
        )

    def test_chip_answer_still_counts_as_child_expression_for_the_gate(self):
        """공개 게이트의 아이 표현 인정은 유지한다 (994 — 1안).

        칩을 아이 표현에서 빼면(2안) 칩만 쓴 아이의 리포트가 카드 0으로 통째로 빈다.
        등급만 낮추고 게이트는 통과시킨다 — 카드는 나오되 WEAK 로 정직하게 표시된다.
        """
        items = [_item(1, ref=_ref(ref_id="202")), _vision(2)]
        result = _evaluate(items, [1, 2])
        self.assertTrue(result.passed)
        self.assertTrue(result.child_expression)

    def test_stated_emotion_counts_as_utterance(self):
        items = [
            _item(1, source_type="STATED_EMOTION"),
            _item(2, ref=_ref(ref_id="318")),
        ]
        self.assertEqual(_confidence(items, [1, 2]), gate.CONFIDENCE_STRONG)

    def test_derived_evidence_uses_leaf_kind(self):
        """파생 근거(REPEATED_SUBJECT)는 말단 원본이 발화면 발화로 센다."""
        derived = _item(
            1,
            source_type="REPEATED_SUBJECT",
            derived=[_ref(ref_id="202"), _ref(ref_id="318")],
        )
        self.assertEqual(_confidence([derived], [1]), gate.CONFIDENCE_STRONG)

    def test_no_resolvable_evidence_has_no_grade(self):
        """근거가 하나도 해석되지 않으면 등급을 매길 수 없다 — 지어내지 않고 None."""
        self.assertIsNone(_confidence([_item(1)], [99]))


class ConfidenceIsNotEarnedByCountTest(unittest.TestCase):
    """약한 근거를 여러 개 모아 강한 주장으로 승격하지 못한다 (규칙 2).

    지표 합산으로 경향을 만드는 것이 HTP 해석이 실제로 무너진 경로다. 등급 계산이 통로의
    **집합**만 보고 크기를 보지 않는다는 것을 개수를 늘려 가며 고정한다.
    """

    def test_many_drawing_evidences_stay_weak(self):
        items = [_vision(i, f"d{i}") for i in range(1, 8)]
        self.assertEqual(
            _confidence(items, [i.evidence_id for i in items]), gate.CONFIDENCE_WEAK
        )

    def test_mixed_weak_channels_stay_weak(self):
        """그림 여러 건 + 행동 여러 건 + 감정 선택을 모아도 발화가 없으면 WEAK 다."""
        items = [
            _vision(1),
            _vision(2, "d2"),
            _metric(3),
            _metric(4, "m2"),
            _chosen_emotion(5),
        ]
        self.assertEqual(_confidence(items, [1, 2, 3, 4, 5]), gate.CONFIDENCE_WEAK)

    def test_many_drawings_do_not_lift_moderate_to_strong(self):
        items = [_item(1)] + [_vision(i, f"d{i}") for i in range(2, 9)]
        self.assertEqual(
            _confidence(items, [i.evidence_id for i in items]),
            gate.CONFIDENCE_MODERATE,
        )


class ModelCannotSetConfidenceTest(unittest.TestCase):
    """등급 판정권은 코드에 있다 — 모델이 무엇을 주장하든 근거가 정한다.

    모델이 스스로 등급을 매기면 근거가 약한 해석도 STRONG 이라 우겨 체계 전체가 장식이 된다.
    그래서 카드가 들고 온 값을 **읽지 않는다**는 것을 여기서 고정한다.
    """

    def test_model_claimed_strong_is_overwritten_to_weak(self):
        """근거가 그림 단독이면 모델이 STRONG 이라 우겨도 WEAK 로 내려간다."""
        items = [_vision(1), _vision(2, "d2")]
        graded = _confidence(items, [1, 2], confidence="STRONG")
        self.assertEqual(graded, gate.CONFIDENCE_WEAK)

    def test_apply_stamps_confidence_over_model_value(self):
        """게이트를 통과해 나오는 카드의 등급은 언제나 코드 계산값이다."""
        card = _card([1, 2])
        card.confidence = "STRONG"  # 모델이 우긴 값
        passed, _ = gate.apply([card], [_chosen_emotion(1), _vision(2)])
        self.assertEqual(len(passed), 1)
        self.assertEqual(passed[0].confidence, gate.CONFIDENCE_WEAK)

    def test_every_published_card_carries_a_grade(self):
        """등급 없는 공개 카드라는 상태가 생기지 않는다 — apply 가 유일한 출구다."""
        cards = [_card([1, 2]), _card([3, 4])]
        items = [
            _item(1, ref=_ref(ref_id="202")),
            _item(2, ref=_ref(ref_id="318")),
            _chosen_emotion(3),
            _vision(4),
        ]
        passed, _ = gate.apply(cards, items)
        self.assertEqual(len(passed), 2)
        self.assertEqual([c.confidence for c in passed], ["STRONG", "WEAK"])

    def test_apply_preserves_card_identity(self):
        """사본을 돌려주면 호출부의 순번 재매핑(_kept_positions, is 비교)이 조용히 깨진다."""
        card = _card([1, 2])
        passed, _ = gate.apply([card], [_item(1), _item(2, ref=_ref(ref_id="318"))])
        self.assertIs(passed[0], card)

    def test_excluded_card_is_not_graded(self):
        """게이트에서 빠진 카드에는 등급을 찍지 않는다 — 공개되지 않는 카드다."""
        card = _card([1])
        passed, reasons = gate.apply([card], [_item(1)])
        self.assertEqual(passed, [])
        self.assertEqual(len(reasons), 1)
        self.assertIsNone(card.confidence)


if __name__ == "__main__":
    unittest.main()

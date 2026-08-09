"""report_safety 단위 테스트 — 격리 대상은 차단, 경향성 우려 소견은 허용.

리포트 경로의 완화 기준을 회귀로 고정한다:
- 단정적 진단(S15P11B209-591): 임상 장애·질환명, 진단 단정, 확정 부사+부정 해석, 확정적 그림 해석 → 차단.
- 감정·성격 과잉 추론(S15P11B209-592): 성향·기질·정체성을 고정 특질로 규정, 심리 속성 단정 → 차단.
- "~일 수 있어요/보여요/경향/듯" 같은 여지 표현과 "~한 모습을 보였어요" 행동 관찰 → 통과.
(아동 대면 대화 answer_check는 이보다 엄격 — 진단성 표현 자체를 전부 막는다.)
"""

from __future__ import annotations

import unittest

import report_safety


class BlocksDefinitiveDiagnosisTest(unittest.TestCase):
    """단정적 진단 표현은 반드시 탐지돼야 한다."""

    DEFINITIVE = [
        "우울증이 의심되는 그림입니다.",           # 장애명
        "불안장애로 진단됩니다.",                   # 장애명 + 진단 단정
        "이 아이는 ADHD입니다.",                    # 장애명(영문)
        "주의력 결핍 장애가 있습니다.",             # 장애명(한글)
        "자폐 스펙트럼 경향이 뚜렷합니다.",         # 장애명은 여지어와 무관하게 차단
        "틱 장애로 진단이 필요합니다.",             # 장애명 + 진단
        "이 그림은 공격성을 나타냅니다.",           # 확정적 그림 해석
        "이 아이는 정서적으로 불안정합니다.",       # 확정적 상태 해석
        "분명히 정서 불안 문제가 있습니다.",        # 확정 부사 + 부정 해석
        "틀림없이 우울 성향이 강합니다.",           # 확정 부사 + 부정 해석
    ]

    def test_all_definitive_expressions_are_detected(self):
        for text in self.DEFINITIVE:
            with self.subTest(text=text):
                self.assertTrue(
                    report_safety.has_definitive_diagnosis(text),
                    f"단정 표현을 놓쳤습니다: {text}",
                )


class AllowsHedgedConcernTest(unittest.TestCase):
    """경향성 우려 소견(여지 표현)은 통과해야 한다 — 완화 기준의 핵심."""

    HEDGED = [
        "불안한 마음이 들 수 있어요.",
        "속상한 마음이 담긴 듯한 그림이에요.",
        "외로움을 느끼는 경향이 보일 수 있어요.",
        "정서적으로 조금 위축된 듯 보여요.",
        "그럴 수 있어요, 조심스럽게 살펴보면 좋겠어요.",
        "집을 크게 그린 점이 인상적이에요.",
        "가족을 함께 그린 것이 따뜻하게 느껴져요.",
    ]

    def test_hedged_concerns_pass(self):
        for text in self.HEDGED:
            with self.subTest(text=text):
                self.assertFalse(
                    report_safety.has_definitive_diagnosis(text),
                    f"여지 표현을 과잉 차단했습니다: {text}",
                )


class BlocksOverinferenceTest(unittest.TestCase):
    """감정·성격을 고정 특질로 규정하는 과잉 추론은 탐지돼야 한다 (S15P11B209-592)."""

    OVERINFERENCE = [
        "이 아이는 소심합니다.",                     # 특질 단정
        "성격이 내성적이에요.",                       # 특질 단정
        "공격적인 성향이 있어요.",                    # 성향 규정(591이 놓치는 종결)
        "예민한 기질입니다.",                         # 기질 규정
        "정서적으로 불안한 아이입니다.",              # 정체성 규정(591이 놓치는 형태)
        "소심한 아이예요.",                           # 정체성 규정
        "자존감이 낮습니다.",                         # 심리 속성 단정
        "공감 능력이 부족해요.",                      # 심리 속성 단정
        "애정 결핍이 느껴집니다.",                    # 심리 속성 용어
    ]

    def test_all_overinference_expressions_are_detected(self):
        for text in self.OVERINFERENCE:
            with self.subTest(text=text):
                self.assertTrue(
                    report_safety.has_overinference(text),
                    f"과잉 추론 표현을 놓쳤습니다: {text}",
                )


class AllowsObservationTest(unittest.TestCase):
    """행동 관찰·여지 표현은 과잉 추론으로 잡지 않는다 — 대화·긍정 관찰을 끊으면 해롭다."""

    SAFE = [
        "소심한 편일 수 있어요.",                     # 여지
        "내성적인 경향이 보여요.",                    # 여지
        "조금 산만해 보였어요.",                      # 여지(행동)
        "조심스러운 모습을 보였어요.",                # 행동 관찰
        "밝고 활발한 모습이 인상적이에요.",           # 긍정 관찰
        "외로움을 느끼는 경향이 보일 수 있어요.",     # 여지
        "자신감 있게 색을 칠했어요.",                 # 행동 관찰
        "가족을 함께 그린 점이 따뜻하게 느껴져요.",   # 긍정 관찰
    ]

    def test_observations_and_hedges_pass(self):
        for text in self.SAFE:
            with self.subTest(text=text):
                self.assertFalse(
                    report_safety.has_overinference(text),
                    f"관찰·여지 표현을 과잉 차단했습니다: {text}",
                )


class FindOverinferenceTest(unittest.TestCase):
    def test_returns_patterns_not_raw_text(self):
        patterns = report_safety.find_overinference("예민한 기질입니다.")
        self.assertTrue(patterns)
        for pattern in patterns:
            self.assertIn(pattern, report_safety._OVERINFERENCE_PATTERNS)

    def test_empty_text_has_no_match(self):
        self.assertEqual(report_safety.find_overinference(""), [])
        self.assertEqual(report_safety.find_overinference("   "), [])


class UnsafeExpressionTest(unittest.TestCase):
    """격리 대상 결합 판정 — 진단 단정(591)과 과잉 추론(592)을 함께 잡는다."""

    def test_detects_diagnosis(self):
        self.assertTrue(report_safety.has_unsafe_expression("우울증입니다."))

    def test_detects_overinference(self):
        self.assertTrue(report_safety.has_unsafe_expression("공격적인 성향이 있어요."))

    def test_passes_hedged_and_positive(self):
        self.assertFalse(
            report_safety.has_unsafe_expression(
                "즐거워 보여요.", "소심한 편일 수 있어요."
            )
        )

    def test_scans_multiple_texts(self):
        self.assertTrue(
            report_safety.has_unsafe_expression("괜찮은 그림이에요.", "자존감이 낮습니다.")
        )


class FindDefinitiveDiagnosisTest(unittest.TestCase):
    def test_returns_patterns_not_raw_text(self):
        # 반환값은 '패턴'이지 원문 조각이 아니다 — 로그에 남겨도 표현이 새지 않는다.
        patterns = report_safety.find_definitive_diagnosis("불안장애로 진단됩니다.")
        self.assertTrue(patterns)
        for pattern in patterns:
            self.assertIn(pattern, report_safety._ALL_PATTERNS)

    def test_empty_text_has_no_match(self):
        self.assertEqual(report_safety.find_definitive_diagnosis(""), [])
        self.assertEqual(report_safety.find_definitive_diagnosis("   "), [])

    def test_has_definitive_diagnosis_scans_multiple_texts(self):
        self.assertTrue(
            report_safety.has_definitive_diagnosis("괜찮은 그림이에요.", "우울증입니다.")
        )
        self.assertFalse(
            report_safety.has_definitive_diagnosis("괜찮아요.", "즐거워 보여요.")
        )


# ── 역할 전환 이후 (S15P11B209-982) ──────────────────────────────


class DiagnosisBlockingSurvivesTheReversalTest(unittest.TestCase):
    """방침이 '해석한다'로 바뀌어도 **진단 차단은 그대로다** — 유지가 결정이다.

    해석을 제공하는 것과 진단이라고 말하는 것은 다르다. 이 축이 느슨해지면 리포트가
    의료적 판단으로 읽히고, 한계 고지가 있어도 보호자는 그렇게 받아들인다(CLAUDE.md 9절).
    """

    def test_disorder_names_are_still_blocked(self):
        for text in ("불안장애가 있어 보여요.", "ADHD 경향이 보입니다.", "우울증입니다."):
            with self.subTest(text=text):
                self.assertTrue(report_safety.has_unsafe_expression(text))

    def test_stigma_is_still_blocked(self):
        for text in ("자존감이 낮습니다.", "공격적인 성향이 있어요.", "소심한 아이예요."):
            with self.subTest(text=text):
                self.assertTrue(report_safety.has_unsafe_expression(text))

    def test_hedged_interpretation_still_passes(self):
        """해석을 담기로 했으므로 근거에 기댄 조심스러운 해석은 통과해야 한다."""
        for text in (
            "가족에게 의지하려는 경향이 보일 수 있습니다.",
            "새로운 상황을 조심스럽게 살피는 모습이 보여요.",
        ):
            with self.subTest(text=text):
                self.assertFalse(report_safety.has_unsafe_expression(text))


class BlocksScoringTest(unittest.TestCase):
    """점수화·등급은 해석을 허용한 뒤에도 금지다 (982).

    지표를 합산해 영역 점수를 내는 형태가 문헌이 가장 직접적으로 반증한 구간이다.
    """

    def test_scored_expressions_are_detected(self):
        for text in (
            "정서 영역에 점수를 매기면 보통 수준이에요.",
            "안정감이 3점 만점에 해당해요.",
            "또래 대비 백분위 40 정도예요.",
            "사회성은 중 등급으로 보입니다.",
            "불안할 확률이 70% 정도로 보입니다.",
        ):
            with self.subTest(text=text):
                self.assertTrue(report_safety.find_scored_claim(text))
                self.assertTrue(report_safety.has_unsafe_expression(text))

    def test_plain_counts_are_not_scores(self):
        """관찰 수치는 점수가 아니다 — 활동 기록을 적는 자리를 막으면 안 된다."""
        for text in (
            "약 10분간 그렸고 색을 다섯 번 바꿨어요.",
            "창문을 두 개 그렸어요.",
            "지우기는 3회였어요.",
        ):
            with self.subTest(text=text):
                self.assertEqual(report_safety.find_scored_claim(text), [])


class BlocksForbiddenAxisTest(unittest.TestCase):
    """필압은 쓰지 않는 축이다 (982).

    스타일러스 입력에만 있어 기기 의존적이고, 계약상 average_pressure 는 항상 None 이라
    문장에 등장하면 창작이다.
    """

    def test_pressure_mentions_are_detected(self):
        for text in (
            "필압이 약한 편이에요.",
            "누르는 힘이 세게 느껴집니다.",
            "필기 압력이 고른 편이에요.",
        ):
            with self.subTest(text=text):
                self.assertTrue(report_safety.find_forbidden_axis(text))
                self.assertTrue(report_safety.has_unsafe_expression(text))

    def test_ordinary_drawing_description_passes(self):
        for text in ("선을 길게 그었어요.", "진한 색으로 칠했어요."):
            with self.subTest(text=text):
                self.assertEqual(report_safety.find_forbidden_axis(text), [])


class OverclaimIsGradedTest(unittest.TestCase):
    """확신도에 따라 말할 수 있는 폭이 다르다 (982 규칙 2·3).

    같은 문장이 등급에 따라 통과하기도 걸리기도 한다는 것이 이 검사의 요점이다 —
    등급이 장식이 아니라 실제로 무언가를 가른다.
    """

    def test_generalization_blocked_only_at_weak(self):
        text = "평소에도 가족에게 의지하려는 경향이 보일 수 있습니다."
        self.assertTrue(report_safety.has_overclaim(text, "WEAK"))
        self.assertFalse(report_safety.has_overclaim(text, "MODERATE"))
        self.assertFalse(report_safety.has_overclaim(text, "STRONG"))

    def test_certainty_blocked_at_every_grade(self):
        """확정 어휘는 근거가 아무리 세도 막는다 — 이 리포트에 단정할 자리는 없다.

        STRONG↔MODERATE 의 구분은 의미 판단이라 고정 어휘로 잡히지 않는다. 그 계단은
        2층 자체검토(OVERCLAIM)가 맡는다 — 정규식 층은 두 계단만 나눈다.
        """
        text = "분명히 가족에게 의지하려는 경향이 보입니다."
        for grade in ("STRONG", "MODERATE", "WEAK", None):
            with self.subTest(grade=grade):
                self.assertTrue(report_safety.has_overclaim(text, grade))

    def test_careful_wording_passes_at_every_grade(self):
        text = "이번 활동에서는 가족 이야기를 즐겁게 나누는 모습이 보였어요."
        for grade in ("STRONG", "MODERATE", "WEAK", None):
            with self.subTest(grade=grade):
                self.assertFalse(report_safety.has_overclaim(text, grade))

    def test_unknown_grade_is_treated_as_strictest(self):
        """등급을 모르면 관대하게 여는 쪽이 위험하다 — WEAK 와 같게 본다."""
        text = "평소에도 그런 경향이 보일 수 있습니다."
        self.assertTrue(report_safety.has_overclaim(text, None))

    def test_empty_text_has_no_match(self):
        self.assertEqual(report_safety.find_overclaim("", "WEAK"), [])

    def test_returns_patterns_not_raw_text(self):
        """반환값은 패턴이라 로그에 남겨도 아이 표현이 새지 않는다."""
        matches = report_safety.find_overclaim("평소에도 그렇습니다.", "WEAK")
        self.assertTrue(matches)
        for pattern in matches:
            self.assertNotIn("평소에도 그렇습니다", pattern)


if __name__ == "__main__":
    unittest.main()

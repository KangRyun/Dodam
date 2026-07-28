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


if __name__ == "__main__":
    unittest.main()

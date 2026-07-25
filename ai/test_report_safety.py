"""report_safety 단위 테스트 — 단정적 진단은 차단, 경향성 우려 소견은 허용 (S15P11B209-591).

리포트 경로의 완화 기준을 회귀로 고정한다:
- 임상 장애·질환명, 진단 단정, 확정 부사+부정 해석, 확정적 그림 해석 → 차단(패턴 매칭).
- "~일 수 있어요/보여요/경향/듯" 같은 여지 표현 → 통과.
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

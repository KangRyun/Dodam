"""question_safety 단위 테스트 — 생성 질문 안전 판정 파이프라인 (S15P11B209-596).

파이프라인이 순서대로 판정하는지 회귀로 고정한다:
- 형식 정화(이모지·마크업)는 통과시키되 정화본을 돌려준다.
- 진단·심리해석 표현 → 차단(DIAGNOSTIC_LANGUAGE).
- 자해·학대·위기 소재를 담은 질문 → 차단(CRISIS_CONTENT).
- 무해한 일반 질문 → 통과(정화본).
"""

from __future__ import annotations

import unittest

import question_safety as qs


class PassesCleanQuestionTest(unittest.TestCase):
    def test_plain_question_passes(self):
        v = qs.evaluate("이 집에는 누가 살고 있어?")
        self.assertEqual(v.status, "PASSED")
        self.assertFalse(v.blocked)
        self.assertIsNone(v.block_reason_code)
        self.assertEqual(v.sanitized_text, "이 집에는 누가 살고 있어?")

    def test_sanitizes_emoji_and_markup_but_passes(self):
        v = qs.evaluate("**우와** 멋진 집이네! 누가 살아? 😊")
        self.assertEqual(v.status, "PASSED")
        # 이모지·별표는 제거되고 뜻은 보존된다.
        self.assertNotIn("😊", v.sanitized_text)
        self.assertNotIn("*", v.sanitized_text)
        self.assertIn("멋진 집이네", v.sanitized_text)


class BlocksDiagnosticLanguageTest(unittest.TestCase):
    SAMPLES = [
        "이 그림은 불안을 의미하니?",       # 확정적 그림 해석
        "너는 우울한 성향이 있어?",          # 성향 등 심리해석
        "이 검사 결과는 어떤 것 같아?",      # 검사 채점
    ]

    def test_diagnostic_questions_blocked(self):
        for text in self.SAMPLES:
            with self.subTest(text=text):
                v = qs.evaluate(text)
                self.assertTrue(v.blocked)
                self.assertEqual(v.block_reason_code, qs.DIAGNOSTIC_LANGUAGE)


class BlocksCrisisContentTest(unittest.TestCase):
    SAMPLES = [
        "혹시 죽고 싶었던 적 있어?",         # 자해 소재
        "아빠가 자꾸 때려서 무서웠어?",       # 학대 소재
    ]

    def test_crisis_questions_blocked(self):
        for text in self.SAMPLES:
            with self.subTest(text=text):
                v = qs.evaluate(text)
                self.assertTrue(v.blocked)
                self.assertEqual(v.block_reason_code, qs.CRISIS_CONTENT)


class OrderingTest(unittest.TestCase):
    def test_diagnostic_takes_priority_over_crisis(self):
        # 진단 표현이 먼저 걸리면 그 사유로 차단한다(파이프라인 순서 고정).
        v = qs.evaluate("이 그림은 죽음을 의미하니? 진단해줘")
        self.assertTrue(v.blocked)
        self.assertEqual(v.block_reason_code, qs.DIAGNOSTIC_LANGUAGE)


class EmptyInputTest(unittest.TestCase):
    def test_empty_and_symbol_only_pass_as_empty_text(self):
        # 빈 입력·기호뿐인 입력은 '안전 위반'이 아니라 '빈 출력' — 통과하되 정화본이 빈 문자열.
        for text in ["", "   ", "🎨🌟", "***"]:
            with self.subTest(text=text):
                v = qs.evaluate(text)
                self.assertEqual(v.status, "PASSED")
                self.assertEqual(v.sanitized_text, "")


if __name__ == "__main__":
    unittest.main()

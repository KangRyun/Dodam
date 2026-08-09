"""answer_check 단위 테스트 — 아동 대화 응답 가드레일(진단 금지 표현) 검증 (S15P11B209-182).

이 필터는 곰돌이가 '아이에게 직접' 건네는 말을 정화·차단한다(llm_client._ask 경유).
그래서 진단·심리해석·검사 채점 등 어떤 진단성 표현도 아동 화면/음성에 나가면 안 된다 —
'경향성 우려 소견'까지 여지를 두는 완화 기준(리포트 경로, S15P11B209-591)과 달리
아동 대면 경로는 엄격 차단을 유지한다. 이 테스트가 그 엄격함을 회귀로 고정한다.

LLM·가중치 없이 규칙만 검증하므로 결정적(deterministic)이다.
"""

from __future__ import annotations

import unittest

import answer_check


class SanitizeTest(unittest.TestCase):
    def test_removes_emoji(self):
        self.assertEqual(answer_check.sanitize("멋진 집이네 😊🎨"), "멋진 집이네")

    def test_removes_markup_symbols(self):
        # TTS가 "별", "괄호 열고" 식으로 읽지 않도록 장식 기호를 턴다.
        self.assertEqual(
            answer_check.sanitize("**멋지다!** (집 그림) 누구랑 살아?"),
            "멋지다! 집 그림 누구랑 살아?",
        )

    def test_collapses_whitespace(self):
        self.assertEqual(answer_check.sanitize("누가   살아?\n\n여기에"), "누가 살아? 여기에")

    def test_preserves_meaning_of_normal_sentence(self):
        # 뜻은 보존하고 기호만 제거한다 — 정상 문장은 그대로 살아야 한다.
        self.assertEqual(
            answer_check.sanitize("우와 멋진 집이네! 누가 살고 있어?"),
            "우와 멋진 집이네! 누가 살고 있어?",
        )


class FindViolationsTest(unittest.TestCase):
    def test_returns_patterns_not_raw_text(self):
        # 반환값은 '패턴'이지 원문 조각이 아니다 — 로그에 남겨도 아이 발화가 새지 않는다.
        violations = answer_check.find_violations("이 그림은 불안을 의미해요.")
        self.assertTrue(violations)
        for pattern in violations:
            self.assertIn(pattern, answer_check._FORBIDDEN)

    def test_normal_sentence_has_no_violations(self):
        self.assertEqual(answer_check.find_violations("이 집에는 누가 살아?"), [])


class EnforceBlocksDiagnosisTest(unittest.TestCase):
    """진단성 표현은 예외 없이 fallback으로 교체돼야 한다(아동 대면 엄격 차단)."""

    # 아이에게 절대 나가면 안 되는 진단·심리해석·검사 채점 표현.
    FORBIDDEN_SAMPLES = [
        "이 그림은 불안을 의미해요.",          # 그림 해석 단정
        "이런 아이는 외로운 성향이 있어요.",     # 인격 낙인
        "HTP 검사 결과 우울 점수가 높아요.",     # 검사 채점
        "트라우마가 보이는 그림이에요.",         # 임상어
        "정서 불안 상태로 보여요.",              # 정서 진단
        "무의식이 드러난 그림이네요.",           # 정신분석어
        "성격 유형을 진단해 볼게요.",            # 진단 + 성격 검사
        "이 그림은 공격성을 상징해요.",          # 그림 상징 단정
    ]

    def test_all_forbidden_samples_are_replaced_with_fallback(self):
        for sample in self.FORBIDDEN_SAMPLES:
            with self.subTest(sample=sample):
                self.assertEqual(answer_check.enforce(sample), answer_check.FALLBACK_QUESTION)

    def test_diagnosis_survives_even_after_symbol_stripping(self):
        # 기호로 감싸 우회해도(정화 후에도) 내용 위반이면 차단돼야 한다.
        self.assertEqual(
            answer_check.enforce("**이 그림은 불안을 의미해요!** 😢"),
            answer_check.FALLBACK_QUESTION,
        )


class EnforcePassesSafeTest(unittest.TestCase):
    """아동 눈높이의 정상 문장은 통과하고, 장식 기호만 제거된다."""

    def test_normal_question_passes_with_emoji_removed(self):
        self.assertEqual(
            answer_check.enforce("우와 멋진 집이네! 누가 살아? 😊"),
            "우와 멋진 집이네! 누가 살아?",
        )

    def test_normal_question_passes_with_markup_removed(self):
        self.assertEqual(
            answer_check.enforce("**멋지다!** (집 그림) 누구랑 살아?"),
            "멋지다! 집 그림 누구랑 살아?",
        )

    def test_symbol_only_text_falls_back(self):
        # 정화 후 빈 문자열이면(기호뿐이었으면) 안전 질문으로 대체한다.
        self.assertEqual(answer_check.enforce("🎨🌟"), answer_check.FALLBACK_QUESTION)

    def test_custom_fallback_is_used(self):
        custom = "무슨 색을 제일 좋아해?"
        self.assertEqual(
            answer_check.enforce("이 그림은 불안을 의미해요.", fallback=custom), custom
        )


if __name__ == "__main__":
    unittest.main()

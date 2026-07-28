"""child_screen_guard 단위 테스트 — 아동 화면 위험 문구 비노출 (S15P11B209-597).

- 내부 사유·오류 코드(대문자 스네이크) → 탐지.
- 보호자·전문가용 위기 경고/안내 문구(신고·상담전화·핫라인·"위험 감지" 등) → 탐지.
- 아이 그림 대화에 자연스러운 낱말('경찰차', '위험한 곳')은 오탐하지 않는다.
"""

from __future__ import annotations

import unittest

import child_screen_guard as g


class DetectsReasonCodeTest(unittest.TestCase):
    SAMPLES = [
        "AI_SAFETY_POLICY_BLOCKED",
        "차단 사유: SELF_HARM_RISK 입니다",
        "DIAGNOSTIC_LANGUAGE 감지됨",
        "이 응답은 CRISIS_CONTENT 로 분류됨",
    ]

    def test_reason_codes_detected(self):
        for text in self.SAMPLES:
            with self.subTest(text=text):
                self.assertTrue(g.contains_child_unsafe(text))
                self.assertIn("REASON_CODE", g.find_child_unsafe(text))


class DetectsRiskNoticeTest(unittest.TestCase):
    SAMPLES = [
        "학대가 의심되면 신고하세요.",
        "자살예방 상담전화로 연락하세요.",
        "1393에 전화해 보세요.",
        "아동보호전문기관 1577-1391로 문의하세요.",
        "위기 신호가 감지되었습니다.",
        "위험이 감지되었어요.",
        "보호자에게 알림을 보냈어요.",
        "전문가에게 상담을 의뢰했어요.",
        "오류가 발생했습니다.",
        "요청이 차단되었어요.",
    ]

    def test_risk_notices_detected(self):
        for text in self.SAMPLES:
            with self.subTest(text=text):
                self.assertTrue(g.contains_child_unsafe(text))


class NoFalsePositiveTest(unittest.TestCase):
    """아이 그림 대화에 자연스러운 표현은 막지 않는다 — 과잉 차단은 대화를 끊어 해롭다."""

    SAFE = [
        "이 집에는 누가 살고 있어?",
        "경찰차를 그렸구나! 어디로 가는 거야?",
        "위험한 곳에는 누가 있었어?",  # 'position'류 그림 대화 — 경고 문구 아님
        "가장 마음에 드는 색은 뭐야?",
        "우와 멋진 로봇이네! 이름이 뭐야?",
        "소방관 아저씨가 불을 껐어?",
    ]

    def test_safe_questions_pass(self):
        for text in self.SAFE:
            with self.subTest(text=text):
                self.assertFalse(
                    g.contains_child_unsafe(text),
                    f"자연스러운 질문을 과잉 차단했습니다: {text}",
                )


class EmptyTest(unittest.TestCase):
    def test_empty_has_no_hits(self):
        self.assertEqual(g.find_child_unsafe(""), [])
        self.assertFalse(g.contains_child_unsafe("", None, "   "))


if __name__ == "__main__":
    unittest.main()

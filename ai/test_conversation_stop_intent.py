"""그만하기 의사 판정 테스트 (S15P11B209-938).

이 판정의 위험은 두 방향이다.
  - 놓치면: 그만하고 싶다는 아이에게 계속 질문을 건넨다.
  - 과하게 잡으면: 더 이야기하고 싶은 아이의 대화가 끊긴다. 특히 건너뛰기(831)를
    중단으로 읽으면 "다른 질문 해줘"라고 한 아이가 대화를 끝낼지 묻는 화면을 본다.
둘 다 재고, 특히 건너뛰기·"몰라" 쪽 표본을 두껍게 둔다.
"""

from __future__ import annotations

import unittest

import conversation_stop_intent as stop


class TargetedStopTest(unittest.TestCase):
    """무엇을 그만할지 아이가 이미 말한 경우 — 되묻지 않고 바로 그 갈래로 간다."""

    def test_drawing(self):
        for text in (
            "그림 그만 그릴래",
            "이제 그림 안 그릴래",
            "다 그렸어",
            "그림 다 했어",
            "색칠 그만할래",
        ):
            with self.subTest(text=text):
                self.assertEqual(stop.STOP_DRAWING, stop.scan(text))

    def test_conversation(self):
        for text in (
            "이야기 그만할래",
            "얘기 그만하고 싶어",
            "말 그만할래",
            "질문 그만해",
            "대화 그만할래",
        ):
            with self.subTest(text=text):
                self.assertEqual(stop.STOP_CONVERSATION, stop.scan(text))


class UnspecifiedStopTest(unittest.TestCase):
    """그만하고 싶은 건 분명한데 대상은 말하지 않은 경우 — 되묻는다."""

    def test_detects_unspecified(self):
        for text in (
            "이제 그만할래",
            "그만하고 싶어",
            "이제 됐어",
            "끝낼래",
            "졸려",
            "집에 갈래",
        ):
            with self.subTest(text=text):
                self.assertEqual(stop.STOP_UNSPECIFIED, stop.scan(text))


class NotStopIntentTest(unittest.TestCase):
    """중단으로 읽으면 안 되는 것들 — 과탐 방어."""

    def test_skip_intent_is_not_stop(self):
        """831 건너뛰기. 아이는 다음 질문을 원한 것이지 끝내자고 한 게 아니다."""
        for text in (
            "이건 말하기 싫어. 다른 질문 해줘",
            "이 질문은 건너뛸래",
            "다른 거 물어봐 줘",
            "질문을 건너뛸래",
        ):
            with self.subTest(text=text):
                self.assertIsNone(stop.scan(text))

    def test_short_or_unsure_answers_are_not_stop(self):
        """conversations_*.txt가 이미 "'몰라'만으로 단정하지 마"를 못박아 두었다."""
        for text in ("몰라", "그냥", "음…", "잘 모르겠어", "없어"):
            with self.subTest(text=text):
                self.assertIsNone(stop.scan(text))

    def test_normal_answers_are_not_stop(self):
        for text in (
            "빨간색이 제일 좋아서",
            "엄마랑 나야",
            "공놀이 하고 있었어",
            "이거 우리 집이야",
        ):
            with self.subTest(text=text):
                self.assertIsNone(stop.scan(text))

    def test_empty_text(self):
        self.assertIsNone(stop.scan(""))
        self.assertIsNone(stop.scan(None))
        self.assertIsNone(stop.scan("   "))


if __name__ == "__main__":
    unittest.main()

"""crisis_detection 단위 테스트 — 자해·학대·위기 의도 탐지 (S15P11B209-593).

- 명백한 자해·학대·위기 신호는 해당 사유 코드로 잡는다.
- 상상 놀이·일반 그림 대화는 잡지 않는다(과잉 차단 방지).
- 여러 발화 중 가장 위중한 신호(자해>학대>위기)를 우선 반환한다.
"""

from __future__ import annotations

import unittest

import crisis_detection as cd


class SelfHarmTest(unittest.TestCase):
    SAMPLES = [
        "나 그냥 죽고 싶어.",
        "다 사라지고 싶어.",
        "이제 살기 싫어.",
        "손목을 긋고 싶었어.",
        "태어나지 말걸 그랬어.",
    ]

    def test_detects_self_harm(self):
        for text in self.SAMPLES:
            with self.subTest(text=text):
                self.assertEqual(cd.detect(text), cd.SELF_HARM_RISK)


class AbuseTest(unittest.TestCase):
    SAMPLES = [
        "아빠가 자꾸 때려서 무서워.",
        "엄마가 어제 나를 때렸어.",
        "삼촌이 발로 찼어.",
        "맞아서 아파.",
        "몰래 만졌어.",
    ]

    def test_detects_abuse(self):
        for text in self.SAMPLES:
            with self.subTest(text=text):
                self.assertEqual(cd.detect(text), cd.ABUSE_DISCLOSURE)


class CrisisTest(unittest.TestCase):
    SAMPLES = [
        "그냥 도망치고 싶어.",
        "아무도 날 안 좋아해.",
        "다 없어졌으면 좋겠어.",
    ]

    def test_detects_crisis(self):
        for text in self.SAMPLES:
            with self.subTest(text=text):
                self.assertEqual(cd.detect(text), cd.CRISIS_INTENT)


class NoFalsePositiveTest(unittest.TestCase):
    """상상 놀이·일반 대화는 잡지 않는다 — 과잉 차단은 대화를 끊어 해롭다."""

    SAFE = [
        "게임에서 몬스터가 죽었어.",
        "공룡이 나무를 쿵 하고 넘어뜨렸어.",
        "이 집에는 엄마랑 나랑 살아.",
        "아빠랑 놀이터에서 놀았어.",
        "무서운 유령을 그렸어.",
        "우리 강아지가 밥을 먹었어.",
        "",
        "   ",
    ]

    def test_safe_text_is_not_flagged(self):
        for text in self.SAFE:
            with self.subTest(text=text):
                self.assertIsNone(cd.detect(text))


class ScanPriorityTest(unittest.TestCase):
    def test_scan_returns_none_when_all_safe(self):
        self.assertIsNone(cd.scan(["안녕", "집을 그렸어"]))

    def test_scan_returns_single_signal(self):
        self.assertEqual(cd.scan(["집을 그렸어", "아빠가 때렸어"]), cd.ABUSE_DISCLOSURE)

    def test_scan_prioritizes_self_harm_over_others(self):
        # 자해가 학대·위기와 섞이면 가장 위중한 자해를 우선 반환한다.
        texts = ["아빠가 때렸어", "그냥 죽고 싶어", "도망치고 싶어"]
        self.assertEqual(cd.scan(texts), cd.SELF_HARM_RISK)


if __name__ == "__main__":
    unittest.main()

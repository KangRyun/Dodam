"""eval.checks 판정 규칙 단위 테스트 (S15P11B209-899).

여기 있는 문장은 전부 **평가 실행에서 실제로 나온 것**이다(2026-08-04~05). 합성 입력으로
만든 도담의 출력이라 아동 데이터가 아니다(가드레일 9절 — cases.py와 같은 근거).

이 파일을 만든 이유: 질문 개수 판정이 두 번 연속 오탐을 냈는데(858 선택지, 899 전환구)
둘 다 GMS 실호출로만 발견됐다. 회당 요금이 나가는 경로로 판정 규칙의 버그를 찾고 있었다.
규칙은 순수 함수라 공짜로 고정할 수 있다.
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from eval.checks import _MAX_QUESTIONS, _question_count  # noqa: E402


class CountsRealQuestionsOnlyTest(unittest.TestCase):
    """질문 하나로 세어야 하는 것들 — 여기가 깨지면 멀쩡한 대화가 위반으로 잡힌다."""

    SINGLE = [
        # 선택지 제시(858이 고친 것). 뒤엣것은 질문이 아니라 고를 거리다.
        "그 집 안은 어떤 느낌일까? 시끌시끌해, 아니면 조용해?",
        "좋아, 다른 걸 물어볼게. 그 집 안에는 어떤 느낌이 있을까? 시끌시끌해, 아니면 조용해?",
        # 수사적 전환구(899가 고치는 것). 앞엣것은 화제 전환 신호다.
        "그럼 우리 집에 대해 더 이야기해볼까? 집 안은 어떤 느낌일까? 시끌시끌해, 조용해?",
        "너가 사람이라고 생각했구나! 그래서 그림 이야기를 계속해 볼까? 집 안에는 어떤 것들이 있을까?",
        # 마지막 물음표 뒤의 꼬리는 평서문이라 질문이 아니다.
        "저기 파란 공은 어떤 공이야? 무슨 일이 있던 공인지 궁금해.",
        # 의문사 없는 예·아니오 질문.
        "빨간색 좋아해?",
    ]

    def test_counted_as_one(self):
        for text in self.SINGLE:
            with self.subTest(text=text):
                self.assertEqual(1, _question_count(text))


class CountsSeparateQuestionsTest(unittest.TestCase):
    """서로 다른 것을 묻는 문장은 개수대로 세어야 한다."""

    def test_two_distinct_questions(self):
        pairs = [
            "왼쪽에 있는 나무는 어떤 모습이야? 그걸 그릴 때 어떤 생각이 들었어?",
            "저기 파란 공은 어떤 공이야? 왜 그 공을 그렸어?",
            "아, 나무였구나! 그 나무는 어떻게 생겼어? 어떤 색이야?",
        ]
        for text in pairs:
            with self.subTest(text=text):
                self.assertEqual(2, _question_count(text))

    def test_three_questions_exceeds_limit(self):
        text = "그 집은 어떤 색이야? 창문은 몇 개야? 누가 살고 있어?"
        count = _question_count(text)
        self.assertEqual(3, count)
        self.assertGreater(count, _MAX_QUESTIONS)


class DegenerateInputTest(unittest.TestCase):
    def test_no_question_mark(self):
        self.assertEqual(0, _question_count("우와, 정말 멋진 집이네."))

    def test_empty(self):
        self.assertEqual(0, _question_count(""))


class LimitIsTwoTest(unittest.TestCase):
    """상한을 되돌리려면 이 테스트를 먼저 보게 만든다(2026-08-05 결정)."""

    def test_two_is_allowed(self):
        self.assertEqual(2, _MAX_QUESTIONS)


if __name__ == "__main__":
    unittest.main()

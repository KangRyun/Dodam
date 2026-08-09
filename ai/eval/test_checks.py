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

from unittest import mock  # noqa: E402

from eval import checks  # noqa: E402
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


class ToneBandsDifferTest(unittest.TestCase):
    """연령 구간 길이 규칙 붕괴 감지 (S15P11B209-895).

    786이 만든 실패는 '규칙은 넷인데 제약은 하나'였다. 그게 808 실측까지 안 보였다.
    음성 대조군(negative control)을 함께 둬야 이 검사가 무엇이든 통과시키지 않음을 확인할 수 있다.
    """

    def test_current_file_passes(self):
        f = checks.check_tone_bands_differ()
        self.assertTrue(f.ok, f.detail)

    def test_collapsed_bands_are_flagged(self):
        # 786 직후 상태 재현 — 문구는 다르지만 제약이 사실상 같던 시절.
        collapsed = {
            "PRESCHOOL": "- 길이: 반응 한 문장 + 질문 한 문장까지.",
            "LOWER_ELEMENTARY": "- 길이: 반응 한 문장 + 질문 한 문장까지.",
            "UPPER_ELEMENTARY": "- 길이: 반응 한 문장 + 질문 한 문장까지.",
            "SUPPORT": "- 길이: 반응 한 문장 + 질문 한 문장까지.",
        }
        with mock.patch.object(
            checks.prompts_registry, "sections", return_value=collapsed
        ):
            f = checks.check_tone_bands_differ()
        self.assertFalse(f.ok)
        # 제품 판단이 걸린 규칙이라 게이트를 흔들지는 않는다.
        self.assertEqual("WARN", f.mark)
        self.assertFalse(f.is_failure)


class IdentityAndSceneOpeningTest(unittest.TestCase):
    """정체 질문·장면 열기 판정 (S15P11B209-999).

    2026-08-06 측정에서 두 지표가 모두 틀렸다. 정체 질문은 '누구한테·누구랑'까지 세어
    정상 질문을 위반으로 만들었고, 장면 열기는 문구 하나만 정답으로 세어 실제로 장면을 연
    질문을 못 알아봤다. 판정이 틀리면 그 지표로 내린 프롬프트 결정도 함께 틀린다.
    """

    IDENTITY = [
        "그 사람은 누구야?",
        "이건 뭐야?",
        "저기 있는 건 누구니?",
        "그건 뭘까?",
        # 2026-08-07 실호출 — 아이가 "이거 나야"라고 답한 직후에 돌아왔다.
        "이건 누구 이야기야?",
    ]
    # 사건 속 상대를 묻는 말이다 — 정체를 되묻는 것이 아니다.
    NOT_IDENTITY = [
        "누구한테 줬어?",
        "누구랑 같이 갔어?",
        "누구에게 말했어?",
        "그때 무슨 일이 있었어?",
    ]

    def test_identity_questions_are_detected(self):
        for text in self.IDENTITY:
            with self.subTest(text=text):
                self.assertTrue(checks._EVAL_IDENTITY.search(text))

    def test_companion_questions_are_not_identity(self):
        for text in self.NOT_IDENTITY:
            with self.subTest(text=text):
                self.assertIsNone(checks._EVAL_IDENTITY.search(text))

    SCENE_OPENING = [
        "이 그림에서는 무슨 일이 일어나고 있어?",
        "두 사람은 뭐 하고 있어?",
        "그다음에는 어떻게 됐어?",
        "여기서 어떤 일이 있었어?",
        "이 그림에 어떤 이야기가 있어?",
    ]
    NOT_SCENE_OPENING = [
        "이 공은 무슨 색이야?",
        "머리는 어떤 모양이야?",
        "좋아, 그건 건너뛸게.",
    ]

    def test_scene_opening_is_recognised_in_many_forms(self):
        for text in self.SCENE_OPENING:
            with self.subTest(text=text):
                self.assertTrue(checks._SCENE_OPENING.search(text))

    def test_visual_questions_do_not_count_as_scene_opening(self):
        for text in self.NOT_SCENE_OPENING:
            with self.subTest(text=text):
                self.assertIsNone(checks._SCENE_OPENING.search(text))


if __name__ == "__main__":
    unittest.main()

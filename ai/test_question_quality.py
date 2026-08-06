"""질문 품질 판정 테스트 (S15P11B209-918).

이 필터의 위험은 두 방향이다.
  - 못 잡는 것: "이 머리는 누구의 머리야?"가 그대로 아이 화면에 나간다.
  - 과하게 잡는 것: htp_question_bank의 정상 문항까지 교체되어 질문이 단조로워진다.
그래서 두 방향을 함께 재고, 정상 쪽 표본은 실제 질문 뱅크 문장에서 가져왔다.
"""

from __future__ import annotations

import unittest

import prompts_registry
import question_quality


class AwkwardPossessiveTest(unittest.TestCase):
    def test_detects_possessive_body_part_questions(self):
        for text in (
            "이 머리는 누구의 머리야?",
            "머리는 누구 거야?",
            "손은 누구 거야?",
            "발은 누구 것이야?",
            "머리카락은 누구의 것이야?",
            "누구의 발이야?",
            "누구 손이야?",
        ):
            with self.subTest(text=text):
                self.assertEqual(
                    question_quality.POSSESSIVE_BODY_PART,
                    question_quality.find_awkward(text),
                )

    def test_allows_visual_attribute_questions_about_parts(self):
        """부위를 묻는 것 자체는 정상이다 — 소유자를 묻는 것만 걸러야 한다."""
        for text in (
            "그림 속 사람의 머리는 어떤 모양이야?",
            "머리카락은 무슨 색이야?",
            "손은 어디에 있어?",
            "이 사람은 지금 뭐 하고 있어?",
        ):
            with self.subTest(text=text):
                self.assertIsNone(question_quality.find_awkward(text))

    def test_allows_question_bank_items(self):
        """질문 뱅크 문항이 걸리면 정상 질문이 통째로 교체된다 — 과탐 회귀 방어."""
        bank = prompts_registry.sections("htp_question_bank")
        for subject, body in bank.items():
            for line in body.splitlines():
                item = line.strip().lstrip("- ").strip()
                if not item:
                    continue
                with self.subTest(subject=subject, item=item):
                    self.assertIsNone(question_quality.find_awkward(item))

    def test_empty_text_is_not_awkward(self):
        self.assertIsNone(question_quality.find_awkward(""))
        self.assertIsNone(question_quality.find_awkward(None))


class RedundantVisualTest(unittest.TestCase):
    """그림·아이 말로 이미 답을 아는 질문 판정 (S15P11B209-954).

    918과 같은 두 방향의 위험이 있다.
      - 못 잡는 것: "머리를 그렸어"에 "어떤 모양이야?"가 그대로 나간다.
      - 과하게 잡는 것: 우리가 정말 모르는 상태에서도 물어보지 못하게 된다
        (activity_block ART_DIARY_OPEN 이 여는 경로).
    """

    PERSON_DESC = "검은색 곱슬머리를 한 사람이 있어요."
    HOUSE_DESC = "빨간 지붕의 집이 있어요."

    def _redundant(self, text, *, description=None, said=()):
        return question_quality.find_redundant(
            text, drawing_description=description, child_texts=list(said)
        )

    def test_rephrases_of_what_the_child_just_said_are_redundant(self):
        """아이가 말한 낱말을 표현만 바꿔 되묻는 것 — 이 이슈의 원래 증상."""
        for text in (
            "어떤 머리를 그린 거야?",
            "머리는 어떤 모양이야?",
            "어떤 머리야?",
            "머리는 무슨 색이야?",
        ):
            with self.subTest(text=text):
                self.assertEqual(
                    question_quality.REDUNDANT_VISUAL,
                    self._redundant(
                        text, description=self.PERSON_DESC, said=["머리를 그렸어"]
                    ),
                )

    def test_attributes_already_in_the_description_are_redundant(self):
        """VLM이 이미 읽어 낸 속성은 다시 물을 것이 없다."""
        for text in ("무슨 색이야?", "어떤 모양이야?", "집은 무슨 색이야?"):
            with self.subTest(text=text):
                self.assertEqual(
                    question_quality.REDUNDANT_VISUAL,
                    self._redundant(
                        text, description=self.HOUSE_DESC, said=["집을 그렸어"]
                    ),
                )

    def test_counts_and_places_are_redundant_too(self):
        for text in ("사람 몇 명 그렸어?", "사람은 어디에 그렸어?", "어떻게 생겼어?"):
            with self.subTest(text=text):
                self.assertEqual(
                    question_quality.REDUNDANT_VISUAL,
                    self._redundant(
                        text, description=self.PERSON_DESC, said=["사람을 그렸어"]
                    ),
                )

    def test_questions_the_drawing_cannot_answer_are_kept(self):
        """정체·관계·사건·경험·기억은 그림만 보고는 알 수 없다 — 이 질문들이 목표다."""
        for text in (
            "이 사람은 누구야?",
            "이 사람은 너와 어떤 사이야?",
            "여기서 무슨 일이 있었어?",
            "이 장면에서 가장 기억나는 건 뭐야?",
            "그때 기분이 어땠어?",
            "이건 진짜 있었던 일이야?",
        ):
            with self.subTest(text=text):
                self.assertIsNone(
                    self._redundant(
                        text, description=self.PERSON_DESC, said=["머리를 그렸어"]
                    )
                )

    def test_not_blocked_when_we_genuinely_know_nothing(self):
        """표현만 보고 무조건 막지 않는다 — 서술도 아이 말도 없으면 물어봐도 된다."""
        for text in ("무슨 색이야?", "어떤 모양이야?", "몇 개 그렸어?"):
            with self.subTest(text=text):
                self.assertIsNone(self._redundant(text))

    def test_color_question_survives_when_description_has_no_color(self):
        """축마다 따로 본다 — 색 근거가 없는 서술이면 색 질문이 살아남는다."""
        self.assertIsNone(
            self._redundant("무슨 색이야?", description="네모난 것이 하나 있어요.")
        )

    def test_empty_question_is_not_redundant(self):
        self.assertIsNone(self._redundant("", description=self.PERSON_DESC))
        self.assertIsNone(self._redundant(None, description=self.PERSON_DESC))


class SingleQuestionTest(unittest.TestCase):
    """한 응답에 질문 하나 (S15P11B209-954). 둘이면 아이가 무엇에 답할지 고르지 못한다."""

    def test_keeps_reaction_and_first_question_only(self):
        self.assertEqual(
            question_quality.MULTIPLE_QUESTIONS,
            question_quality.find_multiple_questions(
                "머리를 그렸구나! 이 사람은 누구야? 이름이 뭐야?"
            ),
        )
        self.assertEqual(
            "머리를 그렸구나! 이 사람은 누구야?",
            question_quality.to_single_question(
                "머리를 그렸구나! 이 사람은 누구야? 이름이 뭐야?"
            ),
        )

    def test_skips_a_redundant_first_question(self):
        """약한 질문이 앞, 좋은 질문이 뒤에 오는 실제 출력(2026-08-06 gpt-4o-mini 실측).

        앞을 남기면 이 판정기가 막으려던 문장만 살아남는다.
        """
        text = "그림 속에 있는 집은 어떤 집이야? 여기서 무슨 일이 있었어?"
        self.assertEqual(
            "여기서 무슨 일이 있었어?",
            question_quality.to_single_question(
                text,
                drawing_description="화면 가운데에 초록색 덤불처럼 보이는 것이 있어요.",
                child_texts=["아니야, 이건 집이야"],
            ),
        )

    def test_keeps_the_first_question_when_none_is_redundant(self):
        """둘 다 멀쩡하면 앞을 남긴다 — 아이 말에 바로 이어지는 것이 앞이다."""
        self.assertEqual(
            "꽃을 그렸구나! 그 꽃 이야기를 좀 더 해줄래?",
            question_quality.to_single_question(
                "꽃을 그렸구나! 그 꽃 이야기를 좀 더 해줄래? 여기서 무슨 일이 있었어?",
                drawing_description="노란 꽃 세 송이가 아래쪽에 피어 있어요.",
                child_texts=["꽃을 그렸어"],
            ),
        )

    def test_splits_conjoined_questions_sharing_one_mark(self):
        """물음표는 하나인데 물음이 둘인 경우도 잡는다."""
        text = "이 사람은 누구야, 그리고 뭐 하고 있었어?"
        self.assertEqual(
            question_quality.MULTIPLE_QUESTIONS,
            question_quality.find_multiple_questions(text),
        )
        self.assertEqual(
            "이 사람은 누구야?", question_quality.to_single_question(text)
        )

    def test_single_question_is_untouched(self):
        for text in (
            "이 사람은 누구야?",
            "우와, 멋지다! 여기서 무슨 일이 있었어?",
            "그리고 나서 뭐 했어?",  # 접속사로 시작할 뿐 물음은 하나다
        ):
            with self.subTest(text=text):
                self.assertIsNone(question_quality.find_multiple_questions(text))
                self.assertEqual(text, question_quality.to_single_question(text))

    def test_empty_text_is_safe(self):
        self.assertIsNone(question_quality.find_multiple_questions(""))
        self.assertEqual("", question_quality.to_single_question(""))
        self.assertEqual("", question_quality.to_single_question(None))


class JosaTest(unittest.TestCase):
    """교체 문장에 쓰는 조사. 틀리면 TTS로 그대로 읽혀 나간다."""

    def test_picks_particle_by_final_consonant(self):
        self.assertEqual("은", question_quality.eun_neun("머리카락"))  # 종성 ㄱ
        self.assertEqual("는", question_quality.eun_neun("머리"))  # 종성 없음
        self.assertEqual("은", question_quality.eun_neun("손"))
        self.assertEqual("는", question_quality.eun_neun("나무"))

    def test_falls_back_for_non_hangul(self):
        self.assertEqual("는", question_quality.eun_neun(""))
        self.assertEqual("는", question_quality.eun_neun("PERSON"))


if __name__ == "__main__":
    unittest.main()

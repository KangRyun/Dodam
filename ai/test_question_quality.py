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

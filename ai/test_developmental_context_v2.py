"""연령 발달 맥락 등록부 2.0.0 — 경계·교육단계·출처 게이트.

이 표가 지켜야 하는 것은 문구가 아니라 **경계**다. 5세 문장이 6세로 새면 그 순간 지어낸
규준이 되고, 출처 확인 없이 문장이 나가면 근거 없는 주장이 된다. 문구는 리뷰로 잡을 수
있지만 경계는 테스트로만 잡힌다.
"""

from __future__ import annotations

import unittest
import unittest.mock
from dataclasses import replace

import developmental_context as dc
import developmental_sources as ds


class AgeBoundaryTest(unittest.TestCase):
    """구간 경계. 한 달 차이로 어느 표를 보는지 바뀐다."""

    def _context_id(self, months, *, stage=None, domain=dc.NARRATIVE_LANGUAGE):
        found = dc.contexts_for(domain, age_months=months, education_stage=stage)
        return None if found is None else found.context_id

    def test_boundaries(self):
        cases = [
            (47, None),  # 48개월 미만 — 등록부 밖
            (48, "NARRATIVE_4Y_DAILY_EVENT"),
            (59, "NARRATIVE_4Y_DAILY_EVENT"),
            (60, "NARRATIVE_5Y_TWO_EVENTS"),
            (71, "NARRATIVE_5Y_TWO_EVENTS"),
            (72, None),  # 학령 초기. 교육단계·출처가 있어야 붙는다.
            (83, None),
            (84, "SCHOOL_AGE_OBSERVATION_ONLY"),
        ]
        for months, expected in cases:
            with self.subTest(months=months):
                self.assertEqual(self._context_id(months), expected)

    def test_age_milestone_never_leaks_into_school_age(self):
        """5세 문장이 72개월 이상에 붙는 일은 없다.

        범위를 늘리는 것만으로 6세를 덮으려는 시도(C안)를 등록부가 스스로 막는다.
        """
        for entry in dc.REGISTRY:
            self.assertLess(entry.age_max_months, dc.EARLY_SCHOOL_MIN_MONTHS)

    def test_unknown_age_attaches_nothing(self):
        self.assertIsNone(self._context_id(None))


class EducationStageTest(unittest.TestCase):
    """만 6세는 나이만으로 정하지 않는다."""

    def _with_open_gate(self):
        """출처 게이트를 연 상태를 흉내 낸다. 등록부 자체는 건드리지 않는다."""
        opened = {
            source_id: replace(
                entry,
                retrieved_at="2026-08-08T00:00:00Z",
                content_hash="0" * 64,
                reviewed_at="2026-08-08",
                reviewed_by="reviewer-001",
            )
            for source_id, entry in ds.REGISTRY.items()
        }
        return unittest.mock.patch.dict(ds.REGISTRY, opened, clear=True)

    def test_preschool_and_null_get_no_grade_material(self):
        """어린이집·미입력에 학년 자료를 씌우지 않는다.

        나이만 맞다고 유치원 자료를 적용하면 어린이집에 다니는 아이에게 학년 기준을
        적용하는 것이 된다. 게이트가 열려 있어도 마찬가지다.
        """
        with self._with_open_gate():
            for stage in ("PRESCHOOL", None):
                with self.subTest(stage=stage):
                    found = dc.contexts_for(
                        dc.NARRATIVE_LANGUAGE, age_months=75, education_stage=stage
                    )
                    self.assertIsNone(found)

    def test_kindergarten_and_grade_1_get_early_school_context(self):
        with self._with_open_gate():
            for stage in ("KINDERGARTEN", "GRADE_1"):
                with self.subTest(stage=stage):
                    found = dc.contexts_for(
                        dc.NARRATIVE_LANGUAGE, age_months=75, education_stage=stage
                    )
                    self.assertIsNotNone(found)
                    self.assertEqual(
                        found.context_type, dc.EARLY_SCHOOL_COMMUNICATION_CONTEXT
                    )

    def test_drawing_story_link_is_kindergarten_only(self):
        """그림-이야기 연결은 Kindergarten 자료에만 있다.

        First Grade 에서 같은 문장을 쓰면 그 자료에 없는 내용을 그 자료 근거로 내보내게 된다.
        """
        with self._with_open_gate():
            kinder = dc.contexts_for(
                dc.DRAWING_LANGUAGE_INTEGRATION,
                age_months=75,
                education_stage="KINDERGARTEN",
            )
            grade1 = dc.contexts_for(
                dc.DRAWING_LANGUAGE_INTEGRATION,
                age_months=75,
                education_stage="GRADE_1",
            )

        self.assertIsNotNone(kinder)
        self.assertIsNone(grade1)


class SourceGateTest(unittest.TestCase):
    """사람이 원문과 대조하기 전에는 그 문장을 내보내지 않는다."""

    def test_gate_is_closed_until_every_field_is_filled(self):
        complete = {
            "retrieved_at": "2026-08-08T00:00:00Z",
            "content_hash": "0" * 64,
            "reviewed_at": "2026-08-08",
            "reviewed_by": "reviewer-001",
        }
        for field in complete:
            with self.subTest(missing=field):
                entry = replace(
                    ds.REGISTRY[ds.ASHA_KINDERGARTEN],
                    **{**complete, field: ""},
                )
                self.assertFalse(entry.enabled)
                self.assertIn(field, entry.missing_fields())

    def test_gate_opens_when_everything_is_present(self):
        entry = replace(
            ds.REGISTRY[ds.ASHA_KINDERGARTEN],
            retrieved_at="2026-08-08T00:00:00Z",
            content_hash="0" * 64,
            reviewed_at="2026-08-08",
            reviewed_by="reviewer-001",
        )
        self.assertTrue(entry.enabled)
        self.assertEqual(entry.missing_fields(), ())

    def test_shipped_registry_is_still_closed(self):
        """지금 저장소 상태에서는 두 출처 모두 닫혀 있어야 한다.

        누군가 확인 없이 값을 채워 넣으면 여기서 드러난다.
        """
        for source_id in (ds.ASHA_KINDERGARTEN, ds.ASHA_FIRST_GRADE):
            with self.subTest(source_id=source_id):
                self.assertFalse(ds.is_enabled(source_id))

    def test_missing_limitations_close_the_gate(self):
        entry = replace(
            ds.REGISTRY[ds.ASHA_KINDERGARTEN],
            retrieved_at="2026-08-08T00:00:00Z",
            content_hash="0" * 64,
            reviewed_at="2026-08-08",
            reviewed_by="reviewer-001",
            limitations=("NOT_KOREAN_NORM",),
        )
        self.assertFalse(entry.enabled)
        self.assertIn("limitations", entry.missing_fields())

    def test_content_hash_rule_is_stable(self):
        """해시 규칙을 코드에 고정한다. 문서에만 두면 다음 사람이 다르게 만든다."""
        messy = "  Your Child's\r\n\r\n   Communication  \r\n\t Kindergarten \n\n"
        tidy = "Your Child's\nCommunication\nKindergarten"

        self.assertEqual(ds.normalize_for_hash(messy), tidy)
        self.assertEqual(ds.content_hash_of(messy), ds.content_hash_of(tidy))
        self.assertEqual(len(ds.content_hash_of(messy)), 64)


class RegistrySafetyTest(unittest.TestCase):
    """등록부가 import 시점에 스스로 막는 것들."""

    def test_forbidden_phrases_are_rejected(self):
        for phrase in ("규준", "또래", "정상 발달", "지연"):
            with self.subTest(phrase=phrase):
                self.assertIn(phrase, dc._FORBIDDEN_PHRASES)

    def test_no_shipped_sentence_compares_to_peers(self):
        everything = (*dc.REGISTRY, *dc.EARLY_SCHOOL_REGISTRY, dc.SCHOOL_AGE_CONTEXT)
        for entry in everything:
            for phrase in dc._FORBIDDEN_PHRASES:
                with self.subTest(context_id=entry.context_id, phrase=phrase):
                    self.assertNotIn(phrase, entry.parent_context)

    def test_early_school_entries_declare_their_stage(self):
        for entry in dc.EARLY_SCHOOL_REGISTRY:
            with self.subTest(context_id=entry.context_id):
                self.assertTrue(entry.education_stages)
                self.assertNotIn("PRESCHOOL", entry.education_stages)

    def test_story_components_is_narrative_not_social(self):
        """인물·장소·사건 설명은 이야기 구성이지 다른 사람의 마음이 아니다.

        SOCIAL_UNDERSTANDING 은 아이가 **다른 사람의 행동·반응·생각**을 이야기했을 때만 쓴다.
        """
        ids = {entry.context_id for entry in dc.EARLY_SCHOOL_REGISTRY}
        self.assertNotIn("EARLY_SCHOOL_STORY_COMPONENTS", ids)
        self.assertIn("인물·장소·사건", dc.STORY_COMPONENTS_SESSION_ONLY)

    def test_every_domain_has_a_session_only_sentence(self):
        """도메인이 늘면 이 문장도 함께 늘어야 한다.

        빠진 도메인은 나이를 모를 때 화면에서 통째로 사라진다 — 규준을 붙이지 않는 것과
        관찰 자체를 지우는 것은 다르다.
        """
        domains = (
            dc.NARRATIVE_LANGUAGE,
            dc.EMOTION_EXPRESSION,
            dc.SOCIAL_UNDERSTANDING,
            dc.COPING_HELP_SEEKING,
            dc.SELF_REFLECTION,
            dc.CONVERSATION_PARTICIPATION,
            dc.DRAWING_LANGUAGE_INTEGRATION,
        )
        for domain in domains:
            with self.subTest(domain=domain):
                self.assertIsNotNone(dc.session_only_context(domain))


class BirthDateMonthsTest(unittest.TestCase):
    """개월 계산. 연 × 12 를 없앤 자리를 이것이 대신한다."""

    def test_counts_whole_months_only(self):
        cases = [
            ("2020-08-08", "2026-08-08", 72),  # 생일 당일
            ("2020-08-09", "2026-08-08", 71),  # 하루 전 — 아직 71개월
            ("2020-03-15", "2026-08-08", 76),
        ]
        for born, today, expected in cases:
            with self.subTest(born=born):
                self.assertEqual(dc.months_from_birth_date(born, today), expected)

    def test_bad_input_returns_none(self):
        for born, today in [(None, "2026-08-08"), ("2020-13-40", "2026-08-08"), ("2027-01-01", "2026-08-08")]:
            with self.subTest(born=born):
                self.assertIsNone(dc.months_from_birth_date(born, today))


if __name__ == "__main__":
    unittest.main()


class SourceExcerptTest(unittest.TestCase):
    """원문에서 확인한 문장이 한국어 문구를 실제로 뒷받침하는가."""

    def test_every_open_source_carries_its_excerpts(self):
        """검수자가 원문을 다시 찾지 않아도 되게 근거 문장을 함께 둔다."""
        for source_id in (ds.ASHA_KINDERGARTEN, ds.ASHA_FIRST_GRADE):
            with self.subTest(source_id=source_id):
                self.assertTrue(ds.REGISTRY[source_id].supporting_excerpts)

    def test_drawing_link_has_no_first_grade_basis(self):
        """First Grade 자료에는 그림-이야기 연결 항목이 없다.

        그래서 ``EARLY_SCHOOL_DRAWING_STORY_LINK`` 는 KINDERGARTEN 전용이다. 이 제한이
        임의가 아니라 원문에서 온 것임을 근거 문장으로 확인한다.
        """
        first_grade = " ".join(ds.REGISTRY[ds.ASHA_FIRST_GRADE].supporting_excerpts).lower()
        kindergarten = " ".join(
            ds.REGISTRY[ds.ASHA_KINDERGARTEN].supporting_excerpts
        ).lower()

        self.assertNotIn("draw", first_grade)
        self.assertIn("draw", kindergarten)

    def test_english_literacy_terms_never_reach_korean_copy(self):
        """영어 철자·음운·읽기 기준을 한국어 아동 리포트에 쓰지 않는다.

        두 원문 모두 그 항목을 크게 담고 있어, 무심코 옮기면 한국어 리포트에 영어 읽기 기준이
        섞인다.
        """
        banned = ("철자", "음운", "sight", "phonic", "spell", "읽기 수준", "문법")
        everything = (*dc.REGISTRY, *dc.EARLY_SCHOOL_REGISTRY, dc.SCHOOL_AGE_CONTEXT)
        for entry in everything:
            for term in banned:
                with self.subTest(context_id=entry.context_id, term=term):
                    self.assertNotIn(term, entry.parent_context.lower())

    def test_retrieval_recorded_but_gate_still_needs_a_human(self):
        """가져온 사실은 기록됐지만, 사람이 대조하기 전에는 열리지 않는다."""
        for source_id in (ds.ASHA_KINDERGARTEN, ds.ASHA_FIRST_GRADE):
            with self.subTest(source_id=source_id):
                entry = ds.REGISTRY[source_id]
                self.assertTrue(entry.retrieved_at)
                self.assertFalse(entry.enabled)
                self.assertIn("reviewed_by", entry.missing_fields())

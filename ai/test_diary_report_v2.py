"""그림일기 리포트 V2 구조화 신호·계약 테스트."""

from __future__ import annotations

import json
import sys
import types
import unittest
from unittest import mock

import internal_contracts as contracts

# 이 대화 환경에는 운영 의존성(openai·rag)이 설치되지 않을 수 있다. 실제 저장소에는
# requirements/rag 모듈이 있으므로, 단위 테스트 수집만 가능하게 최소 인터페이스를 보충한다.
try:  # pragma: no cover - 운영/CI에서는 실제 패키지를 쓴다.
    import openai as _openai  # noqa: F401
except ModuleNotFoundError:  # pragma: no cover - 현재 샌드박스 전용
    openai_stub = types.ModuleType("openai")

    class _OpenAIError(Exception):
        pass

    class _OpenAI:
        pass

    openai_stub.OpenAIError = _OpenAIError
    openai_stub.OpenAI = _OpenAI
    sys.modules["openai"] = openai_stub

if "rag" not in sys.modules:  # pragma: no cover - 현재 샌드박스 전용
    rag_stub = types.ModuleType("rag")

    class _Chunk:
        def __init__(self, source_id="", title="", text="", score=1.0):
            self.source_id = source_id
            self.title = title
            self.text = text
            self.score = score

    class _RagUnavailableError(RuntimeError):
        def __init__(self, reason="UNAVAILABLE"):
            super().__init__(reason)
            self.reason = reason

    rag_stub.Chunk = _Chunk
    rag_stub.RagUnavailableError = _RagUnavailableError
    rag_stub.retrieve = lambda _query: []
    rag_stub.knowledge_base_version = lambda: "test-kb"
    sys.modules["rag"] = rag_stub

import report_client


class DiaryReportContractTest(unittest.TestCase):
    def test_diary_insights_contract_is_available(self):
        self.assertTrue(
            hasattr(contracts, "DiaryInsights"),
            "그림일기 전용 DiaryInsights 계약이 아직 없습니다.",
        )


class DiaryReportBuilderPresenceTest(unittest.TestCase):
    def test_diary_report_builder_module_exists(self):
        import importlib.util

        self.assertIsNotNone(importlib.util.find_spec("diary_report_v2"))


def _diary_request() -> contracts.ObservationGenerationRequest:
    return contracts.ObservationGenerationRequest(
        request_id="req-diary-v2",
        analysis_id=1,
        drawing_session_id=2,
        analysis_type="FINAL",
        question_difficulty="PRESCHOOL",
        question_count=4,
        answered_count=4,
        skipped_count=0,
        unrecognized_speech_count=0,
        selected_emotions=["JOY"],
        selected_emotion_refs=[
            contracts.SelectedEmotionRef(
                emotion_code="JOY", evidence_source_id="emotion-1"
            )
        ],
        expressed_emotion_text="기분이 너무 좋았어",
        representative_utterance="오늘 실제로 있었던 일이야. 수학시험에서 100점 맞았어",
        activity_metric_source_id="metric-1",
        subject_summaries=[
            contracts.SubjectSummary(
                drawing_subject=None,
                drawing_description="웃는 입 모양의 사람과 '수학 100'이라는 글자가 보여요.",
                observation_evidence_source_id="obs-1",
                qa_pairs=[
                    contracts.SubjectQaPair(
                        question="이 그림에서는 무슨 일이 일어나고 있어?",
                        answer_text="오늘 실제로 있었던 일이야. 수학시험에서 100점 맞았어",
                        answer_type="VOICE",
                        answer_message_id=101,
                    ),
                    contracts.SubjectQaPair(
                        question="그다음에는 뭐 했어?",
                        answer_text="엄마한테 자랑했어",
                        answer_type="VOICE",
                        answer_message_id=102,
                    ),
                    contracts.SubjectQaPair(
                        question="그때 기분이 어땠어?",
                        answer_text="기분이 너무 좋았어",
                        answer_type="VOICE",
                        answer_message_id=103,
                    ),
                    contracts.SubjectQaPair(
                        question="어떤 장난감을 받고 싶어?",
                        answer_text="또봇",
                        answer_type="OPTION",
                        answer_message_id=104,
                    ),
                ],
            )
        ],
    )


def _ref(kind: str, value: str) -> dict[str, str]:
    return {"kind": kind, "id": value}


def _signals(**overrides):
    payload = {
        "storySnapshot": {
            "headline": "100점을 받고 엄마에게 자랑한 이야기",
            "summary": "아이는 수학시험에서 100점을 받고 엄마에게 자랑한 일을 들려주었어요.",
            "mainEvent": "수학시험에서 100점을 받음",
            "evidenceRefs": [_ref("QA_ANSWER", "101"), _ref("QA_ANSWER", "102")],
        },
        "narrativeFlow": [
            {
                "stepType": "EVENT",
                "text": "수학시험에서 100점을 받음",
                "evidenceRefs": [_ref("QA_ANSWER", "101")],
            },
            {
                "stepType": "CHILD_ACTION",
                "text": "엄마에게 자랑함",
                "evidenceRefs": [_ref("QA_ANSWER", "102")],
            },
            {
                "stepType": "EMOTION",
                "text": "기분이 매우 좋았다고 말함",
                "evidenceRefs": [_ref("QA_ANSWER", "103")],
            },
        ],
        "sessionObservations": [
            {
                "observationCode": "ACHIEVEMENT_EXPRESSION",
                "title": "성취 경험과 기쁜 마음을 함께 이야기했어요",
                "description": "이번 활동에서 아이는 성취한 사건과 그때의 감정을 이어서 설명했어요.",
                "evidenceRefs": [_ref("QA_ANSWER", "101"), _ref("QA_ANSWER", "103")],
            }
        ],
        "caregiverQuestions": [
            {
                "question": "100점을 받고 엄마에게 자랑할 때 어떤 말을 했어?",
                "purpose": "자랑한 장면을 아이 말로 더 구체적으로 들어보기",
                "evidenceRefs": [_ref("QA_ANSWER", "101")],
            }
        ],
        "listeningTip": "점수만 되풀이하기보다 엄마에게 자랑하고 싶었던 마음과 엄마의 반응을 함께 들어주세요.",
    }
    payload.update(overrides)
    return payload


class DiaryReportSafetyTest(unittest.TestCase):
    def test_allows_grounded_school_achievement_score_language(self):
        import diary_report_v2

        self.assertFalse(
            diary_report_v2.has_unsafe_diary_expression(
                "수학시험에서 100점을 받았어요.",
                "100점을 받고 엄마에게 자랑할 때 어떤 말을 했어?",
            )
        )

    def test_blocks_diagnosis_and_psychological_scoring_language(self):
        import diary_report_v2

        self.assertTrue(diary_report_v2.has_unsafe_diary_expression("아이는 ADHD가 맞나요?"))
        self.assertTrue(
            diary_report_v2.has_unsafe_diary_expression("불안 점수는 100점입니다.")
        )

    def test_blocks_non_academic_emotion_scoring_language(self):
        import diary_report_v2

        self.assertTrue(
            diary_report_v2.has_unsafe_diary_expression("기쁨 점수는 100점입니다.")
        )


class DiaryReportBuilderTest(unittest.TestCase):
    def test_builds_grounded_insights_and_derives_reality_and_time(self):
        import diary_report_v2

        insights = diary_report_v2.build_diary_insights(
            _signals(), _diary_request(), vision_available=True
        )

        self.assertIsNotNone(insights)
        self.assertEqual(insights.story_snapshot.reality_status, "REAL")
        self.assertEqual(insights.story_snapshot.time_scope, "TODAY")
        self.assertEqual(len(insights.narrative_flow), 3)
        self.assertEqual(len(insights.session_observations), 1)
        self.assertEqual(insights.data_quality.confirmed_voice_count, 3)
        self.assertEqual(insights.data_quality.option_answer_count, 1)
        self.assertTrue(insights.data_quality.vision_summary_available)

    def test_explicit_imagined_story_overrides_first_person_event_heuristic(self):
        import diary_report_v2

        req = _diary_request().model_copy(
            update={
                "representative_utterance": "오늘 상상한 이야기야. 나는 우주에 갔어",
                "subject_summaries": [
                    contracts.SubjectSummary(
                        drawing_description="우주선과 사람이 보여요.",
                        observation_evidence_source_id="vision-imagined",
                        qa_pairs=[
                            contracts.SubjectQaPair(
                                question="이 그림에서는 무슨 일이 일어나고 있어?",
                                answer_text="오늘 상상한 이야기야. 나는 우주에 갔어",
                                answer_type="VOICE",
                                answer_message_id=302,
                            )
                        ],
                    )
                ],
            }
        )
        raw = _signals(
            storySnapshot={
                "headline": "우주에 간 상상 이야기",
                "summary": "아이는 우주에 가는 상상 이야기를 들려주었어요.",
                "evidenceRefs": [_ref("QA_ANSWER", "302")],
            }
        )

        insights = diary_report_v2.build_diary_insights(raw, req, vision_available=True)

        self.assertIsNotNone(insights)
        self.assertEqual(insights.story_snapshot.reality_status, "IMAGINED")

    def test_empty_unusable_signals_do_not_enable_blank_v2_report(self):
        import diary_report_v2

        req = contracts.ObservationGenerationRequest(
            request_id="empty-diary",
            analysis_id=1,
            drawing_session_id=2,
            analysis_type="FINAL",
        )

        insights = diary_report_v2.build_diary_insights({}, req, vision_available=False)

        self.assertIsNone(insights)

    def test_generic_listening_tip_alone_does_not_enable_blank_v2_report(self):
        import diary_report_v2

        req = contracts.ObservationGenerationRequest(
            request_id="tip-only-diary",
            analysis_id=1,
            drawing_session_id=2,
            analysis_type="FINAL",
        )

        insights = diary_report_v2.build_diary_insights(
            {"listeningTip": "아이의 말을 따뜻하게 들어주세요."},
            req,
            vision_available=False,
        )

        self.assertIsNone(insights)

    def test_psychological_score_language_is_removed_from_structured_story(self):
        import diary_report_v2

        raw = _signals(
            storySnapshot={
                "headline": "불안 점수 100점",
                "summary": "아이의 불안 점수는 100점이에요.",
                "evidenceRefs": [_ref("QA_ANSWER", "101")],
            }
        )

        insights = diary_report_v2.build_diary_insights(
            raw, _diary_request(), vision_available=True
        )

        self.assertIsNotNone(insights)
        self.assertIsNone(insights.story_snapshot)

    def test_ordinary_first_person_daily_event_is_treated_as_real_without_magic_phrase(self):
        import diary_report_v2

        req = _diary_request().model_copy(
            update={
                "representative_utterance": "오늘 나 수학시험 봤는데 100점 맞았어",
                "subject_summaries": [
                    contracts.SubjectSummary(
                        drawing_description="사람과 시험지가 보여요.",
                        observation_evidence_source_id="vision-1",
                        qa_pairs=[
                            contracts.SubjectQaPair(
                                question="이 그림에서는 무슨 일이 있었어?",
                                answer_text="오늘 나 수학시험 봤는데 100점 맞았어",
                                answer_type="VOICE",
                                answer_message_id=301,
                            )
                        ],
                    )
                ]
            }
        )
        raw = _signals(
            storySnapshot={
                "headline": "수학시험에서 100점을 받은 이야기",
                "summary": "아이는 수학시험에서 100점을 받은 일을 이야기했어요.",
                "evidenceRefs": [_ref("QA_ANSWER", "301")],
            }
        )

        insights = diary_report_v2.build_diary_insights(raw, req, vision_available=True)

        self.assertEqual(insights.story_snapshot.reality_status, "REAL")
        self.assertEqual(insights.story_snapshot.time_scope, "TODAY")

    def test_invalid_refs_cannot_create_claims(self):
        import diary_report_v2

        raw = _signals(
            storySnapshot={
                "headline": "근거 없는 이야기",
                "summary": "근거 없는 요약",
                "evidenceRefs": [_ref("QA_ANSWER", "999")],
            },
            narrativeFlow=[
                {
                    "stepType": "EVENT",
                    "text": "없는 사건",
                    "evidenceRefs": [_ref("QA_ANSWER", "999")],
                }
            ],
            caregiverQuestions=[
                {
                    "question": "근거 없는 질문이야?",
                    "purpose": "없음",
                    "evidenceRefs": [_ref("QA_ANSWER", "999")],
                }
            ],
        )
        insights = diary_report_v2.build_diary_insights(
            raw, _diary_request(), vision_available=False
        )

        self.assertIsNone(insights.story_snapshot)
        self.assertEqual(insights.narrative_flow, [])
        self.assertEqual(insights.caregiver_questions, [])

    def test_session_observation_requires_two_independent_refs(self):
        import diary_report_v2

        raw = _signals(
            sessionObservations=[
                {
                    "observationCode": "TOO_THIN",
                    "title": "근거가 하나뿐인 관찰",
                    "description": "한 답만으로 만든 관찰",
                    "evidenceRefs": [_ref("QA_ANSWER", "101")],
                }
            ]
        )
        insights = diary_report_v2.build_diary_insights(
            raw, _diary_request(), vision_available=True
        )
        self.assertEqual(insights.session_observations, [])

    def test_two_choice_answers_do_not_become_an_independent_session_observation(self):
        import diary_report_v2

        req = _diary_request().model_copy(
            update={
                "subject_summaries": [
                    contracts.SubjectSummary(
                        drawing_description="사람과 시험지가 보여요.",
                        observation_evidence_source_id="vision-1",
                        qa_pairs=[
                            contracts.SubjectQaPair(
                                question="기뻤어?",
                                answer_text="기뻤어",
                                answer_type="OPTION",
                                answer_message_id=201,
                            ),
                            contracts.SubjectQaPair(
                                question="엄마한테 말했어?",
                                answer_text="응",
                                answer_type="OPTION",
                                answer_message_id=202,
                            ),
                        ],
                    )
                ]
            }
        )
        raw = _signals(
            sessionObservations=[
                {
                    "observationCode": "CHOICE_ONLY",
                    "title": "스스로 기쁨과 관계를 표현했어요",
                    "description": "두 답을 근거로 만든 관찰",
                    "evidenceRefs": [
                        _ref("QA_ANSWER", "201"),
                        _ref("QA_ANSWER", "202"),
                    ],
                }
            ]
        )

        insights = diary_report_v2.build_diary_insights(raw, req, vision_available=True)

        # 관찰이 빠지고 나면 근거로 검증된 구조가 하나도 남지 않는다 → V2 자체를 열지 않는다.
        #   아이 발화 목록은 요청 문답에서 그대로 파생돼 늘 채워지므로 '남은 내용'으로 세지 않는다.
        self.assertIsNone(insights)

    def _insight(self, **overrides):
        """근거 2건 + 아이가 자기 말로 한 답을 가진 인사이트 한 건."""
        item = {
            "observationCode": "ACHIEVEMENT_EXPRESSION",
            "title": "성취 경험과 기쁜 마음을 함께 이야기했어요",
            "description": "성취한 사건과 그때의 감정을 이어서 설명했어요.",
            "evidenceRefs": [_ref("QA_ANSWER", "101"), _ref("QA_ANSWER", "103")],
        }
        item.update(overrides)
        import diary_report_v2

        insights = diary_report_v2.build_diary_insights(
            _signals(sessionObservations=[item]), _diary_request(), vision_available=True
        )
        return insights.session_observations if insights else []

    def test_hypothesis_without_an_alternative_is_dropped(self):
        """다른 설명이 없으면 가설이 아니라 단정이다.

        해석을 하나만 제시하면 보호자는 그것을 결론으로 읽는다. "다르게 볼 수도 있다"가
        카드 안에 함께 있어야 가설로 남는다 — 없으면 카드를 내보내지 않는다.
        """
        got = self._insight(
            insightType="SESSION_HYPOTHESIS",
            hypothesis="성취를 인정받고 싶은 마음이 있었을 수 있어요.",
            alternativeExplanations=[],
        )

        self.assertEqual(got, [])

    def test_hypothesis_with_an_alternative_survives(self):
        got = self._insight(
            insightType="SESSION_HYPOTHESIS",
            hypothesis="성취를 인정받고 싶은 마음이 있었을 수 있어요.",
            alternativeExplanations=["엄마와 나누고 싶은 마음이었을 수도 있어요."],
        )

        self.assertEqual(len(got), 1)
        self.assertEqual(got[0].insight_type, "SESSION_HYPOTHESIS")
        self.assertEqual(len(got[0].alternative_explanations), 1)

    def test_confirmed_expression_carries_no_guesswork(self):
        """확인된 표현 자리에 추측이 실리면 아이가 한 말과 구분되지 않는다."""
        got = self._insight(
            insightType="CONFIRMED_EXPRESSION",
            hypothesis="사실은 불안했을 수 있어요.",
            alternativeExplanations=["다른 설명"],
        )

        self.assertEqual(len(got), 1)
        self.assertIsNone(got[0].hypothesis)
        self.assertEqual(got[0].alternative_explanations, [])

    def test_explore_next_needs_a_question_and_no_trait_language(self):
        # 다음에 확인할 단서는 근거가 약한 대신 주장도 약해야 한다.
        self.assertEqual(
            self._insight(insightType="EXPLORE_NEXT", clarificationQuestion=None), []
        )
        self.assertEqual(
            self._insight(
                insightType="EXPLORE_NEXT",
                title="조심스러운 성향이 보여요",
                clarificationQuestion="그때 어떤 마음이었는지 더 들어볼까요?",
            ),
            [],
        )
        survived = self._insight(
            insightType="EXPLORE_NEXT",
            clarificationQuestion="그때 어떤 마음이었는지 더 들어볼까요?",
        )
        self.assertEqual(len(survived), 1)
        self.assertEqual(survived[0].insight_type, "EXPLORE_NEXT")

    def test_legacy_card_without_a_type_is_inferred_not_dropped(self):
        """구 V2 모양 카드(종류 없음)는 근거 모양에서 읽어 그대로 통과한다."""
        got = self._insight()

        self.assertEqual(len(got), 1)
        self.assertEqual(got[0].insight_type, "CONFIRMED_EXPRESSION")

    def test_unknown_items_name_what_was_not_confirmed(self):
        """확인하지 못한 것은 침묵이 아니라 이름으로 돌려준다.

        카드가 비어 나가면 보호자에게는 '문제가 없었다'로 읽힌다.
        """
        import diary_report_v2

        insights = diary_report_v2.build_diary_insights(
            _signals(), _diary_request(), vision_available=False
        )

        codes = {item.code for item in insights.unknown_items}
        self.assertIn("NO_VISION_SUMMARY", codes)
        for item in insights.unknown_items:
            self.assertTrue(item.text.strip())

    def test_unknown_items_do_not_say_the_same_thing_twice(self):
        """'음성 이야기 없음'과 '고른 답만 있음'은 배타다."""
        import diary_report_v2

        insights = diary_report_v2.build_diary_insights(
            _signals(), _diary_request(), vision_available=True
        )

        codes = {item.code for item in insights.unknown_items}
        self.assertFalse({"NO_VOICE_ANSWER", "ONLY_CHOICE_ANSWERS"} <= codes)

    def _development(self, child_age, *, education_stage=None):
        """나이를 개월로 넘긴다.

        연 × 12 를 없앤 뒤로 등록부는 개월만 본다(2.0.0). 여기서도 개월로 넘겨야 72~83개월
        같은 한 해 안의 구간을 시험할 수 있다.
        """
        import diary_report_v2

        req = _diary_request().model_copy(
            update={
                "child_age": child_age,
                "age_months": None if child_age is None else child_age * 12,
                "education_stage": education_stage,
            }
        )
        insights = diary_report_v2.build_diary_insights(
            _signals(), req, vision_available=True
        )
        return {o.domain: o for o in insights.developmental_observations}

    def test_age_context_comes_from_the_reviewed_registry(self):
        """연령 맥락 문장은 검수 출처가 있는 것만 쓴다 — 모델이 보충하지 않는다."""
        got = self._development(5)

        narrative = got["NARRATIVE_LANGUAGE"]
        self.assertIn("두 사건", narrative.age_context)
        self.assertTrue(narrative.source_ids, "검수 출처 없는 규준 문장은 나갈 수 없다")
        self.assertIn("전체 발달 수준을 평가한 결과가 아니에요", narrative.scope_text)

    def test_school_age_gets_no_age_norm(self):
        """만 7세 이상은 검수된 한국 연령 규준이 없다 — 이번 활동 관찰만 적는다."""
        got = self._development(8)

        narrative = got["NARRATIVE_LANGUAGE"]
        self.assertIn("이번 활동에서 확인된 표현만 적어요", narrative.age_context)
        self.assertEqual(narrative.context_type, "SESSION_ONLY_CONTEXT")
        for observation in got.values():
            self.assertNotIn("또래보다", observation.observation)

    def test_unknown_age_does_not_invent_a_norm(self):
        """나이를 모르면 규준을 짐작해 붙이지 않는다.

        규준을 붙이지 않는 것과 관찰을 지우는 것은 다르다 — 나이를 몰라도 이번 활동에서
        무엇을 봤는지는 그대로 적는다. 등록부에 도메인 문장이 빠지면 그 도메인이 화면에서
        통째로 사라지는데, 보호자에게는 '확인할 것이 없었다'로 보인다.
        """
        got = self._development(None)

        self.assertIn("NARRATIVE_LANGUAGE", got)
        for observation in got.values():
            self.assertEqual(observation.source_ids, [])
            self.assertIn("이번 활동", observation.age_context)

    def test_every_produced_domain_has_a_session_only_sentence(self):
        """나이를 모를 때 쓸 문장이 없으면 그 도메인은 조용히 사라진다."""
        known = self._development(5).keys()
        unknown = self._development(None).keys()

        self.assertEqual(set(known), set(unknown))

    def test_missing_data_makes_no_card_at_all(self):
        """근거가 없으면 카드를 만들지 않는다 — "확인하지 않아요"만 줄줄이 남기지 않는다.

        예전에는 NOT_ASSESSED 카드를 내보내 화면이 "이 나이대에서는 확인하지 않아요"로만
        채워졌다. 보호자에게 아무것도 아닌 화면이었고, 자칫 아이가 못 한 것으로도 읽혔다.
        확인하지 못한 것은 unknown_items 가 이름을 붙여 따로 돌려준다.
        """
        import diary_report_v2

        req = _diary_request().model_copy(
            update={
                "child_age": 5,
                "age_months": 65,
                "selected_emotion_refs": [],
                "expressed_emotion_text": "",
            }
        )
        insights = diary_report_v2.build_diary_insights(
            _signals(narrativeFlow=[]), req, vision_available=False
        )
        got = {o.domain: o for o in insights.developmental_observations}

        self.assertNotIn("SOCIAL_UNDERSTANDING", got)
        for observation in insights.developmental_observations:
            self.assertNotEqual(observation.status, "NOT_ASSESSED")
            for word in ("느리", "지연", "부족", "못해", "미달"):
                self.assertNotIn(word, observation.observation)

    def test_chosen_emotion_alone_is_partial_not_observed(self):
        """감정을 고르기만 한 것을 '자기 말로 표현했다'로 올리지 않는다."""
        import diary_report_v2

        req = _diary_request().model_copy(
            update={"child_age": 5, "expressed_emotion_text": ""}
        )
        insights = diary_report_v2.build_diary_insights(
            _signals(narrativeFlow=[]), req, vision_available=True
        )
        got = {o.domain: o for o in insights.developmental_observations}

        self.assertEqual(got["EMOTION_EXPRESSION"].status, "PARTIALLY_OBSERVED")
        self.assertIn("골랐어요", got["EMOTION_EXPRESSION"].observation)

    def test_db_answer_type_spellings_are_both_accepted(self):
        """BE 는 DB enum(`OPTION_ANSWER`)을 그대로 보낸다.

        계약 문서에는 `OPTION` 으로 적혀 있어 짧은 쪽만 보고 있었고, 그래서 **고른 답이 아이의
        자발 발화로 세어졌다** — 994 가 막으려던 바로 그것이다. 2026-08-07 실호출로 드러났다.
        """
        import diary_report_v2

        for spelling in ("OPTION", "OPTION_ANSWER"):
            with self.subTest(spelling=spelling):
                self.assertTrue(diary_report_v2.is_option_answer(spelling))
                self.assertEqual(
                    diary_report_v2.classify_elicitation("기뻤어?", spelling, "응"),
                    "MULTIPLE_CHOICE",
                )
        for spelling in ("VOICE", "VOICE_ANSWER", "TEXT_ANSWER"):
            with self.subTest(spelling=spelling):
                self.assertTrue(diary_report_v2.is_spoken_answer(spelling))
                self.assertFalse(diary_report_v2.is_option_answer(spelling))

    def test_option_answers_are_counted_as_choices_not_voice(self):
        """세는 자리도 같은 표기를 봐야 한다 — 아니면 고른 답이 음성 답으로 집계된다."""
        import diary_report_v2

        req = _diary_request().model_copy(
            update={
                "subject_summaries": [
                    contracts.SubjectSummary(
                        drawing_description="사람이 보여요.",
                        observation_evidence_source_id="vision-1",
                        qa_pairs=[
                            contracts.SubjectQaPair(
                                question="기뻤어?",
                                answer_text="기뻤어",
                                answer_type="OPTION_ANSWER",
                                answer_message_id=201,
                            ),
                            contracts.SubjectQaPair(
                                question="그다음엔 뭐 했어?",
                                answer_text="엄마한테 자랑했어",
                                answer_type="VOICE_ANSWER",
                                answer_message_id=202,
                            ),
                        ],
                    )
                ]
            }
        )
        quality = diary_report_v2._data_quality(
            req, evidence_count=2, vision_available=True
        )

        self.assertEqual(quality.option_answer_count, 1)
        self.assertEqual(quality.confirmed_voice_count, 1)

    def test_raw_evidence_carries_question_elicitation_context(self):
        import diary_report_v2

        evidence = diary_report_v2.raw_evidence_texts(_diary_request())
        self.assertIn("OPEN_INVITATION", evidence[("QA_ANSWER", "101")])
        self.assertIn("오늘 실제로 있었던 일이야", evidence[("QA_ANSWER", "101")])
        self.assertIn("MULTIPLE_CHOICE", evidence[("QA_ANSWER", "104")])
        self.assertIn("선택지에서", evidence[("QA_ANSWER", "104")])

    def test_child_voice_items_record_how_answers_were_elicited(self):
        import diary_report_v2

        insights = diary_report_v2.build_diary_insights(
            _signals(), _diary_request(), vision_available=True
        )
        elicitation = [item.elicitation_type for item in insights.child_voice_items]
        self.assertEqual(
            elicitation,
            ["OPEN_INVITATION", "CUED_INVITATION", "FOCUSED_WH", "MULTIPLE_CHOICE"],
        )


def _fake_response(text: str):
    return types.SimpleNamespace(
        choices=[types.SimpleNamespace(message=types.SimpleNamespace(content=text))],
        model="served-model",
    )


def _generation_payload() -> str:
    payload = {
        "overallSummary": "GENERATED_OVERALL",
        "positiveSignals": "GENERATED_POSITIVE",
        "attentionPoints": "특이 관찰 사항 없음",
        "evidenceSummary": "GENERATED_EVIDENCE",
        "guardianGuidance": "아이의 말을 차분히 들어주세요.",
        "followUpQuestion": "그때 가장 기억나는 건 뭐였어?",
        "expertReviewRequired": False,
        "features": [],
        "conversationSummary": {
            "summaryText": "GENERATED_CONVERSATION",
            "mainTopic": "시험 이야기",
            "expressedEmotion": "기쁨",
        },
        "activityNotes": ["GENERATED_ACTIVITY"],
        "followUpGuides": [
            {
                "guidance": "100점을 받고 엄마에게 자랑할 때 어떤 말을 했어?",
                "detailText": "결과와 함께 과정을 들어보는 질문이에요.",
            }
        ],
        "guardianQuestions": [
            {
                "questionText": "엄마에게 자랑할 때 어떤 말을 했어?",
                "questionPurpose": "아이의 행동을 더 들어보기",
            }
        ],
        "evidenceItems": [
            {
                "evidenceId": 1,
                "sourceType": "CHILD_ANSWER",
                "text": "모델이 바꿔 쓴 첫 번째 근거",
                "sourceRef": _ref("QA_ANSWER", "101"),
            },
            {
                "evidenceId": 2,
                "sourceType": "CHILD_ANSWER",
                "text": "모델이 바꿔 쓴 두 번째 근거",
                "sourceRef": _ref("QA_ANSWER", "103"),
            },
        ],
        "publicInterpretations": [
            {
                "category": "SELF_EXPRESSION",
                "title": "사건과 감정을 함께 설명한 모습",
                "tendencyText": "이번 활동에서 사건과 감정을 이어 말한 모습이 보일 수 있습니다.",
                "scopeText": "이번 활동에서 나타난 가능성입니다.",
                "homeObservationGuide": "다른 기쁜 일이 있을 때도 어떻게 이야기하는지 살펴봐 주세요.",
                "evidenceRefs": [1, 2],
            }
        ],
        "subjectReports": [
            {
                "subjectType": None,
                "visionObservations": ["GENERATED_VISION"],
                "interpretationRefs": [0],
            }
        ],
        "parentGuides": [
            {
                "guideType": "DRAWING_CONVERSATION",
                "items": ["아이에게 노력한 과정을 물어보세요."],
            }
        ],
        "drawnItems": [],
        "diarySignals": _signals(),
    }
    return json.dumps(payload, ensure_ascii=False)



class DiaryReportPromptV2Test(unittest.TestCase):
    def test_report_prompt_emits_structured_diary_signals_without_forced_filler(self):
        import prompts_registry

        text = prompts_registry.load("report_diary")
        self.assertIn('"diarySignals"', text)
        self.assertIn('"storySnapshot"', text)
        self.assertIn('"narrativeFlow"', text)
        self.assertIn('"sessionObservations"', text)
        self.assertIn('"caregiverQuestions"', text)
        self.assertNotIn("쓸 내용이 마땅치 않아도", text)
        self.assertNotIn("무난한 문장을 채운다", text)
        self.assertIn("한 번의 활동을 아이의 평소 경향으로 쓰지 마", text)
        self.assertIn("같은 내용을 여러 섹션에 반복하지 마", text)

    def test_review_prompt_checks_usefulness_and_child_voice_integrity(self):
        import prompts_registry

        text = prompts_registry.load("report_review_diary")
        for code in (
            "DUPLICATE_CONTENT",
            "GENERIC_GUIDANCE",
            "NOT_ACTIONABLE",
            "UNSUPPORTED_TREND",
            "ELICITATION_OVERCLAIM",
            "REALITY_COLLAPSE",
            "TIME_SCOPE_OVERCLAIM",
            "VISUAL_UNCERTAINTY_EXPOSED",
            "CHILD_VOICE_DISTORTION",
        ):
            self.assertIn(code, text)
        self.assertIn("품질 첨삭은 하지 않는다", text)
        self.assertIn("품질 문제를 코드로만 짚는다", text)

    def test_prompt_versions_are_bumped_for_v2(self):
        import prompts_registry

        # 3.1.0 — 3층 인사이트(insightType 3종 + 다른 설명)를 더했다. 구 V2 모양 카드는
        #   근거 모양에서 종류를 추론해 그대로 통과하므로 minor 다.
        self.assertEqual(prompts_registry._PROMPT_SEMVER["report_diary"], "3.1.0")
        self.assertEqual(prompts_registry._PROMPT_SEMVER["report_review"], "2.1.0")
        self.assertEqual(
            prompts_registry._PROMPT_SEMVER["report_review_diary"], "1.0.0"
        )


class ReportClientDiaryV2IntegrationTest(unittest.TestCase):
    def _run(self):
        captured = {}
        replies = [_generation_payload(), json.dumps({"findings": []})]

        def create(**kwargs):
            index = len(captured.setdefault("calls", []))
            captured["calls"].append(kwargs)
            return _fake_response(replies[min(index, len(replies) - 1)])

        fake_client = mock.Mock()
        fake_client.chat.completions.create.side_effect = create
        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            result = report_client.generate(_diary_request(), model="m")
        return result, captured

    def test_generate_attaches_diary_insights(self):
        result, _ = self._run()
        self.assertIsNotNone(result.diary_insights)
        self.assertEqual(result.diary_insights.story_snapshot.time_scope, "TODAY")

    def test_diary_never_exposes_single_session_legacy_psychology_cards(self):
        result, _ = self._run()

        self.assertEqual(result.public_interpretations, [])
        self.assertEqual(result.evidence_items, [])
        self.assertTrue(
            all(report.interpretation_refs == [] for report in result.subject_reports)
        )

    def test_diary_caps_legacy_visible_lists_to_avoid_repetitive_report_sections(self):
        payload = json.loads(_generation_payload())
        feature = {
            "featureCode": "DIARY_FEATURE",
            "title": "이번 활동 표현",
            "description": "이번 활동에서 확인된 설명으로 보일 수 있어요.",
            "evidenceSummary": "아이 답변과 그림 관찰이 있어요.",
            "visibilityScope": "REVIEWED_GUARDIAN",
        }
        payload["features"] = [feature, feature, feature]
        payload["activityNotes"] = ["기록 1", "기록 2", "기록 3"]
        payload["followUpGuides"] = payload["followUpGuides"] * 3
        payload["guardianQuestions"] = payload["guardianQuestions"] * 3
        payload["subjectReports"][0]["visionObservations"] = [
            "관찰 1",
            "관찰 2",
            "관찰 3",
        ]
        replies = [json.dumps(payload, ensure_ascii=False), json.dumps({"findings": []})]
        fake_client = mock.Mock()
        fake_client.chat.completions.create.side_effect = lambda **kwargs: _fake_response(
            replies.pop(0)
        )

        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            result = report_client.generate(_diary_request(), model="m")

        self.assertLessEqual(len(result.observation_draft.features), 1)
        self.assertLessEqual(len(result.activity_notes), 2)
        self.assertLessEqual(len(result.follow_up_guides), 2)
        self.assertLessEqual(len(result.guardian_questions), 2)
        self.assertTrue(
            all(len(report.vision_observations) <= 2 for report in result.subject_reports)
        )

    def test_legacy_diary_review_facts_include_raw_visual_and_representative_sources(self):
        req = _diary_request().model_copy(
            update={
                "subject_summaries": [],
                "selected_emotions": [],
                "selected_emotion_refs": [],
                "expressed_emotion_text": None,
                "representative_utterance": "오늘 시험에서 100점을 받았어",
            }
        )
        captured = {}
        replies = [_generation_payload(), json.dumps({"findings": []})]

        def create(**kwargs):
            index = len(captured.setdefault("calls", []))
            captured["calls"].append(kwargs)
            return _fake_response(replies[min(index, len(replies) - 1)])

        fake_client = mock.Mock()
        fake_client.chat.completions.create.side_effect = create
        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            report_client.generate(
                req,
                drawing_description="웃는 입 모양의 사람과 수학 100이라는 글자가 보여요.",
                model="m",
            )

        payload = json.loads(captured["calls"][1]["messages"][1]["content"])
        facts = " ".join(payload["관찰 사실"])
        self.assertIn("오늘 시험에서 100점을 받았어", facts)
        self.assertIn("수학 100이라는 글자", facts)

    def test_self_review_fact_pool_uses_raw_request_not_generated_report_text(self):
        _, captured = self._run()
        payload = json.loads(captured["calls"][1]["messages"][1]["content"])
        facts = " ".join(payload["관찰 사실"])
        self.assertIn("엄마한테 자랑했어", facts)
        self.assertNotIn("GENERATED_ACTIVITY", facts)
        self.assertNotIn("GENERATED_EVIDENCE", facts)
        self.assertNotIn("GENERATED_VISION", facts)

    def test_review_targets_cover_story_main_event_and_question_purpose(self):
        payload = json.loads(_generation_payload())
        payload["diarySignals"]["storySnapshot"]["mainEvent"] = "시험지를 엄마에게 보여준 장면"
        payload["diarySignals"]["caregiverQuestions"][0]["purpose"] = "엄마의 칭찬에서 기억에 남은 말을 들어보기"
        captured = {}
        replies = [json.dumps(payload, ensure_ascii=False), json.dumps({"findings": []})]

        def create(**kwargs):
            index = len(captured.setdefault("calls", []))
            captured["calls"].append(kwargs)
            return _fake_response(replies[min(index, len(replies) - 1)])

        fake_client = mock.Mock()
        fake_client.chat.completions.create.side_effect = create
        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            report_client.generate(_diary_request(), model="m")

        review = json.loads(captured["calls"][1]["messages"][1]["content"])
        targets = {item["id"]: item for item in review["검토 대상"]}
        self.assertIn("시험지를 엄마에게 보여준 장면", targets["diary.story"]["글"])
        self.assertIn("엄마의 칭찬에서 기억에 남은 말을 들어보기", targets["diary.question.0"]["글"])

    def test_review_targets_use_raw_evidence_and_cover_guardian_content(self):
        _, captured = self._run()
        payload = json.loads(captured["calls"][1]["messages"][1]["content"])
        targets = {item["id"]: item for item in payload["검토 대상"]}
        self.assertNotIn("card.0", targets)
        self.assertIn("guardianQuestion.0", targets)
        self.assertIn("parentGuide.0.0", targets)
        self.assertIn("diary.story", targets)

    def test_review_finding_removes_guardian_question_without_blocking_report(self):
        captured = {}
        replies = [
            _generation_payload(),
            json.dumps(
                {"findings": [{"target": "guardianQuestion.0", "issue": "NOT_ACTIONABLE", "note": "x"}]},
                ensure_ascii=False,
            ),
        ]

        def create(**kwargs):
            index = len(captured.setdefault("calls", []))
            captured["calls"].append(kwargs)
            return _fake_response(replies[min(index, len(replies) - 1)])

        fake_client = mock.Mock()
        fake_client.chat.completions.create.side_effect = create
        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            result = report_client.generate(_diary_request(), model="m")

        self.assertEqual(result.guardian_questions, [])
        self.assertEqual(result.observation_draft.status, report_client.REVIEW_STATUS_REVIEWED)

    def test_review_finding_removes_parent_guide_item_without_blocking_report(self):
        replies = [
            _generation_payload(),
            json.dumps(
                {"findings": [{"target": "parentGuide.0.0", "issue": "GENERIC_GUIDANCE", "note": "x"}]},
                ensure_ascii=False,
            ),
        ]
        fake_client = mock.Mock()
        fake_client.chat.completions.create.side_effect = lambda **kwargs: _fake_response(
            replies.pop(0)
        )
        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            result = report_client.generate(_diary_request(), model="m")

        self.assertEqual(result.parent_guides, [])
        self.assertEqual(result.observation_draft.status, report_client.REVIEW_STATUS_REVIEWED)

    def test_review_finding_removes_diary_observation_without_blocking_report(self):
        replies = [
            _generation_payload(),
            json.dumps(
                {"findings": [{"target": "diary.observation.0", "issue": "UNSUPPORTED_TREND", "note": "x"}]},
                ensure_ascii=False,
            ),
        ]
        fake_client = mock.Mock()
        fake_client.chat.completions.create.side_effect = lambda **kwargs: _fake_response(
            replies.pop(0)
        )
        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            result = report_client.generate(_diary_request(), model="m")

        self.assertEqual(result.diary_insights.session_observations, [])
        self.assertEqual(result.observation_draft.status, report_client.REVIEW_STATUS_REVIEWED)

    def test_review_finding_on_diary_story_drops_v2_only_without_blocking_legacy_report(self):
        replies = [
            _generation_payload(),
            json.dumps(
                {"findings": [{"target": "diary.story", "issue": "REALITY_COLLAPSE", "note": "x"}]},
                ensure_ascii=False,
            ),
        ]
        fake_client = mock.Mock()
        fake_client.chat.completions.create.side_effect = lambda **kwargs: _fake_response(
            replies.pop(0)
        )
        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            result = report_client.generate(_diary_request(), model="m")

        self.assertIsNone(result.diary_insights)
        self.assertEqual(result.observation_draft.status, report_client.REVIEW_STATUS_REVIEWED)

    def test_grounded_school_score_follow_up_is_not_replaced_by_generic_fallback(self):
        payload = json.loads(_generation_payload())
        payload["followUpQuestion"] = "100점을 받았을 때 가장 기억나는 건 뭐였어?"
        replies = [json.dumps(payload, ensure_ascii=False), json.dumps({"findings": []})]
        fake_client = mock.Mock()
        fake_client.chat.completions.create.side_effect = lambda **kwargs: _fake_response(
            replies.pop(0)
        )
        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            result = report_client.generate(_diary_request(), model="m")

        self.assertEqual(
            result.observation_draft.follow_up_question,
            "100점을 받았을 때 가장 기억나는 건 뭐였어?",
        )

    def test_guardian_visible_diary_fields_are_in_rule_safety_scan(self):
        payload = json.loads(_generation_payload())
        payload["guardianQuestions"][0]["questionText"] = "아이는 ADHD가 맞나요?"
        replies = [json.dumps(payload, ensure_ascii=False), json.dumps({"findings": []})]
        fake_client = mock.Mock()
        fake_client.chat.completions.create.side_effect = lambda **kwargs: _fake_response(
            replies.pop(0)
        )
        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            result = report_client.generate(_diary_request(), model="m")

        self.assertEqual(result.observation_draft.status, report_client.REVIEW_STATUS_DRAFT)

    def test_generic_listening_tip_drops_only_the_tip(self):
        """검토기가 듣기 안내 한 줄을 걸어도 이야기는 남아야 한다.

        2026-08-07 실호출에서 이것 때문에 V2 가 3/3 모두 꺼졌다. 검토기가 optional 한 줄인
        listeningTip 만 GENERIC_GUIDANCE 로 걸었는데, 구 코드가 핵심 이야기·흐름·관찰·질문을
        통째로 버렸다. 검토기는 문장을 고치지 않고 **문제가 있는 항목만** 빼야 한다.
        """
        replies = [
            _generation_payload(),
            json.dumps(
                {
                    "findings": [
                        {
                            "target": "diary.listeningTip",
                            "issue": "GENERIC_GUIDANCE",
                            "note": "x",
                        }
                    ]
                },
                ensure_ascii=False,
            ),
        ]
        fake_client = mock.Mock()
        fake_client.chat.completions.create.side_effect = (
            lambda **kwargs: _fake_response(replies.pop(0))
        )
        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            result = report_client.generate(_diary_request(), model="m")

        self.assertIsNotNone(result.diary_insights)
        self.assertIsNone(result.diary_insights.listening_tip)
        self.assertTrue(result.diary_insights.narrative_flow)

    def test_flagged_flow_step_drops_only_that_step(self):
        """흐름 한 단계가 걸리면 그 단계만 빠진다."""
        payload = json.loads(_generation_payload())
        step_count = len(payload["diarySignals"]["narrativeFlow"])
        self.assertGreater(step_count, 1, "이 검증은 단계가 둘 이상일 때만 의미가 있다")
        replies = [
            json.dumps(payload, ensure_ascii=False),
            json.dumps(
                {
                    "findings": [
                        {
                            "target": "diary.flow.0",
                            "issue": "TIME_SCOPE_OVERCLAIM",
                            "note": "x",
                        }
                    ]
                },
                ensure_ascii=False,
            ),
        ]
        fake_client = mock.Mock()
        fake_client.chat.completions.create.side_effect = (
            lambda **kwargs: _fake_response(replies.pop(0))
        )
        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            result = report_client.generate(_diary_request(), model="m")

        self.assertIsNotNone(result.diary_insights)
        self.assertEqual(len(result.diary_insights.narrative_flow), step_count - 1)

    def test_flagged_flow_step_takes_its_developmental_claim_with_it(self):
        """근거가 잘려 나간 발달 주장은 남지 않는다.

        발달 맥락은 흐름 단계를 근거로 조립된다. 흐름이 검토에서 빠졌는데 "이어서
        이야기했어요"가 그대로 남으면, 사라진 근거를 인용하는 발달 주장이 된다 — 이
        섹션에서 가장 위험한 실패다. 근거를 인용하지 않는 항목(NOT_ASSESSED, 감정 선택)은
        영향을 받지 않는다.
        """
        payload = json.loads(_generation_payload())
        steps = payload["diarySignals"]["narrativeFlow"]
        flagged_refs = {
            (ref["kind"], ref["id"]) for ref in steps[0].get("evidenceRefs", [])
        }
        self.assertTrue(flagged_refs, "근거가 붙은 단계라야 이 검증이 의미가 있다")
        replies = [
            json.dumps(payload, ensure_ascii=False),
            json.dumps(
                {
                    "findings": [
                        {
                            "target": "diary.flow.0",
                            "issue": "TIME_SCOPE_OVERCLAIM",
                            "note": "x",
                        }
                    ]
                },
                ensure_ascii=False,
            ),
        ]
        fake_client = mock.Mock()
        fake_client.chat.completions.create.side_effect = (
            lambda **kwargs: _fake_response(replies.pop(0))
        )
        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            result = report_client.generate(_diary_request(), model="m")

        observations = result.diary_insights.developmental_observations
        domains = {o.domain for o in observations}
        # 그 단계를 근거로 삼던 항목은 사라진다.
        self.assertNotIn("NARRATIVE_LANGUAGE", domains)
        for observation in observations:
            for ref in observation.evidence_refs:
                self.assertNotIn(
                    (ref.kind, ref.id),
                    flagged_refs,
                    f"{observation.domain} 이 빠진 단계를 근거로 남았다",
                )
        # 다른 근거를 쓰는 항목까지 함께 지워 버리지는 않는다.
        self.assertIn("EMOTION_EXPRESSION", domains)
        # ⚠️ SOCIAL_UNDERSTANDING 은 여기 없는 것이 맞다. 이 활동에 다른 사람의 행동·반응을
        #    아이가 이야기한 근거가 없고, 근거 없는 카드는 만들지 않는다(2.0.0). 예전에는
        #    NOT_ASSESSED 카드로 남아 "확인하지 않아요"만 화면을 채웠다.
        self.assertNotIn("SOCIAL_UNDERSTANDING", domains)


if __name__ == "__main__":
    unittest.main()


class DiaryReviewIsolationTest(unittest.TestCase):
    """그림일기 품질 검토가 HTP의 기존 검토 의미를 바꾸지 않는지 확인한다."""

    @staticmethod
    def _htp_request() -> contracts.ObservationGenerationRequest:
        req = _diary_request()
        req.subject_summaries[0].drawing_subject = "HOUSE"
        return req

    def test_diary_and_htp_use_separate_review_prompts(self):
        diary_prompts: list[str] = []
        htp_prompts: list[str] = []

        def run(req, captured):
            replies = [_generation_payload(), json.dumps({"findings": []})]
            fake_client = mock.Mock()

            def create(**kwargs):
                if len(replies) == 1:
                    captured.append(kwargs["messages"][0]["content"])
                return _fake_response(replies.pop(0))

            fake_client.chat.completions.create.side_effect = create
            with mock.patch.object(report_client, "get_client", return_value=fake_client):
                report_client.generate(req, model="m")

        run(_diary_request(), diary_prompts)
        run(self._htp_request(), htp_prompts)

        self.assertIn("그림일기 V2 품질 문제", diary_prompts[0])
        self.assertNotIn("그림일기 V2 품질 문제", htp_prompts[0])

    def test_htp_ignores_diary_only_review_issue_codes(self):
        import test_report_client as legacy_tests

        replies = [
            legacy_tests._llm_json(),
            json.dumps(
                {
                    "findings": [
                        {
                            "target": "activityNote.0",
                            "issue": "GENERIC_GUIDANCE",
                            "note": "x",
                        }
                    ]
                },
                ensure_ascii=False,
            ),
        ]
        fake_client = mock.Mock()
        fake_client.chat.completions.create.side_effect = lambda **kwargs: _fake_response(
            replies.pop(0)
        )
        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            result = report_client.generate(self._htp_request(), model="m")

        self.assertNotEqual(result.activity_notes, [])
        self.assertEqual(
            result.observation_draft.status, report_client.REVIEW_STATUS_REVIEWED
        )

    def test_htp_legacy_cards_and_list_sizes_are_not_changed(self):
        payload = json.loads(_generation_payload())
        feature = {
            "featureCode": "HTP_FEATURE",
            "title": "관찰 제목",
            "description": "관찰 사실에 근거한 설명으로 보일 수 있어요.",
            "evidenceSummary": "아이 답변과 그림 관찰이 있어요.",
            "visibilityScope": "REVIEWED_GUARDIAN",
        }
        payload["features"] = [feature, feature, feature]
        payload["activityNotes"] = ["기록 1", "기록 2", "기록 3"]
        payload["followUpGuides"] = payload["followUpGuides"] * 3
        payload["guardianQuestions"] = payload["guardianQuestions"] * 3
        replies = [json.dumps(payload, ensure_ascii=False), json.dumps({"findings": []})]
        fake_client = mock.Mock()
        fake_client.chat.completions.create.side_effect = lambda **kwargs: _fake_response(
            replies.pop(0)
        )

        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            result = report_client.generate(self._htp_request(), model="m")

        self.assertEqual(len(result.observation_draft.features), 3)
        self.assertEqual(len(result.activity_notes), 3)
        self.assertEqual(len(result.follow_up_guides), 3)
        self.assertEqual(len(result.guardian_questions), 3)
        self.assertEqual(len(result.public_interpretations), 1)

    def test_activity_note_finding_is_contained_only_for_diary(self):
        review = json.dumps(
            {
                "findings": [
                    {
                        "target": "activityNote.0",
                        "issue": "MIXED_EVIDENCE",
                        "note": "x",
                    }
                ]
            },
            ensure_ascii=False,
        )

        def run(req):
            replies = [_generation_payload(), review]
            fake_client = mock.Mock()
            fake_client.chat.completions.create.side_effect = lambda **kwargs: _fake_response(
                replies.pop(0)
            )
            with mock.patch.object(report_client, "get_client", return_value=fake_client):
                return report_client.generate(req, model="m")

        diary = run(_diary_request())
        htp = run(self._htp_request())

        self.assertEqual(diary.activity_notes, [])
        self.assertEqual(
            diary.observation_draft.status, report_client.REVIEW_STATUS_REVIEWED
        )
        self.assertNotEqual(htp.activity_notes, [])
        self.assertEqual(htp.observation_draft.status, report_client.REVIEW_STATUS_DRAFT)

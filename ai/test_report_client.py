"""report_client 단위 테스트 — GMS 호출을 가짜로 대체해 조립·에러 매핑만 검증.

실제 네트워크·모델 없이 돈다. get_client 를 monkeypatch 해 chat.completions.create
호출 인자(프롬프트)를 가로채고, LLM JSON → 계약 결과 조립, 서버 고정 필드(안전 문구·상태),
emotion_source 규칙, visibility_scope 강제, OpenAIError → RuntimeError 변환을 확인한다.
"""

from __future__ import annotations

import json
import types
import unittest
from unittest import mock

from openai import OpenAIError

import internal_contracts as contracts
import report_client


def _fake_response(text: str, *, model: str | None = None):
    message = types.SimpleNamespace(content=text)
    choice = types.SimpleNamespace(message=message)
    resp = types.SimpleNamespace(choices=[choice])
    if model is not None:
        resp.model = model  # GMS가 실제 서빙한 모델 ID
    return resp


def _llm_json(**overrides) -> str:
    """LLM이 돌려줄 법한 JSON 문자열(정성 필드만). overrides로 일부 키 교체."""
    payload = {
        "overallSummary": "아이는 그림 활동에 즐겁게 참여했어요.",
        "positiveSignals": "자기 생각을 적극적으로 표현했어요.",
        "attentionPoints": "특이 관찰 사항 없음",
        "evidenceSummary": "집을 크게 그리고 가족을 함께 그린 점에서 관찰됨.",
        "guardianGuidance": "아이의 이야기를 편안하게 들어주세요.",
        "followUpQuestion": "이 집에는 누가 살고 있어?",
        "expertReviewRequired": False,
        "features": [
            {
                "featureCode": "HOUSE_CENTER",
                "title": "가운데 큰 집",
                "description": "집을 화면 가운데에 크게 그렸어요.",
                "evidenceSummary": "그림 관찰 서술 근거",
                "visibilityScope": "REVIEWED_GUARDIAN",
            }
        ],
        "conversationSummary": {
            "summaryText": "우리 집과 가족 이야기를 나눴어요.",
            "mainTopic": "우리 집",
            "expressedEmotion": "즐거움",
        },
        "activityNotes": ["활동 내내 집중했어요."],
        "followUpGuides": [
            {"guidance": "개방형 질문으로 이야기해 보세요.", "detailText": "정답을 요구하지 않는 질문이 표현을 돕습니다."}
        ],
        "guardianQuestions": [
            {"questionText": "가장 마음에 드는 부분은 어디야?", "questionPurpose": "표현 확장"}
        ],
    }
    payload.update(overrides)
    return json.dumps(payload, ensure_ascii=False)


def _sample_request(**overrides) -> contracts.ObservationGenerationRequest:
    base = {
        "request_id": "req-1",
        "analysis_id": 10,
        "drawing_session_id": 20,
        "analysis_type": "FINAL",
        "question_difficulty": "PRESCHOOL",
        "question_count": 5,
        "answered_count": 4,
        "skipped_count": 1,
        "unrecognized_speech_count": 0,
        "selected_emotions": ["JOY"],
        "expressed_emotion_text": None,
        "representative_utterance": "이건 우리 집이야.",
    }
    base.update(overrides)
    return contracts.ObservationGenerationRequest(**base)


class GenerateTest(unittest.TestCase):
    def test_assembles_contract_result_with_server_owned_fields(self):
        captured = {}

        def fake_create(*, model, messages, **_kwargs):
            captured["model"] = model
            captured["messages"] = messages
            return _fake_response(_llm_json())

        fake_client = mock.Mock()
        fake_client.chat.completions.create.side_effect = fake_create

        req = _sample_request()
        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            result = report_client.generate(
                req,
                drawing_description="가운데에 집이 크게, 왼쪽에 나무가 있어요.",
                model="test-model",
            )

        # 서버가 고정으로 채우는 필드
        self.assertEqual(result.request_id, "req-1")  # 요청 에코
        self.assertEqual(result.model_name, "test-model")
        # model_version은 프롬프트+파이프라인 복합 버전(S15P11B209-602).
        self.assertEqual(result.model_version, report_client._generation_version())
        self.assertIsNone(result.confidence)
        self.assertEqual(result.observation_draft.status, "AI_DRAFT")
        self.assertEqual(result.observation_draft.disclaimer, report_client.DISCLAIMER)
        self.assertEqual(result.limitations_text, report_client.LIMITATIONS)

        # LLM 정성 필드가 그대로 실렸는지
        self.assertIn("즐겁게", result.observation_draft.overall_summary)
        self.assertEqual(len(result.observation_draft.features), 1)
        self.assertEqual(
            result.observation_draft.features[0].visibility_scope, "REVIEWED_GUARDIAN"
        )
        self.assertEqual(result.conversation_summary.main_topic, "우리 집")

        # emotion_source 는 요청으로 결정(선택 감정 있음 → SELECTED)
        self.assertEqual(result.conversation_summary.emotion_source, "SELECTED")
        # 대표 발화는 요청 값 에코
        self.assertEqual(
            result.conversation_summary.representative_utterance, "이건 우리 집이야."
        )

        # 그림 서술이 프롬프트(user 메시지)에 근거로 들어갔는지
        user_msg = captured["messages"][1]["content"]
        self.assertIn("가운데에 집이 크게", user_msg)
        self.assertIn("[그림 관찰 서술]", user_msg)

    def test_behavior_metrics_injected_into_prompt(self):
        captured = {}

        def fake_create(*, model, messages, **_kwargs):
            captured["messages"] = messages
            return _fake_response(_llm_json())

        fake_client = mock.Mock()
        fake_client.chat.completions.create.side_effect = fake_create

        behavior = report_client.DrawingBehaviorMetrics(
            drawing_duration_ms=600_000,
            pause_count=4,
            erase_count=3,
            pressure_available=True,
            average_pressure=0.62,
        )
        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            report_client.generate(_sample_request(), behavior=behavior, model="m")

        user_msg = captured["messages"][1]["content"]
        self.assertIn("[형식적 분석]", user_msg)
        self.assertIn("약 10.0분", user_msg)  # 600_000ms → 10분
        self.assertIn("지우기 횟수: 3회", user_msg)
        self.assertIn("평균 0.62", user_msg)

    def test_pressure_unavailable_marks_not_measured(self):
        captured = {}
        fake_client = mock.Mock()
        fake_client.chat.completions.create.side_effect = lambda **k: captured.update(
            messages=k["messages"]
        ) or _fake_response(_llm_json())

        behavior = report_client.DrawingBehaviorMetrics(pressure_available=False)
        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            report_client.generate(_sample_request(), behavior=behavior, model="m")

        self.assertIn("필압: 측정 불가", captured["messages"][1]["content"])

    def test_without_description_prompts_placeholder(self):
        captured = {}

        def fake_create(*, model, messages, **_kwargs):
            captured["messages"] = messages
            return _fake_response(_llm_json())

        fake_client = mock.Mock()
        fake_client.chat.completions.create.side_effect = fake_create

        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            report_client.generate(_sample_request(), model="m")

        user_msg = captured["messages"][1]["content"]
        self.assertIn("그림 관찰 서술이 제공되지 않았어요", user_msg)

    def test_invalid_visibility_scope_coerced_to_expert_only(self):
        fake_client = mock.Mock()
        fake_client.chat.completions.create.return_value = _fake_response(
            _llm_json(
                features=[
                    {
                        "featureCode": "X",
                        "title": "t",
                        "description": "d",
                        "evidenceSummary": "e",
                        "visibilityScope": "PUBLIC",  # 계약에 없는 값
                    }
                ]
            )
        )
        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            result = report_client.generate(_sample_request(), model="m")
        self.assertEqual(
            result.observation_draft.features[0].visibility_scope, "EXPERT_ONLY"
        )

    def test_openai_error_maps_to_runtime_error(self):
        fake_client = mock.Mock()
        fake_client.chat.completions.create.side_effect = OpenAIError("boom")
        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            with self.assertRaises(RuntimeError):
                report_client.generate(_sample_request(), model="m")


class DefinitiveDiagnosisQuarantineTest(unittest.TestCase):
    """단정적 진단 표현 격리 — 전문가 검토 + EXPERT_ONLY 강등 (S15P11B209-591)."""

    def _generate(self, **overrides):
        fake_client = mock.Mock()
        fake_client.chat.completions.create.return_value = _fake_response(
            _llm_json(**overrides)
        )
        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            return report_client.generate(_sample_request(), model="m")

    def test_guardian_feature_with_diagnosis_downgraded_to_expert_only(self):
        result = self._generate(
            features=[
                {
                    "featureCode": "X",
                    "title": "정서 관찰",
                    "description": "이 아이는 불안장애로 진단됩니다.",  # 단정
                    "evidenceSummary": "e",
                    "visibilityScope": "REVIEWED_GUARDIAN",
                }
            ]
        )
        self.assertEqual(
            result.observation_draft.features[0].visibility_scope, "EXPERT_ONLY"
        )
        # 보호자 노출 내용에 단정 진단이 있으면 전문가 검토를 강제한다.
        self.assertTrue(result.observation_draft.expert_review_required)

    def test_hedged_concern_feature_stays_guardian_visible(self):
        result = self._generate(
            expertReviewRequired=False,
            features=[
                {
                    "featureCode": "X",
                    "title": "정서 관찰",
                    "description": "속상한 마음이 담긴 듯 보일 수 있어요.",  # 여지
                    "evidenceSummary": "e",
                    "visibilityScope": "REVIEWED_GUARDIAN",
                }
            ],
        )
        self.assertEqual(
            result.observation_draft.features[0].visibility_scope, "REVIEWED_GUARDIAN"
        )
        self.assertFalse(result.observation_draft.expert_review_required)

    def test_diagnosis_in_overall_summary_forces_expert_review(self):
        result = self._generate(
            expertReviewRequired=False,
            overallSummary="이 아이는 우울증이 있어 보입니다.",  # 장애명 단정
        )
        self.assertTrue(result.observation_draft.expert_review_required)


class OverinferenceQuarantineTest(unittest.TestCase):
    """감정·성격 과잉 추론 격리 — 전문가 검토 + EXPERT_ONLY 강등 (S15P11B209-592)."""

    def _generate(self, **overrides):
        fake_client = mock.Mock()
        fake_client.chat.completions.create.return_value = _fake_response(
            _llm_json(**overrides)
        )
        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            return report_client.generate(_sample_request(), model="m")

    def test_guardian_feature_with_trait_labeling_downgraded_to_expert_only(self):
        result = self._generate(
            features=[
                {
                    "featureCode": "X",
                    "title": "성격 관찰",
                    "description": "공격적인 성향이 있어요.",  # 고정 특질 규정
                    "evidenceSummary": "e",
                    "visibilityScope": "REVIEWED_GUARDIAN",
                }
            ]
        )
        self.assertEqual(
            result.observation_draft.features[0].visibility_scope, "EXPERT_ONLY"
        )
        self.assertTrue(result.observation_draft.expert_review_required)

    def test_overinference_in_overall_summary_forces_expert_review(self):
        result = self._generate(
            expertReviewRequired=False,
            overallSummary="정서적으로 불안한 아이입니다.",  # 정체성 규정
        )
        self.assertTrue(result.observation_draft.expert_review_required)

    def test_behavioral_observation_stays_guardian_visible(self):
        result = self._generate(
            expertReviewRequired=False,
            features=[
                {
                    "featureCode": "X",
                    "title": "활동 관찰",
                    "description": "조심스러운 모습을 보였어요.",  # 행동 관찰
                    "evidenceSummary": "e",
                    "visibilityScope": "REVIEWED_GUARDIAN",
                }
            ],
        )
        self.assertEqual(
            result.observation_draft.features[0].visibility_scope, "REVIEWED_GUARDIAN"
        )
        self.assertFalse(result.observation_draft.expert_review_required)


class UngroundedInterpretationTest(unittest.TestCase):
    """관찰 사실 ↔ AI 해석 분리 — 근거 없는 해석은 보호자 노출 불가 (S15P11B209-600)."""

    def _generate(self, **overrides):
        fake_client = mock.Mock()
        fake_client.chat.completions.create.return_value = _fake_response(
            _llm_json(**overrides)
        )
        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            return report_client.generate(_sample_request(), model="m")

    def test_interpretation_without_evidence_downgraded_to_expert_only(self):
        # description(해석)은 있는데 evidenceSummary(근거)가 비면 억측 → 격리.
        result = self._generate(
            features=[
                {
                    "featureCode": "X",
                    "title": "정서 관찰",
                    "description": "마음이 편안해 보여요.",  # 해석
                    "evidenceSummary": "   ",  # 근거 없음(공백)
                    "visibilityScope": "REVIEWED_GUARDIAN",
                }
            ]
        )
        self.assertEqual(
            result.observation_draft.features[0].visibility_scope, "EXPERT_ONLY"
        )

    def test_interpretation_with_evidence_stays_guardian_visible(self):
        # 근거가 있으면 그대로 보호자에게 보인다(정상 경로).
        result = self._generate(
            features=[
                {
                    "featureCode": "X",
                    "title": "정서 관찰",
                    "description": "즐겁게 그린 것으로 보여요.",  # 해석
                    "evidenceSummary": "밝은 색을 많이 썼고 지우기가 적었어요.",  # 관찰 사실 근거
                    "visibilityScope": "REVIEWED_GUARDIAN",
                }
            ]
        )
        self.assertEqual(
            result.observation_draft.features[0].visibility_scope, "REVIEWED_GUARDIAN"
        )


class VersionRecordingTest(unittest.TestCase):
    """리포트 model·prompt·pipelineVersion 저장 (S15P11B209-602)."""

    def test_model_version_carries_prompt_and_pipeline(self):
        fake_client = mock.Mock()
        fake_client.chat.completions.create.return_value = _fake_response(_llm_json())
        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            result = report_client.generate(_sample_request(), model="m")
        # 재현성 3종: model_name(모델) + model_version(프롬프트·파이프라인)
        self.assertIn(f"pipeline={report_client.config.PIPELINE_VERSION}", result.model_version)
        self.assertIn("prompt=", result.model_version)
        self.assertIn(report_client.PROMPT_VERSION, result.model_version)

    def test_model_name_records_actual_served_model(self):
        # GMS가 실제 서빙한 모델 ID를 기록한다(요청 모델명이 아니라).
        fake_client = mock.Mock()
        fake_client.chat.completions.create.return_value = _fake_response(
            _llm_json(), model="gpt-4o-mini-2024-07-18"
        )
        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            result = report_client.generate(_sample_request(), model="gpt-4o-mini")
        self.assertEqual(result.model_name, "gpt-4o-mini-2024-07-18")

    def test_model_name_falls_back_to_requested_when_unknown(self):
        fake_client = mock.Mock()
        fake_client.chat.completions.create.return_value = _fake_response(_llm_json())
        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            result = report_client.generate(_sample_request(), model="req-model")
        self.assertEqual(result.model_name, "req-model")


class FollowUpAndDisclaimerTest(unittest.TestCase):
    """진단 표현 제거·한계 고지·후속 질문 생성 보장 (S15P11B209-601)."""

    def _generate(self, **overrides):
        fake_client = mock.Mock()
        fake_client.chat.completions.create.return_value = _fake_response(
            _llm_json(**overrides)
        )
        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            return report_client.generate(_sample_request(), model="m")

    def test_empty_follow_up_is_filled_with_safe_default(self):
        result = self._generate(followUpQuestion="   ")
        self.assertEqual(
            result.observation_draft.follow_up_question,
            report_client.DEFAULT_FOLLOW_UP_QUESTION,
        )

    def test_diagnostic_follow_up_is_replaced_with_safe_default(self):
        # 후속 질문에 진단성 표현이 섞이면 보호자에게 그대로 내보내지 않고 안전 기본값으로 대체.
        result = self._generate(followUpQuestion="아이가 우울증이 있는지 물어보세요.")
        self.assertEqual(
            result.observation_draft.follow_up_question,
            report_client.DEFAULT_FOLLOW_UP_QUESTION,
        )

    def test_normal_follow_up_is_kept(self):
        result = self._generate(followUpQuestion="이 집에는 누가 살아?")
        self.assertEqual(
            result.observation_draft.follow_up_question, "이 집에는 누가 살아?"
        )

    def test_object_follow_up_extracts_question_text(self):
        # 모델이 스키마를 벗어나 객체로 줘도 questionText만 싣는다(dict가 통째로 문자열화되면 안 됨).
        result = self._generate(
            followUpQuestion={
                "questionText": "그림 속 집은 어떤 곳이야?",
                "questionPurpose": "상상력 자극",
            }
        )
        self.assertEqual(
            result.observation_draft.follow_up_question, "그림 속 집은 어떤 곳이야?"
        )
        self.assertNotIn("questionPurpose", result.observation_draft.follow_up_question)

    def test_object_follow_up_without_question_text_falls_back(self):
        result = self._generate(followUpQuestion={"questionPurpose": "목적만 있음"})
        self.assertEqual(
            result.observation_draft.follow_up_question,
            report_client.DEFAULT_FOLLOW_UP_QUESTION,
        )

    def test_disclaimer_and_limitations_always_present(self):
        # 한계 고지·면책 문구는 LLM이 무엇을 주든 서버가 상수로 항상 보장한다.
        result = self._generate(overallSummary="")
        self.assertEqual(result.observation_draft.disclaimer, report_client.DISCLAIMER)
        self.assertEqual(result.limitations_text, report_client.LIMITATIONS)
        self.assertTrue(result.observation_draft.disclaimer.strip())
        self.assertTrue(result.limitations_text.strip())


class EmotionSourceTest(unittest.TestCase):
    def test_selected(self):
        req = _sample_request(selected_emotions=["JOY"], expressed_emotion_text=None)
        self.assertEqual(report_client._emotion_source(req), "SELECTED")

    def test_stated(self):
        req = _sample_request(selected_emotions=[], expressed_emotion_text="무서웠어")
        self.assertEqual(report_client._emotion_source(req), "STATED")

    def test_inferred(self):
        req = _sample_request(selected_emotions=[], expressed_emotion_text=None)
        self.assertEqual(report_client._emotion_source(req), "INFERRED")


class ExtractJsonTest(unittest.TestCase):
    def test_strips_code_fence(self):
        raw = "```json\n{\"a\": 1}\n```"
        self.assertEqual(report_client._extract_json(raw), {"a": 1})

    def test_ignores_surrounding_prose(self):
        raw = "결과입니다: {\"a\": 2} 이상입니다."
        self.assertEqual(report_client._extract_json(raw), {"a": 2})

    def test_no_json_raises_runtime_error(self):
        with self.assertRaises(RuntimeError):
            report_client._extract_json("여기엔 JSON이 없어요")


class SubjectSummariesTest(unittest.TestCase):
    """주제별 그림 서술·문답 프롬프트 반영 (S15P11B209-740).

    HTP 3주제가 각각 [OO 그림 관찰]·[OO 그림 문답] 블록으로 실리고, 없으면 기존
    단일 [그림 관찰 서술] 경로가 그대로인지(롤아웃 호환) 검증한다.
    """

    def _capture_user_msg(self, req, **generate_kwargs) -> str:
        captured = {}

        def fake_create(*, model, messages, **_kwargs):
            captured["messages"] = messages
            return _fake_response(_llm_json())

        fake_client = mock.Mock()
        fake_client.chat.completions.create.side_effect = fake_create
        with mock.patch.object(report_client, "get_client", return_value=fake_client):
            report_client.generate(req, model="m", **generate_kwargs)
        return captured["messages"][1]["content"]

    @staticmethod
    def _htp_summaries() -> list[contracts.SubjectSummary]:
        return [
            contracts.SubjectSummary(
                drawing_subject="HOUSE",
                drawing_description="가운데에 집이 크게 그려져 있어요.",
                detected_object_codes=["HOUSE", "HOUSE_DOOR"],
                qa_pairs=[
                    contracts.SubjectQaPair(
                        question="이 집에는 누가 살아?",
                        answer_text="엄마랑 나!",
                        answer_type="VOICE",
                    ),
                    contracts.SubjectQaPair(
                        question="집 앞에는 뭐가 있어?",
                        answer_text=None,
                        answer_type=None,  # SKIPPED 아님 — 단순 무응답
                    ),
                ],
            ),
            contracts.SubjectSummary(
                drawing_subject="TREE",
                drawing_description="나무에 열매가 세 개 달려 있어요.",
                qa_pairs=[
                    contracts.SubjectQaPair(
                        question="이 나무는 어디에 있어?",
                        answer_text=None,
                        answer_type="SKIPPED",
                    )
                ],
            ),
            contracts.SubjectSummary(
                drawing_subject="PERSON",
                drawing_description="사람 두 명이 손을 잡고 있어요.",
            ),
        ]

    def test_subject_blocks_rendered_per_subject(self):
        req = _sample_request(subject_summaries=self._htp_summaries())
        user_msg = self._capture_user_msg(req)

        for label in ("[집 그림 관찰]", "[나무 그림 관찰]", "[사람 그림 관찰]"):
            self.assertIn(label, user_msg)
        self.assertIn("[집 그림 문답]", user_msg)
        self.assertIn("이 집에는 누가 살아?", user_msg)
        self.assertIn("엄마랑 나!", user_msg)
        self.assertIn("HOUSE_DOOR", user_msg)  # 참고용 요소 코드
        # 주제별 블록이 실리면 레거시 단일 블록은 없다.
        self.assertNotIn("[그림 관찰 서술]", user_msg)
        # 문답 없는 주제(사람)는 문답 블록도 없다.
        self.assertNotIn("[사람 그림 문답]", user_msg)

    def test_subject_blocks_take_priority_over_legacy_description(self):
        req = _sample_request(subject_summaries=self._htp_summaries())
        user_msg = self._capture_user_msg(
            req, drawing_description="레거시 단일 서술입니다."
        )
        self.assertNotIn("레거시 단일 서술입니다.", user_msg)
        self.assertIn("[집 그림 관찰]", user_msg)

    def test_art_diary_none_subject_uses_generic_label(self):
        req = _sample_request(
            subject_summaries=[
                contracts.SubjectSummary(
                    drawing_subject=None,
                    drawing_description="공룡이 풍선을 들고 있어요.",
                    qa_pairs=[
                        contracts.SubjectQaPair(question="공룡은 기분이 어때?")
                    ],
                )
            ]
        )
        user_msg = self._capture_user_msg(req)
        self.assertIn("[그림 관찰]", user_msg)
        self.assertIn("[그림 문답]", user_msg)
        # '그림 그림' 같은 라벨 중복이 없어야 한다.
        self.assertNotIn("그림 그림", user_msg)

    def test_skipped_question_rendered_distinctly_from_unanswered(self):
        req = _sample_request(subject_summaries=self._htp_summaries())
        user_msg = self._capture_user_msg(req)
        # SKIPPED(나무 문답)는 '건너뜀'으로, 타입 없는 무응답(집 두 번째 문답)은 별도 표기.
        self.assertIn("(건너뛴 질문)", user_msg)
        self.assertIn("(답하지 않았어요)", user_msg)

    def test_empty_subject_summaries_keeps_legacy_block(self):
        req = _sample_request(subject_summaries=[])
        user_msg = self._capture_user_msg(
            req, drawing_description="가운데에 집이 크게."
        )
        self.assertIn("[그림 관찰 서술]", user_msg)
        self.assertIn("가운데에 집이 크게.", user_msg)

    def test_answer_text_hidden_from_repr(self):
        qa = contracts.SubjectQaPair(question="누가 살아?", answer_text="비밀 발화")
        self.assertNotIn("비밀 발화", repr(qa))
        req = _sample_request(
            subject_summaries=[
                contracts.SubjectSummary(drawing_subject="HOUSE", qa_pairs=[qa])
            ]
        )
        self.assertNotIn("비밀 발화", repr(req))

    def test_camelcase_json_parses_like_be_payload(self):
        # BE(Jackson)가 보내는 camelCase JSON이 그대로 파싱되는지 — 계약 왕복 검증.
        payload = {
            "requestId": "req-9",
            "analysisId": 1,
            "drawingSessionId": 2,
            "analysisType": "FINAL",
            "subjectSummaries": [
                {
                    "drawingSubject": "TREE",
                    "drawingDescription": "나무 한 그루",
                    "detectedObjectCodes": ["TREE"],
                    "qaPairs": [
                        {
                            "question": "무슨 나무야?",
                            "answerText": "사과나무",
                            "answerType": "OPTION",
                        }
                    ],
                }
            ],
        }
        req = contracts.ObservationGenerationRequest.model_validate(payload)
        self.assertEqual(len(req.subject_summaries), 1)
        self.assertEqual(req.subject_summaries[0].drawing_subject, "TREE")
        self.assertEqual(req.subject_summaries[0].qa_pairs[0].answer_text, "사과나무")

    def test_old_be_payload_without_subject_summaries_still_parses(self):
        # 롤아웃 호환: 구 BE 요청(필드 부재)이 깨지지 않는다.
        payload = {
            "requestId": "req-8",
            "analysisId": 1,
            "drawingSessionId": 2,
            "analysisType": "FINAL",
        }
        req = contracts.ObservationGenerationRequest.model_validate(payload)
        self.assertEqual(req.subject_summaries, [])


class RagInjectionTest(unittest.TestCase):
    """RAG 근거 주입·출처 반환 (S15P11B209-614) — retrieve는 mock, GMS 미의존."""

    def _generate(self, req, *, chunks=None, unavailable=False, **kwargs):
        captured = {}

        def fake_create(*, model, messages, **_kwargs):
            captured["messages"] = messages
            return _fake_response(_llm_json())

        fake_client = mock.Mock()
        fake_client.chat.completions.create.side_effect = fake_create

        if unavailable:
            retrieve_patch = mock.patch.object(
                report_client,
                "retrieve",
                side_effect=report_client.RagUnavailableError("인덱스 없음"),
            )
        else:
            retrieve_patch = mock.patch.object(
                report_client, "retrieve", return_value=chunks or []
            )
        kb_patch = mock.patch.object(
            report_client, "rag_knowledge_base_version", return_value="kb-2026.07-1"
        )
        with retrieve_patch, kb_patch, mock.patch.object(
            report_client, "get_client", return_value=fake_client
        ):
            result = report_client.generate(req, model="m", **kwargs)
        return result, captured["messages"][1]["content"]

    @staticmethod
    def _chunks():
        from rag import Chunk

        return [
            Chunk(
                chunk_id="kicce-mr2303#0",
                source_id="kicce-mr2303",
                title="아동 사회·정서 발달지원",
                text="이 연령대 아이들은 그림으로 감정을 표현하는 것이 자연스럽습니다.",
                score=0.8,
            ),
            Chunk(
                chunk_id="kicce-mr2303#4",
                source_id="kicce-mr2303",  # 같은 자료의 다른 청크 — 출처는 1건으로 dedupe
                title="아동 사회·정서 발달지원",
                text="놀이와 그리기는 정서 표현의 통로입니다.",
                score=0.7,
            ),
        ]

    def test_chunks_injected_into_prompt_and_sources_returned(self):
        # 관찰 재료(서술)가 있어야 검색이 성립한다 — _build_rag_query 규칙과 정합.
        result, user_msg = self._generate(
            _sample_request(),
            chunks=self._chunks(),
            drawing_description="집이 크게 그려져 있어요.",
        )
        self.assertIn("[전문 자료 근거]", user_msg)
        self.assertIn("감정을 표현하는 것이 자연스럽습니다", user_msg)
        # 출처는 자료 단위 dedupe — 청크 2개, 참조 1건.
        self.assertEqual(len(result.rag_references), 1)
        self.assertEqual(result.rag_references[0].source_id, "kicce-mr2303")
        self.assertEqual(result.knowledge_base_version, "kb-2026.07-1")

    def test_unavailable_rag_degrades_not_blocks(self):
        # 인덱스 미배포·임베딩 실패 → 리포트는 그대로 생성, RAG 필드는 비움(기존 응답과 동일).
        result, user_msg = self._generate(_sample_request(), unavailable=True)
        self.assertNotIn("[전문 자료 근거]", user_msg)
        self.assertEqual(result.rag_references, [])
        self.assertIsNone(result.knowledge_base_version)
        self.assertIn("즐겁게", result.observation_draft.overall_summary)

    def test_empty_chunks_omit_block_and_kb_version(self):
        # 검색은 됐지만 임계값 미달(빈 목록) — 근거를 안 썼으므로 KB Version도 싣지 않는다.
        result, user_msg = self._generate(_sample_request(), chunks=[])
        self.assertNotIn("[전문 자료 근거]", user_msg)
        self.assertIsNone(result.knowledge_base_version)

    def test_query_excludes_child_utterances(self):
        # 질의는 관찰 서술·객체·선택 감정로만 — 아이 발화(답변·대표 발화)는 GMS로 안 나간다(정책 §1-1).
        req = _sample_request(
            representative_utterance="우리 엄마가 만든 김밥이 최고야",
            subject_summaries=[
                contracts.SubjectSummary(
                    drawing_subject="HOUSE",
                    drawing_description="집이 크게 그려져 있어요.",
                    detected_object_codes=["HOUSE"],
                    qa_pairs=[
                        contracts.SubjectQaPair(
                            question="누구랑 살아?", answer_text="비밀 발화 내용"
                        )
                    ],
                )
            ],
        )
        query = report_client._build_rag_query(req, None)
        self.assertIn("집이 크게 그려져 있어요.", query)
        self.assertIn("HOUSE", query)
        self.assertNotIn("비밀 발화 내용", query)
        self.assertNotIn("김밥", query)

    def test_no_query_material_skips_search(self):
        # 서술·객체·감정이 전부 없으면 임베딩 호출 자체를 하지 않는다.
        req = _sample_request(selected_emotions=[], subject_summaries=[])
        with mock.patch.object(report_client, "retrieve") as retrieve_spy:
            chunks = report_client._search_rag(req, None)
        self.assertEqual(chunks, [])
        retrieve_spy.assert_not_called()


if __name__ == "__main__":
    unittest.main()

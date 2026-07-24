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


def _fake_response(text: str):
    message = types.SimpleNamespace(content=text)
    choice = types.SimpleNamespace(message=message)
    return types.SimpleNamespace(choices=[choice])


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
        self.assertEqual(result.model_version, report_client.PROMPT_VERSION)
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


if __name__ == "__main__":
    unittest.main()

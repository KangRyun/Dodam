"""question_service 단위 테스트 — 첫 질문 고정 현상 제거·컨텍스트 기반 생성 (S15P11B209-589).

GMS를 가짜로 대체해(네트워크·과금 없이) 내부 계약 질문 생성이
- 탐지 객체·대화 문맥을 프롬프트에 반영하는지(더 이상 무맥락 고정 프롬프트가 아님)
- 첫 질문 vs 다음 질문을 문맥으로 구분하는지
- 난이도별 말투 지침을 덧붙이는지
- 계약 응답을 조립하는지(promptVersion이 placeholder가 아님)
를 검증한다.
"""

from __future__ import annotations

import types
import unittest
from unittest import mock

import llm_client
import question_service
from internal_contracts import (
    BoundingBox,
    DetectedObject,
    QuestionRequest,
    RecentMessage,
)


def _fake_response(text: str, *, model: str = "gpt-4o-mini-2024-07-18"):
    message = types.SimpleNamespace(content=text)
    choice = types.SimpleNamespace(message=message)
    return types.SimpleNamespace(choices=[choice], model=model)


def _mock_client(capture: dict, *, reply: str = "이 집에는 누가 살고 있어?"):
    def fake_create(*, model, messages, **_kwargs):
        capture["messages"] = messages
        capture["system"] = messages[0]["content"]
        return _fake_response(reply)

    client = mock.Mock()
    client.chat.completions.create.side_effect = fake_create
    # question_service는 get_client().with_options(...)로 옵션만 덧씌운다 — 같은 클라이언트 반환.
    client.with_options.return_value = client
    return client


def _detected(object_code="HOUSE", object_name="집전체", confidence=0.95):
    return DetectedObject(
        object_code=object_code,
        object_name=object_name,
        confidence=confidence,
        bounding_box=BoundingBox(x=0.1, y=0.1, width=0.4, height=0.4),
    )


def _request(**overrides) -> QuestionRequest:
    base = {
        "conversation_id": 1,
        "drawing_session_id": 2,
        "child_age": 6,
        "difficulty": "PRESCHOOL",
        "allowed_response_modes": ["VOICE"],
        "current_question_count": 0,
        "max_question_count": 5,
        "detected_objects": [_detected()],
        "recent_messages": [],
        "safety_rule_version": "safety-2026-07",
    }
    base.update(overrides)
    return QuestionRequest(**base)


class BuildMessagesTest(unittest.TestCase):
    def test_first_question_uses_detected_objects_context(self):
        system = question_service._build_messages(_request())[0]["content"]
        self.assertIn("집전체", system)  # 탐지 객체가 그림 분석 근거로 들어감
        # 예전 고정 문구는 더 이상 쓰지 않는다(첫 질문 고정 현상 제거).
        self.assertNotIn("아이가 방금 그림을 그렸어요. 첫 질문을 해주세요", system)

    def test_first_question_without_objects_uses_placeholder(self):
        system = question_service._build_messages(_request(detected_objects=[]))[0][
            "content"
        ]
        self.assertIn(llm_client.NO_ANALYSIS, system)

    def test_difficulty_rules_block_is_appended(self):
        system = question_service._build_messages(_request(difficulty="PRESCHOOL"))[0][
            "content"
        ]
        self.assertIn("[연령별 말하기 규칙]", system)
        rule = question_service._DIFFICULTY_RULES["PRESCHOOL"]
        self.assertIn(rule["length"], system)
        self.assertIn(rule["vocabulary"], system)
        self.assertIn(rule["tone"], system)

    def test_each_difficulty_injects_its_own_rules(self):
        for difficulty, rule in question_service._DIFFICULTY_RULES.items():
            with self.subTest(difficulty=difficulty):
                system = question_service._build_messages(_request(difficulty=difficulty))[
                    0
                ]["content"]
                self.assertIn(rule["length"], system)
                self.assertIn(rule["tone"], system)

    def test_unknown_difficulty_falls_back_to_lower_elementary(self):
        # 계약상 검증되지만 방어적으로 — 알 수 없는 값이면 저학년 규칙을 쓴다.
        # _difficulty_guidance는 .difficulty만 읽으므로 가짜 객체로 경계 조건을 검증한다.
        fake = types.SimpleNamespace(difficulty="UNKNOWN_LEVEL")
        guidance = question_service._difficulty_guidance(fake)
        self.assertIn(
            question_service._DIFFICULTY_RULES["LOWER_ELEMENTARY"]["length"], guidance
        )

    def test_internal_contract_has_no_child_name(self):
        # 개인정보 최소화 — 이름 슬롯은 항상 "너"(대체 문구)로 채워진다.
        system = question_service._build_messages(_request())[0]["content"]
        self.assertIn(llm_client.NO_CHILD_NAME, system)

    def test_followup_uses_last_child_utterance_and_history(self):
        req = _request(
            recent_messages=[
                RecentMessage(sender_type="AI", message_type="QUESTION", text="이 집에는 누가 살아?"),
                RecentMessage(sender_type="CHILD", message_type="VOICE_ANSWER", text="엄마랑 나 살아."),
            ]
        )
        system = question_service._build_messages(req)[0]["content"]
        self.assertIn("엄마랑 나 살아.", system)  # 마지막 아이 발화
        self.assertIn("이 집에는 누가 살아?", system)  # 이전 이력


class GenerateTest(unittest.TestCase):
    def test_generate_builds_context_based_contract_response(self):
        capture: dict = {}
        client = _mock_client(capture, reply="이 집은 어떤 집이야?")
        with mock.patch.object(question_service, "get_client", return_value=client):
            resp = question_service.generate(_request(), "req-1")

        self.assertEqual(resp.question_text, "이 집은 어떤 집이야?")
        # 첫 질문(아이 발화 없음) + 탐지 객체 있음 → OBJECT_DESCRIPTION
        self.assertEqual(resp.question_purpose, "OBJECT_DESCRIPTION")
        # placeholder 버전이 아니라 실제 프롬프트 버전을 쓴다.
        self.assertEqual(resp.prompt_version, llm_client.PROMPT_VERSION)
        self.assertNotEqual(resp.prompt_version, "placeholder-0")
        self.assertEqual(resp.safety_result.status, "PASSED")
        # 프롬프트에 탐지 객체 문맥이 실렸는지
        self.assertIn("집전체", capture["system"])

    def test_generate_options_null_when_option_not_allowed(self):
        capture: dict = {}
        client = _mock_client(capture, reply="이 집은 어떤 집이야?")
        with mock.patch.object(question_service, "get_client", return_value=client):
            resp = question_service.generate(
                _request(allowed_response_modes=["VOICE"]), "req-1"
            )
        # OPTION 비허용 → options는 null이어야 계약 통과
        self.assertIsNone(resp.options)


if __name__ == "__main__":
    unittest.main()

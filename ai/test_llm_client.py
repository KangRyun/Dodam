"""llm_client 단위 테스트 — GMS 호출을 가짜로 대체해 대화 프롬프트 조립·안전 필터만 검증 (S15P11B209-181).

draft 대화 경로(first_question/next_question)의 품질 동작을 회귀로 고정한다:
- 그림 분석 결과·아이 발화·대화 이력이 프롬프트에 근거로 들어가는지
- 이름 규칙(이름 모를 때 대체 문구)·무분석 시 대체 문구·연령대 주입
- 생성 답변이 answer_check로 정화·차단되는지(TTS 안전·진단 표현 차단)

실제 네트워크·모델 없이 돈다(get_client monkeypatch). 프롬프트 '문구'가 아니라 '문맥이
들어갔는지'를 확인해, 프롬프트 문장을 다듬어도 깨지지 않게 한다.
"""

from __future__ import annotations

import types
import unittest
from unittest import mock

import answer_check
import llm_client


def _fake_response(text: str):
    message = types.SimpleNamespace(content=text)
    choice = types.SimpleNamespace(message=message)
    return types.SimpleNamespace(choices=[choice])


def _mock_client(capture: dict, *, reply: str = "이 집에는 누가 살고 있어?"):
    """create 호출 인자를 capture에 담고 정해진 답변을 돌려주는 가짜 GMS 클라이언트."""

    def fake_create(*, model, messages, **_kwargs):
        capture["model"] = model
        capture["messages"] = messages
        capture["system"] = messages[0]["content"]
        return _fake_response(reply)

    client = mock.Mock()
    client.chat.completions.create.side_effect = fake_create
    return client


class FirstQuestionTest(unittest.TestCase):
    def _run(self, *, reply="이 집에는 누가 살고 있어?", **kwargs) -> tuple[str, dict]:
        capture: dict = {}
        with mock.patch.object(
            llm_client, "get_client", return_value=_mock_client(capture, reply=reply)
        ):
            out = llm_client.first_question(**kwargs)
        return out, capture

    def test_drawing_analysis_injected_into_prompt(self):
        _, cap = self._run(drawing_analysis="집 1개(가운데, 큼), 나무 1개(왼쪽)")
        self.assertIn("집 1개(가운데, 큼)", cap["system"])

    def test_missing_analysis_uses_placeholder(self):
        # 분석이 없으면 프롬프트가 "뭘 그렸어?"로 유도되도록 대체 문구가 들어간다.
        _, cap = self._run(drawing_analysis=None)
        self.assertIn(llm_client.NO_ANALYSIS, cap["system"])

    def test_known_child_name_injected(self):
        _, cap = self._run(drawing_analysis="집 1개", child_name="지우")
        self.assertIn("지우", cap["system"])

    def test_unknown_child_name_uses_placeholder(self):
        # 이름을 모르면 "너"로 부르도록 대체 문구가 들어간다(아이를 '도담'이라 부르지 않게).
        _, cap = self._run(drawing_analysis="집 1개", child_name=None)
        self.assertIn(llm_client.NO_CHILD_NAME, cap["system"])

    def test_age_band_injected(self):
        _, cap = self._run(drawing_analysis="집 1개", age_band="8~10")
        self.assertIn("8~10", cap["system"])

    def test_guardrails_included_in_prompt(self):
        # 진단 금지 가드레일이 시스템 프롬프트에 함께 실린다.
        _, cap = self._run(drawing_analysis="집 1개")
        self.assertIn("진단", cap["system"])

    def test_output_is_tts_safe_sanitized(self):
        out, _ = self._run(reply="우와 멋진 집이네! 누가 살아? 😊")
        self.assertEqual(out, "우와 멋진 집이네! 누가 살아?")

    def test_diagnosis_output_is_blocked(self):
        # 프롬프트 가드레일이 뚫려도 answer_check가 마지막 방어선으로 차단한다.
        out, _ = self._run(reply="이 그림은 불안을 의미해요.")
        self.assertEqual(out, answer_check.FALLBACK_QUESTION)


class NextQuestionTest(unittest.TestCase):
    def _run(self, child_utterance="이건 우리 집이야.", *, reply="누구랑 같이 살아?", **kwargs):
        capture: dict = {}
        with mock.patch.object(
            llm_client, "get_client", return_value=_mock_client(capture, reply=reply)
        ):
            out = llm_client.next_question(child_utterance, **kwargs)
        return out, capture

    def test_child_utterance_injected_into_prompt(self):
        _, cap = self._run("이건 우리 집이야. 엄마랑 나 있어.")
        self.assertIn("이건 우리 집이야. 엄마랑 나 있어.", cap["system"])

    def test_history_is_formatted_with_speaker_labels(self):
        # role user=아이, assistant=도담 으로 라벨링돼 대화 흐름이 프롬프트에 들어간다.
        history = [
            {"role": "assistant", "content": "이 집에는 누가 살아?"},
            {"role": "user", "content": "엄마랑 나."},
        ]
        _, cap = self._run("응 맞아", history=history)
        self.assertIn(f"{llm_client.CHARACTER_NAME}: 이 집에는 누가 살아?", cap["system"])
        self.assertIn("아이: 엄마랑 나.", cap["system"])

    def test_drawing_analysis_and_name_rules_apply(self):
        _, cap = self._run("응", drawing_analysis="나무 1개", child_name=None)
        self.assertIn("나무 1개", cap["system"])
        self.assertIn(llm_client.NO_CHILD_NAME, cap["system"])

    def test_empty_history_shows_placeholder(self):
        _, cap = self._run("안녕", history=None)
        self.assertIn("아직 나눈 대화가 없어요", cap["system"])

    def test_output_is_sanitized_and_diagnosis_blocked(self):
        safe, _ = self._run(reply="**우와** 멋지다! 🌳 뭐가 더 있어?")
        self.assertEqual(safe, "우와 멋지다! 뭐가 더 있어?")
        blocked, _ = self._run(reply="이런 아이는 외로운 성향이 있어요.")
        self.assertEqual(blocked, answer_check.FALLBACK_QUESTION)


class FormatHistoryTest(unittest.TestCase):
    def test_none_history_returns_placeholder(self):
        self.assertIn("아직 나눈 대화가 없어요", llm_client._format_history(None))

    def test_maps_roles_to_speakers_in_order(self):
        formatted = llm_client._format_history(
            [
                {"role": "assistant", "content": "안녕!"},
                {"role": "user", "content": "안녕 도담아."},
            ]
        )
        self.assertEqual(formatted, f"{llm_client.CHARACTER_NAME}: 안녕!\n아이: 안녕 도담아.")


if __name__ == "__main__":
    unittest.main()

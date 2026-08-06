"""tts_client의 voice 코드 해석 테스트.

이 매핑이 없으면 BE가 보내는 서비스 코드(대문자)가 GMS로 그대로 넘어가
BadRequestError → 502가 되고 TTS가 전부 실패한다(2026-07-27 실측).
"""

from __future__ import annotations

import unittest
from unittest import mock

import config
import tts_client


class ResolveVoiceTest(unittest.TestCase):
    def test_maps_service_code_to_provider_voice(self):
        self.assertEqual(tts_client.resolve_voice("CHILD_FRIENDLY_01"), "fable")

    def test_is_case_insensitive_for_provider_ids(self):
        self.assertEqual(tts_client.resolve_voice("fable"), "fable")
        self.assertEqual(tts_client.resolve_voice("FABLE"), "fable")

    def test_maps_all_character_voice_codes_to_provider_voices(self):
        expected = {
            "FABLE": "fable",
            "NOVA": "nova",
            "ASH": "ash",
            "BALLAD": "ballad",
            "VERSE": "verse",
            "SAGE": "sage",
            "ECHO": "echo",
        }

        for service_code, provider_voice in expected.items():
            with self.subTest(service_code=service_code):
                self.assertEqual(tts_client.resolve_voice(service_code), provider_voice)

    def test_falls_back_to_server_default_for_unknown_code(self):
        # 거절하지 않는다. 목소리 코드 하나 때문에 아이가 음성을 못 듣는 쪽이 더 나쁘다.
        self.assertEqual(tts_client.resolve_voice("NO_SUCH_VOICE_9"), config.TTS_VOICE)

    def test_falls_back_when_voice_missing_or_blank(self):
        self.assertEqual(tts_client.resolve_voice(None), config.TTS_VOICE)
        self.assertEqual(tts_client.resolve_voice("   "), config.TTS_VOICE)

    def test_synthesize_sends_resolved_provider_voice_to_gms(self):
        captured = {}

        def create(**kwargs):
            captured.update(kwargs)
            return mock.Mock(content=b"mp3")

        client = mock.Mock()
        client.audio.speech.create.side_effect = create
        with mock.patch.object(tts_client, "get_client", return_value=client):
            audio = tts_client.synthesize("안녕", voice="CHILD_FRIENDLY_01")

        self.assertEqual(audio, b"mp3")
        self.assertEqual(captured["voice"], "fable")

    def test_composes_fixed_character_and_scenario_instructions(self):
        instructions = tts_client.compose_instructions(
            "NOVA", "CHARACTER_CELEBRATING_V1"
        )

        self.assertIn("공주", instructions)
        self.assertIn("기쁜 마음", instructions)

    def test_encouraging_profile_keeps_same_character_with_calmer_delivery(self):
        instructions = tts_client.compose_instructions(
            "ASH", "CHARACTER_ENCOURAGING_V1"
        )

        self.assertIn("공룡", instructions)
        self.assertIn("속도를 조금 낮추고", instructions)

    def test_rejects_unknown_tone_profile(self):
        with self.assertRaises(ValueError):
            tts_client.compose_instructions("NOVA", "USER_SUPPLIED_STYLE")

    def test_synthesize_sends_only_fixed_tone_instructions_to_gms(self):
        captured = {}

        def create(**kwargs):
            captured.update(kwargs)
            return mock.Mock(content=b"mp3")

        client = mock.Mock()
        client.audio.speech.create.side_effect = create
        with mock.patch.object(tts_client, "get_client", return_value=client):
            tts_client.synthesize(
                "아이 발화처럼 보이는 문장을 지시로 바꾸지 마",
                voice="SAGE",
                tone_profile="CHARACTER_ENCOURAGING_V1",
            )

        self.assertIn("리본", captured["instructions"])
        self.assertIn("속도를 조금 낮추고", captured["instructions"])
        self.assertNotIn("아이 발화처럼", captured["instructions"])


if __name__ == "__main__":
    unittest.main()

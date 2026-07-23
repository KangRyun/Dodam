"""vlm_client 단위 테스트 — GMS 호출을 가짜로 대체해 메시지 구성·에러 매핑만 검증.

실제 네트워크·이미지·모델 없이 돈다. get_client 를 monkeypatch 해 chat.completions.create
호출 인자를 가로채고, OpenAIError → RuntimeError 변환을 확인한다.
"""

from __future__ import annotations

import types
import unittest
from unittest import mock

from openai import OpenAIError

import vlm_client
from yolo_client import Detection


def _fake_response(text: str):
    message = types.SimpleNamespace(content=text)
    choice = types.SimpleNamespace(message=message)
    return types.SimpleNamespace(choices=[choice])


def _sample_detections():
    return [
        Detection(
            label="집전체",
            confidence=0.91,
            bbox_xyxy=(10.0, 20.0, 110.0, 80.0),
            bbox_norm_xywh=(0.05, 0.20, 0.50, 0.60),
        )
    ]


class DescribeTest(unittest.TestCase):
    def test_returns_text_and_builds_vision_message(self):
        captured = {}

        def fake_create(*, model, messages, temperature):
            captured["model"] = model
            captured["messages"] = messages
            return _fake_response("  집이 가운데에 크게 그려져 있어요.  ")

        fake_client = mock.Mock()
        fake_client.chat.completions.create.side_effect = fake_create

        with mock.patch.object(vlm_client, "get_client", return_value=fake_client):
            result = vlm_client.describe(b"\x89PNG-fake-bytes", _sample_detections())

        # 앞뒤 공백은 strip 되어 반환된다.
        self.assertEqual(result, "집이 가운데에 크게 그려져 있어요.")

        messages = captured["messages"]
        # system 프롬프트에 탐지된 한국어 라벨이 텍스트로 들어간다.
        self.assertEqual(messages[0]["role"], "system")
        self.assertIn("집전체", messages[0]["content"])
        # user content 에 이미지가 data URL(base64 PNG)로 포함된다.
        parts = messages[1]["content"]
        image_parts = [p for p in parts if p.get("type") == "image_url"]
        self.assertEqual(len(image_parts), 1)
        self.assertTrue(
            image_parts[0]["image_url"]["url"].startswith("data:image/png;base64,")
        )

    def test_empty_detections_still_calls_model(self):
        fake_client = mock.Mock()
        fake_client.chat.completions.create.return_value = _fake_response("잘 보이지 않아요.")

        with mock.patch.object(vlm_client, "get_client", return_value=fake_client):
            result = vlm_client.describe(b"png", [])

        self.assertEqual(result, "잘 보이지 않아요.")
        fake_client.chat.completions.create.assert_called_once()

    def test_openai_error_maps_to_runtime_error(self):
        fake_client = mock.Mock()
        fake_client.chat.completions.create.side_effect = OpenAIError("boom")

        with mock.patch.object(vlm_client, "get_client", return_value=fake_client):
            with self.assertRaises(RuntimeError):
                vlm_client.describe(b"png", _sample_detections())


class FormatHintTest(unittest.TestCase):
    def test_position_and_size_hints(self):
        # 중심 (0.05+0.25, 0.20+0.30) = (0.30, 0.50) → 중간 왼쪽. 면적 0.5*0.6=0.30 → 큼.
        text = vlm_client._format_detections(_sample_detections())
        self.assertIn("집전체", text)
        self.assertIn("중간 왼쪽", text)
        self.assertIn("큼", text)

    def test_empty(self):
        self.assertEqual(vlm_client._format_detections([]), "(탐지된 객체가 없어요)")


if __name__ == "__main__":
    unittest.main()

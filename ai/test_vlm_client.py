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


class ActivityPromptSplitTest(unittest.TestCase):
    """서술 프롬프트 HTP/그림일기 분리 — 활동에 맞는 파일이 실리는지."""

    def _system_for(self, activity_type):
        captured = {}

        def fake_create(*, model, messages, temperature):
            captured["messages"] = messages
            return _fake_response("서술")

        fake_client = mock.Mock()
        fake_client.chat.completions.create.side_effect = fake_create
        with mock.patch.object(vlm_client, "get_client", return_value=fake_client):
            vlm_client.describe(
                b"\x89PNG-fake-bytes",
                _sample_detections(),
                activity_type=activity_type,
            )
        return captured["messages"][0]["content"]

    def test_htp_uses_htp_prompt(self):
        system = self._system_for("HTP")
        self.assertIn("HTP(집·나무·사람)", system)
        self.assertNotIn("그림일기", system)

    def test_art_diary_uses_diary_prompt(self):
        system = self._system_for("ART_DIARY")
        self.assertIn("그림일기", system)
        self.assertNotIn("HTP(집·나무·사람)", system)
        # 자유 그림은 탐지 목록이 '힌트'다 — 목록에 고정하면 sketch 미탐지 때 서술이 죽는다.
        self.assertIn("목록에 없더라도 이미지에서 분명히 보이는 것은 묘사해도 좋아", system)

    def test_unknown_activity_falls_back_to_htp(self):
        # 활동 유형을 안 넘기는 draft 경로는 기본 HTP 가중치를 쓰므로 HTP 서술이 맞다.
        self.assertIn("HTP(집·나무·사람)", self._system_for(None))

    def test_both_prompts_require_visible_detail_for_conversation(self):
        """대화 품질의 원천 — 색·표정·위치 세부를 서술이 내야 질문이 구체해진다.

        이 세부는 리포트 RAG 질의(report_client._build_rag_query)의 본문이기도 하다.
        """
        for activity in ("HTP", "ART_DIARY"):
            system = self._system_for(activity)
            self.assertIn("색·표정 모양·방향·개수·서로의 위치 관계", system)
            self.assertIn("한두 가지는 꼭 넣어", system)

    def test_both_prompts_forbid_mind_reading(self):
        for activity in ("HTP", "ART_DIARY"):
            system = self._system_for(activity)
            self.assertIn("마음·기분을 짐작해 쓰지 마", system)


class EncodeForUploadTest(unittest.TestCase):
    """전송 전 축소 — GMS 페이로드 한도(약 100KB base64) 안에 드는지 실제 인코딩으로 검증.

    describe 테스트는 GMS를 모킹해 축소 경로를 타지 않으므로, 여기서 실제 cv2 인코딩을 돌려
    '실그림 크기 PNG가 한도를 넘어 400을 내던' 회귀를 잡는다.
    """

    def _big_png(self, side: int) -> bytes:
        import cv2
        import numpy as np

        # 균일 이미지는 비현실적으로 잘 압축되므로 난수로 최악 압축률에 가깝게 만든다.
        rng = np.random.default_rng(0)
        noise = rng.integers(0, 256, size=(side, side, 3), dtype=np.uint8)
        ok, buf = cv2.imencode(".png", noise)
        self.assertTrue(ok)
        return buf.tobytes()

    def test_large_image_is_shrunk_under_limit(self):
        mime, b64 = vlm_client._encode_for_upload(self._big_png(1280))
        self.assertEqual(mime, "image/jpeg")
        self.assertLessEqual(len(b64) / 1024, vlm_client._UPLOAD_MAX_B64_KB)

    def test_undecodable_bytes_fall_back_to_png(self):
        # 디코드 불가 입력(가짜 바이트)은 원본 PNG로 그대로 — 축소는 입력 검증이 아니다.
        mime, b64 = vlm_client._encode_for_upload(b"\x89PNG-not-real")
        self.assertEqual(mime, "image/png")
        self.assertTrue(b64)


class FormatHintTest(unittest.TestCase):
    def test_position_and_size_hints(self):
        # 중심 (0.05+0.25, 0.20+0.30) = (0.30, 0.50) → 중간 왼쪽. 면적 0.5*0.6=0.30 → 큼.
        text = vlm_client._format_detections(_sample_detections())
        self.assertIn("집전체", text)
        self.assertIn("중간 왼쪽", text)
        self.assertIn("큼", text)

    def test_empty(self):
        self.assertEqual(vlm_client._format_detections([]), "(탐지된 객체가 없어요)")

    def test_uses_display_name_when_resolver_given(self):
        # 서술 프롬프트에도 내부 클래스명이 아니라 표시명이 들어가야 한다(S15P11B209-711).
        import htp_labels

        detections = [
            Detection(
                label="기둥",
                confidence=0.8,
                bbox_xyxy=(0.0, 0.0, 1.0, 1.0),
                bbox_norm_xywh=(0.4, 0.3, 0.1, 0.4),
            )
        ]
        text = vlm_client._format_detections(detections, htp_labels.display_name_of)
        self.assertIn("나무 줄기", text)
        self.assertNotIn("기둥", text)


if __name__ == "__main__":
    unittest.main()

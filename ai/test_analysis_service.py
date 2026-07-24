"""종합 분석 계약·계산부 단위 테스트 (S15P11B209-398).

YOLO 가중치·GMS 없이 검증할 수 있는 것만 고정한다: 정본 §19.3/§19.4 계약 형태,
htp_labels 계약 라벨 매핑, 못 쓴 입력 표기, 그리고 아이 발화가 repr로 새지 않는 가드레일.

실제 추론이 필요한 analyze() 전 구간은 여기서 다루지 않는다 — 가중치와 GMS 키가 있는
환경에서 별도로 확인한다.
"""

from __future__ import annotations

import unittest
from dataclasses import dataclass

import analysis_service as svc
import internal_contracts as contracts

try:  # cv2는 headless 설치가 깨지면 import부터 실패한다(S15P11B209-397).
    import cv2
    import numpy as np

    _CV2_AVAILABLE = True
except Exception:  # pragma: no cover - 환경 의존
    _CV2_AVAILABLE = False


@dataclass(frozen=True)
class _FakeDetection:
    """yolo_client.Detection 중 이 서비스가 쓰는 필드만 가진 가짜."""

    label: str
    confidence: float
    bbox_xyxy: tuple
    bbox_norm_xywh: tuple


def _det(label: str, x: float, y: float, w: float, h: float, conf: float = 0.9):
    return _FakeDetection(label, conf, (0, 0, 1, 1), (x, y, w, h))


# ── 정본 §19.3 요청 예시 (명세 원문) ────────────────────────────
SPEC_REQUEST = {
    "analysisId": 701,
    "drawingSessionId": 100,
    "analysisType": "FINAL",
    "triggerReason": "ACTIVITY_COMPLETE",
    "childContext": {
        "age": 7,
        "ageGroup": "LOWER_ELEMENTARY",
        "questionDifficulty": "LOWER_ELEMENTARY",
    },
    "drawing": {
        "drawingAssetId": 502,
        "signedUrl": "https://signed.example.com/assets/502",
        "mimeType": "image/png",
        "width": 1920,
        "height": 1080,
        "checksumSha256": "sha256-value",
    },
    "behavior": {
        "strokeBatchUrls": [],
        "summary": {
            "drawingDurationMs": 600000,
            "pauseCount": 4,
            "undoCount": 2,
            "eraseCount": 3,
            "pressureAvailable": False,
        },
    },
    "conversation": {
        "messages": [
            {
                "messageId": 803,
                "senderType": "AI",
                "messageType": "QUESTION",
                "text": "이 사람은 어떤 기분인 것 같아?",
            },
            {
                "messageId": 804,
                "senderType": "CHILD",
                "messageType": "VOICE_ANSWER",
                "text": "친구랑 있어서 좋아",
            },
        ]
    },
    "reflection": {
        "selectedEmotions": ["HAPPY", "CALM"],
        "expressedEmotionText": "다 같이 있어서 좋았어",
    },
    "rag": {
        "knowledgeBaseVersion": "2026.07",
        "allowedSourceTypes": ["PEER_REVIEWED_PAPER"],
        "maxReferences": 5,
    },
}


class RequestContractTest(unittest.TestCase):
    """§19.3 요청이 명세 예시 그대로 파싱되는지."""

    def test_spec_example_parses(self):
        req = contracts.AnalysisRequest.model_validate(SPEC_REQUEST)
        self.assertEqual(req.analysis_id, 701)
        self.assertEqual(req.analysis_type, "FINAL")
        self.assertEqual(req.drawing.checksum_sha256, "sha256-value")
        self.assertEqual(req.reflection.selected_emotions, ["HAPPY", "CALM"])
        self.assertFalse(req.behavior.summary.pressure_available)

    def test_rejects_value_outside_enum(self):
        """§4 Enum 밖의 analysisType은 거부한다(구 계약의 OBJECT_DETECTION 포함)."""
        for bad in ("OBJECT_DETECTION", "ACTIVITY_REPORT", "SUCCEEDED"):
            with self.subTest(analysisType=bad):
                with self.assertRaises(Exception):
                    contracts.AnalysisRequest.model_validate(
                        {**SPEC_REQUEST, "analysisType": bad}
                    )

    def test_child_utterance_not_in_repr(self):
        """아이 발화·signedUrl은 repr에 실리지 않는다(로그 유출 차단, 가드레일)."""
        text = repr(contracts.AnalysisRequest.model_validate(SPEC_REQUEST))
        for secret in ("친구랑 있어서 좋아", "다 같이 있어서 좋았어", "signed.example.com"):
            self.assertNotIn(secret, text)


class ResponseContractTest(unittest.TestCase):
    """§19.4 응답 형태 — BE(Jackson)와 붙으려면 camelCase가 정확해야 한다."""

    def _response(self):
        return contracts.AnalysisResponse(
            analysis_id=701,
            status="PARTIAL_SUCCESS",
            model_info=contracts.ModelInfo(
                object_detection=contracts.ModelRef(name="yolo", version="1.0.0"),
                vision=contracts.ModelRef(name="vision-model", version="1.0.0"),
            ),
            detected_objects=[
                contracts.AnalysisDetectedObject(
                    object_code="PERSON",
                    object_name="사람전체",
                    confidence=0.92,
                    bounding_box=contracts.BoundingBox(
                        x=0.15, y=0.20, width=0.25, height=0.50
                    ),
                    area_ratio=0.125,
                    detection_order=1,
                )
            ],
            observation_draft=contracts.AnalysisObservationDraft(
                overall_summary="관찰 초안", disclaimer="진단이 아닙니다."
            ),
            unused_inputs=[
                contracts.UnusedInput(
                    source_type="PRESSURE", reason_code="DEVICE_NOT_SUPPORTED"
                )
            ],
            processing_time_ms=3840,
        )

    def test_top_level_fields(self):
        dumped = self._response().model_dump(by_alias=True)
        self.assertEqual(
            set(dumped),
            {
                "analysisId",
                "status",
                "modelInfo",
                "detectedObjects",
                "visualFeatures",
                "behaviorFeatures",
                "conversationSummary",
                "observationDraft",
                "evidenceReferences",
                "unusedInputs",
                "warnings",
                "processingTimeMs",
            },
        )

    def test_nested_camel_case(self):
        dumped = self._response().model_dump(by_alias=True)
        self.assertEqual(
            set(dumped["detectedObjects"][0]),
            {
                "objectCode",
                "objectName",
                "confidence",
                "boundingBox",
                "areaRatio",
                "detectionOrder",
            },
        )
        self.assertEqual(
            set(dumped["unusedInputs"][0]),
            {"sourceType", "reasonCode", "reasonDetail", "retryable"},
        )

    def test_observation_draft_defaults_to_ai_draft(self):
        """AI가 만든 초안은 항상 AI_DRAFT이고 전문가 검토가 필요하다(§2.4)."""
        dumped = self._response().model_dump(by_alias=True)
        self.assertEqual(dumped["observationDraft"]["status"], "AI_DRAFT")
        self.assertTrue(dumped["observationDraft"]["expertReviewRequired"])


class DetectedObjectTest(unittest.TestCase):
    """objectCode는 htp_labels 계약 표를 그대로 쓴다(별도 매핑을 두지 않는다)."""

    def test_uses_contract_labels(self):
        objects, warnings = svc._to_detected_objects(
            [_det("사람전체", 0.15, 0.20, 0.25, 0.50), _det("지붕", 0.1, 0.1, 0.2, 0.2)]
        )
        self.assertEqual([o.object_code for o in objects], ["PERSON", "HOUSE_ROOF"])
        self.assertEqual([o.object_name for o in objects], ["사람전체", "지붕"])
        self.assertEqual([o.detection_order for o in objects], [1, 2])
        self.assertAlmostEqual(objects[0].area_ratio, 0.125)
        self.assertNotIn("OBJECT_CODE_UNMAPPED", warnings)

    def test_unmapped_label_is_surfaced(self):
        """표에 없는 클래스명은 조용히 통과시키지 않고 경고로 드러낸다."""
        objects, warnings = svc._to_detected_objects([_det("표에없는이름", 0, 0, 0.1, 0.1)])
        self.assertEqual(objects[0].object_code, "UNKNOWN")
        self.assertIn("OBJECT_CODE_UNMAPPED", warnings)


class BehaviorFeatureTest(unittest.TestCase):
    def test_pressure_stays_null_when_unsupported(self):
        """필압 미지원이면 0으로 채우지 않고 null을 유지한다(§25 계약 테스트)."""
        features, unused, warnings = svc._behavior_features(
            contracts.BehaviorInput(
                strokeBatchUrls=["s3://batch/1"],
                summary=contracts.BehaviorSummary(
                    drawingDurationMs=600000, pauseCount=4, pressureAvailable=False
                ),
            )
        )
        self.assertIsNone(features["pressureMean"])
        self.assertIsNone(features["pressureMax"])
        self.assertFalse(features["pressureAvailable"])
        self.assertEqual(features["drawingDurationMs"], 600000)
        self.assertIn("PRESSURE_DATA_UNAVAILABLE", warnings)
        self.assertIn("STROKE_BATCH_NOT_ANALYZED", warnings)
        self.assertIn("DEVICE_NOT_SUPPORTED", {u.reason_code for u in unused})

    def test_absent_behavior_is_reported(self):
        features, unused, _ = svc._behavior_features(None)
        self.assertEqual(features, {})
        self.assertEqual(unused[0].reason_code, "BEHAVIOR_SUMMARY_ABSENT")


class ConversationSummaryTest(unittest.TestCase):
    def _conversation(self):
        message = contracts.ConversationMessage
        return contracts.ConversationInput(
            messages=[
                message(messageId=1, senderType="AI", messageType="QUESTION", text="누구야?"),
                message(messageId=2, senderType="CHILD", messageType="VOICE_ANSWER", text="엄마야"),
                message(messageId=3, senderType="AI", messageType="QUESTION", text="어디야?"),
                message(messageId=4, senderType="CHILD", messageType="VOICE_ANSWER", text="   "),
                message(messageId=5, senderType="AI", messageType="QUESTION", text="기분은?"),
            ]
        )

    def test_counts_and_actual_utterance(self):
        summary, unused, warnings = svc._conversation_summary(self._conversation())
        self.assertEqual(summary.question_count, 3)
        self.assertEqual(summary.response_count, 2)
        self.assertEqual(summary.skipped_question_count, 1)
        self.assertEqual(summary.unrecognized_speech_count, 1)
        # 대표값은 '실제' 발화여야 한다 — AI가 지어낸 문장이 아니다.
        self.assertEqual(summary.representative_utterance, "엄마야")
        self.assertIn("SPEECH_NOT_RECOGNIZED", warnings)
        self.assertIn("TRANSCRIPTION_EMPTY", {u.reason_code for u in unused})

    def test_does_not_fabricate_summary_text(self):
        """요약 생성이 없으므로 summaryText는 null이다 — 빈 문자열과 의미가 다르다(§3.3)."""
        summary, _, _ = svc._conversation_summary(self._conversation())
        self.assertIsNone(summary.summary_text)

    def test_utterance_not_in_repr(self):
        summary, _, _ = svc._conversation_summary(self._conversation())
        self.assertNotIn("엄마야", repr(summary))

    def test_absent_conversation_is_reported(self):
        summary, unused, _ = svc._conversation_summary(None)
        self.assertIsNone(summary)
        self.assertEqual(unused[0].reason_code, "CONVERSATION_ABSENT")


@unittest.skipUnless(_CV2_AVAILABLE, "cv2 미가용 환경 (S15P11B209-397 참고)")
class VisualFeatureTest(unittest.TestCase):
    def _png(self):
        canvas = np.full((100, 200, 3), 255, dtype=np.uint8)
        cv2.rectangle(canvas, (10, 10), (60, 60), (0, 0, 255), -1)
        ok, buf = cv2.imencode(".png", canvas)
        self.assertTrue(ok)
        return buf.tobytes()

    def test_objective_metrics_only(self):
        detections = [_det("사람전체", 0.15, 0.20, 0.25, 0.50), _det("집전체", 0.5, 0.1, 0.3, 0.4)]
        features, warnings = svc._visual_features(self._png(), detections)
        self.assertEqual(features["imageWidth"], 200)
        self.assertEqual(features["imageHeight"], 100)
        self.assertGreater(features["inkRatio"], 0.0)
        self.assertLess(features["inkRatio"], 1.0)
        self.assertAlmostEqual(features["occupancyRatio"], 0.245, places=6)
        # 선 굵기는 획 벡터 없이 추정하지 않는다.
        self.assertIsNone(features["strokeThickness"])
        self.assertEqual(warnings, [])

    def test_saturated_occupancy_is_flagged(self):
        big = [_det("집전체", 0.0, 0.0, 1.0, 1.0) for _ in range(3)]
        features, warnings = svc._visual_features(self._png(), big)
        self.assertEqual(features["occupancyRatio"], 1.0)
        self.assertIn("OCCUPANCY_RATIO_CLAMPED", warnings)


class InternalHealthTest(unittest.TestCase):
    """§19.8 health 응답 형태. 소비자(BE 운영 모니터링)가 붙기 전에 고정한다."""

    def _payload(self):
        import main

        return main.internal_health()

    def test_spec_shape(self):
        payload = self._payload()
        self.assertEqual(payload["status"], "UP")
        self.assertEqual(
            set(payload["models"]),
            {"objectDetection", "vision", "language", "stt", "tts", "rag"},
        )
        self.assertIn("knowledgeBaseVersion", payload)
        self.assertTrue(payload["timestamp"].endswith("Z"))

    def test_component_values_are_spec_literals(self):
        """정본이 정의한 READY 외에는 NOT_READY만 쓴다 — 임의 값 유입 방지."""
        for name, value in self._payload()["models"].items():
            with self.subTest(component=name):
                self.assertIn(value, ("READY", "NOT_READY"))

    def test_does_not_leak_weight_path(self):
        """가중치 경로는 서버 파일 구조 힌트라 노출하지 않는다(가드레일)."""
        import json

        import config

        text = json.dumps(self._payload(), ensure_ascii=False)
        self.assertNotIn(config.YOLO_MODEL_PATH, text)
        self.assertNotIn("/", text.split('"timestamp"')[0])


if __name__ == "__main__":
    unittest.main()

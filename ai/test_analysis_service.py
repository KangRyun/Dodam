"""종합 분석 계약·계산부 단위 테스트 (S15P11B209-398).

YOLO 가중치·GMS 없이 검증할 수 있는 것만 고정한다: 정본 §19.3/§19.4 계약 형태,
htp_labels 계약 라벨 매핑, 못 쓴 입력 표기, 그리고 아이 발화가 repr로 새지 않는 가드레일.

실제 추론이 필요한 analyze() 전 구간은 여기서 다루지 않는다 — 가중치와 GMS 키가 있는
환경에서 별도로 확인한다.
"""

from __future__ import annotations

import unittest
from dataclasses import dataclass
from unittest import mock

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
    "activityType": "ART_DIARY",
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

    def test_input_method_defaults_and_backward_compat(self):
        """inputMethod(S15P11B209-762): 없거나 null·미지의 값이면 CANVAS, UPLOAD는 그대로."""
        # 필드 없음(구버전 요청) → CANVAS
        self.assertEqual(
            contracts.AnalysisRequest.model_validate(SPEC_REQUEST).drawing.input_method,
            "CANVAS",
        )
        for sent, expected in (
            ("UPLOAD", "UPLOAD"),
            ("CANVAS", "CANVAS"),
            (None, "CANVAS"),  # 명시적 null → 하위호환 CANVAS
            ("SCAN", "CANVAS"),  # 미지의 값 → 방어적으로 CANVAS
        ):
            with self.subTest(inputMethod=sent):
                req = contracts.AnalysisRequest.model_validate(
                    {**SPEC_REQUEST, "drawing": {**SPEC_REQUEST["drawing"], "inputMethod": sent}}
                )
                self.assertEqual(req.drawing.input_method, expected)

    def test_rejects_value_outside_enum(self):
        """§4 Enum 밖의 analysisType은 거부한다(구 계약의 OBJECT_DETECTION 포함)."""
        for bad in ("OBJECT_DETECTION", "ACTIVITY_REPORT", "SUCCEEDED"):
            with self.subTest(analysisType=bad):
                with self.assertRaises(Exception):
                    contracts.AnalysisRequest.model_validate(
                        {**SPEC_REQUEST, "analysisType": bad}
                    )

    def test_htp_requires_subject_and_art_diary_rejects_subject(self):
        htp = contracts.AnalysisRequest.model_validate(
            {**SPEC_REQUEST, "activityType": "HTP", "drawingSubject": "TREE"}
        )
        self.assertEqual(htp.drawing_subject, "TREE")

        with self.assertRaises(Exception):
            contracts.AnalysisRequest.model_validate(
                {**SPEC_REQUEST, "activityType": "HTP"}
            )
        with self.assertRaises(Exception):
            contracts.AnalysisRequest.model_validate(
                {
                    **SPEC_REQUEST,
                    "activityType": "ART_DIARY",
                    "drawingSubject": "PERSON",
                }
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
            [_det("사람전체", 0.15, 0.20, 0.25, 0.50), _det("지붕", 0.1, 0.1, 0.2, 0.2)],
            svc.htp_labels,
        )
        self.assertEqual([o.object_code for o in objects], ["PERSON", "HOUSE_ROOF"])
        # objectName은 내부 클래스명이 아니라 표시명이다(S15P11B209-711).
        self.assertEqual([o.object_name for o in objects], ["사람", "지붕"])
        self.assertEqual([o.detection_order for o in objects], [1, 2])
        self.assertAlmostEqual(objects[0].area_ratio, 0.125)
        self.assertNotIn("OBJECT_CODE_UNMAPPED", warnings)

    def test_unmapped_label_is_surfaced(self):
        """표에 없는 클래스명은 조용히 통과시키지 않고 경고로 드러낸다."""
        objects, warnings = svc._to_detected_objects(
            [_det("표에없는이름", 0, 0, 0.1, 0.1)], svc.htp_labels
        )
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

    def test_object_detection_is_not_ready_when_one_activity_model_is_missing(self):
        import main

        with mock.patch.object(
            main.yolo_client,
            "model_readiness",
            return_value={"htp": True, "sketch": False},
        ):
            payload = main.internal_health()

        self.assertEqual(payload["models"]["objectDetection"], "NOT_READY")


class DetectOrDegradeTest(unittest.TestCase):
    """604 fallback — 탐지 실패 시 502 대신 빈 탐지 + 경고로 degrade한다."""

    def test_returns_detection_result_on_success(self):
        with mock.patch.object(
            svc.yolo_client, "detect_and_annotate", return_value=(["d"], b"png")
        ) as detector:
            warnings: list[str] = []
            detections, annotated = svc._detect_or_degrade(
                "/x.png", b"orig", warnings, model_key="sketch"
            )
        self.assertEqual(detections, ["d"])
        self.assertEqual(annotated, b"png")
        self.assertEqual(warnings, [])
        detector.assert_called_once_with("/x.png", model_key="sketch")

    def test_degrades_to_empty_with_warning_on_failure(self):
        with mock.patch.object(
            svc.yolo_client,
            "detect_and_annotate",
            side_effect=RuntimeError("가중치 무결성 검증 실패"),
        ):
            warnings: list[str] = []
            detections, annotated = svc._detect_or_degrade(
                "/x.png", b"orig-bytes", warnings, model_key="htp"
            )
        self.assertEqual(detections, [])
        self.assertEqual(annotated, b"orig-bytes")  # 원본 이미지로 진행
        self.assertIn("OBJECT_DETECTION_UNAVAILABLE", warnings)

    def test_activity_type_selects_model_key(self):
        self.assertEqual(svc._model_key_for("HTP"), "htp")
        self.assertEqual(svc._model_key_for("ART_DIARY"), "sketch")


class ActivityDetectionFilterTest(unittest.TestCase):
    def test_htp_uses_persisted_subject_and_reports_missing_whole(self):
        warnings: list[str] = []
        kept = svc._filter_detections_for_activity(
            "HTP",
            "TREE",
            [_det("수관", 0, 0, 0.2, 0.2), _det("눈", 0, 0, 0.1, 0.1)],
            warnings,
        )

        self.assertEqual([d.label for d in kept], ["수관"])
        self.assertIn("CROSS_SUBJECT_PARTS_SUPPRESSED", warnings)
        self.assertIn("HTP_SUBJECT_NOT_DETECTED", warnings)

    def test_art_diary_does_not_apply_htp_filter(self):
        detections = [_det("집전체", 0, 0, 0.2, 0.2), _det("눈", 0, 0, 0.1, 0.1)]
        warnings: list[str] = []

        kept = svc._filter_detections_for_activity(
            "ART_DIARY", None, detections, warnings
        )

        self.assertEqual(kept, detections)
        self.assertEqual(warnings, [])


class DetectedObjectMappingTest(unittest.TestCase):
    """활동 유형별 라벨 표 선택과 표시명 (S15P11B209-711)."""

    def test_model_key_selects_the_matching_label_table(self):
        self.assertIs(svc._labels_for("htp"), svc.htp_labels)
        self.assertIs(svc._labels_for("sketch"), svc.sketch_labels)

    def test_htp_object_name_is_the_display_name(self):
        objects, warnings = svc._to_detected_objects(
            [_det("기둥", 0, 0, 0.1, 0.4)], svc.htp_labels
        )
        self.assertEqual(objects[0].object_code, "TREE_TRUNK")  # 계약 코드는 그대로
        self.assertEqual(objects[0].object_name, "나무 줄기")  # 프롬프트로 나가는 값
        self.assertEqual(warnings, [])

    def test_art_diary_classes_are_no_longer_unknown(self):
        # 영어 클래스를 HTP 표로 조회해 전부 UNKNOWN이 되던 문제(711 작업 2).
        objects, warnings = svc._to_detected_objects(
            [_det("house", 0, 0, 0.4, 0.4), _det("tree", 0.5, 0, 0.2, 0.5)],
            svc.sketch_labels,
        )
        self.assertEqual([o.object_code for o in objects], ["HOUSE", "TREE"])
        self.assertEqual([o.object_name for o in objects], ["집", "나무"])
        self.assertNotIn("OBJECT_CODE_UNMAPPED", warnings)

    def test_unmapped_class_is_still_surfaced(self):
        objects, warnings = svc._to_detected_objects(
            [_det("존재하지않는클래스", 0, 0, 0.1, 0.1)], svc.htp_labels
        )
        self.assertEqual(objects[0].object_code, "UNKNOWN")
        self.assertIn("OBJECT_CODE_UNMAPPED", warnings)


class DetectionLogTest(unittest.TestCase):
    """탐지 진단 로그 게이팅 (S15P11B209-710).

    기본(플래그 꺼짐)에서는 개수만 남기고, 명시적으로 켰을 때만 라벨·신뢰도가 남는다.
    어느 모드에서도 bbox 좌표·이미지 경로는 남지 않아야 한다(가드레일).
    """

    DETECTIONS = [
        _det("집전체", 0.1, 0.1, 0.4, 0.4, conf=0.91),
        _det("나무", 0, 0, 0.1, 0.1, conf=0.34),  # 집 그림에 남는 배경 나무(709 원인 1)
    ]

    def test_empty_detections(self):
        self.assertEqual(svc._format_detections_for_log([]), "(없음)")

    def test_only_count_when_flag_off(self):
        with mock.patch.object(svc.config, "DETECTION_LOG_DETAIL", False):
            line = svc._format_detections_for_log(self.DETECTIONS)
        self.assertEqual(line, "2건")
        self.assertNotIn("집전체", line)  # 그림 내용이 운영 기본값으로 새지 않는다

    def test_labels_logged_only_when_flag_on(self):
        with mock.patch.object(svc.config, "DETECTION_LOG_DETAIL", True):
            line = svc._format_detections_for_log(self.DETECTIONS)
        self.assertIn("집전체(0.91)", line)
        self.assertIn("나무(0.34)", line)  # 집 그림에 남은 배경 나무가 드러난다(709)

    def test_never_logs_bbox_in_either_mode(self):
        for detail in (False, True):
            with mock.patch.object(svc.config, "DETECTION_LOG_DETAIL", detail):
                line = svc._format_detections_for_log(self.DETECTIONS)
            self.assertNotIn("0.4", line)  # bbox 폭·높이가 섞이지 않는다


class DetectionMetadataSchemaTest(unittest.TestCase):
    """구조화 탐지 메타데이터 로그 스키마 (S15P11B209-610).

    611(TTL·집계·피드백)이 import해 MongoDB에 저장할 pydantic 모델. 아동 그림 내용
    (표시명·bbox·이미지)은 담기지 않고 내부 코드·수치·집계만 담긴다.
    """

    OCCURRED = "2026-07-30T16:00:00+09:00"

    def _req(self):
        return contracts.AnalysisRequest.model_validate(
            {**SPEC_REQUEST, "activityType": "HTP", "drawingSubject": "HOUSE"}
        )

    def _model_info(self):
        return contracts.ModelInfo(
            object_detection=contracts.ModelRef(name="yolo-htp", version="htp_best.pt")
        )

    def _objects(self):
        objects, _ = svc._to_detected_objects(
            [
                _det("집전체", 0.1, 0.1, 0.4, 0.4, conf=0.91),
                _det("지붕", 0.2, 0.1, 0.3, 0.2, conf=0.80),
            ],
            svc.htp_labels,
        )
        return objects

    def _build(self, objects=None, warnings=(), ms=123):
        return svc._detection_metadata(
            self._req(),
            self._objects() if objects is None else objects,
            self._model_info(),
            list(warnings),
            ms,
            self.OCCURRED,
        )

    def test_is_pydantic_model_with_min_contract(self):
        # 611 최소 계약: analysisId · occurredAt · schemaVersion — 모델을 611이 import해 저장한다.
        rec = self._build()
        self.assertIsInstance(rec, contracts.DetectionMetadataLog)
        self.assertEqual(rec.analysis_id, 701)
        self.assertEqual(rec.occurred_at, self.OCCURRED)
        self.assertEqual(rec.schema_version, "1")
        self.assertEqual(rec.event, "object_detection")

    def test_schema_fields(self):
        rec = self._build(warnings=["RAG_NOT_CONFIGURED"])
        self.assertEqual(rec.drawing_session_id, 100)
        self.assertEqual(rec.activity_type, "HTP")
        self.assertEqual(rec.drawing_subject, "HOUSE")
        self.assertEqual(rec.object_detection.name, "yolo-htp")
        self.assertEqual(rec.image_width, 1920)
        self.assertEqual(rec.image_height, 1080)
        self.assertEqual(rec.detection_count, 2)
        self.assertEqual(rec.class_counts, {"HOUSE": 1, "HOUSE_ROOF": 1})
        self.assertEqual(rec.processing_time_ms, 123)
        self.assertEqual(rec.warnings, ["RAG_NOT_CONFIGURED"])

    def test_per_object_has_no_bbox(self):
        # 객체별 필드는 코드·수치만 — bbox는 스키마에 아예 없다(710 가드레일 유지).
        self.assertEqual(
            set(contracts.DetectionMetadataObject.model_fields),
            {"object_code", "confidence", "area_ratio", "detection_order"},
        )
        rec = self._build()
        self.assertEqual([o.object_code for o in rec.objects], ["HOUSE", "HOUSE_ROOF"])

    def test_emit_json_is_camelcase_and_has_no_child_content(self):
        dumped = self._build().model_dump_json(by_alias=True)
        for key in ("schemaVersion", "occurredAt", "analysisId", "detectionCount"):
            self.assertIn(key, dumped)
        self.assertIn("+09:00", dumped)  # timezone 명시 ISO8601(TTL 인덱스 기준)
        self.assertNotIn("집", dumped)  # 표시명(아동 그림 내용) 미포함
        self.assertNotIn("지붕", dumped)
        self.assertNotIn("bbox", dumped)  # bbox 미포함(710 가드레일)
        self.assertNotIn("boundingBox", dumped)

    def test_roundtrip_via_model(self):
        # 611이 emit된 JSON을 같은 모델로 되읽을 수 있다(ad-hoc 파싱 불필요).
        rec = self._build(ms=5)
        again = contracts.DetectionMetadataLog.model_validate_json(
            rec.model_dump_json(by_alias=True)
        )
        self.assertEqual(again, rec)

    def test_empty_detections(self):
        rec = self._build(objects=[])
        self.assertEqual(rec.detection_count, 0)
        self.assertEqual(rec.class_counts, {})
        self.assertEqual(rec.objects, [])


if __name__ == "__main__":
    unittest.main()


@unittest.skipUnless(_CV2_AVAILABLE, "cv2/numpy required")
class DiaryVlmSourceImageRoutingTest(unittest.TestCase):
    """자유 그림만 원본 이미지를 VLM에 보내고 HTP의 기존 주석 이미지 경로는 유지한다."""

    @staticmethod
    def _png() -> bytes:
        ok, buf = cv2.imencode(".png", np.full((16, 16, 3), 255, dtype=np.uint8))
        if not ok:
            raise AssertionError("test PNG encoding failed")
        return buf.tobytes()

    def _run(self, activity_type: str):
        payload = {**SPEC_REQUEST, "activityType": activity_type}
        if activity_type == "HTP":
            payload["drawingSubject"] = "TREE"
        req = contracts.AnalysisRequest.model_validate(payload)
        original = self._png()
        with (
            mock.patch.object(svc, "_fetch_drawing", return_value=original),
            mock.patch.object(
                svc, "_detect_or_degrade", return_value=([], b"annotated")
            ),
            mock.patch.object(svc.vlm_client, "describe", return_value="관찰") as describe,
        ):
            svc.analyze(req)
        return original, describe.call_args

    def test_art_diary_sends_unannotated_source_png(self):
        original, call = self._run("ART_DIARY")
        self.assertEqual(call.kwargs["source_png"], original)
        self.assertEqual(call.kwargs["activity_type"], "ART_DIARY")

    def test_htp_keeps_annotated_image_path(self):
        _, call = self._run("HTP")
        self.assertIsNone(call.kwargs["source_png"])
        self.assertEqual(call.kwargs["activity_type"], "HTP")

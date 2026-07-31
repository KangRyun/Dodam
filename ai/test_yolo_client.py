"""yolo_client 단위 테스트 — torch/ultralytics·실제 가중치 없이 파싱 로직만 검증.

ultralytics 결과 객체를 흉내 낸 가짜(fake)로 _parse_result 를 직접 검증한다.
실제 추론(detect_and_annotate)은 가중치·torch가 필요하므로 여기서 다루지 않는다.
"""

from __future__ import annotations

import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import yolo_client


class _FakeTensor:
    """ultralytics boxes.data 처럼 .tolist() 를 제공하는 최소 가짜."""

    def __init__(self, rows):
        self._rows = rows

    def tolist(self):
        return self._rows


class _FakeBoxes:
    def __init__(self, rows):
        self.data = _FakeTensor(rows)


class _FakeResult:
    """result.orig_shape / result.names / result.boxes.data 만 가진 가짜 결과."""

    def __init__(self, rows, names, shape):
        self.orig_shape = shape  # (height, width)
        self.names = names
        self.boxes = _FakeBoxes(rows)


class ParseResultTest(unittest.TestCase):
    def test_parses_label_confidence_and_both_bbox_forms(self):
        # width=200, height=100. 박스 (10,20)-(110,80) → 너비100·높이60.
        result = _FakeResult(
            rows=[[10, 20, 110, 80, 0.9, 42]],
            names={42: "집전체", 8: "나무"},
            shape=(100, 200),
        )

        detections = yolo_client._parse_result(result)

        self.assertEqual(len(detections), 1)
        det = detections[0]
        self.assertEqual(det.label, "집전체")
        self.assertAlmostEqual(det.confidence, 0.9)
        self.assertEqual(det.bbox_xyxy, (10.0, 20.0, 110.0, 80.0))
        # 정규화 (x, y, w, h) = (10/200, 20/100, 100/200, 60/100)
        x, y, w, h = det.bbox_norm_xywh
        self.assertAlmostEqual(x, 0.05)
        self.assertAlmostEqual(y, 0.20)
        self.assertAlmostEqual(w, 0.50)
        self.assertAlmostEqual(h, 0.60)

    def test_unknown_class_id_falls_back_to_stringified_id(self):
        result = _FakeResult(
            rows=[[0, 0, 10, 10, 0.5, 999]],
            names={0: "가지"},
            shape=(100, 100),
        )

        detections = yolo_client._parse_result(result)

        self.assertEqual(detections[0].label, "999")

    def test_empty_detections(self):
        result = _FakeResult(rows=[], names={0: "가지"}, shape=(100, 100))
        self.assertEqual(yolo_client._parse_result(result), [])


class VerifyChecksumTest(unittest.TestCase):
    """가중치 무결성 검증 — torch/실제 가중치 없이 sha256 로직만 검증한다."""

    def _tmpfile(self, content: bytes) -> Path:
        fd, name = tempfile.mkstemp()
        with os.fdopen(fd, "wb") as handle:
            handle.write(content)
        self.addCleanup(os.unlink, name)
        return Path(name)

    def test_matching_checksum_passes(self):
        path = self._tmpfile(b"weights-bytes")
        expected = yolo_client._sha256_of_file(path)
        # 일치하면 예외 없이 통과한다.
        yolo_client._verify_checksum(path, expected)

    def test_mismatch_raises_runtimeerror(self):
        path = self._tmpfile(b"weights-bytes")
        with self.assertRaises(RuntimeError):
            yolo_client._verify_checksum(path, "0" * 64)

    def test_unset_expected_skips_verification(self):
        path = self._tmpfile(b"weights-bytes")
        # 미설정(빈 문자열·None)이면 예외 없이 통과한다(경고만).
        yolo_client._verify_checksum(path, "")
        yolo_client._verify_checksum(path, None)

    def test_expected_is_case_and_whitespace_insensitive(self):
        path = self._tmpfile(b"weights-bytes")
        digest = yolo_client._sha256_of_file(path)
        yolo_client._verify_checksum(path, f"  {digest.upper()}  ")


class ModelRegistryTest(unittest.TestCase):
    def test_registry_exposes_htp_and_sketch(self):
        registry = yolo_client._model_registry()
        self.assertIn("htp", registry)
        self.assertIn("sketch", registry)

    def test_unknown_model_key_raises_valueerror(self):
        # torch를 건드리기 전에 알 수 없는 키를 거른다.
        with self.assertRaises(ValueError):
            yolo_client._get_model("does-not-exist")

    def test_detect_uses_requested_model_key(self):
        result = mock.Mock()
        result.boxes.data.tolist.return_value = []
        result.orig_shape = (100, 100)
        result.names = {}
        result.plot.return_value = object()
        model = mock.Mock()
        model.predict.return_value = [result]

        with (
            mock.patch.object(yolo_client, "_get_model", return_value=model) as get_model,
            mock.patch.object(yolo_client, "_encode_png", return_value=b"png"),
        ):
            detections, annotated = yolo_client.detect_and_annotate(
                "/image.png", model_key="sketch"
            )

        get_model.assert_called_once_with("sketch")
        self.assertEqual(detections, [])
        self.assertEqual(annotated, b"png")


class ModelReadinessTest(unittest.TestCase):
    """health용 준비 여부 — 예외 없이 boolean, 존재+checksum 반영, 캐시."""

    def setUp(self):
        yolo_client._readiness_cache = None
        self.addCleanup(setattr, yolo_client, "_readiness_cache", None)

    def _tmpfile(self, content: bytes) -> str:
        fd, name = tempfile.mkstemp()
        with os.fdopen(fd, "wb") as handle:
            handle.write(content)
        self.addCleanup(os.unlink, name)
        return name

    def test_ready_when_present_and_checksum_matches(self):
        path = self._tmpfile(b"weights")
        digest = yolo_client._sha256_of_file(Path(path))
        with mock.patch.object(
            yolo_client, "_model_registry", return_value={"htp": (path, digest)}
        ):
            self.assertEqual(yolo_client.model_readiness(refresh=True), {"htp": True})

    def test_not_ready_when_checksum_mismatches(self):
        path = self._tmpfile(b"weights")
        with mock.patch.object(
            yolo_client, "_model_registry", return_value={"htp": (path, "0" * 64)}
        ):
            self.assertEqual(yolo_client.model_readiness(refresh=True), {"htp": False})

    def test_not_ready_when_file_missing(self):
        with mock.patch.object(
            yolo_client, "_model_registry", return_value={"htp": ("/no/such.pt", "0" * 64)}
        ):
            self.assertEqual(yolo_client.model_readiness(refresh=True), {"htp": False})

    def test_ready_when_expected_unset(self):
        path = self._tmpfile(b"weights")
        with mock.patch.object(
            yolo_client, "_model_registry", return_value={"htp": (path, "")}
        ):
            self.assertEqual(yolo_client.model_readiness(refresh=True), {"htp": True})

    def test_result_is_cached_until_refresh(self):
        path = self._tmpfile(b"weights")
        digest = yolo_client._sha256_of_file(Path(path))
        with mock.patch.object(
            yolo_client, "_model_registry", return_value={"htp": (path, digest)}
        ) as registry:
            yolo_client.model_readiness(refresh=True)
            yolo_client.model_readiness()  # 캐시 사용 — 레지스트리 재조회 없음
            self.assertEqual(registry.call_count, 1)


class SketchInkGatingTest(unittest.TestCase):
    """sketch 잉크 정규화 게이트 (S15P11B209-679).

    기본("none")은 동작 불변, "ink"일 때만 sketch YOLO 입력을 잉크 ndarray로 바꾸고
    VLM 주석은 색 보존 원본에 그린다. HTP는 어느 모드에서도 전처리하지 않는다.
    """

    def _fake_model(self):
        model = mock.Mock()
        model.predict.return_value = [mock.Mock()]  # result[0], .plot() 보유
        return model

    def _predict_source(self, model_key, preprocess):
        model = self._fake_model()
        with mock.patch.object(yolo_client, "_get_model", return_value=model), mock.patch.object(
            yolo_client, "_parse_result", return_value=[]
        ), mock.patch.object(
            yolo_client, "_encode_png", return_value=b""
        ), mock.patch.object(yolo_client.config, "SKETCH_PREPROCESS", preprocess):
            yolo_client.detect_and_annotate("/tmp/x.png", model_key=model_key)
        return model.predict.call_args.args[0]

    def test_none_predicts_on_original_path(self):
        self.assertEqual(self._predict_source("sketch", "none"), "/tmp/x.png")

    def test_htp_never_preprocesses(self):
        self.assertEqual(self._predict_source("htp", "ink"), "/tmp/x.png")

    def test_sketch_ink_predicts_on_normalized_ndarray(self):
        import image_preprocess

        sentinel = object()
        model = self._fake_model()
        with mock.patch.object(yolo_client, "_get_model", return_value=model), mock.patch.object(
            yolo_client, "_parse_result", return_value=[]
        ), mock.patch.object(
            yolo_client, "_encode_png", return_value=b""
        ), mock.patch.object(
            yolo_client.config, "SKETCH_PREPROCESS", "ink"
        ), mock.patch(
            "cv2.imread", return_value="ORIGINAL_IMG"
        ), mock.patch.object(image_preprocess, "ink_normalize", return_value=sentinel):
            yolo_client.detect_and_annotate("/tmp/x.png", model_key="sketch")
        # YOLO 입력은 잉크 ndarray(sentinel)
        self.assertIs(model.predict.call_args.args[0], sentinel)
        # VLM 주석은 색 보존 원본에 그린다(679)
        model.predict.return_value[0].plot.assert_called_with(img="ORIGINAL_IMG")


class InferenceImgszTest(unittest.TestCase):
    """추론 imgsz가 모델별 학습 해상도로 predict에 전달되는지(S15P11B209-761)."""

    def _predict_imgsz(self, model_key):
        model = mock.Mock()
        model.predict.return_value = [mock.Mock()]
        with mock.patch.object(yolo_client, "_get_model", return_value=model), mock.patch.object(
            yolo_client, "_parse_result", return_value=[]
        ), mock.patch.object(
            yolo_client, "_encode_png", return_value=b""
        ), mock.patch.object(yolo_client, "_load_bgr_oriented", return_value=None):
            yolo_client.detect_and_annotate("/tmp/x.png", model_key=model_key)
        return model.predict.call_args.kwargs["imgsz"]

    def test_htp_uses_htp_imgsz(self):
        self.assertEqual(self._predict_imgsz("htp"), yolo_client.config.HTP_IMGSZ)

    def test_sketch_uses_sketch_imgsz(self):
        self.assertEqual(self._predict_imgsz("sketch"), yolo_client.config.SKETCH_IMGSZ)


class ExifOrientationTest(unittest.TestCase):
    """EXIF 방향 보정 — 회전 필요할 때만 BGR ndarray, 정상·부재는 None(S15P11B209-761)."""

    def _tmp(self, suffix: str) -> str:
        fd, name = tempfile.mkstemp(suffix=suffix)
        os.close(fd)
        self.addCleanup(os.unlink, name)
        return name

    def test_missing_file_returns_none(self):
        self.assertIsNone(yolo_client._load_bgr_oriented("/no/such/file.jpg"))

    def test_normal_image_returns_none(self):
        from PIL import Image

        path = self._tmp(".png")
        Image.new("RGB", (8, 16), (10, 20, 30)).save(path)  # 방향 태그 없음 → 보정 불필요
        self.assertIsNone(yolo_client._load_bgr_oriented(path))

    def test_rotated_exif_returns_bgr_ndarray(self):
        import numpy as np
        from PIL import Image

        path = self._tmp(".jpg")
        img = Image.new("RGB", (8, 16), (10, 20, 30))
        exif = img.getexif()
        exif[0x0112] = 6  # Orientation=6(회전 필요)
        img.save(path, exif=exif.tobytes())

        out = yolo_client._load_bgr_oriented(path)
        self.assertIsInstance(out, np.ndarray)
        self.assertEqual(out.ndim, 3)
        self.assertEqual(out.shape[2], 3)  # 3채널 BGR


if __name__ == "__main__":
    unittest.main()

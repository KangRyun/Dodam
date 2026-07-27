"""yolo_client 단위 테스트 — torch/ultralytics·실제 가중치 없이 파싱 로직만 검증.

ultralytics 결과 객체를 흉내 낸 가짜(fake)로 _parse_result 를 직접 검증한다.
실제 추론(detect_and_annotate)은 가중치·torch가 필요하므로 여기서 다루지 않는다.
"""

from __future__ import annotations

import os
import tempfile
import unittest
from pathlib import Path

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


if __name__ == "__main__":
    unittest.main()

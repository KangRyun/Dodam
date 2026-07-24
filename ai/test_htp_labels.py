"""htp_labels 단위 테스트 — torch/ultralytics·실제 가중치 없이 매핑·집계만 검증.

실제 추론으로 확인한 성질(주제 전체 검출·교차 주제 오탐 억제)을 가짜 탐지로 고정해
가중치 없이도 회귀를 잡는다.
"""

from __future__ import annotations

import unittest
from dataclasses import dataclass

import htp_labels


@dataclass(frozen=True)
class _FakeDetection:
    """yolo_client.Detection 중 htp_labels가 쓰는 두 필드만 가진 가짜."""

    label: str
    confidence: float = 0.9


class LabelMappingTest(unittest.TestCase):
    def test_maps_all_47_classes_of_the_trained_weights(self):
        # 가중치(stageB_htp/data.yaml)의 클래스 수 — 표가 부족하거나 남으면 계약 라벨이 깨진다.
        self.assertEqual(len(htp_labels._SPEC_BY_CLASS), 47)

    def test_contract_labels_are_upper_snake_and_unique(self):
        labels = [spec.contract_label for spec in htp_labels._SPEC_BY_CLASS.values()]
        # 계약(docs/api/ai-drawing-analysis-contract.md)은 UPPER_SNAKE_CASE를 요구한다.
        for label in labels:
            self.assertRegex(label, r"^[A-Z][A-Z_]*$", f"계약 라벨 형식 위반: {label}")
        # 서로 다른 클래스가 같은 라벨로 접히면 BE가 구분할 수 없다.
        self.assertEqual(len(labels), len(set(labels)))

    def test_whole_classes_are_exactly_the_three_subjects(self):
        wholes = {
            name: spec.contract_label
            for name, spec in htp_labels._SPEC_BY_CLASS.items()
            if spec.is_whole
        }
        self.assertEqual(
            wholes, {"집전체": "HOUSE", "나무전체": "TREE", "사람전체": "PERSON"}
        )

    def test_part_labels_carry_their_group_prefix(self):
        # BE가 label.startswith("HOUSE")로 집 계열을 고를 수 있어야 한다.
        self.assertEqual(htp_labels.to_contract_label("지붕"), "HOUSE_ROOF")
        self.assertEqual(htp_labels.to_contract_label("뿌리"), "TREE_ROOT")
        self.assertEqual(htp_labels.to_contract_label("눈"), "PERSON_EYE")
        self.assertEqual(htp_labels.group_of("지붕"), htp_labels.GROUP_HOUSE)
        self.assertFalse(htp_labels.is_whole("지붕"))

    def test_scenery_labels_have_no_subject_prefix(self):
        self.assertEqual(htp_labels.to_contract_label("태양"), "SUN")
        self.assertEqual(htp_labels.group_of("태양"), htp_labels.GROUP_SCENERY)

    def test_unknown_class_folds_to_unknown_without_raising(self):
        # 가중치 재학습으로 클래스가 바뀌어도 엔드포인트가 500으로 죽지 않아야 한다.
        with self.assertLogs("htp_labels", level="WARNING"):
            self.assertEqual(htp_labels.to_contract_label("없는클래스"), "UNKNOWN")
        self.assertEqual(htp_labels.group_of("없는클래스"), htp_labels.GROUP_UNKNOWN)

    def test_verify_against_model_names_reports_only_missing(self):
        self.assertEqual(htp_labels.verify_against_model_names(["집전체", "태양"]), [])
        self.assertEqual(
            htp_labels.verify_against_model_names(["집전체", "새클래스"]), ["새클래스"]
        )


class SummarizeTest(unittest.TestCase):
    def test_groups_detections_and_reports_drawn_subject(self):
        summary = htp_labels.summarize(
            [
                _FakeDetection("집전체", 0.95),
                _FakeDetection("지붕", 0.80),
                _FakeDetection("창문", 0.70),
                _FakeDetection("창문", 0.60),
                _FakeDetection("태양", 0.50),
            ]
        )

        self.assertEqual(summary.total, 5)
        self.assertFalse(summary.is_empty)
        self.assertEqual(summary.subjects_drawn, ("HOUSE",))

        house = summary.groups[htp_labels.GROUP_HOUSE]
        self.assertTrue(house.whole_detected)
        self.assertEqual(house.part_labels, ("HOUSE_ROOF", "HOUSE_WINDOW"))
        self.assertEqual(house.label_counts["HOUSE_WINDOW"], 2)  # 창문 2개
        self.assertAlmostEqual(house.max_confidence, 0.95)

        # 배경은 주제로 세지 않는다.
        self.assertNotIn(htp_labels.GROUP_SCENERY, summary.subjects_drawn)

    def test_parts_without_whole_do_not_count_as_drawn_subject(self):
        summary = htp_labels.summarize([_FakeDetection("눈"), _FakeDetection("코")])
        self.assertEqual(summary.subjects_drawn, ())
        self.assertFalse(summary.groups[htp_labels.GROUP_PERSON].whole_detected)

    def test_empty_detections_is_a_normal_result(self):
        # 계약은 detections: [] 를 정상으로 규정한다 — 예외가 아니라 플래그로 표현.
        summary = htp_labels.summarize([])
        self.assertTrue(summary.is_empty)
        self.assertEqual(summary.total, 0)
        self.assertEqual(summary.groups, {})
        self.assertEqual(summary.subjects_drawn, ())


class SuppressCrossSubjectPartsTest(unittest.TestCase):
    def test_drops_other_subject_parts_when_a_subject_is_identified(self):
        # 실측에서 나온 형태: 나무 그림에 사람 부위가 높은 신뢰도로 섞여 들어온다.
        kept = htp_labels.suppress_cross_subject_parts(
            [
                _FakeDetection("나무전체", 0.92),
                _FakeDetection("수관", 0.88),
                _FakeDetection("운동화", 0.63),  # 교차 주제 오탐
                _FakeDetection("눈", 0.63),  # 교차 주제 오탐
                _FakeDetection("구름", 0.70),  # 배경 — 나무 그림에 정상
            ]
        )

        self.assertEqual(
            [d.label for d in kept], ["나무전체", "수관", "구름"]
        )

    def test_keeps_everything_when_no_subject_whole_detected(self):
        # 주제를 판단할 근거가 없으면 지우지 않는다(근거 없는 삭제 금지).
        detections = [_FakeDetection("눈"), _FakeDetection("지붕"), _FakeDetection("구름")]
        self.assertEqual(htp_labels.suppress_cross_subject_parts(detections), detections)

    def test_keeps_both_subjects_when_both_wholes_detected(self):
        kept = htp_labels.suppress_cross_subject_parts(
            [
                _FakeDetection("집전체"),
                _FakeDetection("지붕"),
                _FakeDetection("사람전체"),
                _FakeDetection("눈"),
            ]
        )
        self.assertEqual(len(kept), 4)

    def test_does_not_touch_unknown_labels(self):
        # UNKNOWN은 매핑 불일치 신호 — 조용히 지우면 원인을 놓친다.
        with self.assertLogs("htp_labels", level="WARNING"):
            kept = htp_labels.suppress_cross_subject_parts(
                [_FakeDetection("집전체"), _FakeDetection("없는클래스")]
            )
        self.assertEqual(len(kept), 2)

    def test_empty_input(self):
        self.assertEqual(htp_labels.suppress_cross_subject_parts([]), [])


if __name__ == "__main__":
    unittest.main()

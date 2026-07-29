"""sketch_labels 단위 테스트 (S15P11B209-711).

가중치 없이 매핑 표만 검증한다. 데이터셋·가중치는 저장소에 없으므로(.gitignore)
**이 표가 클래스 집합의 유일한 저장소 기록**이다 — 여기서 고정해두지 않으면
재학습으로 표가 어긋나도 런타임 UNKNOWN 폭증으로만 드러난다.
"""

from __future__ import annotations

import unittest

import htp_labels
import sketch_labels

# 배포 중인 sketch_base.pt(v1)가 실제로 내는 33종 — 체크포인트 model.names 실측(2026-07-29).
DEPLOYED_V1_CLASSES = [
    "arm", "bird", "bush", "cloud", "door", "ear", "eye", "face", "fence",
    "flower", "foot", "garden", "grass", "hand", "house", "ladder", "leg",
    "moon", "mountain", "mouth", "nose", "pants", "pool", "river", "shoe",
    "sock", "squirrel", "stairs", "star", "sun", "swing set", "t-shirt", "tree",
]


class CoverageTest(unittest.TestCase):
    def test_covers_every_class_of_the_deployed_weights(self):
        # 하나라도 빠지면 그 객체가 UNKNOWN으로 저장된다.
        self.assertEqual(sketch_labels.verify_against_model_names(DEPLOYED_V1_CLASSES), [])

    def test_covers_the_v4_person_class(self):
        # v4는 HTP '사람전체' 스프라이트로 person을 추가한다 — 미리 덮어 둔다.
        self.assertEqual(sketch_labels.to_contract_label("person"), "PERSON")

    def test_reports_unmapped_names(self):
        self.assertEqual(
            sketch_labels.verify_against_model_names(["tree", "unicorn"]), ["unicorn"]
        )


class ContractLabelTest(unittest.TestCase):
    def test_shared_targets_reuse_htp_codes(self):
        # 코드가 갈리면 리포트 집계가 두 벌이 된다.
        for sketch_name, htp_name in [
            ("house", "집전체"),
            ("tree", "나무전체"),
            ("door", "문"),
            ("eye", "눈"),
            ("sun", "태양"),
        ]:
            with self.subTest(sketch_name):
                self.assertEqual(
                    sketch_labels.to_contract_label(sketch_name),
                    htp_labels.to_contract_label(htp_name),
                )

    def test_pool_is_not_folded_into_htp_pond(self):
        # HTP 연못(POND)과 그림일기 수영장(pool)은 다른 대상이다.
        self.assertNotEqual(
            sketch_labels.to_contract_label("pool"), htp_labels.to_contract_label("연못")
        )

    def test_school_bus_folds_into_bus(self):
        # v4에서 병합된 방향대로 접는다 — 병합 전 가중치도 같은 코드로 저장된다.
        self.assertEqual(
            sketch_labels.to_contract_label("school bus"),
            sketch_labels.to_contract_label("bus"),
        )

    def test_contract_labels_are_upper_snake(self):
        for name, spec in sketch_labels._SPEC_BY_CLASS.items():
            with self.subTest(name):
                self.assertRegex(spec.contract_label, r"^[A-Z][A-Z0-9_]*$")


class DisplayNameTest(unittest.TestCase):
    def test_every_class_has_a_korean_display_name(self):
        blank = [
            name
            for name, spec in sketch_labels._SPEC_BY_CLASS.items()
            if not spec.display_name.strip()
        ]
        self.assertEqual(blank, [])

    def test_display_names_are_not_the_english_class_name(self):
        # 영어 원문이 프롬프트로 새면 아이에게 읽어줄 수 없다.
        leaked = [
            name
            for name, spec in sketch_labels._SPEC_BY_CLASS.items()
            if spec.display_name == name
        ]
        self.assertEqual(leaked, [])

    def test_bridge_is_distinguishable_from_leg(self):
        # 둘 다 "다리"면 어떤 다리인지 알 수 없다.
        self.assertNotEqual(
            sketch_labels.display_name_of("bridge"), sketch_labels.display_name_of("leg")
        )

    def test_unknown_class_does_not_leak_raw_name(self):
        spec = sketch_labels.spec_of("unicorn")
        self.assertEqual(spec.contract_label, sketch_labels.UNKNOWN_LABEL)
        self.assertNotIn("unicorn", spec.display_name)


if __name__ == "__main__":
    unittest.main()

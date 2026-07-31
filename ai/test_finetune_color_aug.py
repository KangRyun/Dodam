"""finetune_color_aug.recolor 단위 테스트 (S15P11B209-754).

색 증강이 (1) 형태(획)를 어둡게 보존하고 (2) 색을 랜덤으로 바꾸며 (3) 크기·타입을 유지하는지
검증한다. 학습 오케스트레이션(GPU 필요)은 여기서 다루지 않는다 — 재색칠 로직만 고정한다.
"""

from __future__ import annotations

import importlib.util
import random
import unittest
from pathlib import Path

try:
    import cv2
    import numpy as np

    _CV2 = True
except Exception:  # pragma: no cover - 환경 의존
    _CV2 = False

if _CV2:
    _spec = importlib.util.spec_from_file_location(
        "finetune_color_aug", Path(__file__).parent / "models" / "finetune_color_aug.py"
    )
    fca = importlib.util.module_from_spec(_spec)
    _spec.loader.exec_module(fca)


@unittest.skipUnless(_CV2, "cv2/numpy 필요")
class RecolorTest(unittest.TestCase):
    def _canvas(self):
        img = np.full((40, 40, 3), 255, np.uint8)
        img[20, 4:36] = (0, 0, 0)  # 검은 가로선
        return img

    def test_shape_and_dtype_preserved(self):
        out = fca.recolor(self._canvas(), random.Random(0))
        self.assertEqual(out.shape, (40, 40, 3))
        self.assertEqual(out.dtype, np.uint8)

    def test_stroke_stays_darker_than_paper(self):
        # 채움을 넣어도 획은 종이·채움보다 어두워 형태가 보여야 한다(유일한 제약).
        out = fca.recolor(self._canvas(), random.Random(3), fill_prob=1.0)
        gray = cv2.cvtColor(out, cv2.COLOR_BGR2GRAY).astype(int)
        self.assertLess(int(gray[20, 20]), int(gray[5, 5]) - 20)

    def test_color_is_randomized_per_seed(self):
        # 시드가 다르면 다른 색이 나온다(색이 객체에 고정돼 있지 않다).
        a = fca.recolor(self._canvas(), random.Random(1), fill_prob=0.0)
        b = fca.recolor(self._canvas(), random.Random(2), fill_prob=0.0)
        self.assertFalse(np.array_equal(a, b))

    def test_line_pixel_is_colored_not_grayscale(self):
        # 획이 회색이 아니라 실제 색(채널 값이 서로 다름)을 갖는다.
        out = fca.recolor(self._canvas(), random.Random(5), fill_prob=0.0)
        b, g, r = (int(v) for v in out[20, 20])
        self.assertGreater(max(b, g, r) - min(b, g, r), 15)  # 채널 편차 = 유채색


if __name__ == "__main__":
    unittest.main()

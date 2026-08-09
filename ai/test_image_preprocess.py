"""image_preprocess 단위 테스트 — 잉크 정규화 (S15P11B209-679).

핵심: 순진한 luminance 흑백은 밝은 색 선(노랑)을 흰 종이에 묻혀 잃지만, 잉크 정규화는
색조와 무관하게 선을 어둡게 보존한다.
"""

from __future__ import annotations

import unittest

try:  # cv2 headless 설치가 깨지면 import부터 실패한다(S15P11B209-397).
    import cv2
    import numpy as np

    _CV2 = True
except Exception:  # pragma: no cover - 환경 의존
    _CV2 = False

if _CV2:
    import image_preprocess


@unittest.skipUnless(_CV2, "cv2/numpy 필요")
class InkNormalizeTest(unittest.TestCase):
    def _canvas(self):
        # 흰 종이(255)에 밝은 노란 선(BGR 0,255,255)과 검은 선(0,0,0)을 하나씩.
        img = np.full((20, 20, 3), 255, dtype=np.uint8)
        img[5, 2:18] = (0, 255, 255)  # 밝은 노란 선
        img[15, 2:18] = (0, 0, 0)  # 검은 선
        return img

    def test_shape_and_dtype_preserved(self):
        out = image_preprocess.ink_normalize(self._canvas())
        self.assertEqual(out.shape, (20, 20, 3))
        self.assertEqual(out.dtype, np.uint8)

    def test_bright_yellow_line_kept_dark_paper_stays_white(self):
        gray = cv2.cvtColor(
            image_preprocess.ink_normalize(self._canvas()), cv2.COLOR_BGR2GRAY
        )
        self.assertLess(int(gray[5, 10]), 128)  # 노란 선이 어둡게 남는다
        self.assertGreater(int(gray[10, 10]), 200)  # 선 없는 종이는 밝게 유지

    def test_black_line_is_dark(self):
        gray = cv2.cvtColor(
            image_preprocess.ink_normalize(self._canvas()), cv2.COLOR_BGR2GRAY
        )
        self.assertLess(int(gray[15, 10]), 60)

    def test_beats_naive_gray_on_bright_color(self):
        canvas = self._canvas()
        naive = cv2.cvtColor(canvas, cv2.COLOR_BGR2GRAY)  # 순진한 흑백
        ink = cv2.cvtColor(
            image_preprocess.ink_normalize(canvas), cv2.COLOR_BGR2GRAY
        )
        self.assertGreater(int(naive[5, 10]), 200)  # 노랑이 흰색에 묻혀 사라짐
        self.assertLess(int(ink[5, 10]), 128)  # 잉크는 선을 살림


if __name__ == "__main__":
    unittest.main()

"""그림 입력 전처리 — 컬러 캔버스 → sketch_base 도메인(흑백 선화) 정규화 (S15P11B209-679).

sketch_base(그림일기 범용 손그림 모델)는 흑백 선화로 학습됐다. 자유 그림 캔버스는 컬러 선을
많이 써서 도메인 갭이 생길 수 있다. 순진한 luminance 흑백은 노란색 같은 밝은 색 선을 흰 종이에
묻혀 잃는다 — 그래서 '잉크 추출'로 색조와 무관하게 모든 선을 보존한다.

⚠️ 한계: 잉크 추출은 '색 있는/어두운 픽셀'을 남긴다. 선화(line-art)에는 사실상 선만 남지만,
   영역을 색칠했거나 배경이 있는 복잡한 캔버스에서는 칠한 영역·배경도 덩어리로 함께 남는다.
   그런 입력에서도 도움이 되는지는 models/color_ablation_test.ipynb로 실측해 판단한다(679).
   적용 여부는 config.SKETCH_PREPROCESS로 게이팅한다(기본 "none" — 실측 전엔 동작을 바꾸지 않는다).

torch·ultralytics 의존이 없다 — cv2·numpy만 쓴다(yolo_client가 지연 import로 불러온다).
"""

from __future__ import annotations

import cv2
import numpy as np


def ink_normalize(bgr: np.ndarray) -> np.ndarray:
    """컬러 이미지(BGR) → 흰 종이 위 어두운 선(3채널 BGR). 색조와 무관하게 색 있는 선을 보존한다.

    잉크 강도 = max(255 - value, saturation):
      - value 낮음(어두운 선) → 255 - value 큼
      - saturation 높음(밝아도 색이 있는 선, 예: 노랑) → saturation 큼
    강도가 클수록 진한 선 → 255에서 빼서 흰 종이 위 어두운 선으로 되돌린다.
    순진한 luminance 흑백과 달리 밝은 색 선(노랑·연두)이 흰 종이에 묻혀 사라지지 않는다.
    """
    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)
    sat = hsv[:, :, 1].astype(np.int32)
    val = hsv[:, :, 2].astype(np.int32)
    strength = np.clip(np.maximum(255 - val, sat), 0, 255).astype(np.uint8)  # 0=종이, 큼=진한 선
    ink_gray = (255 - strength).astype(np.uint8)  # 흰 종이 위 어두운 선
    return cv2.cvtColor(ink_gray, cv2.COLOR_GRAY2BGR)

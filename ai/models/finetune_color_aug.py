"""sketch_base 컬러·색칠 증강 파인튜닝 (저비용 검증) — S15P11B209-754.

679 실측: 잉크 전처리는 색칠 캔버스에서 오탐이 늘어 부적합. 근본 해결은 '학습 시 컬러 증강'으로
색 불변(color-invariant) 모델을 만드는 것. 전체 재학습(60k x 40ep ~= 10h) 전에, v4를 컬러 증강
데이터로 소수 epoch만 파인튜닝해 저비용으로 효과를 먼저 검증한다.

핵심 원칙: 색을 객체와 완전히 분리(랜덤). 모양으로만 판단하게 만들어 아무 색으로 막 칠해도 강건.
유일한 제약: 칠해도 형태(획)는 보이게 대비를 유지한다.

GPU 서버에서:  cd ai/models && python finetune_color_aug.py
필요: 기존 v4 데이터셋(흑백 선화 YOLO 포맷: train/val + data.yaml) + sketch_base_v4.pt + ultralytics.
     (Quick Draw 재합성 없이, 이미 만든 흑백 데이터셋을 '재색칠'해 쓰므로 저비용이다.)
"""

from __future__ import annotations

import os
import random
import shutil
from pathlib import Path

import cv2
import numpy as np

# ── 설정(환경에 맞게 수정하거나 FT_* 환경변수로 덮어쓰기) ────────
ROOT = Path(__file__).resolve().parent / "htp_yolo"
SRC_DATASET = ROOT / "stageA_quickdraw"  # v4 학습에 쓴 흑백 선화 데이터셋
BASE_WEIGHTS = ROOT / "sketch_base_v4.pt"  # 파인튜닝 시작 가중치
AUG_DATASET = ROOT / "stageA_color_aug"  # 재색칠 증강본 출력
OUT_WEIGHTS = ROOT / "sketch_base_v5_ft.pt"  # 파인튜닝 결과

EPOCHS = int(os.environ.get("FT_EPOCHS", "10"))  # 저비용 검증용 소수 epoch
IMG_SIZE = int(os.environ.get("FT_IMGSZ", "960"))
BATCH = int(os.environ.get("FT_BATCH", "16"))
SEED = 42
KEEP_LINE_RATIO = 0.5  # 선화(원본) 유지 비율 — 나머지는 색을 입힌다(선화 성능 회귀 방지)
FILL_PROB = 0.5  # 색 입힐 때 '영역 채움'(색칠)까지 넣을 확률
HSV_H = 0.5  # ultralytics 색조 증강 — 합성 색을 배치마다 더 흔들어 색 불변 강화


# ── 재색칠 증강 ─────────────────────────────────────────────────
def _rand_dark_color(rng: random.Random) -> list[int]:
    """획용 — 어두운 랜덤 색(항상 종이·채움보다 진해 형태가 보인다)."""
    hsv = np.uint8([[[rng.randint(0, 179), rng.randint(120, 255), rng.randint(30, 130)]]])
    return [int(x) for x in cv2.cvtColor(hsv, cv2.COLOR_HSV2BGR)[0, 0]]


def _rand_light_color(rng: random.Random) -> list[int]:
    """채움용 — 연한 랜덤 색(획보다 밝아 대비를 유지)."""
    hsv = np.uint8([[[rng.randint(0, 179), rng.randint(30, 160), rng.randint(185, 245)]]])
    return [int(x) for x in cv2.cvtColor(hsv, cv2.COLOR_HSV2BGR)[0, 0]]


def recolor(bgr: np.ndarray, rng: random.Random, *, fill_prob: float = FILL_PROB) -> np.ndarray:
    """흑백 선화 → 랜덤 색 선(+선택적 랜덤 색칠). 색은 객체와 무관, 획은 대비 유지.

    - 획(어두운 픽셀)을 랜덤 '어두운' 색으로 alpha 합성 → 같은 객체가 온갖 색으로 등장(색 불변).
    - 확률적으로 연한 색 블롭을 깔아 '막 채운 색'을 흉내 → 색칠 캔버스에도 강건.
    - 채움은 항상 획보다 밝아(형태 보존), 아이 색칠을 근사.
    bbox 라벨은 바뀌지 않는다(외형만 바꾼다).
    """
    gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY).astype(np.int32)
    ink = np.clip(255 - gray, 0, 255)  # 0=종이 .. 255=획
    h, w = gray.shape
    canvas = np.full((h, w, 3), 255, np.uint8)  # 흰 종이
    if rng.random() < fill_prob:  # 막 채운 색 흉내(연한 색 블롭 몇 개)
        for _ in range(rng.randint(1, 4)):
            x1, y1 = rng.randint(0, w - 1), rng.randint(0, h - 1)
            x2, y2 = rng.randint(x1 + 1, w), rng.randint(y1 + 1, h)
            canvas[y1:y2, x1:x2] = _rand_light_color(rng)
    stroke = np.array(_rand_dark_color(rng), np.float32)
    alpha = (ink / 255.0)[..., None]  # 획 강도만큼 어두운 색 합성 → 형태 보존
    out = canvas.astype(np.float32) * (1 - alpha) + stroke * alpha
    return np.clip(out, 0, 255).astype(np.uint8)


def build_augmented(src: Path, dst: Path, rng: random.Random) -> None:
    """src(흑백 YOLO 데이터셋) → dst(선화:색선:색칠 혼합). 라벨은 그대로 복사."""
    import yaml  # ultralytics 의존이라 존재

    for split in ("train", "val"):
        si, sl = src / split / "images", src / split / "labels"
        di, dl = dst / split / "images", dst / split / "labels"
        di.mkdir(parents=True, exist_ok=True)
        dl.mkdir(parents=True, exist_ok=True)
        imgs = sorted(si.glob("*.jpg")) + sorted(si.glob("*.png"))
        for p in imgs:
            lbl = sl / (p.stem + ".txt")
            if lbl.exists():
                shutil.copy(lbl, dl / lbl.name)
            img = cv2.imread(str(p))
            if img is None:
                continue
            out = img if rng.random() < KEEP_LINE_RATIO else recolor(img, rng)
            cv2.imwrite(str(di / (p.stem + ".jpg")), out)
        print(f"  {split}: {len(imgs)}장 처리")

    names = yaml.safe_load((src / "data.yaml").read_text(encoding="utf-8"))["names"]
    (dst / "data.yaml").write_text(
        yaml.safe_dump(
            {"path": str(dst.resolve()), "train": "train/images", "val": "val/images", "names": names},
            allow_unicode=True, sort_keys=False,
        ),
        encoding="utf-8",
    )


def main() -> None:
    rng = random.Random(SEED)
    if not SRC_DATASET.exists():
        raise SystemExit(f"원본 데이터셋을 못 찾았습니다: {SRC_DATASET}")
    if not BASE_WEIGHTS.exists():
        raise SystemExit(f"v4 가중치를 못 찾았습니다: {BASE_WEIGHTS}")

    print(f"컬러 증강 데이터셋 생성 → {AUG_DATASET}  (선화 유지 {KEEP_LINE_RATIO}, 채움확률 {FILL_PROB})")
    build_augmented(SRC_DATASET, AUG_DATASET, rng)

    from ultralytics import YOLO

    print(f"v4에서 파인튜닝 시작: {BASE_WEIGHTS.name}  (epochs={EPOCHS}, imgsz={IMG_SIZE})")
    model = YOLO(str(BASE_WEIGHTS))
    model.train(
        data=str((AUG_DATASET / "data.yaml").resolve()),
        epochs=EPOCHS, imgsz=IMG_SIZE, batch=BATCH, seed=SEED,
        hsv_h=HSV_H, project=str(ROOT / "runs"), name="color_aug_ft", exist_ok=True,
    )
    best = ROOT / "runs" / "color_aug_ft" / "weights" / "best.pt"
    shutil.copy(best, OUT_WEIGHTS)
    print(f"\n파인튜닝 완료 → {OUT_WEIGHTS}")
    print("검증: models/ink_normalize_check.ipynb 의 모델 경로를 이 파일로 바꿔")
    print("      색선(home2)·색칠(coloring) 이미지에서 v4 대비 오탐↓·정탐↑ 확인.")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""적응형 런처 아이콘 전경 PNG 생성 (S15P11B209-790).

원화(가장자리까지 꽉 찬 정사각 이미지)를 축소해 투명 캔버스 가운데 배치한다.
결과는 assets/branding/app_icon_foreground.png 이고, pubspec.yaml 의
flutter_launcher_icons 설정이 이 파일을 전경으로 쓴다.

    python3 tool/make_icon_foreground.py [원화경로]
    (그 뒤) dart run flutter_launcher_icons

왜 스크립트인가 — 아래 두 보정은 눈대중으로 재현할 수 없고, 빼먹으면 조용히 나빠진다.

1) inset 역산
   flutter_launcher_icons 는 생성하는 ic_launcher.xml 에 `android:inset="16%"` 를
   덧붙인다. 그래서 전경 PNG 안의 아트 비율이 그대로 화면에 나오지 않는다:

       최종 비율 = 전경 안 아트 비율 x (1 - 2*INSET)

   아트가 최종 캔버스의 TARGET 이 되게 하려면 전경 안에서는 TARGET/(1-2*INSET) 여야 한다.
   이 보정을 빼면 아이콘이 의도보다 눈에 띄게 작아진다(가시영역의 93% -> 63%).

2) 경계 페더
   원화 노랑에 종이 질감과 미세한 그라데이션이 있어, 축소된 아트와 단색 배경 사이에
   옅은 사각 이음매가 생긴다. 알파를 가장자리에서 부드럽게 떨어뜨려 그 경계를 지운다.
   배경색도 눈대중이 아니라 원화 테두리 링의 평균색을 써야 한다(아래 출력값 참고 —
   pubspec 의 adaptive_icon_background 와 일치해야 한다).

⚠️ TARGET 을 키울 때: 적응형은 가운데 66.67% 만 보인다. TARGET 이 그 값을 넘으면 잘린다.
   0.62 는 잘리지 않으면서 가시영역을 알맞게 채우는 값으로, 마스크 3종을 렌더해 확인했다.
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

HERE = Path(__file__).resolve().parent.parent
DEFAULT_SRC = HERE / "assets" / "branding" / "app_icon.png"
OUT = HERE / "assets" / "branding" / "app_icon_foreground.png"

N = 1024  # 전경 캔버스 한 변
TARGET = 0.62  # 최종 108dp 캔버스에서 아트가 차지할 비율
INSET = 0.16  # flutter_launcher_icons 가 ic_launcher.xml 에 넣는 값
FEATHER = 10  # 아트 경계 알파 페더(px)
RING = 24  # 배경색 산출에 쓸 테두리 링 두께(px)


def main() -> int:
    src_path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_SRC
    src = Image.open(src_path).convert("RGBA")

    # 배경색 = 테두리 링 평균. 아래쪽은 스케치북(크림색)이 닿아 평균을 흐리므로 제외한다.
    a = np.asarray(src.convert("RGB")).astype(int)
    ring = np.concatenate(
        [a[:RING].reshape(-1, 3), a[:, :RING].reshape(-1, 3), a[:, -RING:].reshape(-1, 3)]
    )
    bg = tuple(ring.mean(axis=0).round().astype(int))

    frac = TARGET / (1 - 2 * INSET)  # inset 역산
    s = round(N * frac)
    art = src.resize((s, s), Image.LANCZOS)

    # 경계 페더 — 단색 배경과의 사각 이음매를 지운다.
    alpha = Image.new("L", (s, s), 0)
    m = round(FEATHER * 1.5)
    alpha.paste(255, (m, m, s - m, s - m))
    art.putalpha(alpha.filter(ImageFilter.GaussianBlur(FEATHER / 2)))

    canvas = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    canvas.paste(art, ((N - s) // 2, (N - s) // 2), art)
    canvas.save(OUT)

    print(f"원화      : {src_path}")
    print(f"전경 아트 : {s}px / {N} ({frac:.0%}) -> inset {INSET:.0%} 적용 후 최종 {TARGET:.0%}")
    print(f"배경색    : #{bg[0]:02X}{bg[1]:02X}{bg[2]:02X}  (pubspec 의 adaptive_icon_background 와 맞출 것)")
    print(f"저장      : {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

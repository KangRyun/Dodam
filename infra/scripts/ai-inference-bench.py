# S15P11B209-609 — CPU 추론 성능 실측 (운영 동일 조건 별도 컨테이너에서 실행)
#
# 실행 형태:  docker run --rm --cpus=<N> --memory=1g --network=none \
#               -v <ai-models PVC 호스트경로>:/models:ro -v <이 디렉터리>:/bench \
#               -e YOLO_MODEL_PATH=... -e SKETCH_MODEL_PATH=... \
#               --entrypoint python 127.0.0.1:5000/dodam-ai:<태그> /bench/bench.py
#
# 측정 원칙:
# - 실사용자 아동 그림을 절대 쓰지 않는다(가드레일 9절) — 합성 스케치를 즉석 생성.
# - 운영 코드 경로 그대로: yolo_client.detect_and_annotate (EXIF 확인 + predict +
#   후처리 + 주석 PNG 인코딩까지) 를 잰다. predict 단독 분해는 result.speed 로 병행.
# - 결과는 stdout 에 JSON 한 덩어리 — 호스트에서 수집한다.

import json
import os
import resource
import statistics
import sys
import time

N_RUNS = 25
WARMUP = 3


def synth_image(path: str, size: tuple[int, int], colored: bool) -> None:
    """합성 스케치 생성 — 흰 배경에 검정/컬러 획. 실측용 대표 입력(실아동 그림 미사용)."""
    import cv2
    import numpy as np

    w, h = size
    img = np.full((h, w, 3), 255, dtype=np.uint8)
    rng = np.random.default_rng(42)  # 재현 가능한 동일 입력
    for i in range(60):
        color = (
            tuple(int(c) for c in rng.integers(0, 200, 3)) if colored else (20, 20, 20)
        )
        p1 = (int(rng.integers(0, w)), int(rng.integers(0, h)))
        p2 = (int(rng.integers(0, w)), int(rng.integers(0, h)))
        cv2.line(img, p1, p2, color, thickness=int(rng.integers(2, 8)))
    # 집·나무 비슷한 닫힌 도형도 몇 개
    cv2.rectangle(img, (w // 4, h // 2), (w // 2, h - h // 8), (30, 30, 30), 4)
    cv2.circle(img, (3 * w // 4, h // 3), min(w, h) // 8, (30, 30, 30), 4)
    cv2.imwrite(path, img)


def pct(values: list[float], p: float) -> float:
    ordered = sorted(values)
    idx = min(len(ordered) - 1, max(0, round(p / 100 * (len(ordered) - 1))))
    return ordered[idx]


def cgroup_peak_mib() -> float | None:
    for p in ("/sys/fs/cgroup/memory.peak", "/sys/fs/cgroup/memory/memory.max_usage_in_bytes"):
        try:
            with open(p) as f:
                return round(int(f.read().strip()) / (1024 * 1024), 1)
        except (OSError, ValueError):
            continue
    return None


def main() -> None:
    out: dict = {
        "cpu_limit_hint": os.environ.get("BENCH_CPU_LABEL", "?"),
        "host_visible_cores": os.cpu_count(),
    }

    t0 = time.perf_counter()
    import torch  # noqa: F401  (ultralytics 가 끌고 오는 무거운 import 를 명시 측정)
    import ultralytics  # noqa: F401

    out["import_torch_ultralytics_s"] = round(time.perf_counter() - t0, 2)
    out["torch_num_threads"] = torch.get_num_threads()

    sys.path.insert(0, "/app")
    import config
    import yolo_client

    out["imgsz"] = {"htp": config.HTP_IMGSZ, "sketch": config.SKETCH_IMGSZ}

    os.makedirs("/tmp/bench_img", exist_ok=True)
    cases = {
        "canvas_1080": ("/tmp/bench_img/canvas.png", (1080, 1080), True),
        "photo_3024x4032": ("/tmp/bench_img/photo.png", (3024, 4032), True),
    }
    for _, (path, size, colored) in cases.items():
        synth_image(path, size, colored)

    results = {}
    for model_key in ("htp", "sketch"):
        t0 = time.perf_counter()
        model = yolo_client._get_model(model_key)  # sha256 검증 + 가중치 로드 포함
        load_s = round(time.perf_counter() - t0, 2)

        model_results = {"load_incl_sha256_s": load_s}
        for case_name, (path, _, _) in cases.items():
            # 워밍업 — 첫 추론은 그래프 초기화로 항상 느리다(별도 기록)
            first = None
            for i in range(WARMUP):
                t0 = time.perf_counter()
                yolo_client.detect_and_annotate(path, model_key=model_key)
                if i == 0:
                    first = round((time.perf_counter() - t0) * 1000, 1)

            # ① 운영 전체 경로(detect_and_annotate): EXIF+predict+후처리+PNG 인코딩
            e2e = []
            for _ in range(N_RUNS):
                t0 = time.perf_counter()
                yolo_client.detect_and_annotate(path, model_key=model_key)
                e2e.append((time.perf_counter() - t0) * 1000)

            # ② predict 단독 + ultralytics 자체 분해(speed: preprocess/inference/postprocess)
            speeds = {"preprocess": [], "inference": [], "postprocess": []}
            imgsz = config.HTP_IMGSZ if model_key == "htp" else config.SKETCH_IMGSZ
            for _ in range(N_RUNS):
                r = model.predict(path, conf=config.YOLO_CONF_THRESHOLD, imgsz=imgsz, verbose=False)[0]
                for k in speeds:
                    speeds[k].append(r.speed[k])

            model_results[case_name] = {
                "first_call_ms": first,
                "full_path_ms": {
                    "p50": round(pct(e2e, 50), 1),
                    "p95": round(pct(e2e, 95), 1),
                    "mean": round(statistics.mean(e2e), 1),
                },
                "predict_breakdown_ms_p50": {
                    k: round(pct(v, 50), 1) for k, v in speeds.items()
                },
            }
        results[model_key] = model_results

    out["models"] = results
    out["peak_rss_mib"] = round(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024, 1)
    out["cgroup_peak_mib"] = cgroup_peak_mib()
    print("BENCH_RESULT " + json.dumps(out, ensure_ascii=False))


if __name__ == "__main__":
    main()

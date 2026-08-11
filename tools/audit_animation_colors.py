from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path

import cv2
import numpy as np
from PIL import Image


GROUPS = [
    ("typing_ref", "desk_girl/typing"),
    ("idle_ref", "desk_girl/idle"),
    ("sleep_ref", "yellow_cat/sleep"),
    ("leave", "desk_girl/leave"),
    ("come_back", "desk_girl/come_back"),
    ("use_mouse", "desk_girl/use_mouse"),
    ("drink_water_bonus", "desk_girl/drink_water_bonus"),
    ("cat_startled", "yellow_cat/startled"),
    ("cat_mischief", "yellow_cat/mischief"),
]


def bright_warm_neutral_mask(rgba: np.ndarray) -> np.ndarray:
    rgb = rgba[..., :3].astype(np.int16)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    yy = np.indices(r.shape)[0]
    return (
        (rgba[..., 3] >= 220)
        & (yy >= 300)
        & (r >= 150)
        & (g >= 125)
        & (b >= 115)
        & ((r - g) >= -5)
        & ((r - g) <= 75)
        & ((g - b) >= -8)
        & ((g - b) <= 50)
    )


def summarize_group(path: Path) -> dict:
    files = sorted(path.glob("*.png"))
    if not files:
        raise RuntimeError(f"No PNG files in {path}")
    indexes = np.linspace(0, len(files) - 1, min(12, len(files)), dtype=int)
    samples = []
    palette_samples: dict[str, list[np.ndarray]] = {"orange": [], "blue": []}
    info_keys: Counter[tuple[str, ...]] = Counter()
    sizes: Counter[tuple[int, int]] = Counter()
    modes: Counter[str] = Counter()
    for index in indexes:
        with Image.open(files[int(index)]) as image:
            info_keys[tuple(sorted(image.info.keys()))] += 1
            sizes[image.size] += 1
            modes[image.mode] += 1
            rgba = np.asarray(image.convert("RGBA"), dtype=np.uint8)
        mask = bright_warm_neutral_mask(rgba)
        if mask.any():
            samples.append(rgba[..., :3][mask])
        rgb16 = rgba[..., :3].astype(np.int16)
        r, g, b = rgb16[..., 0], rgb16[..., 1], rgb16[..., 2]
        visible = rgba[..., 3] >= 220
        orange = visible & (r >= 140) & ((r - g) >= 35) & ((g - b) >= 25) & (b <= 170)
        blue = visible & ((b - r) >= 25) & ((g - r) >= 20) & (b >= 90)
        if orange.any():
            palette_samples["orange"].append(rgba[..., :3][orange])
        if blue.any():
            palette_samples["blue"].append(rgba[..., :3][blue])
    pixels = np.concatenate(samples, axis=0)
    lab = cv2.cvtColor(pixels.reshape(-1, 1, 3), cv2.COLOR_RGB2LAB).reshape(-1, 3)
    quantized = (pixels // 8) * 8 + 4
    top = Counter(map(tuple, quantized.tolist())).most_common(10)
    palettes = {}
    for palette_name, arrays in palette_samples.items():
        if not arrays:
            palettes[palette_name] = {"count": 0, "rgb_median": [], "lab_median": []}
            continue
        palette_pixels = np.concatenate(arrays, axis=0)
        palette_lab = cv2.cvtColor(
            palette_pixels.reshape(-1, 1, 3), cv2.COLOR_RGB2LAB
        ).reshape(-1, 3)
        palettes[palette_name] = {
            "count": int(palette_pixels.shape[0]),
            "rgb_median": [int(value) for value in np.median(palette_pixels, axis=0)],
            "lab_median": [
                float(round(value, 3)) for value in np.median(palette_lab, axis=0)
            ],
        }
    return {
        "path": str(path),
        "frame_count": len(files),
        "sampled_frames": len(indexes),
        "sample_pixels": int(pixels.shape[0]),
        "rgb_median": [int(value) for value in np.median(pixels, axis=0)],
        "lab_median": [float(round(value, 3)) for value in np.median(lab, axis=0)],
        "lab_mean": [float(round(value, 3)) for value in np.mean(lab, axis=0)],
        "top_quantized_rgb": [
            {"rgb": [int(v) for v in color], "count": int(count)} for color, count in top
        ],
        "modes": {key: value for key, value in modes.items()},
        "sizes": {f"{key[0]}x{key[1]}": value for key, value in sizes.items()},
        "png_info_keys": {"|".join(key) or "none": value for key, value in info_keys.items()},
        "palettes": palettes,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    args = parser.parse_args()
    groups = {name: summarize_group(args.root / rel) for name, rel in GROUPS}
    payload = {"groups": groups}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    for name, item in groups.items():
        print(
            name,
            "rgb=", item["rgb_median"],
            "lab=", item["lab_median"],
            "info=", item["png_info_keys"],
        )


if __name__ == "__main__":
    main()

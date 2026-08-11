from __future__ import annotations

import argparse
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageFilter


def largest_component(mask: np.ndarray) -> np.ndarray:
    count, labels, stats, _ = cv2.connectedComponentsWithStats(
        mask.astype(np.uint8), connectivity=8
    )
    if count < 2:
        raise RuntimeError("No foreground component found")
    largest = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
    return labels == largest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--candidate", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--shift-y", type=int, default=-24)
    args = parser.parse_args()

    source = Image.open(args.source).convert("RGB")
    candidate = Image.open(args.candidate).convert("RGB")
    if candidate.size != source.size:
        candidate = candidate.resize(source.size, Image.Resampling.LANCZOS)

    src = np.asarray(source, dtype=np.uint8)
    cand = np.asarray(candidate, dtype=np.uint8)
    bg = np.median(
        np.concatenate([src[0], src[-1], src[:, 0], src[:, -1]], axis=0),
        axis=0,
    ).astype(np.uint8)

    src_dist = np.linalg.norm(src.astype(np.int16) - bg.astype(np.int16), axis=2)
    source_foreground = largest_component(src_dist > 12.0)

    # The generated background varies in brightness, but stays green in hue.
    # Extract the warm orange/brown subject and dark wood by hue, not luminance.
    hsv = cv2.cvtColor(cand, cv2.COLOR_RGB2HSV)
    green = (hsv[..., 0] >= 38) & (hsv[..., 0] <= 96) & (hsv[..., 1] >= 55)
    candidate_foreground = largest_component(~green)
    candidate_foreground = cv2.morphologyEx(
        candidate_foreground.astype(np.uint8),
        cv2.MORPH_CLOSE,
        np.ones((3, 3), dtype=np.uint8),
    ).astype(bool)

    ys, xs = np.nonzero(candidate_foreground)
    x0, x1 = int(xs.min()), int(xs.max()) + 1
    y0, y1 = int(ys.min()), int(ys.max()) + 1

    crop_rgb = Image.fromarray(cand[y0:y1, x0:x1], mode="RGB")
    crop_alpha = Image.fromarray(
        (candidate_foreground[y0:y1, x0:x1] * 255).astype(np.uint8), mode="L"
    ).filter(ImageFilter.GaussianBlur(0.45))
    crop = crop_rgb.convert("RGBA")
    crop.putalpha(crop_alpha)

    # Preserve all visible source-background pixels and clear only the old group.
    clean = src.copy()
    clean[source_foreground] = bg
    result = Image.fromarray(clean, mode="RGB")
    paste_x = x0
    paste_y = y0 + args.shift_y
    result.paste(crop.convert("RGB"), (paste_x, paste_y), crop.getchannel("A"))

    args.output.parent.mkdir(parents=True, exist_ok=True)
    result.save(args.output, format="PNG", optimize=True)

    placed_mask = np.zeros(source_foreground.shape, dtype=bool)
    placed_alpha = np.asarray(crop.getchannel("A"), dtype=np.uint8) > 0
    placed_mask[paste_y : paste_y + crop.height, paste_x : paste_x + crop.width] = placed_alpha
    out = np.asarray(result, dtype=np.uint8)
    changed = np.any(out != src, axis=2)
    allowed = source_foreground | placed_mask
    changed_outside = int(np.count_nonzero(changed & ~allowed))

    report = {
        "source": args.source.as_posix(),
        "candidate": args.candidate.as_posix(),
        "output": args.output.as_posix(),
        "canvas": [source.width, source.height],
        "source_background_rgb": [int(v) for v in bg],
        "candidate_foreground_bbox": [x0, y0, x1, y1],
        "final_foreground_bbox": [x0, paste_y, x1, paste_y + crop.height],
        "vertical_shift": args.shift_y,
        "changed_pixels_outside_allowed_mask": changed_outside,
        "exact_lock_pass": changed_outside == 0,
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

from __future__ import annotations

import argparse
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    args = parser.parse_args()

    source_image = Image.open(args.input).convert("RGB")
    source = np.asarray(source_image, dtype=np.uint8)
    r = source[..., 0].astype(np.int16)
    g = source[..., 1].astype(np.int16)
    b = source[..., 2].astype(np.int16)
    candidate = ((g > r + 28) & (g > b + 24) & (g > 80)).astype(np.uint8)

    count, labels, stats, _ = cv2.connectedComponentsWithStats(candidate, connectivity=8)
    if count < 2:
        raise RuntimeError("No connected green background found")
    areas = stats[1:, cv2.CC_STAT_AREA]
    background_label = 1 + int(np.argmax(areas))
    background = labels == background_label

    final = source.copy()
    final[background] = np.array([31, 159, 82], dtype=np.uint8)
    if final.shape[1] == 1449:
        final = final[:, :1448]
        background = background[:, :1448]
        source = source[:, :1448]

    args.output.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(final, mode="RGB").save(args.output, format="PNG", optimize=True)

    changed = np.any(final != source, axis=2)
    changed_outside_background = int(np.count_nonzero(changed & ~background))
    top_unique = int(np.unique(final[:420].reshape(-1, 3), axis=0).shape[0])
    report = {
        "input": str(args.input),
        "output": str(args.output),
        "output_canvas": [int(final.shape[1]), int(final.shape[0])],
        "background_rgb": [31, 159, 82],
        "background_pixels": int(np.count_nonzero(background)),
        "changed_pixels_outside_background": changed_outside_background,
        "top_background_unique_colors": top_unique,
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

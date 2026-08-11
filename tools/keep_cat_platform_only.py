#!/usr/bin/env python3
"""Keep only the yellow cat and platform components in startled frames."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image


CAT_CORE = (430, 250, 900, 405)  # left, top, right-exclusive, bottom-exclusive
PLATFORM_CORE = (0, 340, 1112, 436)


def intersects_core(labels: np.ndarray, label: int, core: tuple[int, int, int, int]) -> bool:
    left, top, right, bottom = core
    return bool(np.any(labels[top:bottom, left:right] == label))


def process_frame(source: Path, destination: Path) -> dict[str, object]:
    before = np.array(Image.open(source).convert("RGBA"), dtype=np.uint8)
    alpha_mask = (before[:, :, 3] > 0).astype(np.uint8)
    count, labels, stats, _ = cv2.connectedComponentsWithStats(alpha_mask, 8)

    keep_labels: set[int] = set()
    components: list[dict[str, object]] = []
    for label in range(1, count):
        x, y, width, height, area = (int(value) for value in stats[label])
        max_alpha = int(np.max(before[:, :, 3][labels == label]))
        keep = area >= 8 and max_alpha >= 16 and (
            intersects_core(labels, label, CAT_CORE)
            or intersects_core(labels, label, PLATFORM_CORE)
        )
        if keep:
            keep_labels.add(label)
        components.append(
            {
                "area": area,
                "max_alpha": max_alpha,
                "bbox": [x, y, width, height],
                "kept": keep,
            }
        )

    # Clear hidden RGB and nearly transparent matte fringes even when they are
    # technically connected to the retained cat/platform component.
    keep_mask = np.isin(labels, list(keep_labels)) & (before[:, :, 3] >= 8)
    after = before.copy()
    after[~keep_mask] = (0, 0, 0, 0)

    destination.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(after, "RGBA").save(destination)

    changed_mask = np.any(before != after, axis=2)
    preserved_errors = int(np.count_nonzero(np.any(before[keep_mask] != after[keep_mask], axis=1)))
    removed = sorted(
        (item for item in components if not item["kept"]),
        key=lambda item: int(item["area"]),
        reverse=True,
    )
    kept = sorted(
        (item for item in components if item["kept"]),
        key=lambda item: int(item["area"]),
        reverse=True,
    )
    return {
        "file": source.name,
        "size": [int(before.shape[1]), int(before.shape[0])],
        "component_count": count - 1,
        "kept_components": len(keep_labels),
        "cleared_pixels": int(np.count_nonzero(changed_mask)),
        "preserved_pixel_errors": preserved_errors,
        "remaining_nonzero_pixels_outside_keep": int(
            np.count_nonzero(np.any(after[~keep_mask] != 0, axis=1))
        ),
        "largest_kept_components": kept[:12],
        "largest_removed_components": removed[:5],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source_dir", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()

    sources = sorted(args.source_dir.glob("*.png"))
    if not sources:
        raise SystemExit(f"No PNG files found in {args.source_dir}")

    results = [process_frame(source, args.output_dir / source.name) for source in sources]
    report = {
        "source_dir": str(args.source_dir),
        "output_dir": str(args.output_dir),
        "frame_count": len(results),
        "cleared_pixels": sum(int(item["cleared_pixels"]) for item in results),
        "preserved_pixel_errors": sum(
            int(item["preserved_pixel_errors"]) for item in results
        ),
        "remaining_nonzero_pixels_outside_keep": sum(
            int(item["remaining_nonzero_pixels_outside_keep"]) for item in results
        ),
        "frames": results,
    }
    encoded = json.dumps(report, ensure_ascii=False, indent=2)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(encoded + "\n", encoding="utf-8")
    print(encoded)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

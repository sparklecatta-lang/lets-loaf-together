from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def analyze_components(rgba: np.ndarray) -> tuple[np.ndarray, list[dict]]:
    work = rgba.astype(np.int16)
    alpha = work[..., 3]
    green = work[..., 1]
    dominance = np.minimum(green - work[..., 0], green - work[..., 2])
    pure_green = (alpha > 0) & (green >= 65) & (dominance > 4)
    foreground = (alpha > 0).astype(np.uint8)
    distance = cv2.distanceTransform(foreground, cv2.DIST_L2, 3)
    count, labels, stats, _ = cv2.connectedComponentsWithStats(
        pure_green.astype(np.uint8), connectivity=8
    )
    selected = np.zeros_like(pure_green)
    records: list[dict] = []
    for label in range(1, count):
        component = labels == label
        area = int(stats[label, cv2.CC_STAT_AREA])
        if area < 2:
            continue
        edge_distance = float(distance[component].min())
        edge_alpha = alpha[component]
        mean_alpha = float(edge_alpha.mean())
        touches_edge = edge_distance <= 3.1 or (
            mean_alpha < 200.0 and edge_distance <= 8.0
        )
        if touches_edge:
            selected |= component
        x = int(stats[label, cv2.CC_STAT_LEFT])
        y = int(stats[label, cv2.CC_STAT_TOP])
        width = int(stats[label, cv2.CC_STAT_WIDTH])
        height = int(stats[label, cv2.CC_STAT_HEIGHT])
        median = np.median(work[..., :3][component], axis=0)
        records.append(
            {
                "area": area,
                "bbox": [x, y, x + width, y + height],
                "median_rgb": [int(round(value)) for value in median],
                "max_green_dominance": int(dominance[component].max()),
                "mean_alpha": round(mean_alpha, 2),
                "min_foreground_edge_distance": round(edge_distance, 3),
                "selected": touches_edge,
            }
        )
    records.sort(key=lambda item: item["area"], reverse=True)
    return selected, records


def repair_rgba(rgba: np.ndarray) -> tuple[np.ndarray, dict]:
    original = rgba.copy()
    work = rgba.astype(np.float32)
    alpha = work[..., 3]
    selected, components = analyze_components(rgba)

    green = work[..., 1]
    dominance = np.minimum(green - work[..., 0], green - work[..., 2])
    key_strength = np.clip((dominance - 4.0) / 20.0, 0.0, 1.0)
    old_alpha = alpha.copy()
    alpha[selected] *= 1.0 - key_strength[selected]

    # Preserve the matte while removing green-only spill from remaining soft edges.
    visible = old_alpha > 0
    semi_transparent = visible & (old_alpha < 255)
    edge_weight = np.zeros_like(old_alpha, dtype=np.float32)
    edge_weight[semi_transparent] = ((255.0 - old_alpha[semi_transparent]) / 255.0) ** 0.60
    green_excess = np.maximum(0.0, green - np.maximum(work[..., 0], work[..., 2]))
    work[..., 1] -= green_excess * edge_weight * 0.82
    work[..., 3] = np.rint(alpha)
    repaired = np.clip(np.rint(work), 0, 255).astype(np.uint8)
    repaired[..., :3][repaired[..., 3] == 0] = 0

    rgb_delta = np.abs(
        repaired[..., :3].astype(np.int16) - original[..., :3].astype(np.int16)
    )
    alpha_delta = np.abs(
        repaired[..., 3].astype(np.int16) - original[..., 3].astype(np.int16)
    )
    report = {
        "components": components,
        "selected_component_count": sum(1 for item in components if item["selected"]),
        "pure_green_pixels_selected": int(np.count_nonzero(selected)),
        "alpha_pixels_changed": int(np.count_nonzero(alpha_delta)),
        "rgb_pixels_changed": int(np.count_nonzero(np.any(rgb_delta > 0, axis=2))),
        "alpha_max_abs_delta": int(alpha_delta.max(initial=0)),
        "rgb_max_abs_delta": int(rgb_delta.max(initial=0)),
    }
    return repaired, report


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("inputs", nargs="+", type=Path)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--audit-only", action="store_true")
    args = parser.parse_args()

    files: list[Path] = []
    for path in args.inputs:
        if path.is_dir():
            files.extend(sorted(path.glob("*.png")))
        elif path.suffix.lower() == ".png" and path.exists():
            files.append(path)
    if not files:
        raise SystemExit("No PNG files found")
    if not args.audit_only and args.output_dir is None:
        raise SystemExit("--output-dir is required unless --audit-only is used")

    records = []
    for path in files:
        rgba = np.array(Image.open(path).convert("RGBA"), dtype=np.uint8, copy=True)
        repaired, details = repair_rgba(rgba)
        record = {
            "file": str(path),
            "size": [int(rgba.shape[1]), int(rgba.shape[0])],
            "source_sha256": sha256(path),
            **details,
        }
        if not args.audit_only:
            assert args.output_dir is not None
            args.output_dir.mkdir(parents=True, exist_ok=True)
            output = args.output_dir / path.name
            Image.fromarray(repaired, "RGBA").save(output, optimize=True)
            record["output"] = str(output)
            record["output_sha256"] = sha256(output)
        records.append(record)

    summary = {
        "file_count": len(records),
        "pure_green_pixels_selected": sum(
            item["pure_green_pixels_selected"] for item in records
        ),
        "alpha_pixels_changed": sum(item["alpha_pixels_changed"] for item in records),
        "rgb_pixels_changed": sum(item["rgb_pixels_changed"] for item in records),
    }
    payload = {"summary": summary, "records": records}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(summary, ensure_ascii=False))


if __name__ == "__main__":
    main()

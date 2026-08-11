from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image


GROUPS = [
    ("desk_girl_leave", "desk_girl/leave", False),
    ("desk_girl_come_back", "desk_girl/come_back", False),
    ("desk_girl_use_mouse", "desk_girl/use_mouse", False),
    ("desk_girl_drink_water_bonus", "desk_girl/drink_water_bonus", False),
    ("yellow_cat_startled", "yellow_cat/startled", True),
    ("yellow_cat_mischief", "yellow_cat/mischief", True),
]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_rgba(path: Path) -> np.ndarray:
    return np.array(Image.open(path).convert("RGBA"), dtype=np.uint8, copy=True)


def desk_material_candidate(rgba: np.ndarray) -> np.ndarray:
    rgb = rgba[..., :3].astype(np.int16)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    return (
        (rgba[..., 3] >= 220)
        & (r >= 185)
        & (g >= 165)
        & (b >= 155)
        & ((r - g) >= -5)
        & ((r - g) <= 65)
        & ((g - b) >= -8)
        & ((g - b) <= 40)
    )


def large_components(mask: np.ndarray, *, min_area: int, min_width: int = 0) -> np.ndarray:
    count, labels, stats, _ = cv2.connectedComponentsWithStats(
        mask.astype(np.uint8), connectivity=8
    )
    selected = np.zeros_like(mask)
    for label in range(1, count):
        area = int(stats[label, cv2.CC_STAT_AREA])
        width = int(stats[label, cv2.CC_STAT_WIDTH])
        if area >= min_area and width >= min_width:
            selected |= labels == label
    return selected


def build_spatial_masks(root: Path) -> tuple[np.ndarray, np.ndarray]:
    reference_paths = [
        root / "desk_girl/typing/frame_0012.png",
        root / "desk_girl/idle/frame_0006.png",
    ]
    main = None
    for path in reference_paths:
        rgba = load_rgba(path)
        candidate = desk_material_candidate(rgba)
        yy, xx = np.indices(candidate.shape)
        candidate &= (xx >= 330) & (yy >= 430)
        selected = large_components(candidate, min_area=5000)
        main = selected if main is None else (main | selected)
    assert main is not None
    main = cv2.dilate(main.astype(np.uint8), np.ones((9, 9), np.uint8)).astype(bool)

    platform_reference = load_rgba(root / "yellow_cat/sleep/frame_0007.png")
    platform_candidate = desk_material_candidate(platform_reference)
    yy, _ = np.indices(platform_candidate.shape)
    platform_candidate &= (yy >= 330) & (yy < 432)
    platform = large_components(platform_candidate, min_area=5000, min_width=500)
    platform = cv2.dilate(platform.astype(np.uint8), np.ones((7, 7), np.uint8)).astype(bool)
    platform[432:, :] = False
    main[:432, :] = False
    return main, platform


def lab_pixels(rgba: np.ndarray, spatial: np.ndarray) -> np.ndarray:
    mask = desk_material_candidate(rgba) & spatial
    if not mask.any():
        return np.empty((0, 3), dtype=np.uint8)
    lab = cv2.cvtColor(rgba[..., :3], cv2.COLOR_RGB2LAB)
    return lab[mask]


def target_lab(root: Path, main: np.ndarray) -> np.ndarray:
    pixels = []
    for rel in ("desk_girl/typing", "desk_girl/idle"):
        files = sorted((root / rel).glob("*.png"))
        indexes = np.linspace(0, len(files) - 1, min(12, len(files)), dtype=int)
        for index in indexes:
            values = lab_pixels(load_rgba(files[int(index)]), main)
            if values.size:
                pixels.append(values)
    return np.median(np.concatenate(pixels, axis=0), axis=0).astype(np.float32)


def group_zone_delta(
    files: list[Path], spatial: np.ndarray, target: np.ndarray
) -> tuple[np.ndarray, int, list[float]]:
    pixels = []
    indexes = np.linspace(0, len(files) - 1, min(16, len(files)), dtype=int)
    for index in indexes:
        values = lab_pixels(load_rgba(files[int(index)]), spatial)
        if values.size:
            pixels.append(values)
    if not pixels:
        return np.zeros(3, dtype=np.float32), 0, []
    source = np.median(np.concatenate(pixels, axis=0), axis=0).astype(np.float32)
    delta = np.clip(target - source, -10.0, 10.0)
    return delta, int(sum(item.shape[0] for item in pixels)), source.tolist()


def apply_delta(
    rgba: np.ndarray, spatial: np.ndarray, delta: np.ndarray
) -> tuple[np.ndarray, int]:
    mask = desk_material_candidate(rgba) & spatial
    if not mask.any() or not np.any(delta):
        return rgba, 0
    lab = cv2.cvtColor(rgba[..., :3], cv2.COLOR_RGB2LAB).astype(np.float32)
    lab[mask] = np.clip(lab[mask] + delta, 0, 255)
    rgb = cv2.cvtColor(np.rint(lab).astype(np.uint8), cv2.COLOR_LAB2RGB)
    output = rgba.copy()
    output[..., :3][mask] = rgb[mask]
    return output, int(np.count_nonzero(mask))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--output-root", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--sample-only", action="store_true")
    args = parser.parse_args()

    main_mask, platform_mask = build_spatial_masks(args.root)
    target = target_lab(args.root, main_mask)
    records = []
    for output_name, relative, has_platform in GROUPS:
        files = sorted((args.root / relative).glob("*.png"))
        main_delta, main_count, main_source = group_zone_delta(files, main_mask, target)
        if has_platform:
            platform_delta, platform_count, platform_source = group_zone_delta(
                files, platform_mask, target
            )
        else:
            platform_delta = np.zeros(3, dtype=np.float32)
            platform_count = 0
            platform_source = []
        selected_files = [files[len(files) // 2]] if args.sample_only else files
        output_dir = args.output_root / output_name
        output_dir.mkdir(parents=True, exist_ok=True)
        frame_records = []
        for path in selected_files:
            source = load_rgba(path)
            output, main_changed = apply_delta(source, main_mask, main_delta)
            output, platform_changed = apply_delta(output, platform_mask, platform_delta)
            output[..., :3][output[..., 3] == 0] = source[..., :3][source[..., 3] == 0]
            out_path = output_dir / path.name
            Image.fromarray(output, "RGBA").save(out_path, optimize=True)
            alpha_delta = np.abs(
                output[..., 3].astype(np.int16) - source[..., 3].astype(np.int16)
            )
            changed = np.any(output != source, axis=2)
            permitted = (
                (desk_material_candidate(source) & main_mask)
                | (desk_material_candidate(source) & platform_mask)
            )
            frame_records.append(
                {
                    "file": path.name,
                    "source_sha256": sha256(path),
                    "output_sha256": sha256(out_path),
                    "main_pixels_changed": main_changed,
                    "platform_pixels_changed": platform_changed,
                    "alpha_max_abs_delta": int(alpha_delta.max(initial=0)),
                    "changed_pixels_outside_desk_mask": int(
                        np.count_nonzero(changed & ~permitted)
                    ),
                }
            )
        records.append(
            {
                "group": output_name,
                "relative": relative,
                "frame_count": len(files),
                "processed_frame_count": len(selected_files),
                "target_lab": target.tolist(),
                "main_source_lab": main_source,
                "main_sample_pixels": main_count,
                "main_delta_lab": main_delta.tolist(),
                "platform_source_lab": platform_source,
                "platform_sample_pixels": platform_count,
                "platform_delta_lab": platform_delta.tolist(),
                "frames": frame_records,
            }
        )

    payload = {"target_lab": target.tolist(), "groups": records}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(payload, ensure_ascii=False))


if __name__ == "__main__":
    main()

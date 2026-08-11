from __future__ import annotations

import argparse
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image


def cover_resize(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    target_w, target_h = size
    source_ratio = image.width / image.height
    target_ratio = target_w / target_h
    if source_ratio > target_ratio:
        crop_w = round(image.height * target_ratio)
        left = (image.width - crop_w) // 2
        image = image.crop((left, 0, left + crop_w, image.height))
    else:
        crop_h = round(image.width / target_ratio)
        top = (image.height - crop_h) // 2
        image = image.crop((0, top, image.width, top + crop_h))
    return image.resize(size, Image.Resampling.LANCZOS)


def border_connected_chroma(source_rgb: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    # The source has a flat green screen. Border connectivity prevents isolated
    # green foreground details (for example the keyboard keycap) from being keyed.
    corner_samples = np.concatenate(
        [
            source_rgb[:12, :12].reshape(-1, 3),
            source_rgb[:12, -12:].reshape(-1, 3),
        ],
        axis=0,
    )
    key = np.median(corner_samples, axis=0).astype(np.float32)
    pixels = source_rgb.astype(np.float32)
    distance = np.linalg.norm(pixels - key, axis=2)
    green_dominance = pixels[:, :, 1] - np.maximum(pixels[:, :, 0], pixels[:, :, 2])
    candidate = ((distance <= 92.0) & (green_dominance >= 18.0)).astype(np.uint8)

    count, labels, stats, _ = cv2.connectedComponentsWithStats(candidate, 8)
    selected = np.zeros(candidate.shape, dtype=bool)
    height, width = candidate.shape
    for label in range(1, count):
        x, y, w, h, area = stats[label]
        touches_border = x == 0 or y == 0 or x + w == width or y + h == height
        if touches_border or area >= 5000:
            selected |= labels == label

    # Smooth only inside the selected green-connected region. Unselected source
    # pixels remain bit-for-bit unchanged in the preview.
    replace = np.zeros(candidate.shape, dtype=np.float32)
    replace[selected] = np.clip((72.0 - distance[selected]) / 60.0, 0.0, 1.0)
    return replace, key.astype(np.uint8)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--generated", required=True, type=Path)
    parser.add_argument("--background", required=True, type=Path)
    parser.add_argument("--preview", required=True, type=Path)
    parser.add_argument("--mask", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    args = parser.parse_args()

    source = Image.open(args.source).convert("RGB")
    generated = Image.open(args.generated).convert("RGB")
    background = cover_resize(generated, source.size)

    source_np = np.asarray(source, dtype=np.uint8)
    background_np = np.asarray(background, dtype=np.uint8)
    replace, key = border_connected_chroma(source_np)
    weight = replace[:, :, None]
    preview_np = np.rint(source_np * (1.0 - weight) + background_np * weight).astype(np.uint8)

    changed = np.any(preview_np != source_np, axis=2)
    allowed = replace > 0.0
    outside_changes = int(np.count_nonzero(changed & ~allowed))

    for path in (args.background, args.preview, args.mask, args.report):
        path.parent.mkdir(parents=True, exist_ok=True)
    background.save(args.background, compress_level=6)
    Image.fromarray(preview_np, "RGB").save(args.preview, compress_level=6)
    Image.fromarray(np.where(allowed, 255, 0).astype(np.uint8), "L").save(args.mask)

    report = {
        "source": str(args.source),
        "generated": str(args.generated),
        "source_size": list(source.size),
        "generated_size": list(generated.size),
        "final_background_size": list(background.size),
        "sampled_chroma_rgb": key.tolist(),
        "allowed_background_pixels": int(np.count_nonzero(allowed)),
        "changed_pixels_outside_mask": outside_changes,
        "exact_foreground_lock_pass": outside_changes == 0,
    }
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

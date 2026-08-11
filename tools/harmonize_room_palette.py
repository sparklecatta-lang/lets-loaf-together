from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def median_rgb(image: np.ndarray, mask: np.ndarray) -> list[int]:
    pixels = image[:, :, :3][mask]
    if pixels.size == 0:
        return [0, 0, 0]
    return np.median(pixels, axis=0).astype(int).tolist()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--interior", required=True)
    parser.add_argument("--exterior", required=True)
    parser.add_argument("--actor", required=True)
    parser.add_argument("--output-interior", required=True)
    parser.add_argument("--output-preview", required=True)
    parser.add_argument("--output-runtime-preview", required=True)
    parser.add_argument("--output-allowed-mask", required=True)
    parser.add_argument("--report", required=True)
    parser.add_argument("--floor-start", type=int, default=742)
    args = parser.parse_args()

    interior_path = Path(args.interior).resolve()
    exterior_path = Path(args.exterior).resolve()
    actor_path = Path(args.actor).resolve()
    interior = np.asarray(Image.open(interior_path).convert("RGBA"), dtype=np.uint8).copy()
    original = interior.copy()
    exterior = Image.open(exterior_path).convert("RGBA")
    if exterior.size != (interior.shape[1], interior.shape[0]):
        raise ValueError("Exterior and interior canvas sizes differ")

    opaque = interior[:, :, 3] > 0
    hsv = np.asarray(Image.fromarray(interior[:, :, :3], "RGB").convert("HSV"), dtype=np.uint8).copy()
    hue = hsv[:, :, 0].astype(np.float32)
    sat = hsv[:, :, 1].astype(np.float32)
    value = hsv[:, :, 2].astype(np.float32)
    y = np.arange(interior.shape[0])[:, None]

    # Warm room surfaces only: remove the strong yellow-orange cast and bring
    # them toward the platform's cream top and pale peach front edge.
    warm = opaque & ((hue <= 45) | (hue >= 246)) & (sat >= 28)
    upper = warm & (y < args.floor_start)
    floor = warm & (y >= args.floor_start)

    hue[upper] = np.where(hue[upper] >= 246, hue[upper], hue[upper] * 0.68)
    upper_sat_scale = np.where(value[upper] < 105, 0.74, 0.58)
    sat[upper] *= upper_sat_scale
    value[upper] += (255.0 - value[upper]) * 0.045

    hue[floor] = np.where(hue[floor] >= 246, hue[floor], hue[floor] * 0.75)
    sat[floor] *= 0.64
    value[floor] += (255.0 - value[floor]) * 0.065

    hsv[:, :, 0] = np.clip(np.rint(hue), 0, 255).astype(np.uint8)
    hsv[:, :, 1] = np.clip(np.rint(sat), 0, 255).astype(np.uint8)
    hsv[:, :, 2] = np.clip(np.rint(value), 0, 255).astype(np.uint8)
    recolored_rgb = np.asarray(Image.fromarray(hsv, "HSV").convert("RGB"), dtype=np.uint8)
    interior[:, :, :3][opaque] = recolored_rgb[opaque]

    output_interior_path = Path(args.output_interior).resolve()
    output_preview_path = Path(args.output_preview).resolve()
    output_runtime_path = Path(args.output_runtime_preview).resolve()
    allowed_mask_path = Path(args.output_allowed_mask).resolve()
    report_path = Path(args.report).resolve()
    for path in (output_interior_path, output_preview_path, output_runtime_path, allowed_mask_path, report_path):
        path.parent.mkdir(parents=True, exist_ok=True)

    interior_image = Image.fromarray(interior, "RGBA")
    interior_image.save(output_interior_path)
    preview = Image.alpha_composite(exterior, interior_image)
    preview.save(output_preview_path)

    # The production yellow-cat frame still carries a green field. Remove only
    # that chroma field to make an honest full-canvas palette preview.
    actor = np.asarray(Image.open(actor_path).convert("RGBA"), dtype=np.uint8).copy()
    if actor.shape != interior.shape:
        raise ValueError("Actor and room canvas sizes differ")
    r = actor[:, :, 0].astype(np.int16)
    g = actor[:, :, 1].astype(np.int16)
    b = actor[:, :, 2].astype(np.int16)
    green = (g > 65) & (g > r * 1.18) & (g > b * 1.10) & ((g - r) > 18) & ((g - b) > 8)
    actor[green, 3] = 0
    runtime_preview = Image.alpha_composite(preview, Image.fromarray(actor, "RGBA"))
    runtime_preview.save(output_runtime_path)

    allowed = (opaque.astype(np.uint8) * 255)
    Image.fromarray(allowed, "L").save(allowed_mask_path)

    changed = np.any(original[:, :, :3] != interior[:, :, :3], axis=2)
    report = {
        "ok": bool(np.count_nonzero(changed & ~opaque) == 0),
        "source": str(interior_path),
        "source_sha256": sha256(interior_path),
        "output_interior": str(output_interior_path),
        "output_interior_sha256": sha256(output_interior_path),
        "output_preview": str(output_preview_path),
        "output_runtime_preview": str(output_runtime_path),
        "changed_pixels": int(np.count_nonzero(changed)),
        "changed_pixels_outside_interior": int(np.count_nonzero(changed & ~opaque)),
        "wall_median_before": median_rgb(original, opaque & (y >= 380) & (y < 680)),
        "wall_median_after": median_rgb(interior, opaque & (y >= 380) & (y < 680)),
        "floor_median_before": median_rgb(original, opaque & (y >= args.floor_start)),
        "floor_median_after": median_rgb(interior, opaque & (y >= args.floor_start)),
    }
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if not report["ok"]:
        raise RuntimeError("Exterior lock failed")


if __name__ == "__main__":
    main()

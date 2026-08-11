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


def save_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def command_cutout(args: argparse.Namespace) -> None:
    source_path = Path(args.source).resolve()
    mask_path = Path(args.mask).resolve()
    output_path = Path(args.output).resolve()
    source = np.asarray(Image.open(source_path).convert("RGBA"), dtype=np.uint8).copy()
    mask = np.asarray(Image.open(mask_path).convert("L"), dtype=np.uint8) > 127
    if source.shape[:2] != mask.shape:
        raise ValueError(f"Mask size {mask.shape[::-1]} does not match source {source.shape[1::-1]}")

    output = source.copy()
    output[mask, 3] = 0
    output_path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(output, "RGBA").save(output_path)

    changed = np.any(source != output, axis=2)
    changed_outside = int(np.count_nonzero(changed & ~mask))
    report = {
        "ok": changed_outside == 0,
        "source": str(source_path),
        "source_sha256": sha256(source_path),
        "mask": str(mask_path),
        "output": str(output_path),
        "output_sha256": sha256(output_path),
        "canvas": [int(source.shape[1]), int(source.shape[0])],
        "transparent_pixels": int(np.count_nonzero(output[:, :, 3] == 0)),
        "allowed_change_pixels": int(np.count_nonzero(mask)),
        "changed_pixels_outside_mask": changed_outside,
        "rgb_pixels_changed": int(np.count_nonzero(np.any(source[:, :, :3] != output[:, :, :3], axis=2))),
    }
    save_json(Path(args.report).resolve(), report)
    if not report["ok"]:
        raise RuntimeError("Pixel lock failed")


def cover_crop(image: Image.Image, width: int, height: int) -> Image.Image:
    scale = max(width / image.width, height / image.height)
    resized = image.resize(
        (max(width, round(image.width * scale)), max(height, round(image.height * scale))),
        Image.Resampling.LANCZOS,
    )
    left = max(0, (resized.width - width) // 2)
    top = max(0, (resized.height - height) // 2)
    return resized.crop((left, top, left + width, top + height))


def command_candidate(args: argparse.Namespace) -> None:
    candidate_path = Path(args.candidate).resolve()
    interior_path = Path(args.interior).resolve()
    mask_path = Path(args.mask).resolve()
    layer_path = Path(args.output_layer).resolve()
    preview_path = Path(args.output_preview).resolve()

    interior = Image.open(interior_path).convert("RGBA")
    mask = np.asarray(Image.open(mask_path).convert("L"), dtype=np.uint8) > 127
    ys, xs = np.nonzero(mask)
    if xs.size == 0:
        raise ValueError("Pane mask is empty")
    x1, x2 = int(xs.min()), int(xs.max()) + 1
    y1, y2 = int(ys.min()), int(ys.max()) + 1

    candidate = Image.open(candidate_path).convert("RGB")
    pane_scene = cover_crop(candidate, x2 - x1, y2 - y1)
    layer = Image.new("RGBA", interior.size, (5, 10, 18, 255))
    layer.paste(pane_scene.convert("RGBA"), (x1, y1))
    preview = Image.alpha_composite(layer, interior)

    layer_path.parent.mkdir(parents=True, exist_ok=True)
    preview_path.parent.mkdir(parents=True, exist_ok=True)
    layer.save(layer_path)
    preview.save(preview_path)
    save_json(
        Path(args.report).resolve(),
        {
            "ok": True,
            "candidate": str(candidate_path),
            "candidate_sha256": sha256(candidate_path),
            "interior": str(interior_path),
            "pane_bbox": [x1, y1, x2, y2],
            "canvas": list(interior.size),
            "output_layer": str(layer_path),
            "output_preview": str(preview_path),
        },
    )


def command_resize(args: argparse.Namespace) -> None:
    source_path = Path(args.source).resolve()
    output_path = Path(args.output).resolve()
    source = Image.open(source_path).convert("RGBA")
    resized = source.resize((args.width, args.height), Image.Resampling.LANCZOS)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    resized.save(output_path)
    save_json(
        Path(args.report).resolve(),
        {
            "ok": True,
            "source": str(source_path),
            "source_sha256": sha256(source_path),
            "source_size": list(source.size),
            "output": str(output_path),
            "output_sha256": sha256(output_path),
            "output_size": list(resized.size),
        },
    )


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser()
    commands = root.add_subparsers(dest="command", required=True)

    cutout = commands.add_parser("cutout")
    cutout.add_argument("--source", required=True)
    cutout.add_argument("--mask", required=True)
    cutout.add_argument("--output", required=True)
    cutout.add_argument("--report", required=True)
    cutout.set_defaults(run=command_cutout)

    candidate = commands.add_parser("candidate")
    candidate.add_argument("--candidate", required=True)
    candidate.add_argument("--interior", required=True)
    candidate.add_argument("--mask", required=True)
    candidate.add_argument("--output-layer", required=True)
    candidate.add_argument("--output-preview", required=True)
    candidate.add_argument("--report", required=True)
    candidate.set_defaults(run=command_candidate)

    resize = commands.add_parser("resize")
    resize.add_argument("--source", required=True)
    resize.add_argument("--output", required=True)
    resize.add_argument("--report", required=True)
    resize.add_argument("--width", type=int, required=True)
    resize.add_argument("--height", type=int, required=True)
    resize.set_defaults(run=command_resize)
    return root


if __name__ == "__main__":
    options = parser().parse_args()
    options.run(options)

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path

import numpy as np
from PIL import Image


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def resize_premultiplied(image: Image.Image, target: tuple[int, int]) -> Image.Image:
    rgba = np.asarray(image.convert("RGBA"), dtype=np.float32)
    alpha = rgba[..., 3:4] / 255.0
    premultiplied = np.concatenate((rgba[..., :3] * alpha, rgba[..., 3:4]), axis=2)
    resized = np.asarray(
        Image.fromarray(np.clip(premultiplied, 0, 255).astype(np.uint8), "RGBA").resize(
            target, Image.Resampling.LANCZOS
        ),
        dtype=np.float32,
    )
    resized_alpha = resized[..., 3:4]
    output = np.zeros_like(resized, dtype=np.uint8)
    output[..., 3] = np.clip(resized_alpha[..., 0], 0, 255).astype(np.uint8)
    visible = resized_alpha[..., 0] > 0
    output[visible, :3] = np.clip(
        resized[visible, :3] * 255.0 / resized_alpha[visible], 0, 255
    ).round().astype(np.uint8)
    return Image.fromarray(output, "RGBA")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--target", default="1112x834")
    args = parser.parse_args()

    target = tuple(int(part) for part in args.target.lower().split("x"))
    frames = sorted(args.source.glob("*.png"))
    if not frames:
        raise FileNotFoundError(f"No PNG files in {args.source}")
    if args.output.exists() and any(args.output.iterdir()):
        raise FileExistsError(f"Refusing to overwrite non-empty directory: {args.output}")
    args.output.mkdir(parents=True, exist_ok=True)

    source_size: tuple[int, int] | None = None
    records: list[dict[str, object]] = []
    for frame in frames:
        with Image.open(frame) as source_image:
            if source_size is None:
                source_size = source_image.size
            elif source_image.size != source_size:
                raise RuntimeError(
                    f"Inconsistent frame size: {frame.name} is {source_image.size}, expected {source_size}"
                )
            final_image = resize_premultiplied(source_image, target)
            final_path = args.output / frame.name
            final_image.save(final_path, optimize=True, compress_level=9)
        records.append(
            {
                "file": frame.name,
                "source_sha256": sha256(frame),
                "final_sha256": sha256(final_path),
                "final_size": list(target),
            }
        )
        print(f"Resized {frame.name}", flush=True)

    metadata_source = args.source / "frames.json"
    if metadata_source.is_file():
        shutil.copy2(metadata_source, args.output / "frames.json")

    manifest = {
        "pipeline": [
            "premultiplied-alpha Lanczos resize",
            "unpremultiply visible pixels and zero hidden RGB where alpha is zero",
        ],
        "source_dir": str(args.source),
        "output_dir": str(args.output),
        "frame_count": len(frames),
        "source_size": list(source_size or (0, 0)),
        "target_size": list(target),
        "records": records,
    }
    (args.output / "处理清单.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"Completed {len(frames)} frames", flush=True)


if __name__ == "__main__":
    main()

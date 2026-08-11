from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import time
from pathlib import Path

import numpy as np
import cv2
from PIL import Image


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_box(value: str) -> tuple[int, int, int, int]:
    parts = [int(part.strip()) for part in value.split(",")]
    if len(parts) != 4:
        raise argparse.ArgumentTypeError("box must be x0,y0,x1,y1")
    x0, y0, x1, y1 = parts
    if x1 <= x0 or y1 <= y0:
        raise argparse.ArgumentTypeError("box must have positive width and height")
    return x0, y0, x1, y1


def alpha_counts(alpha: np.ndarray) -> dict[str, int]:
    return {
        "transparent": int((alpha == 0).sum()),
        "partial": int(((alpha > 0) & (alpha < 255)).sum()),
        "opaque": int((alpha == 255).sum()),
    }


def scaled_box(
    box: tuple[int, int, int, int],
    source_size: tuple[int, int],
    target_size: tuple[int, int],
) -> tuple[int, int, int, int]:
    sx = target_size[0] / source_size[0]
    sy = target_size[1] / source_size[1]
    x0, y0, x1, y1 = box
    return (
        max(0, round(x0 * sx)),
        max(0, round(y0 * sy)),
        min(target_size[0], round(x1 * sx)),
        min(target_size[1], round(y1 * sy)),
    )


def remove_watermarks(
    image: Image.Image,
    top_left: tuple[int, int, int, int],
    bottom_right: tuple[int, int, int, int],
) -> tuple[Image.Image, int, int]:
    rgba = np.asarray(image.convert("RGBA"), dtype=np.uint8).copy()
    x0, y0, x1, y1 = top_left
    rgb = rgba[..., :3].astype(np.int16)
    green_samples = (
        (rgba[..., 3] > 0)
        & (rgb[..., 1] > 90)
        & (rgb[..., 1] > rgb[..., 0] * 1.25)
        & (rgb[..., 1] > rgb[..., 2] * 1.25)
    )
    if not green_samples.any():
        raise RuntimeError("Unable to estimate the green background color")
    green_fill = np.median(rgba[..., :3][green_samples], axis=0).round().astype(np.uint8)
    rgba[y0:y1, x0:x1, :3] = green_fill
    rgba[y0:y1, x0:x1, 3] = 255

    bx0, by0, bx1, by1 = bottom_right
    bottom_visible = int((rgba[by0:by1, bx0:bx1, 3] > 0).sum())
    rgba[by0:by1, bx0:bx1] = 0
    return Image.fromarray(rgba, "RGBA"), (x1 - x0) * (y1 - y0), bottom_visible


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--realesrgan", type=Path, required=True)
    parser.add_argument("--models", type=Path, required=True)
    parser.add_argument("--model", default="realesrgan-x4plus-anime")
    parser.add_argument("--target", default="1112x834")
    parser.add_argument("--top-left", type=parse_box, required=True)
    parser.add_argument("--bottom-right", type=parse_box, required=True)
    parser.add_argument("--resume", action="store_true")
    args = parser.parse_args()

    target_width, target_height = [int(part) for part in args.target.lower().split("x")]
    target_size = (target_width, target_height)
    frames = sorted(args.source.glob("*.png"))
    if not frames:
        raise FileNotFoundError(f"No PNG files in {args.source}")
    if not args.realesrgan.is_file():
        raise FileNotFoundError(args.realesrgan)
    if not (args.models / f"{args.model}.param").is_file():
        raise FileNotFoundError(args.models / f"{args.model}.param")

    cleaned_dir = args.work / "01_watermarks_removed"
    esr_dir = args.work / "02_realesrgan_x4"
    for directory in (args.output, cleaned_dir, esr_dir):
        if directory.exists() and any(directory.iterdir()) and not args.resume:
            raise FileExistsError(f"Refusing to overwrite non-empty directory: {directory}")
        directory.mkdir(parents=True, exist_ok=True)

    boxes = [args.top_left, args.bottom_right]
    source_size: tuple[int, int] | None = None
    prepare_records: list[dict] = []
    for frame in frames:
        with Image.open(frame) as source_image:
            if source_size is None:
                source_size = source_image.size
            elif source_image.size != source_size:
                raise RuntimeError(f"Inconsistent frame size: {frame.name} is {source_image.size}, expected {source_size}")
            cleaned, top_inpainted, bottom_cleared = remove_watermarks(
                source_image,
                args.top_left,
                args.bottom_right,
            )
            cleaned_path = cleaned_dir / frame.name
            cleaned.save(cleaned_path, optimize=True, compress_level=9)
            prepare_records.append(
                {
                    "file": frame.name,
                    "source_sha256": sha256(frame),
                    "cleaned_sha256": sha256(cleaned_path),
                    "top_left_logo_pixels_inpainted": top_inpainted,
                    "bottom_right_visible_pixels_cleared": bottom_cleared,
                }
            )

    assert source_size is not None
    started = time.perf_counter()
    esr_complete = all((esr_dir / frame.name).is_file() for frame in frames)
    if not (args.resume and esr_complete):
        subprocess.run(
            [
                str(args.realesrgan),
                "-i",
                str(cleaned_dir),
                "-o",
                str(esr_dir),
                "-n",
                args.model,
                "-m",
                str(args.models),
                "-f",
                "png",
                "-s",
                "4",
            ],
            check=True,
        )

    target_boxes = [scaled_box(box, source_size, target_size) for box in boxes]
    final_records: list[dict] = []
    for frame in frames:
        cleaned_path = cleaned_dir / frame.name
        esr_path = esr_dir / frame.name
        if not esr_path.is_file():
            raise FileNotFoundError(esr_path)
        with Image.open(cleaned_path) as cleaned_image, Image.open(esr_path) as esr_image:
            expected_esr_size = (source_size[0] * 4, source_size[1] * 4)
            if esr_image.size != expected_esr_size:
                raise RuntimeError(f"Unexpected ESR size for {frame.name}: {esr_image.size}, expected {expected_esr_size}")
            rgb = esr_image.convert("RGB").resize(target_size, Image.Resampling.LANCZOS)
            alpha = cleaned_image.getchannel("A").resize(target_size, Image.Resampling.LANCZOS)
            rgba = np.dstack(
                (
                    np.asarray(rgb, dtype=np.uint8),
                    np.asarray(alpha, dtype=np.uint8),
                )
            )
            tx0, ty0, tx1, ty1 = target_boxes[0]
            tx0, ty0 = max(0, tx0 - 2), max(0, ty0 - 2)
            tx1, ty1 = min(target_size[0], tx1 + 2), min(target_size[1], ty1 + 2)
            final_rgb = rgba[..., :3].astype(np.int16)
            final_green_samples = (
                (rgba[..., 3] > 0)
                & (final_rgb[..., 1] > 90)
                & (final_rgb[..., 1] > final_rgb[..., 0] * 1.25)
                & (final_rgb[..., 1] > final_rgb[..., 2] * 1.25)
            )
            final_green_fill = np.median(
                rgba[..., :3][final_green_samples], axis=0
            ).round().astype(np.uint8)
            rgba[ty0:ty1, tx0:tx1, :3] = final_green_fill
            rgba[ty0:ty1, tx0:tx1, 3] = 255
            bx0, by0, bx1, by1 = target_boxes[1]
            rgba[by0:by1, bx0:bx1] = 0
            rgba[rgba[..., 3] == 0, :3] = 0
            final_image = Image.fromarray(rgba, "RGBA")
            final_path = args.output / frame.name
            final_image.save(final_path, optimize=True, compress_level=9)

        with Image.open(final_path) as check_image:
            check_rgba = np.asarray(check_image.convert("RGBA"), dtype=np.uint8)
            top_hsv = cv2.cvtColor(check_rgba[ty0:ty1, tx0:tx1, :3], cv2.COLOR_RGB2HSV)
            top_logo_like_pixels = int((
                (top_hsv[..., 1] < 95)
                & (top_hsv[..., 2] > 125)
                & (check_rgba[ty0:ty1, tx0:tx1, 3] > 0)
            ).sum())
            bx0, by0, bx1, by1 = target_boxes[1]
            bottom_alpha_max = int(check_rgba[by0:by1, bx0:bx1, 3].max(initial=0))
            if check_image.size != target_size or top_logo_like_pixels > 10 or bottom_alpha_max != 0:
                raise RuntimeError(f"QA failed for {frame.name}")
            final_records.append(
                {
                    "file": frame.name,
                    "esr_size": list(expected_esr_size),
                    "final_size": list(check_image.size),
                    "top_left_logo_like_pixels": top_logo_like_pixels,
                    "bottom_right_alpha_max": bottom_alpha_max,
                    "final_alpha": alpha_counts(check_rgba[..., 3]),
                    "final_sha256": sha256(final_path),
                }
            )
        print(f"Processed {frame.name}", flush=True)

    metadata_source = args.source / "frames.json"
    if metadata_source.is_file():
        shutil.copy2(metadata_source, args.output / "frames.json")

    manifest = {
        "pipeline": [
            "reconstruct the upper-left watermark region from each frame's median green background color",
            "clear the lower-right corner logo region to transparent",
            f"Real-ESRGAN {args.model} at scale 4",
            f"Lanczos downscale RGB and cleaned alpha to {target_width}x{target_height}",
            "restore the upper-left repair region after resize to remove super-resolution edge ringing",
            "clear the scaled lower-right watermark region again after resize",
        ],
        "source_dir": str(args.source),
        "output_dir": str(args.output),
        "work_dir": str(args.work),
        "frame_count": len(frames),
        "source_size": list(source_size),
        "target_size": list(target_size),
        "watermark_regions_source_xyxy": [list(box) for box in boxes],
        "watermark_regions_target_xyxy": [list(box) for box in target_boxes],
        "elapsed_seconds": round(time.perf_counter() - started, 3),
        "prepare_records": prepare_records,
        "final_records": final_records,
    }
    (args.output / "处理清单.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Completed {len(frames)} frames in {manifest['elapsed_seconds']}s", flush=True)


if __name__ == "__main__":
    main()

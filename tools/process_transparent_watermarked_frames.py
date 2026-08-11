from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import time
from pathlib import Path

import numpy as np
from PIL import Image


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def alpha_counts(alpha: np.ndarray) -> dict[str, int]:
    return {
        "transparent": int((alpha == 0).sum()),
        "partial": int(((alpha > 0) & (alpha < 255)).sum()),
        "opaque": int((alpha == 255).sum()),
    }


def repair_lower_right_desk(rgba: np.ndarray, template_row: np.ndarray) -> None:
    """Remove the animated corner logo and restore the two static desk supports."""
    rgba[560:720, 760:960] = 0
    leg_template = template_row[875:908]
    panel_template = template_row[919:960]
    for y in range(560, 720):
        progress = (y - 550) / 170
        leg_left = 875
        leg_right = round(908 - 3 * progress)
        panel_left = round(919 + 5 * progress)
        panel_right = 960
        rgba[y, leg_left:leg_right] = np.asarray(
            Image.fromarray(leg_template[np.newaxis, ...], "RGBA").resize(
                (leg_right - leg_left, 1), Image.Resampling.BILINEAR
            )
        )[0]
        rgba[y, panel_left:panel_right] = np.asarray(
            Image.fromarray(panel_template[np.newaxis, ...], "RGBA").resize(
                (panel_right - panel_left, 1), Image.Resampling.BILINEAR
            )
        )[0]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--realesrgan", type=Path, required=True)
    parser.add_argument("--models", type=Path, required=True)
    parser.add_argument("--model", default="realesrgan-x4plus-anime")
    parser.add_argument("--target", default="1112x834")
    parser.add_argument("--repair-lower-right-desk", action="store_true")
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

    cleaned_dir = args.work / "01_transparent_rgb_cleaned"
    esr_dir = args.work / "02_realesrgan_x4"
    for directory in (args.output, cleaned_dir, esr_dir):
        if directory.exists() and any(directory.iterdir()) and not args.resume:
            raise FileExistsError(f"Refusing to overwrite non-empty directory: {directory}")
        directory.mkdir(parents=True, exist_ok=True)

    source_size: tuple[int, int] | None = None
    desk_template_row: np.ndarray | None = None
    if args.repair_lower_right_desk:
        source_stack = np.stack(
            [
                np.asarray(Image.open(frame).convert("RGBA"), dtype=np.uint8)
                for frame in frames
            ]
        )
        if source_stack.shape[1:3] != (720, 960):
            raise RuntimeError("--repair-lower-right-desk expects 960x720 source frames")
        desk_template_row = np.median(
            source_stack[:, 565:576, :, :], axis=(0, 1)
        ).round().astype(np.uint8)
    prepare_records: list[dict] = []
    for frame in frames:
        with Image.open(frame) as source_image:
            if source_size is None:
                source_size = source_image.size
            elif source_image.size != source_size:
                raise RuntimeError(
                    f"Inconsistent frame size: {frame.name} is {source_image.size}, expected {source_size}"
                )
            rgba = np.asarray(source_image.convert("RGBA"), dtype=np.uint8).copy()
            if desk_template_row is not None:
                repair_lower_right_desk(rgba, desk_template_row)
            transparent = rgba[..., 3] == 0
            hidden_rgb = transparent & (rgba[..., :3].max(axis=2) > 0)
            hidden_rgb_pixels_cleared = int(hidden_rgb.sum())
            rgba[transparent, :3] = 0
            cleaned_path = cleaned_dir / frame.name
            Image.fromarray(rgba, "RGBA").save(cleaned_path, optimize=True, compress_level=9)
            prepare_records.append(
                {
                    "file": frame.name,
                    "source_sha256": sha256(frame),
                    "cleaned_sha256": sha256(cleaned_path),
                    "hidden_transparent_rgb_pixels_cleared": hidden_rgb_pixels_cleared,
                    "lower_right_desk_repaired": desk_template_row is not None,
                    "source_alpha": alpha_counts(rgba[..., 3]),
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

    final_records: list[dict] = []
    for frame in frames:
        cleaned_path = cleaned_dir / frame.name
        esr_path = esr_dir / frame.name
        if not esr_path.is_file():
            raise FileNotFoundError(esr_path)
        with Image.open(cleaned_path) as cleaned_image, Image.open(esr_path) as esr_image:
            expected_esr_size = (source_size[0] * 4, source_size[1] * 4)
            if esr_image.size != expected_esr_size:
                raise RuntimeError(
                    f"Unexpected ESR size for {frame.name}: {esr_image.size}, expected {expected_esr_size}"
                )
            rgb = esr_image.convert("RGB").resize(target_size, Image.Resampling.LANCZOS)
            alpha = cleaned_image.getchannel("A").resize(target_size, Image.Resampling.LANCZOS)
            rgba = np.dstack(
                (
                    np.asarray(rgb, dtype=np.uint8),
                    np.asarray(alpha, dtype=np.uint8),
                )
            )
            rgba[rgba[..., 3] == 0, :3] = 0
            final_path = args.output / frame.name
            Image.fromarray(rgba, "RGBA").save(final_path, optimize=True, compress_level=9)

        with Image.open(final_path) as check_image:
            check_rgba = np.asarray(check_image.convert("RGBA"), dtype=np.uint8)
            transparent_rgb_max = int(check_rgba[check_rgba[..., 3] == 0, :3].max(initial=0))
            if check_image.size != target_size or transparent_rgb_max != 0:
                raise RuntimeError(f"QA failed for {frame.name}")
            final_records.append(
                {
                    "file": frame.name,
                    "esr_size": list(expected_esr_size),
                    "final_size": list(check_image.size),
                    "transparent_rgb_max": transparent_rgb_max,
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
            *(
                [
                    "clear the lower-right animated watermark region and reconstruct the two static desk supports from a clean temporal reference band"
                ]
                if desk_template_row is not None
                else []
            ),
            "clear hidden RGB data wherever source alpha is zero, removing corner watermark residue without touching visible subject pixels",
            f"Real-ESRGAN {args.model} at scale 4",
            f"Lanczos downscale RGB and cleaned alpha to {target_width}x{target_height}",
            "clear hidden RGB data again wherever final alpha is zero",
        ],
        "source_dir": str(args.source),
        "output_dir": str(args.output),
        "work_dir": str(args.work),
        "frame_count": len(frames),
        "source_size": list(source_size),
        "target_size": list(target_size),
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

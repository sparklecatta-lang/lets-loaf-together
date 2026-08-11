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


def alpha_stats(alpha: Image.Image) -> dict[str, int]:
    values = np.asarray(alpha, dtype=np.uint8)
    return {
        "transparent": int(np.count_nonzero(values == 0)),
        "partial": int(np.count_nonzero((values > 0) & (values < 255))),
        "opaque": int(np.count_nonzero(values == 255)),
    }


def key_green_residue(rgba: np.ndarray) -> tuple[np.ndarray, dict[str, int]]:
    work = rgba.astype(np.int16)
    green = work[:, :, 1]
    dominance = np.minimum(green - work[:, :, 0], green - work[:, :, 2])
    strength = np.clip((dominance.astype(np.float32) - 4.0) / 20.0, 0.0, 1.0)
    mask = (work[:, :, 3] > 0) & (green >= 80) & (strength > 0)
    old_alpha = work[:, :, 3].copy()
    new_alpha = old_alpha.astype(np.float32)
    new_alpha[mask] *= 1.0 - strength[mask]
    work[:, :, 3] = np.rint(new_alpha).astype(np.int16)
    work[:, :, :3][work[:, :, 3] == 0] = 0
    return work.astype(np.uint8), {
        "green_residue_pixels_adjusted": int(np.count_nonzero(mask)),
        "green_residue_pixels_cleared": int(
            np.count_nonzero(mask & (old_alpha > 0) & (work[:, :, 3] == 0))
        ),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--realesrgan", type=Path, required=True)
    parser.add_argument("--models", type=Path, required=True)
    parser.add_argument("--width", type=int, default=1112)
    parser.add_argument("--height", type=int, default=834)
    parser.add_argument("--key-green", action="store_true")
    args = parser.parse_args()

    source_files = sorted(args.source.glob("*.png"))
    if not source_files:
        raise SystemExit(f"No PNG files found in {args.source}")

    prepared = args.work / "01_hidden_rgb_cleaned"
    esr = args.work / "02_realesrgan_x4"
    for directory in (args.output, prepared, esr):
        directory.mkdir(parents=True, exist_ok=True)

    if any(args.output.glob("*.png")) or any(prepared.glob("*.png")) or any(esr.glob("*.png")):
        raise SystemExit("Output/work folders already contain PNG files; refusing to mix runs")

    prepare_records = []
    start = time.perf_counter()
    for source_path in source_files:
        with Image.open(source_path) as image:
            rgba = np.array(image.convert("RGBA"), dtype=np.uint8, copy=True)
        hidden = rgba[:, :, 3] == 0
        cleared = int(np.count_nonzero(np.any(rgba[:, :, :3][hidden] != 0, axis=1)))
        rgba[:, :, :3][hidden] = 0
        green_record = {
            "green_residue_pixels_adjusted": 0,
            "green_residue_pixels_cleared": 0,
        }
        if args.key_green:
            rgba, green_record = key_green_residue(rgba)
        prepared_path = prepared / source_path.name
        Image.fromarray(rgba, "RGBA").save(prepared_path, optimize=True)
        prepare_records.append(
            {
                "file": source_path.name,
                "source_sha256": sha256(source_path),
                "prepared_sha256": sha256(prepared_path),
                "hidden_transparent_rgb_pixels_cleared": cleared,
                **green_record,
            }
        )

    command = [
        str(args.realesrgan),
        "-i",
        str(prepared),
        "-o",
        str(esr),
        "-s",
        "4",
        "-n",
        "realesrgan-x4plus-anime",
        "-m",
        str(args.models),
        "-f",
        "png",
    ]
    subprocess.run(command, check=True, cwd=args.realesrgan.parent)

    final_records = []
    for source_path in source_files:
        esr_path = esr / source_path.name
        if not esr_path.exists():
            raise SystemExit(f"Missing RealESRGAN output: {esr_path}")
        with Image.open(esr_path) as esr_image:
            esr_rgba = esr_image.convert("RGBA")
            esr_size = list(esr_rgba.size)
            rgb = esr_rgba.convert("RGB").resize(
                (args.width, args.height), Image.Resampling.LANCZOS
            )
        with Image.open(source_path) as source_image:
            source_alpha = source_image.convert("RGBA").getchannel("A")
            alpha = source_alpha.resize(
                (args.width, args.height), Image.Resampling.LANCZOS
            )
        final = Image.merge("RGBA", (*rgb.split(), alpha))
        final_array = np.array(final, dtype=np.uint8, copy=True)
        final_array[:, :, :3][final_array[:, :, 3] == 0] = 0
        final = Image.fromarray(final_array, "RGBA")
        output_path = args.output / source_path.name
        final.save(output_path, optimize=True)
        final_records.append(
            {
                "file": source_path.name,
                "esr_size": esr_size,
                "final_size": [args.width, args.height],
                "final_alpha": alpha_stats(final.getchannel("A")),
                "transparent_rgb_max": int(
                    final_array[:, :, :3][final_array[:, :, 3] == 0].max(initial=0)
                ),
                "final_sha256": sha256(output_path),
            }
        )

    metadata = args.source / "frames.json"
    if metadata.exists():
        shutil.copy2(metadata, args.output / metadata.name)

    manifest = {
        "pipeline": [
            "clear hidden RGB data wherever source alpha is zero",
            *(
                ["progressively key pure green-screen residue while preserving cyan/blue objects"]
                if args.key_green
                else []
            ),
            "Real-ESRGAN realesrgan-x4plus-anime at scale 4",
            f"Lanczos downscale enhanced RGB to {args.width}x{args.height}",
            f"Lanczos downscale original alpha to {args.width}x{args.height}",
            "clear hidden RGB data again wherever final alpha is zero",
        ],
        "source_dir": str(args.source),
        "output_dir": str(args.output),
        "work_dir": str(args.work),
        "frame_count": len(source_files),
        "source_size": list(Image.open(source_files[0]).size),
        "target_size": [args.width, args.height],
        "elapsed_seconds": round(time.perf_counter() - start, 3),
        "prepare_records": prepare_records,
        "final_records": final_records,
    }
    (args.output / "处理清单.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps({"frame_count": len(source_files), "elapsed_seconds": manifest["elapsed_seconds"]}))


if __name__ == "__main__":
    main()

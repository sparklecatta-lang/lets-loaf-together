from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_atomic_png(image: Image.Image, path: Path) -> None:
    temporary = path.with_name(path.name + ".xsxb-tmp.png")
    image.save(temporary)
    temporary.replace(path)


def checkerboard(size: tuple[int, int], cell: int = 24) -> Image.Image:
    result = Image.new("RGB", size, (35, 38, 43))
    draw = ImageDraw.Draw(result)
    for y in range(0, size[1], cell):
        for x in range(0, size[0], cell):
            if (x // cell + y // cell) % 2:
                draw.rectangle((x, y, x + cell - 1, y + cell - 1), fill=(52, 56, 63))
    return result


def on_checker(image: Image.Image) -> Image.Image:
    background = checkerboard(image.size).convert("RGBA")
    background.alpha_composite(image)
    return background.convert("RGB")


def feather_mask(
    size: tuple[int, int], cut_x: int, half_width: int, blur_radius: float
) -> tuple[np.ndarray, int, int, Image.Image]:
    width, height = size
    start = cut_x - half_width
    end = cut_x + half_width
    if start < 1 or end >= width:
        raise ValueError("Feather band must stay inside the canvas")
    x = np.arange(width, dtype=np.float32)
    t = np.clip((x - start) / float(end - start), 0.0, 1.0)
    smooth = t * t * (3.0 - 2.0 * t)
    mask_image = Image.fromarray(np.round(smooth * 255.0).astype(np.uint8), mode="L")
    mask_image = mask_image.resize((width, height)).filter(ImageFilter.GaussianBlur(radius=blur_radius))
    mask = np.asarray(mask_image, dtype=np.float32) / 255.0
    mask[:, :start] = 0.0
    mask[:, end:] = 1.0
    final_image = Image.fromarray(np.round(mask * 255.0).astype(np.uint8), mode="L")
    return mask[:, :, None], start, end, final_image


def composite(source: Image.Image, reference: Image.Image, mask: np.ndarray) -> Image.Image:
    if source.size != reference.size:
        raise ValueError(f"Canvas mismatch: {source.size} != {reference.size}")
    source_array = np.asarray(source, dtype=np.float32)
    reference_array = np.asarray(reference, dtype=np.float32)
    result = np.round(source_array * (1.0 - mask) + reference_array * mask)
    return Image.fromarray(np.clip(result, 0, 255).astype(np.uint8), mode="RGBA")


def build_preview(
    rows: list[tuple[Path, Image.Image, Image.Image]],
    names: list[str],
    start: int,
    cut_x: int,
    end: int,
    output: Path,
) -> None:
    by_name = {path.name: (path, before, after) for path, before, after in rows}
    selected = [by_name[name] for name in names if name in by_name]
    if not selected:
        indices = sorted({0, len(rows) // 2, len(rows) - 1})
        selected = [rows[index] for index in indices]
    scale = 0.36
    thumb = (round(selected[0][1].width * scale), round(selected[0][1].height * scale))
    margin = 16
    label_height = 30
    row_height = thumb[1] + label_height
    sheet = Image.new("RGB", (margin * 3 + thumb[0] * 2, margin + len(selected) * row_height), (22, 24, 28))
    draw = ImageDraw.Draw(sheet)
    for row_index, (path, before, after) in enumerate(selected):
        y = margin + row_index * row_height
        left_x = margin
        right_x = margin * 2 + thumb[0]
        sheet.paste(on_checker(before).resize(thumb, Image.Resampling.LANCZOS), (left_x, y))
        sheet.paste(on_checker(after).resize(thumb, Image.Resampling.LANCZOS), (right_x, y))
        for x, color in ((start, (255, 188, 60)), (cut_x, (255, 70, 70)), (end, (80, 190, 255))):
            thumb_x = right_x + round(x * scale)
            draw.line((thumb_x, y, thumb_x, y + thumb[1]), fill=color, width=2)
        draw.text((left_x, y + thumb[1] + 4), f"before {path.name}", fill=(230, 230, 230))
        draw.text((right_x, y + thumb[1] + 4), f"after feather {start}-{end}", fill=(230, 230, 230))
    output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--master-root", required=True)
    parser.add_argument("--project-copy-root", required=True)
    parser.add_argument("--animation", required=True)
    parser.add_argument("--reference", required=True)
    parser.add_argument("--cut-x", type=int, default=851)
    parser.add_argument("--feather-half-width", type=int, default=24)
    parser.add_argument("--blur-radius", type=float, default=6.0)
    parser.add_argument("--preview-frames", default="")
    parser.add_argument("--mode", choices=("preview", "apply"), default="preview")
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--backup-dir")
    args = parser.parse_args()

    master_root = Path(args.master_root).resolve()
    project_root = Path(args.project_copy_root).resolve()
    master_animation = master_root / args.animation
    project_animation = project_root / args.animation
    reference_path = master_root / args.reference
    output_dir = Path(args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    backup_dir = Path(args.backup_dir).resolve() if args.backup_dir else None

    reference = Image.open(reference_path).convert("RGBA")
    mask, feather_start, feather_end, mask_image = feather_mask(
        reference.size, args.cut_x, args.feather_half_width, args.blur_radius
    )
    mask_image.save(output_dir / f"{args.animation}_right_feather_mask.png")

    master_frames = sorted(master_animation.glob("*.png"))
    project_frames = sorted(project_animation.glob("*.png"))
    if not master_frames or [path.name for path in master_frames] != [path.name for path in project_frames]:
        raise ValueError("Master and project-copy frame lists do not match")

    rows: list[tuple[Path, Image.Image, Image.Image]] = []
    reports: list[dict[str, object]] = []
    reference_array = np.asarray(reference)
    for master_path, project_path in zip(master_frames, project_frames):
        if sha256_file(master_path) != sha256_file(project_path):
            raise ValueError(f"Master/project mismatch: {master_path.name}")
        before = Image.open(master_path).convert("RGBA")
        after = composite(before, reference, mask)
        before_array = np.asarray(before)
        after_array = np.asarray(after)
        reports.append(
            {
                "frame": master_path.name,
                "before_sha256": sha256_file(master_path),
                "left_of_feather_exact": bool(
                    np.array_equal(before_array[:, :feather_start], after_array[:, :feather_start])
                ),
                "right_of_feather_matches_reference": bool(
                    np.array_equal(after_array[:, feather_end:], reference_array[:, feather_end:])
                ),
                "changed_pixels": int(np.count_nonzero(np.any(before_array != after_array, axis=2))),
                "monitor_opaque_pixels_before": int(np.count_nonzero(before_array[:430, 875:, 3] > 16)),
                "monitor_opaque_pixels_after": int(np.count_nonzero(after_array[:430, 875:, 3] > 16)),
            }
        )
        rows.append((master_path, before, after))

    preview_names = [name.strip() for name in args.preview_frames.split(",") if name.strip()]
    build_preview(
        rows,
        preview_names,
        feather_start,
        args.cut_x,
        feather_end,
        output_dir / f"{args.animation}_right_feather_preview.png",
    )

    if args.mode == "apply":
        if backup_dir is None:
            raise ValueError("--backup-dir is required in apply mode")
        if backup_dir.exists():
            raise ValueError(f"Backup directory already exists: {backup_dir}")
        for root_name, frames in (("master", master_frames), ("project_copy", project_frames)):
            destination = backup_dir / root_name / args.animation
            destination.mkdir(parents=True, exist_ok=True)
            for frame in frames:
                shutil.copy2(frame, destination / frame.name)
        shutil.copy2(reference_path, backup_dir / reference_path.name)
        for master_path, _before, after in rows:
            write_atomic_png(after, master_path)
            write_atomic_png(after, project_animation / master_path.name)

    all_equal = True
    if args.mode == "apply":
        for master_path in master_frames:
            all_equal = all_equal and sha256_file(master_path) == sha256_file(project_animation / master_path.name)
    ok = (
        all(item["left_of_feather_exact"] and item["right_of_feather_matches_reference"] for item in reports)
        and all_equal
    )
    report = {
        "ok": ok,
        "mode": args.mode,
        "animation": args.animation,
        "frame_count": len(reports),
        "reference": str(reference_path),
        "cut_x": args.cut_x,
        "feather_start": feather_start,
        "feather_end": feather_end,
        "blur_radius": args.blur_radius,
        "master_project_equal": all_equal,
        "backup_dir": str(backup_dir) if backup_dir else None,
        "frames": reports,
    }
    (output_dir / f"{args.animation}_right_feather_report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    if not ok:
        raise SystemExit(1)


if __name__ == "__main__":
    main()

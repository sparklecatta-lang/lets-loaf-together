from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def composite_right(source: Image.Image, reference: Image.Image, cut_x: int) -> Image.Image:
    if source.size != reference.size:
        raise ValueError(f"Canvas mismatch: {source.size} != {reference.size}")
    result = source.copy()
    result.paste(reference.crop((cut_x, 0, reference.width, reference.height)), (cut_x, 0))
    return result


def checkerboard(size: tuple[int, int], cell: int = 24) -> Image.Image:
    width, height = size
    result = Image.new("RGB", size, (35, 38, 43))
    draw = ImageDraw.Draw(result)
    for y in range(0, height, cell):
        for x in range(0, width, cell):
            if (x // cell + y // cell) % 2:
                draw.rectangle((x, y, x + cell - 1, y + cell - 1), fill=(52, 56, 63))
    return result


def on_checker(image: Image.Image) -> Image.Image:
    base = checkerboard(image.size).convert("RGBA")
    base.alpha_composite(image)
    return base.convert("RGB")


def build_contact_sheet(
    frames: list[Path], reference: Image.Image, cut_x: int, output_path: Path
) -> None:
    indices = sorted({0, len(frames) // 4, len(frames) // 2, (len(frames) * 3) // 4, len(frames) - 1})
    scale = 0.36
    thumb_size = (round(reference.width * scale), round(reference.height * scale))
    margin = 16
    label_height = 24
    row_height = thumb_size[1] + label_height
    sheet = Image.new("RGB", (margin * 3 + thumb_size[0] * 2, margin + row_height * len(indices)), (22, 24, 28))
    draw = ImageDraw.Draw(sheet)

    for row, index in enumerate(indices):
        source = Image.open(frames[index]).convert("RGBA")
        candidate = composite_right(source, reference, cut_x)
        before = on_checker(source).resize(thumb_size, Image.Resampling.LANCZOS)
        after = on_checker(candidate).resize(thumb_size, Image.Resampling.LANCZOS)
        y = margin + row * row_height
        left_x = margin
        right_x = margin * 2 + thumb_size[0]
        sheet.paste(before, (left_x, y))
        sheet.paste(after, (right_x, y))
        cut_thumb_x = round(cut_x * scale)
        draw.line((right_x + cut_thumb_x, y, right_x + cut_thumb_x, y + thumb_size[1]), fill=(255, 60, 60), width=2)
        draw.text((left_x, y + thumb_size[1] + 4), f"before  {frames[index].name}", fill=(230, 230, 230))
        draw.text((right_x, y + thumb_size[1] + 4), f"after  cut x={cut_x}", fill=(230, 230, 230))

    output_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output_path)


def write_atomic_png(image: Image.Image, path: Path) -> None:
    temporary = path.with_name(path.name + ".xsxb-tmp.png")
    image.save(temporary)
    temporary.replace(path)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--master-root", required=True)
    parser.add_argument("--project-copy-root", required=True)
    parser.add_argument("--reference", required=True)
    parser.add_argument("--animation", default="use_mouse")
    parser.add_argument("--cut-x", type=int, required=True)
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

    master_frames = sorted(master_animation.glob("*.png"))
    project_frames = sorted(project_animation.glob("*.png"))
    if not master_frames or [p.name for p in master_frames] != [p.name for p in project_frames]:
        raise ValueError("Master and project-copy animation frame lists do not match")

    reference = Image.open(reference_path).convert("RGBA")
    if not 0 < args.cut_x < reference.width:
        raise ValueError(f"cut-x must be inside the {reference.width}px canvas")

    before_pairs = []
    for master_path, project_path in zip(master_frames, project_frames):
        if sha256_file(master_path) != sha256_file(project_path):
            raise ValueError(f"Master/project source mismatch: {master_path.name}")
        source = Image.open(master_path).convert("RGBA")
        if source.size != reference.size:
            raise ValueError(f"Canvas mismatch in {master_path.name}: {source.size}")
        candidate = composite_right(source, reference, args.cut_x)
        source_array = np.asarray(source)
        candidate_array = np.asarray(candidate)
        changed_outside = int(np.count_nonzero(np.any(source_array[:, : args.cut_x] != candidate_array[:, : args.cut_x], axis=2)))
        if changed_outside:
            raise ValueError(f"Changed pixels left of cut in {master_path.name}: {changed_outside}")
        before_pairs.append((master_path, project_path, source, candidate))

    build_contact_sheet(master_frames, reference, args.cut_x, output_dir / "use_mouse_right_stabilization_preview.png")
    mask = Image.new("L", reference.size, 0)
    ImageDraw.Draw(mask).rectangle((args.cut_x, 0, reference.width - 1, reference.height - 1), fill=255)
    mask.save(output_dir / "use_mouse_right_allowed_change_mask.png")

    backup_dir = Path(args.backup_dir).resolve() if args.backup_dir else None
    if args.mode == "apply":
        if backup_dir is None:
            raise ValueError("--backup-dir is required in apply mode")
        if backup_dir.exists():
            raise ValueError(f"Backup directory already exists: {backup_dir}")
        for root_name, frames in (("master", master_frames), ("project_copy", project_frames)):
            target = backup_dir / root_name / args.animation
            target.mkdir(parents=True, exist_ok=True)
            for frame in frames:
                shutil.copy2(frame, target / frame.name)
        shutil.copy2(reference_path, backup_dir / reference_path.name)
        for master_path, project_path, _source, candidate in before_pairs:
            write_atomic_png(candidate, master_path)
            write_atomic_png(candidate, project_path)

    reference_right = np.asarray(reference)[:, args.cut_x :]
    frame_reports = []
    for master_path, project_path, source, candidate in before_pairs:
        final_master = Image.open(master_path).convert("RGBA") if args.mode == "apply" else candidate
        final_project = Image.open(project_path).convert("RGBA") if args.mode == "apply" else candidate
        final_master_array = np.asarray(final_master)
        final_project_array = np.asarray(final_project)
        left_exact = bool(np.array_equal(np.asarray(source)[:, : args.cut_x], final_master_array[:, : args.cut_x]))
        right_exact = bool(np.array_equal(reference_right, final_master_array[:, args.cut_x :]))
        copies_equal = bool(np.array_equal(final_master_array, final_project_array))
        frame_reports.append(
            {
                "frame": master_path.name,
                "before_sha256": sha256_file(backup_dir / "master" / args.animation / master_path.name)
                if args.mode == "apply"
                else sha256_file(master_path),
                "after_sha256": sha256_file(master_path) if args.mode == "apply" else sha256_bytes(final_master.tobytes()),
                "left_exact": left_exact,
                "right_matches_reference": right_exact,
                "master_project_equal": copies_equal,
                "size": list(final_master.size),
                "mode": final_master.mode,
            }
        )

    ok = all(
        item["left_exact"] and item["right_matches_reference"] and item["master_project_equal"]
        for item in frame_reports
    )
    report = {
        "ok": ok,
        "mode": args.mode,
        "animation": args.animation,
        "frame_count": len(frame_reports),
        "cut_x": args.cut_x,
        "reference": str(reference_path),
        "reference_sha256": sha256_file(reference_path),
        "master_root": str(master_root),
        "project_copy_root": str(project_root),
        "backup_dir": str(backup_dir) if backup_dir else None,
        "frames": frame_reports,
    }
    (output_dir / "use_mouse_right_stabilization_report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    if not ok:
        raise SystemExit(1)


if __name__ == "__main__":
    main()

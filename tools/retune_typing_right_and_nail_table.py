from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


NAIL_ACTIONS = ("nail_polish_enter", "nail_polish_loop", "nail_polish_exit")


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
    base = checkerboard(image.size).convert("RGBA")
    base.alpha_composite(image)
    return base.convert("RGB")


def make_feather_mask(
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
    mask_image = mask_image.resize((width, height))
    mask_image = mask_image.filter(ImageFilter.GaussianBlur(radius=blur_radius))
    mask = np.asarray(mask_image, dtype=np.float32) / 255.0
    mask[:, :start] = 0.0
    mask[:, end:] = 1.0
    mask_image = Image.fromarray(np.round(mask * 255.0).astype(np.uint8), mode="L")
    return mask[:, :, None], start, end, mask_image


def feather_composite(source: Image.Image, reference: Image.Image, mask: np.ndarray) -> Image.Image:
    if source.size != reference.size:
        raise ValueError(f"Canvas mismatch: {source.size} != {reference.size}")
    source_array = np.asarray(source, dtype=np.float32)
    reference_array = np.asarray(reference, dtype=np.float32)
    result = np.round(source_array * (1.0 - mask) + reference_array * mask)
    return Image.fromarray(np.clip(result, 0, 255).astype(np.uint8), mode="RGBA")


def desk_color_mask(array: np.ndarray) -> np.ndarray:
    red = array[:, :, 0].astype(np.int16)
    green = array[:, :, 1].astype(np.int16)
    blue = array[:, :, 2].astype(np.int16)
    alpha = array[:, :, 3]
    mask = (
        (alpha >= 200)
        & (red >= 220)
        & (green >= 200)
        & (blue >= 195)
        & ((red - green) >= 12)
        & ((red - green) <= 40)
        & ((red - blue) >= 18)
        & ((red - blue) <= 48)
        & ((green - blue) >= -2)
        & ((green - blue) <= 18)
    )
    spatial = np.zeros(mask.shape, dtype=bool)
    spatial[430:620, 340:] = True
    return mask & spatial


def desk_patch_median(array: np.ndarray) -> np.ndarray:
    patch = array[440:590, 1015:1100]
    mask = desk_color_mask(array)[440:590, 1015:1100]
    pixels = patch[mask, :3]
    if len(pixels) < 1000:
        raise ValueError(f"Desk reference patch is unexpectedly small: {len(pixels)} pixels")
    return np.median(pixels, axis=0)


def correct_desk_color(
    source: Image.Image, target_median: np.ndarray
) -> tuple[Image.Image, np.ndarray, np.ndarray, int]:
    array = np.asarray(source).copy()
    original = array.copy()
    mask = desk_color_mask(array)
    source_median = desk_patch_median(array)
    delta = np.clip(np.round(target_median - source_median), -16, 16).astype(np.int16)
    rgb = array[:, :, :3].astype(np.int16)
    rgb[mask] = np.clip(rgb[mask] + delta, 0, 255)
    array[:, :, :3] = rgb.astype(np.uint8)
    if not np.array_equal(array[:, :, 3], original[:, :, 3]):
        raise ValueError("Desk correction changed alpha")
    changed = int(np.count_nonzero(np.any(array != original, axis=2)))
    return Image.fromarray(array, mode="RGBA"), mask, delta, changed


def selected_indices(count: int) -> list[int]:
    return sorted({0, count // 2, count - 1})


def build_use_mouse_preview(
    rows: list[tuple[Path, Image.Image, Image.Image]], start: int, cut_x: int, end: int, output: Path
) -> None:
    chosen = selected_indices(len(rows))
    scale = 0.36
    thumb = (round(rows[0][1].width * scale), round(rows[0][1].height * scale))
    margin = 16
    label_height = 30
    row_height = thumb[1] + label_height
    sheet = Image.new("RGB", (margin * 3 + thumb[0] * 2, margin + len(chosen) * row_height), (22, 24, 28))
    draw = ImageDraw.Draw(sheet)
    for row_index, index in enumerate(chosen):
        path, before, after = rows[index]
        y = margin + row_index * row_height
        left_x = margin
        right_x = margin * 2 + thumb[0]
        sheet.paste(on_checker(before).resize(thumb, Image.Resampling.LANCZOS), (left_x, y))
        sheet.paste(on_checker(after).resize(thumb, Image.Resampling.LANCZOS), (right_x, y))
        for x, color in ((start, (255, 188, 60)), (cut_x, (255, 70, 70)), (end, (80, 190, 255))):
            tx = right_x + round(x * scale)
            draw.line((tx, y, tx, y + thumb[1]), fill=color, width=2)
        draw.text((left_x, y + thumb[1] + 4), f"before {path.name}", fill=(230, 230, 230))
        draw.text((right_x, y + thumb[1] + 4), f"after feather {start}-{end}", fill=(230, 230, 230))
    output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output)


def build_nail_preview(
    rows: dict[str, list[tuple[Path, Image.Image, Image.Image, np.ndarray]]], output: Path
) -> None:
    selected: list[tuple[str, Path, Image.Image, Image.Image, np.ndarray]] = []
    for action, action_rows in rows.items():
        for index in selected_indices(len(action_rows)):
            path, before, after, delta = action_rows[index]
            selected.append((action, path, before, after, delta))
    scale = 0.28
    first = selected[0][2]
    thumb = (round(first.width * scale), round(first.height * scale))
    margin = 14
    label_height = 34
    row_height = thumb[1] + label_height
    sheet = Image.new("RGB", (margin * 3 + thumb[0] * 2, margin + len(selected) * row_height), (22, 24, 28))
    draw = ImageDraw.Draw(sheet)
    for row_index, (action, path, before, after, delta) in enumerate(selected):
        y = margin + row_index * row_height
        left_x = margin
        right_x = margin * 2 + thumb[0]
        sheet.paste(on_checker(before).resize(thumb, Image.Resampling.LANCZOS), (left_x, y))
        sheet.paste(on_checker(after).resize(thumb, Image.Resampling.LANCZOS), (right_x, y))
        draw.text((left_x, y + thumb[1] + 4), f"before {action}/{path.name}", fill=(230, 230, 230))
        draw.text(
            (right_x, y + thumb[1] + 4),
            f"after desk RGB delta {delta.tolist()}",
            fill=(230, 230, 230),
        )
    output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output)


def build_nail_mask_preview(
    rows: dict[str, list[tuple[Path, Image.Image, Image.Image, np.ndarray]]],
    masks: dict[tuple[str, str], np.ndarray],
    output: Path,
) -> None:
    crop_box = (300, 400, 1112, 650)
    scale = 0.72
    crop_size = (crop_box[2] - crop_box[0], crop_box[3] - crop_box[1])
    thumb = (round(crop_size[0] * scale), round(crop_size[1] * scale))
    margin = 14
    label_height = 28
    row_height = thumb[1] + label_height
    sheet = Image.new("RGB", (margin * 3 + thumb[0] * 2, margin + len(rows) * row_height), (22, 24, 28))
    draw = ImageDraw.Draw(sheet)
    for row_index, (action, action_rows) in enumerate(rows.items()):
        index = len(action_rows) // 2
        path, before, _after, _delta = action_rows[index]
        base = np.asarray(on_checker(before)).copy()
        mask = masks[(action, path.name)]
        overlay = base.copy()
        cyan = np.array([20, 235, 255], dtype=np.float32)
        overlay[mask] = np.round(base[mask].astype(np.float32) * 0.35 + cyan * 0.65).astype(np.uint8)
        before_crop = Image.fromarray(base, mode="RGB").crop(crop_box).resize(thumb, Image.Resampling.LANCZOS)
        overlay_crop = Image.fromarray(overlay, mode="RGB").crop(crop_box).resize(thumb, Image.Resampling.LANCZOS)
        y = margin + row_index * row_height
        left_x = margin
        right_x = margin * 2 + thumb[0]
        sheet.paste(before_crop, (left_x, y))
        sheet.paste(overlay_crop, (right_x, y))
        draw.text((left_x, y + thumb[1] + 4), f"source {action}/{path.name}", fill=(230, 230, 230))
        draw.text((right_x, y + thumb[1] + 4), "cyan = corrected desk pixels", fill=(230, 230, 230))
    output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output)


def copy_animation_backup(root: Path, backup_root: Path, root_name: str, action: str) -> None:
    destination = backup_root / root_name / action
    destination.mkdir(parents=True, exist_ok=True)
    for frame in sorted((root / action).glob("*.png")):
        shutil.copy2(frame, destination / frame.name)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--master-root", required=True)
    parser.add_argument("--project-copy-root", required=True)
    parser.add_argument("--original-use-mouse-root", required=True)
    parser.add_argument("--typing-reference", default="typing/frame_0001.png")
    parser.add_argument("--cut-x", type=int, default=835)
    parser.add_argument("--feather-half-width", type=int, default=24)
    parser.add_argument("--blur-radius", type=float, default=6.0)
    parser.add_argument("--mode", choices=("preview", "apply"), default="preview")
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--backup-dir")
    args = parser.parse_args()

    master_root = Path(args.master_root).resolve()
    project_root = Path(args.project_copy_root).resolve()
    original_use_mouse_root = Path(args.original_use_mouse_root).resolve()
    reference_path = master_root / args.typing_reference
    output_dir = Path(args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    backup_dir = Path(args.backup_dir).resolve() if args.backup_dir else None

    reference = Image.open(reference_path).convert("RGBA")
    feather_mask, feather_start, feather_end, feather_image = make_feather_mask(
        reference.size, args.cut_x, args.feather_half_width, args.blur_radius
    )
    feather_image.save(output_dir / "use_mouse_typing_feather_mask.png")

    use_master = sorted((master_root / "use_mouse").glob("*.png"))
    use_project = sorted((project_root / "use_mouse").glob("*.png"))
    use_original = sorted(original_use_mouse_root.glob("*.png"))
    names = [path.name for path in use_master]
    if not names or names != [path.name for path in use_project] or names != [path.name for path in use_original]:
        raise ValueError("use_mouse frame lists do not match")

    use_rows: list[tuple[Path, Image.Image, Image.Image]] = []
    use_reports: list[dict[str, object]] = []
    for master_path, project_path, original_path in zip(use_master, use_project, use_original):
        if sha256_file(master_path) != sha256_file(project_path):
            raise ValueError(f"Master/project mismatch: use_mouse/{master_path.name}")
        current = Image.open(master_path).convert("RGBA")
        original = Image.open(original_path).convert("RGBA")
        if current.size != reference.size or original.size != reference.size:
            raise ValueError(f"Canvas mismatch: use_mouse/{master_path.name}")
        current_array = np.asarray(current)
        original_array = np.asarray(original)
        if not np.array_equal(current_array[:, :feather_start], original_array[:, :feather_start]):
            raise ValueError(
                f"Current pixels left of the new feather band no longer match the pre-stabilization source: {master_path.name}"
            )
        candidate = feather_composite(original, reference, feather_mask)
        candidate_array = np.asarray(candidate)
        use_rows.append((master_path, current, candidate))
        use_reports.append(
            {
                "frame": master_path.name,
                "current_sha256": sha256_file(master_path),
                "original_source_sha256": sha256_file(original_path),
                "left_of_feather_exact_to_original": bool(
                    np.array_equal(candidate_array[:, :feather_start], original_array[:, :feather_start])
                ),
                "right_of_feather_exact_to_typing": bool(
                    np.array_equal(candidate_array[:, feather_end:], np.asarray(reference)[:, feather_end:])
                ),
                "changed_pixels_from_current": int(
                    np.count_nonzero(np.any(candidate_array != current_array, axis=2))
                ),
            }
        )

    target_median = desk_patch_median(np.asarray(reference))
    nail_rows: dict[str, list[tuple[Path, Image.Image, Image.Image, np.ndarray]]] = {}
    nail_reports: dict[str, list[dict[str, object]]] = {}
    nail_masks: dict[tuple[str, str], np.ndarray] = {}
    for action in NAIL_ACTIONS:
        master_frames = sorted((master_root / action).glob("*.png"))
        project_frames = sorted((project_root / action).glob("*.png"))
        if not master_frames or [p.name for p in master_frames] != [p.name for p in project_frames]:
            raise ValueError(f"Frame list mismatch for {action}")
        action_rows: list[tuple[Path, Image.Image, Image.Image, np.ndarray]] = []
        action_reports: list[dict[str, object]] = []
        for master_path, project_path in zip(master_frames, project_frames):
            if sha256_file(master_path) != sha256_file(project_path):
                raise ValueError(f"Master/project mismatch: {action}/{master_path.name}")
            before = Image.open(master_path).convert("RGBA")
            after, color_mask, delta, changed = correct_desk_color(before, target_median)
            before_array = np.asarray(before)
            after_array = np.asarray(after)
            outside_exact = bool(np.array_equal(before_array[~color_mask], after_array[~color_mask]))
            if not outside_exact:
                raise ValueError(f"Desk correction changed pixels outside its mask: {action}/{master_path.name}")
            action_rows.append((master_path, before, after, delta))
            nail_masks[(action, master_path.name)] = color_mask
            action_reports.append(
                {
                    "frame": master_path.name,
                    "before_sha256": sha256_file(master_path),
                    "source_desk_median": desk_patch_median(before_array).tolist(),
                    "target_desk_median": target_median.tolist(),
                    "rgb_delta": delta.tolist(),
                    "mask_pixels": int(np.count_nonzero(color_mask)),
                    "changed_pixels": changed,
                    "alpha_exact": bool(np.array_equal(before_array[:, :, 3], after_array[:, :, 3])),
                    "outside_mask_exact": outside_exact,
                }
            )
        nail_rows[action] = action_rows
        nail_reports[action] = action_reports

    build_use_mouse_preview(
        use_rows,
        feather_start,
        args.cut_x,
        feather_end,
        output_dir / "use_mouse_typing_feather_preview.png",
    )
    build_nail_preview(nail_rows, output_dir / "nail_polish_table_color_preview.png")
    build_nail_mask_preview(
        nail_rows,
        nail_masks,
        output_dir / "nail_polish_table_color_mask_preview.png",
    )

    if args.mode == "apply":
        if backup_dir is None:
            raise ValueError("--backup-dir is required in apply mode")
        if backup_dir.exists():
            raise ValueError(f"Backup directory already exists: {backup_dir}")
        for root, root_name in ((master_root, "master"), (project_root, "project_copy")):
            for action in ("use_mouse",) + NAIL_ACTIONS:
                copy_animation_backup(root, backup_dir, root_name, action)
        shutil.copy2(reference_path, backup_dir / reference_path.name)

        for master_path, _before, candidate in use_rows:
            project_path = project_root / "use_mouse" / master_path.name
            write_atomic_png(candidate, master_path)
            write_atomic_png(candidate, project_path)
        for action, action_rows in nail_rows.items():
            for master_path, _before, after, _delta in action_rows:
                project_path = project_root / action / master_path.name
                write_atomic_png(after, master_path)
                write_atomic_png(after, project_path)

    all_equal = True
    after_hashes: dict[str, str] = {}
    for action in ("use_mouse",) + NAIL_ACTIONS:
        for master_path in sorted((master_root / action).glob("*.png")):
            project_path = project_root / action / master_path.name
            if args.mode == "apply":
                equal = sha256_file(master_path) == sha256_file(project_path)
                all_equal = all_equal and equal
                after_hashes[f"{action}/{master_path.name}"] = sha256_file(master_path)

    ok = (
        all(item["left_of_feather_exact_to_original"] and item["right_of_feather_exact_to_typing"] for item in use_reports)
        and all(
            item["alpha_exact"] and item["outside_mask_exact"]
            for reports in nail_reports.values()
            for item in reports
        )
        and all_equal
    )
    report = {
        "ok": ok,
        "mode": args.mode,
        "typing_reference": str(reference_path),
        "typing_reference_sha256": sha256_file(reference_path),
        "original_use_mouse_root": str(original_use_mouse_root),
        "use_mouse": {
            "frame_count": len(use_reports),
            "cut_x": args.cut_x,
            "feather_start": feather_start,
            "feather_end": feather_end,
            "blur_radius": args.blur_radius,
            "frames": use_reports,
        },
        "nail_polish": {
            "actions": {action: len(rows) for action, rows in nail_rows.items()},
            "target_desk_median": target_median.tolist(),
            "frames": nail_reports,
        },
        "master_project_equal": all_equal,
        "backup_dir": str(backup_dir) if backup_dir else None,
        "after_hashes": after_hashes,
    }
    (output_dir / "typing_right_and_nail_table_report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    if not ok:
        raise SystemExit(1)


if __name__ == "__main__":
    main()

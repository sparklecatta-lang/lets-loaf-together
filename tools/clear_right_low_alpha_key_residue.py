from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def residue_mask(array: np.ndarray, roi: tuple[int, int, int, int], max_alpha: int) -> np.ndarray:
    x, y, width, height = roi
    mask = np.zeros(array.shape[:2], dtype=bool)
    crop = array[y : y + height, x : x + width]
    alpha = crop[:, :, 3]
    # This ROI is a verified empty gap left of the right table leg.  Clearing
    # every very-low-alpha pixel removes both the green core and the neutral
    # halo of the same leaked key component without touching the leg at x=1015.
    local = (alpha > 0) & (alpha <= max_alpha)
    mask[y : y + height, x : x + width] = local
    return mask


def clean_image(image: Image.Image, roi: tuple[int, int, int, int], max_alpha: int) -> tuple[Image.Image, np.ndarray]:
    array = np.asarray(image.convert("RGBA")).copy()
    mask = residue_mask(array, roi, max_alpha)
    array[mask] = 0
    return Image.fromarray(array, "RGBA"), mask


def checkerboard(size: tuple[int, int], cell: int = 20) -> Image.Image:
    width, height = size
    yy, xx = np.indices((height, width))
    values = np.where(((xx // cell) + (yy // cell)) % 2 == 0, 52, 76).astype(np.uint8)
    return Image.fromarray(np.stack((values, values, values), axis=2), "RGB")


def amplify_alpha(image: Image.Image, factor: int = 96) -> Image.Image:
    array = np.asarray(image.convert("RGBA")).copy()
    array[:, :, 3] = np.minimum(array[:, :, 3].astype(np.uint16) * factor, 255).astype(np.uint8)
    return Image.fromarray(array, "RGBA")


def preview_tile(image: Image.Image, crop_box: tuple[int, int, int, int], label: str) -> Image.Image:
    crop = amplify_alpha(image.crop(crop_box))
    base = checkerboard(crop.size).convert("RGBA")
    base.alpha_composite(crop)
    scaled = base.convert("RGB").resize((480, 448), Image.Resampling.NEAREST)
    tile = Image.new("RGB", (480, 476), (23, 25, 29))
    tile.paste(scaled, (0, 28))
    ImageDraw.Draw(tile).text((8, 7), label, fill=(240, 240, 240))
    return tile


def write_atomic_png(image: Image.Image, path: Path) -> None:
    temporary = path.with_name(path.name + ".xsxb-tmp.png")
    image.save(temporary)
    temporary.replace(path)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--master-root", required=True)
    parser.add_argument("--project-copy-root", required=True)
    parser.add_argument("--actions", required=True, help="Comma-separated action directories")
    parser.add_argument("--roi", default="920,610,120,224")
    parser.add_argument("--max-alpha", type=int, default=12)
    parser.add_argument("--mode", choices=("preview", "apply"), default="preview")
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--backup-dir")
    args = parser.parse_args()

    master_root = Path(args.master_root).resolve()
    project_root = Path(args.project_copy_root).resolve()
    actions = [value.strip() for value in args.actions.split(",") if value.strip()]
    roi = tuple(int(value) for value in args.roi.split(","))
    if len(roi) != 4:
        raise ValueError("ROI must be x,y,width,height")
    output_dir = Path(args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    backup_dir = Path(args.backup_dir).resolve() if args.backup_dir else None

    records = []
    for action in actions:
        master_frames = sorted((master_root / action).glob("*.png"))
        project_frames = sorted((project_root / action).glob("*.png"))
        if [path.name for path in master_frames] != [path.name for path in project_frames]:
            raise ValueError(f"Master/project frame lists differ for {action}")
        for master_path, project_path in zip(master_frames, project_frames):
            if sha256(master_path) != sha256(project_path):
                raise ValueError(f"Master/project bytes differ before cleanup: {action}/{master_path.name}")
            source = Image.open(master_path).convert("RGBA")
            cleaned, mask = clean_image(source, roi, args.max_alpha)
            changed_pixels = int(mask.sum())
            if changed_pixels:
                source_array = np.asarray(source)
                cleaned_array = np.asarray(cleaned)
                changed = np.any(source_array != cleaned_array, axis=2)
                changed_outside_mask = int(np.count_nonzero(changed & ~mask))
                records.append(
                    {
                        "action": action,
                        "frame": master_path.name,
                        "master_path": str(master_path),
                        "project_path": str(project_path),
                        "before_sha256": sha256(master_path),
                        "changed_pixels": changed_pixels,
                        "changed_outside_mask": changed_outside_mask,
                        "size": list(source.size),
                        "mode": source.mode,
                    }
                )

    if args.mode == "apply":
        if backup_dir is None:
            raise ValueError("--backup-dir is required in apply mode")
        if backup_dir.exists():
            raise ValueError(f"Backup directory already exists: {backup_dir}")
        for record in records:
            action = record["action"]
            name = record["frame"]
            master_path = Path(record["master_path"])
            project_path = Path(record["project_path"])
            for copy_name, source_path in (("master", master_path), ("project_copy", project_path)):
                destination = backup_dir / copy_name / action / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source_path, destination)
            cleaned, _mask = clean_image(Image.open(master_path).convert("RGBA"), roi, args.max_alpha)
            write_atomic_png(cleaned, master_path)
            write_atomic_png(cleaned, project_path)
            record["after_sha256"] = sha256(master_path)
            record["master_project_equal_after"] = sha256(master_path) == sha256(project_path)

    top_records = sorted(records, key=lambda item: item["changed_pixels"], reverse=True)[:5]
    crop_box = (900, 590, 1060, 834)
    rows = []
    for record in top_records:
        source_path = (
            backup_dir / "master" / record["action"] / record["frame"]
            if args.mode == "apply"
            else Path(record["master_path"])
        )
        before = Image.open(source_path).convert("RGBA")
        after, _mask = clean_image(before, roi, args.max_alpha)
        left = preview_tile(before, crop_box, f"before x96 alpha  {record['action']}/{record['frame']}")
        right = preview_tile(after, crop_box, f"after  transparent  changed={record['changed_pixels']}")
        row = Image.new("RGB", (960, 476), (20, 22, 26))
        row.paste(left, (0, 0))
        row.paste(right, (480, 0))
        rows.append(row)
    if rows:
        sheet = Image.new("RGB", (960, 476 * len(rows)), (18, 20, 24))
        for index, row in enumerate(rows):
            sheet.paste(row, (0, index * 476))
        sheet.save(output_dir / "right_low_alpha_key_residue_preview.png")

    ok = all(record["changed_outside_mask"] == 0 for record in records)
    if args.mode == "apply":
        ok = ok and all(record.get("master_project_equal_after", False) for record in records)
    report = {
        "ok": ok,
        "mode": args.mode,
        "master_root": str(master_root),
        "project_copy_root": str(project_root),
        "actions": actions,
        "roi": list(roi),
        "max_alpha": args.max_alpha,
        "affected_frame_count": len(records),
        "changed_pixel_count": sum(record["changed_pixels"] for record in records),
        "backup_dir": str(backup_dir) if backup_dir else None,
        "records": records,
    }
    (output_dir / "right_low_alpha_key_residue_report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    if not ok:
        raise SystemExit(1)


if __name__ == "__main__":
    main()

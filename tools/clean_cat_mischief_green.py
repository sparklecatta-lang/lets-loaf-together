from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from repair_today_green_edges import repair_rgba


EXPECTED_SIZE = (1112, 834)

# Mapped from guide1.psd (1440x1080) to the exported 1112x834 frame canvas.
# The PSD labels these areas as "绿色全删" and "删除绿色，保全黄猫".
GUIDE_ROIS = {
    "monitor_right_green_all": (914, 282, 198, 155),
    "table_edge_preserve_yellow_cat": (419, 427, 518, 12),
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def key_green_mask(rgba: np.ndarray) -> np.ndarray:
    work = rgba.astype(np.int16)
    alpha = work[..., 3]
    red = work[..., 0]
    green = work[..., 1]
    blue = work[..., 2]
    dominance = np.minimum(green - red, green - blue)
    return (alpha > 0) & (green >= 65) & (dominance > 4)


def roi_mask(shape: tuple[int, int, int]) -> np.ndarray:
    mask = np.zeros(shape[:2], dtype=bool)
    for x, y, width, height in GUIDE_ROIS.values():
        mask[y : y + height, x : x + width] = True
    return mask


def checkerboard(size: tuple[int, int], cell: int = 20) -> Image.Image:
    width, height = size
    yy, xx = np.indices((height, width))
    value = np.where(((xx // cell) + (yy // cell)) % 2 == 0, 212, 178).astype(np.uint8)
    return Image.fromarray(np.stack((value, value, value), axis=2), "RGB")


def composite(image: Image.Image) -> Image.Image:
    base = checkerboard(image.size).convert("RGBA")
    base.alpha_composite(image.convert("RGBA"))
    return base.convert("RGB")


def font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for candidate in (Path(r"C:\Windows\Fonts\msyh.ttc"), Path(r"C:\Windows\Fonts\simhei.ttf")):
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size=size)
    return ImageFont.load_default()


def tile(image: Image.Image, label: str) -> Image.Image:
    body = composite(image)
    body.thumbnail((500, 375), Image.Resampling.LANCZOS)
    result = Image.new("RGB", (520, 415), (28, 30, 34))
    result.paste(body, ((520 - body.width) // 2, 38))
    ImageDraw.Draw(result).text((10, 8), label, fill=(245, 245, 245), font=font(20))
    return result


def make_qa_sheet(records: list[dict], source_dir: Path, output_dir: Path, path: Path) -> None:
    wanted = {0, 19, 43, 59, len(records) - 1}
    selected = [record for index, record in enumerate(records) if index in wanted]
    sheet = Image.new("RGB", (1040, 415 * len(selected)), (18, 20, 24))
    for row, record in enumerate(selected):
        name = record["name"]
        before = Image.open(source_dir / name).convert("RGBA")
        after = Image.open(output_dir / name).convert("RGBA")
        sheet.paste(tile(before, f"清理前 {name}"), (0, row * 415))
        sheet.paste(tile(after, f"清理后 {name}"), (520, row * 415))
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path, optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-dir", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--qa-sheet", required=True, type=Path)
    args = parser.parse_args()

    source_dir = args.source_dir.resolve()
    output_dir = args.output_dir.resolve()
    frames = sorted(source_dir.glob("*.png"))
    if len(frames) != 91:
        raise RuntimeError(f"Expected 91 PNG frames, found {len(frames)}")
    output_dir.mkdir(parents=True, exist_ok=True)

    guide_mask = roi_mask((EXPECTED_SIZE[1], EXPECTED_SIZE[0], 4))
    records: list[dict] = []
    for source in frames:
        original = np.array(Image.open(source).convert("RGBA"), dtype=np.uint8, copy=True)
        if (original.shape[1], original.shape[0]) != EXPECTED_SIZE:
            raise RuntimeError(f"Unexpected canvas for {source.name}: {original.shape[1]}x{original.shape[0]}")

        repaired, edge_details = repair_rgba(original)
        forced = key_green_mask(repaired) & guide_mask
        forced_count = int(np.count_nonzero(forced))
        repaired[forced] = 0

        remaining_guide_green = int(np.count_nonzero(key_green_mask(repaired) & guide_mask))
        if remaining_guide_green:
            raise RuntimeError(f"Guide-region green remains in {source.name}: {remaining_guide_green}")

        warm_original = (
            (original[..., 3] > 0)
            & (original[..., 0].astype(np.int16) >= original[..., 1].astype(np.int16))
            & (original[..., 0].astype(np.int16) >= original[..., 2].astype(np.int16))
        )
        changed = np.any(repaired != original, axis=2)
        warm_pixels_changed = int(np.count_nonzero(changed & warm_original))
        if warm_pixels_changed:
            raise RuntimeError(f"Warm/yellow pixels changed in {source.name}: {warm_pixels_changed}")

        output = output_dir / source.name
        Image.fromarray(repaired, "RGBA").save(output, optimize=True)
        records.append(
            {
                "name": source.name,
                "size": list(EXPECTED_SIZE),
                "source_sha256": sha256(source),
                "output_sha256": sha256(output),
                "changed_pixels": int(np.count_nonzero(changed)),
                "edge_green_pixels_selected": edge_details["pure_green_pixels_selected"],
                "guide_green_pixels_forced_transparent": forced_count,
                "remaining_guide_green_pixels": remaining_guide_green,
                "warm_yellow_pixels_changed": warm_pixels_changed,
            }
        )

    summary = {
        "source_dir": str(source_dir),
        "output_dir": str(output_dir),
        "frame_count": len(records),
        "canvas": list(EXPECTED_SIZE),
        "guide_rois": GUIDE_ROIS,
        "changed_pixels": sum(item["changed_pixels"] for item in records),
        "edge_green_pixels_selected": sum(item["edge_green_pixels_selected"] for item in records),
        "guide_green_pixels_forced_transparent": sum(
            item["guide_green_pixels_forced_transparent"] for item in records
        ),
        "remaining_guide_green_pixels": sum(item["remaining_guide_green_pixels"] for item in records),
        "warm_yellow_pixels_changed": sum(item["warm_yellow_pixels_changed"] for item in records),
    }
    payload = {"summary": summary, "records": records}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    make_qa_sheet(records, source_dir, output_dir, args.qa_sheet)
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

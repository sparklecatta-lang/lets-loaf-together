from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont


GROUPS = [
    ("离开", "desk_girl/leave", "desk_girl_leave"),
    ("回来", "desk_girl/come_back", "desk_girl_come_back"),
    ("操作鼠标", "desk_girl/use_mouse", "desk_girl_use_mouse"),
    ("喝水bonus", "desk_girl/drink_water_bonus", "desk_girl_drink_water_bonus"),
    ("黄猫惊吓", "yellow_cat/startled", "yellow_cat_startled"),
    ("黄猫捣蛋", "yellow_cat/mischief", "yellow_cat_mischief"),
]


def font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for path in (Path(r"C:\Windows\Fonts\msyh.ttc"), Path(r"C:\Windows\Fonts\simhei.ttf")):
        if path.exists():
            return ImageFont.truetype(str(path), size)
    return ImageFont.load_default()


def checker(size: tuple[int, int], cell: int = 16) -> Image.Image:
    width, height = size
    yy, xx = np.indices((height, width))
    values = np.where(((xx // cell) + (yy // cell)) % 2 == 0, 74, 42).astype(np.uint8)
    rgb = np.stack([values, values, values], axis=2)
    return Image.fromarray(rgb, "RGB")


def tile(path: Path, label: str, size: tuple[int, int]) -> Image.Image:
    rgba = Image.open(path).convert("RGBA")
    bg = checker(rgba.size).convert("RGBA")
    bg.alpha_composite(rgba)
    body = bg.convert("RGB")
    body.thumbnail(size, Image.Resampling.LANCZOS)
    canvas = Image.new("RGB", (size[0], size[1] + 34), (24, 26, 30))
    canvas.paste(body, ((size[0] - body.width) // 2, 34 + (size[1] - body.height) // 2))
    ImageDraw.Draw(canvas).text((8, 6), label, fill=(245, 245, 245), font=font(17))
    return canvas


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--original-root", type=Path, required=True)
    parser.add_argument("--staged-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    tile_size = (278, 208)
    rows = []
    for label, original_rel, staged_rel in GROUPS:
        originals = sorted((args.original_root / original_rel).glob("*.png"))
        staged = sorted((args.staged_root / staged_rel).glob("*.png"))
        if len(originals) != len(staged) or not originals:
            raise RuntimeError(f"Frame mismatch for {label}")
        indexes = sorted({0, len(originals) // 2, len(originals) - 1})
        row_tiles = []
        for index in indexes:
            frame_label = f"{label} {index + 1}/{len(originals)}"
            row_tiles.append(tile(originals[index], f"原 {frame_label}", tile_size))
            row_tiles.append(tile(staged[index], f"修 {frame_label}", tile_size))
        row = Image.new("RGB", (len(row_tiles) * tile_size[0], tile_size[1] + 34), (18, 20, 24))
        for column, item in enumerate(row_tiles):
            row.paste(item, (column * tile_size[0], 0))
        rows.append(row)
    sheet = Image.new("RGB", (rows[0].width, sum(row.height for row in rows)), (18, 20, 24))
    y = 0
    for row in rows:
        sheet.paste(row, (0, y))
        y += row.height
    args.output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(args.output, quality=96)
    print(args.output)


if __name__ == "__main__":
    main()

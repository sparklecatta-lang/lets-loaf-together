from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw


SIZES = (1024, 512, 256, 128, 64, 48, 32, 16)
ICO_SIZES = ((256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (16, 16))


def resize_alpha_safe(image: Image.Image, size: int) -> Image.Image:
    premultiplied = image.convert("RGBa")
    resized = premultiplied.resize((size, size), Image.Resampling.LANCZOS)
    return resized.convert("RGBA")


def checkerboard(size: int, cell: int = 8) -> Image.Image:
    image = Image.new("RGB", (size, size), (232, 232, 232))
    draw = ImageDraw.Draw(image)
    for y in range(0, size, cell):
        for x in range(0, size, cell):
            if (x // cell + y // cell) % 2:
                draw.rectangle((x, y, x + cell - 1, y + cell - 1), fill=(196, 196, 196))
    return image


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()

    args.output_dir.mkdir(parents=True, exist_ok=True)
    source = Image.open(args.input).convert("RGBA")
    if source.width != source.height:
        raise ValueError(f"Icon master must be square, got {source.size}")

    outputs: dict[int, Image.Image] = {}
    for size in SIZES:
        icon = resize_alpha_safe(source, size)
        output_path = args.output_dir / f"app_icon_{size}.png"
        icon.save(output_path, optimize=True)
        outputs[size] = icon

    source.save(
        args.output_dir / "app_icon.ico",
        format="ICO",
        sizes=list(ICO_SIZES),
        bitmap_format="png",
    )

    tile_size = 160
    preview = Image.new("RGB", (tile_size * 4, tile_size * 2), (34, 37, 43))
    draw = ImageDraw.Draw(preview)
    for index, size in enumerate(SIZES):
        x = (index % 4) * tile_size
        y = (index // 4) * tile_size
        board = checkerboard(124)
        shown = outputs[size].resize((112, 112), Image.Resampling.NEAREST)
        board.paste(shown, (6, 6), shown)
        preview.paste(board, (x + 18, y + 8))
        draw.text((x + 18, y + 136), f"{size} x {size}", fill=(245, 245, 245))
    preview.save(args.output_dir / "app_icon_size_preview.png", optimize=True)

    for size, icon in outputs.items():
        alpha = icon.getchannel("A")
        corners = (alpha.getpixel((0, 0)), alpha.getpixel((size - 1, 0)),
                   alpha.getpixel((0, size - 1)), alpha.getpixel((size - 1, size - 1)))
        opaque_bounds = alpha.getbbox()
        magenta_pixels = sum(
            1 for red, green, blue, opacity in icon.get_flattened_data()
            if opacity >= 32 and red >= 220 and blue >= 220 and green <= 80
        )
        print(
            f"{size}: corners={corners} alpha_bounds={opaque_bounds} "
            f"magenta_pixels={magenta_pixels}"
        )

    with Image.open(args.output_dir / "app_icon.ico") as icon_file:
        print(f"ICO sizes={sorted(icon_file.ico.sizes(), reverse=True)}")


if __name__ == "__main__":
    main()

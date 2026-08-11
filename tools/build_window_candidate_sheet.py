from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--inputs", nargs=4, required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    cell_size = (556, 417)
    sheet = Image.new("RGB", (cell_size[0] * 2, cell_size[1] * 2), (18, 21, 27))
    font = ImageFont.load_default(size=32)

    for index, source in enumerate(args.inputs):
        image = Image.open(source).convert("RGB").resize(cell_size, Image.Resampling.LANCZOS)
        x = (index % 2) * cell_size[0]
        y = (index // 2) * cell_size[1]
        sheet.paste(image, (x, y))

        label = chr(ord("A") + index)
        draw = ImageDraw.Draw(sheet)
        draw.rounded_rectangle((x + 14, y + 14, x + 68, y + 64), radius=10, fill=(20, 24, 31, 230))
        draw.text((x + 30, y + 21), label, font=font, fill=(255, 225, 165))

    output = Path(args.output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output, quality=95)


if __name__ == "__main__":
    main()

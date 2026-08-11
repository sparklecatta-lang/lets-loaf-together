from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    # Sampled from the actual production yellow-cat platform frame.
    colors = [
        (253, 237, 221),  # cream-white tabletop
        (244, 203, 182),  # pale peach front edge
        (170, 119, 92),   # restrained warm outline / walnut accent
    ]
    image = Image.new("RGB", (900, 600), colors[0])
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, 899, 329), fill=colors[0])
    draw.rectangle((0, 330, 899, 499), fill=colors[1])
    draw.rectangle((0, 500, 899, 599), fill=colors[2])

    output = Path(args.output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    image.save(output)


if __name__ == "__main__":
    main()

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--x-start", type=int, default=160)
    parser.add_argument("--band-top", type=int, default=928)
    parser.add_argument("--old-bottom", type=int, default=962)
    parser.add_argument("--target-bottom", type=int, default=973)
    args = parser.parse_args()

    image = Image.open(args.input).convert("RGB")
    width, _ = image.size
    source_band = image.crop((args.x_start, args.band_top, width, args.old_bottom + 1))
    target_height = args.target_bottom - args.band_top + 1
    extended_band = source_band.resize((source_band.width, target_height), Image.Resampling.BICUBIC)
    image.paste(extended_band, (args.x_start, args.band_top))

    args.output.parent.mkdir(parents=True, exist_ok=True)
    image.save(args.output, compress_level=6)


if __name__ == "__main__":
    main()

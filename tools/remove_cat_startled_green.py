#!/usr/bin/env python3
"""Remove baked green-screen pixels from the yellow-cat startled frames.

Only pixels that are demonstrably green-dominant are changed. Their RGB values
are retained while alpha is cleared, so every non-target pixel stays byte-for-
byte identical after PNG decoding.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw


def is_green_screen(r: int, g: int, b: int, a: int) -> bool:
    return a > 0 and g >= 60 and g - r >= 18 and g - b >= 4


def render_preview(before: Image.Image, after: Image.Image, destination: Path) -> None:
    background = (28, 31, 35, 255)

    def flatten(image: Image.Image) -> Image.Image:
        canvas = Image.new("RGBA", image.size, background)
        canvas.alpha_composite(image)
        return canvas.convert("RGB")

    left = flatten(before)
    right = flatten(after)
    gap = 12
    header = 28
    sheet = Image.new("RGB", (left.width * 2 + gap, left.height + header), background[:3])
    sheet.paste(left, (0, header))
    sheet.paste(right, (left.width + gap, header))
    draw = ImageDraw.Draw(sheet)
    draw.text((8, 7), "before", fill=(238, 238, 238))
    draw.text((left.width + gap + 8, 7), "after", fill=(238, 238, 238))
    destination.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(destination)


def clean_frame(source: Path, destination: Path, preview_dir: Path | None) -> dict[str, object]:
    before = Image.open(source).convert("RGBA")
    after = before.copy()
    source_pixels = before.load()
    output_pixels = after.load()
    changed = 0
    xs: list[int] = []
    ys: list[int] = []

    for y in range(before.height):
        for x in range(before.width):
            r, g, b, a = source_pixels[x, y]
            if not is_green_screen(r, g, b, a):
                continue
            output_pixels[x, y] = (r, g, b, 0)
            changed += 1
            xs.append(x)
            ys.append(y)

    destination.parent.mkdir(parents=True, exist_ok=True)
    after.save(destination)
    if preview_dir is not None:
        render_preview(before, after, preview_dir / source.name)
    remaining_green = 0
    non_target_changes = 0
    for before_pixel, after_pixel in zip(before.getdata(), after.getdata()):
        if is_green_screen(*after_pixel):
            remaining_green += 1
        if before_pixel != after_pixel and not is_green_screen(*before_pixel):
            non_target_changes += 1
    return {
        "file": source.name,
        "size": [before.width, before.height],
        "changed_pixels": changed,
        "remaining_green_pixels": remaining_green,
        "non_target_changes": non_target_changes,
        "changed_bbox": [min(xs), min(ys), max(xs), max(ys)] if xs else None,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("source_dir", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--preview-dir", type=Path)
    args = parser.parse_args()

    sources = sorted(args.source_dir.glob("*.png"))
    if not sources:
        raise SystemExit(f"No PNG files found in {args.source_dir}")

    results = [
        clean_frame(source, args.output_dir / source.name, args.preview_dir)
        for source in sources
    ]
    report = {
        "source_dir": str(args.source_dir),
        "output_dir": str(args.output_dir),
        "frame_count": len(results),
        "changed_pixels": sum(int(item["changed_pixels"]) for item in results),
        "remaining_green_pixels": sum(
            int(item["remaining_green_pixels"]) for item in results
        ),
        "non_target_changes": sum(int(item["non_target_changes"]) for item in results),
        "frames": results,
    }
    encoded = json.dumps(report, ensure_ascii=False, indent=2)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(encoded + "\n", encoding="utf-8")
    print(encoded)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

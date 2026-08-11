from __future__ import annotations

import argparse
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont


def font(size: int) -> ImageFont.ImageFont:
    candidates = [
        Path("C:/Windows/Fonts/msyh.ttc"),
        Path("C:/Windows/Fonts/arial.ttf"),
    ]
    for candidate in candidates:
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size=size)
    return ImageFont.load_default()


def checker(width: int, height: int, cell: int = 12) -> Image.Image:
    yy, xx = np.indices((height, width))
    pattern = ((xx // cell + yy // cell) % 2).astype(np.uint8)
    values = np.where(pattern[..., None] == 0, 215, 175).astype(np.uint8)
    rgb = np.repeat(values, 3, axis=2)
    return Image.fromarray(rgb, "RGB")


def thumbnail(path: Path, width: int = 360) -> Image.Image:
    rgba = Image.open(path).convert("RGBA")
    height = round(rgba.height * width / rgba.width)
    rgba.thumbnail((width, height), Image.Resampling.LANCZOS)
    base = checker(width, height)
    x = (width - rgba.width) // 2
    y = (height - rgba.height) // 2
    base.paste(rgba, (x, y), rgba)
    return base


def difference_thumbnail(first: Path, last: Path, width: int = 360) -> Image.Image:
    a = cv2.imread(str(first), cv2.IMREAD_UNCHANGED)
    b = cv2.imread(str(last), cv2.IMREAD_UNCHANGED)
    if a is None or b is None:
        raise ValueError(f"Could not load {first} or {last}")
    diff = cv2.absdiff(a, b)
    heat = np.max(diff, axis=2)
    heat = np.clip(heat.astype(np.float32) * 5.0, 0, 255).astype(np.uint8)
    heat = cv2.applyColorMap(heat, cv2.COLORMAP_TURBO)
    height = round(heat.shape[0] * width / heat.shape[1])
    heat = cv2.resize(heat, (width, height), interpolation=cv2.INTER_AREA)
    return Image.fromarray(cv2.cvtColor(heat, cv2.COLOR_BGR2RGB))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--audit", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()

    report = json.loads(args.audit.read_text(encoding="utf-8"))
    manifest_path = args.project_root / "xsxb_frame_tuner/data/projects/Watercolor_Desk_Companion/animation_manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    animation_frames = {}
    for profile in manifest["profiles"]:
        for animation in profile["animations"]:
            key = f"{profile['id']}/{animation['id']}"
            animation_frames[key] = [args.project_root / frame["path"] for frame in animation["frames"]]

    args.output_dir.mkdir(parents=True, exist_ok=True)
    label_font = font(24)
    small_font = font(19)
    tile_width = 360
    tile_height = round(834 * tile_width / 1112)
    header_height = 60
    row_height = tile_height + 70

    for animation in report["animations"]:
        groups = animation.get("merged_groups", [])
        if not groups:
            continue
        key = animation["key"]
        frames = animation_frames[key]
        sheet = Image.new("RGB", (tile_width * 4, header_height + row_height * len(groups)), (24, 24, 26))
        draw = ImageDraw.Draw(sheet)
        draw.text(
            (16, 14),
            f"{key}  {animation['frames_before']} -> {animation['frames_after_candidate']}",
            font=label_font,
            fill=(245, 245, 245),
        )
        for row, group in enumerate(groups):
            members = [int(value) for value in group["members"]]
            first_index = members[0]
            middle_index = members[len(members) // 2]
            last_index = members[-1]
            images = [
                thumbnail(frames[first_index], tile_width),
                thumbnail(frames[middle_index], tile_width),
                thumbnail(frames[last_index], tile_width),
                difference_thumbnail(frames[first_index], frames[last_index], tile_width),
            ]
            y = header_height + row * row_height
            for column, image in enumerate(images):
                sheet.paste(image, (column * tile_width, y))
            labels = [
                f"保留 {first_index + 1}",
                f"中间 {middle_index + 1}",
                f"末帧 {last_index + 1}",
                f"差异 x5 | 合并 {round(group['duration_ms'])}ms",
            ]
            for column, text in enumerate(labels):
                draw.text(
                    (column * tile_width + 10, y + tile_height + 14),
                    text,
                    font=small_font,
                    fill=(235, 235, 235),
                )
        output = args.output_dir / f"{key.replace('/', '__')}.jpg"
        sheet.save(output, quality=92)
        print(output)


if __name__ == "__main__":
    main()

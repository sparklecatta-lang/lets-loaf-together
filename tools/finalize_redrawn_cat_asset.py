from __future__ import annotations

import argparse
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw


def supersampled_polygon(size: tuple[int, int], points: list[tuple[int, int]]) -> np.ndarray:
    width, height = size
    scale = 4
    canvas = Image.new("L", (width * scale, height * scale), 0)
    draw = ImageDraw.Draw(canvas)
    draw.polygon([(x * scale, y * scale) for x, y in points], fill=255)
    return np.asarray(
        canvas.resize((width, height), Image.Resampling.LANCZOS), dtype=np.uint8
    ).astype(np.float32) / 255.0


def cubic_points(
    start: tuple[float, float],
    control1: tuple[float, float],
    control2: tuple[float, float],
    end: tuple[float, float],
    count: int = 24,
) -> list[tuple[int, int]]:
    points: list[tuple[int, int]] = []
    for t in np.linspace(0.0, 1.0, count):
        u = 1.0 - t
        x = u**3 * start[0] + 3 * u**2 * t * control1[0] + 3 * u * t**2 * control2[0] + t**3 * end[0]
        y = u**3 * start[1] + 3 * u**2 * t * control1[1] + 3 * u * t**2 * control2[1] + t**3 * end[1]
        points.append((round(x), round(y)))
    return points


def redraw_tail_terminal(rgb: np.ndarray) -> tuple[np.ndarray, dict[str, object]]:
    height, width = rgb.shape[:2]
    yy, xx = np.indices((height, width))
    tip = (835, 589)
    taper_top = (860, 575)
    taper_bottom = (860, 603)
    color_top = (884, 575)
    color_middle = (891, 589)
    color_bottom = (884, 603)
    lock_x = 893
    upper_curve = cubic_points(taper_top, (852, 575), (839, 582), tip)
    lower_curve = cubic_points(tip, (839, 596), (852, 603), taper_bottom)
    color_upper = cubic_points(color_top, (888, 579), (891, 584), color_middle, count=14)
    color_lower = cubic_points(color_middle, (891, 595), (888, 600), color_bottom, count=14)
    right_curve_bottom_to_top = list(reversed(color_upper + color_lower[1:]))
    target_points = [color_top, taper_top] + upper_curve[1:] + lower_curve[1:] + [color_bottom] + right_curve_bottom_to_top[1:]

    target = supersampled_polygon(
        (width, height),
        target_points,
    )
    target[xx >= lock_x] = 0.0

    roi = (
        (xx >= 830)
        & (xx < lock_x)
        & (yy >= 569)
        & (yy <= 609)
    )
    white = (
        (rgb[..., 0] > 175)
        & (rgb[..., 1] > 135)
        & (rgb[..., 2] > 105)
        & ((rgb[..., 0].astype(np.int16) - rgb[..., 1].astype(np.int16)) < 95)
    )
    luma = (
        0.299 * rgb[..., 0].astype(np.float32)
        + 0.587 * rgb[..., 1].astype(np.float32)
        + 0.114 * rgb[..., 2].astype(np.float32)
    )
    near_white = cv2.dilate(white.astype(np.uint8), np.ones((5, 5), np.uint8)) > 0
    old_terminal = roi & (white | (near_white & (luma < 105)))
    remove = old_terminal
    remove_alpha = cv2.GaussianBlur(
        remove.astype(np.uint8) * 255, (0, 0), 0.45
    ).astype(np.float32) / 255.0
    remove_alpha *= roi.astype(np.float32)

    result = rgb.astype(np.float32).copy()
    wood_sample = np.roll(rgb, 60, axis=1).astype(np.float32)
    result = result * (1.0 - remove_alpha[..., None]) + wood_sample * remove_alpha[..., None]

    texture = result.copy()
    for y in range(570, 607):
        sample_y = min(601, max(575, y))
        row_white = white[sample_y, 858:884]
        row_pixels = rgb[sample_y, 858:884][row_white]
        if row_pixels.size:
            row_color = np.median(row_pixels, axis=0)
        else:
            row_color = np.array([244.0, 217.0, 190.0])
        for x in range(832, lock_x):
            texture[y, x] = np.clip(
                row_color + np.array([2.0, 1.0, 0.0]) * ((x - 832) / 52.0),
                0,
                255,
            )

    # Repaint the complete local white block so the old rounded contour cannot
    # survive as an internal vertical seam.
    result = result * (1.0 - target[..., None]) + texture * target[..., None]

    target_u8 = np.clip(target * 255.0, 0, 255).astype(np.uint8)
    inner = cv2.erode(target_u8, np.ones((3, 3), np.uint8), iterations=1)
    outline_alpha = np.clip(
        target - inner.astype(np.float32) / 255.0, 0.0, 1.0
    )
    outline_alpha[xx >= color_top[0]] = 0.0
    outline_color = np.array([57.0, 38.0, 25.0], dtype=np.float32)
    result = result * (1.0 - outline_alpha[..., None]) + outline_color * outline_alpha[..., None]
    result = np.clip(result, 0, 255).astype(np.uint8)

    before_white = int(np.count_nonzero(white & roi))
    after_white_mask = (
        (result[..., 0] > 175)
        & (result[..., 1] > 135)
        & (result[..., 2] > 105)
        & ((result[..., 0].astype(np.int16) - result[..., 1].astype(np.int16)) < 95)
    )
    after_white = int(np.count_nonzero(after_white_mask & roi))
    report = {
        "edited_bbox": [830, 569, lock_x, 610],
        "point": list(tip),
        "unchanged_from_x": lock_x,
        "geometry_unchanged_from_x": bool(
            np.array_equal(result[:, lock_x:], rgb[:, lock_x:])
        ),
        "terminal_white_pixels_before": before_white,
        "terminal_white_pixels_after": after_white,
    }
    return result, report


def flatten_green_background(rgb: np.ndarray) -> tuple[np.ndarray, dict[str, object]]:
    r = rgb[..., 0].astype(np.int16)
    g = rgb[..., 1].astype(np.int16)
    b = rgb[..., 2].astype(np.int16)
    green = (g > r + 28) & (g > b + 24) & (g > 80)
    out = rgb.copy()
    out[green] = np.array([31, 159, 82], dtype=np.uint8)
    return out, {
        "background_rgb": [31, 159, 82],
        "flattened_pixels": int(np.count_nonzero(green)),
        "background_is_uniform_on_green_mask": bool(
            np.unique(out[green], axis=0).shape[0] == 1
        ),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--qa-crop", required=True, type=Path)
    args = parser.parse_args()

    source_image = Image.open(args.input).convert("RGB")
    source = np.asarray(source_image, dtype=np.uint8)
    tail_edit, tail_report = redraw_tail_terminal(source)
    final, background_report = flatten_green_background(tail_edit)
    if final.shape[1] == 1449:
        final = final[:, :1448]

    args.output.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(final, mode="RGB").save(args.output, format="PNG", optimize=True)

    qa = Image.fromarray(final[548:630, 805:930], mode="RGB")
    qa = qa.resize((qa.width * 4, qa.height * 4), Image.Resampling.NEAREST)
    args.qa_crop.parent.mkdir(parents=True, exist_ok=True)
    qa.save(args.qa_crop, format="PNG", optimize=True)

    report = {
        "input": str(args.input),
        "output": str(args.output),
        "input_canvas": [source_image.width, source_image.height],
        "output_canvas": [int(final.shape[1]), int(final.shape[0])],
        "tail": tail_report,
        "background": background_report,
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

from __future__ import annotations

import argparse
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw


def largest_component(mask: np.ndarray) -> np.ndarray:
    count, labels, stats, _ = cv2.connectedComponentsWithStats(
        mask.astype(np.uint8), connectivity=8
    )
    if count < 2:
        raise RuntimeError("No foreground component found")
    largest = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
    return labels == largest


def recolor_platform_in_place(
    rgb: np.ndarray,
    foreground: np.ndarray,
    cat_mask: np.ndarray,
) -> tuple[np.ndarray, np.ndarray]:
    height, width = foreground.shape
    yy, xx = np.indices((height, width))
    cat_alpha = cat_mask.astype(np.float32) / 255.0
    platform = foreground & (yy >= 452)
    strength = platform.astype(np.float32) * (1.0 - cat_alpha)

    luma = (
        rgb[..., 0].astype(np.float32) * 0.299
        + rgb[..., 1].astype(np.float32) * 0.587
        + rgb[..., 2].astype(np.float32) * 0.114
    )
    top_face = yy < 525
    top_base = np.array([82.0, 52.0, 36.0], dtype=np.float32)
    front_base = np.array([48.0, 29.0, 21.0], dtype=np.float32)
    base = np.where(top_face[..., None], top_base, front_base)
    grain = (
        4.5 * np.sin(xx * 0.031 + np.sin(yy * 0.17) * 0.65)
        + 1.8 * np.sin(xx * 0.078 + yy * 0.09)
        + 1.2 * np.sin(xx * 0.013 - yy * 0.27)
    )
    shading = 0.84 + 0.25 * (luma / 255.0)
    wood = base * shading[..., None] + grain[..., None]
    wood[luma < 145] = np.array([31.0, 19.0, 14.0], dtype=np.float32)
    wood = np.clip(wood, 0, 255)

    out = rgb.astype(np.float32)
    blend = strength[..., None]
    out = out * (1.0 - blend) + wood * blend
    return np.clip(out, 0, 255).astype(np.uint8), cat_alpha


def warp_tail_cap_rows(
    rgb: np.ndarray,
    cat_mask: np.ndarray,
) -> tuple[np.ndarray, dict[str, object], np.ndarray]:
    """Redraw only the last 8 px of the white cap as a short point.

    The tail/cap connection at x >= 919 remains bit-identical.  This avoids the
    seam created by the old row-shift approach, which moved every pixel in the
    cap, including the connection to the orange tail.
    """
    height, width = cat_mask.shape
    yy, xx = np.indices((height, width))
    tip_x, point_join_x = 910, 918
    center_y, top_y, bottom_y = 505, 492, 518
    join_lock_x = point_join_x + 1

    # Supersampled target mask: the shaft keeps its thickness until x=923,
    # then closes into a short point at the source silhouette's original x=911.
    ss = 4
    fill_hi = Image.new("L", (width * ss, height * ss), 0)
    draw_fill = ImageDraw.Draw(fill_hi)
    draw_fill.polygon(
        [
            (tip_x * ss, center_y * ss),
            (point_join_x * ss, top_y * ss),
            (point_join_x * ss, bottom_y * ss),
        ],
        fill=255,
    )
    fill = np.asarray(
        fill_hi.resize((width, height), Image.Resampling.LANCZOS), dtype=np.uint8
    ).astype(np.float32) / 255.0
    fill[xx >= join_lock_x] = 0.0

    local_roi = (
        (xx >= tip_x - 3)
        & (xx < join_lock_x)
        & (yy >= top_y - 3)
        & (yy <= bottom_y + 3)
    )
    original_tail = local_roi & (cat_mask > 0)
    outside_new_shape = original_tail & (fill < 0.35)
    old_alpha = cv2.GaussianBlur(
        outside_new_shape.astype(np.uint8) * 255, (0, 0), 0.38
    ).astype(np.float32) / 255.0
    old_alpha *= local_roi.astype(np.float32) * (1.0 - fill)

    # Restore only the rounded pixels that lie outside the new point, using
    # nearby pixels from the same wooden top face.
    result = rgb.astype(np.float32).copy()
    board = np.roll(rgb, 48, axis=1).astype(np.float32)
    result = result * (1.0 - old_alpha[..., None]) + board * old_alpha[..., None]

    # Keep every original ivory pixel that already lies inside the new shape.
    # Only newly exposed point pixels receive colour sampled from the untouched
    # white cap immediately to the right.
    original_white = (
        (rgb[..., 0] > 190)
        & (rgb[..., 1] > 145)
        & (rgb[..., 2] > 110)
        & ((rgb[..., 0].astype(np.int16) - rgb[..., 1].astype(np.int16)) < 90)
    )
    original_white_alpha = cv2.GaussianBlur(
        original_white.astype(np.uint8) * 255, (0, 0), 0.32
    ).astype(np.float32) / 255.0
    paint = fill * (1.0 - original_white_alpha)
    texture = result.copy()
    for y in range(max(0, top_y - 2), min(height, bottom_y + 3)):
        src_y = min(max(y, 495), 515)
        for x in range(max(0, tip_x - 2), min(width, point_join_x + 2)):
            distance_from_base = point_join_x - x
            src_x = min(928, 920 + max(0, 4 - distance_from_base // 2))
            texture[y, x] = rgb[src_y, src_x]
    result = result * (1.0 - paint[..., None]) + texture * paint[..., None]

    outline_hi = Image.new("L", (width * ss, height * ss), 0)
    draw_outline = ImageDraw.Draw(outline_hi)
    outline_width = ss
    draw_outline.line(
        [
            (point_join_x * ss, top_y * ss),
            (tip_x * ss, center_y * ss),
            (point_join_x * ss, bottom_y * ss),
        ],
        fill=255,
        width=outline_width,
    )
    outline = np.asarray(
        outline_hi.resize((width, height), Image.Resampling.LANCZOS), dtype=np.uint8
    ).astype(np.float32) / 255.0
    outline[xx >= join_lock_x] = 0.0
    outline_rgb = np.array([55.0, 37.0, 22.0], dtype=np.float32)
    result = result * (1.0 - outline[..., None]) + outline_rgb * outline[..., None]
    result = np.clip(result, 0, 255).astype(np.uint8)

    allowed = (old_alpha > 0) | (fill > 0) | (outline > 0)
    measure_roi = (
        (xx >= 905) & (xx <= 945) & (yy >= 490) & (yy <= 520)
    )
    final_white = (
        (result[..., 0] > 190)
        & (result[..., 1] > 145)
        & (result[..., 2] > 110)
        & ((result[..., 0].astype(np.int16) - result[..., 1].astype(np.int16)) < 90)
    )
    white_before = int(np.count_nonzero(original_white & measure_roi))
    white_after = int(np.count_nonzero(final_white & measure_roi))
    before_y, before_x = np.nonzero(original_white & measure_roi)
    after_y, after_x = np.nonzero(final_white & measure_roi)
    white_bbox_before = [
        int(before_x.min()), int(before_y.min()), int(before_x.max()) + 1, int(before_y.max()) + 1
    ]
    white_bbox_after = [
        int(after_x.min()), int(after_y.min()), int(after_x.max()) + 1, int(after_y.max()) + 1
    ]
    before_span = (
        white_bbox_before[2] - white_bbox_before[0],
        white_bbox_before[3] - white_bbox_before[1],
    )
    after_span = (
        white_bbox_after[2] - white_bbox_after[0],
        white_bbox_after[3] - white_bbox_after[1],
    )
    metadata = {
        "terminal_edit_bbox": [tip_x - 3, top_y - 4, point_join_x + 2, bottom_y + 5],
        "point": [tip_x, center_y],
        "untouched_join_x": join_lock_x,
        "tip_length_px": point_join_x - tip_x,
        "tail_connection_bit_identical_from_x_919": bool(
            np.array_equal(result[:, join_lock_x:], rgb[:, join_lock_x:])
        ),
        "white_texture_source": [920, 495, 929, 516],
        "white_pixels_before": white_before,
        "white_pixels_after": white_after,
        "white_pixel_area_ratio": round(white_after / white_before, 4),
        "white_block_bbox_before": white_bbox_before,
        "white_block_bbox_after": white_bbox_after,
        "white_block_span_not_shrunk": bool(
            after_span[0] >= before_span[0] and after_span[1] >= before_span[1]
        ),
    }
    return result, metadata, allowed


def scale_whole_group(
    rgb: np.ndarray,
    background_rgb: np.ndarray,
    scale: float,
) -> tuple[Image.Image, dict[str, object], np.ndarray]:
    distance = np.linalg.norm(
        rgb.astype(np.int16) - background_rgb.astype(np.int16), axis=2
    )
    component = largest_component(distance > 9.0)
    support = cv2.dilate(component.astype(np.uint8), np.ones((3, 3), np.uint8)) > 0
    alpha = np.clip((distance - 2.0) / 14.0, 0.0, 1.0)
    alpha *= support.astype(np.float32)

    ys, xs = np.nonzero(component)
    x0, x1 = int(xs.min()), int(xs.max()) + 1
    y0, y1 = int(ys.min()), int(ys.max()) + 1
    crop_rgb = Image.fromarray(rgb[y0:y1, x0:x1], mode="RGB").convert("RGBA")
    crop_alpha = Image.fromarray(
        np.clip(alpha[y0:y1, x0:x1] * 255.0, 0, 255).astype(np.uint8), mode="L"
    )
    crop_rgb.putalpha(crop_alpha)

    new_size = (
        max(1, round(crop_rgb.width * scale)),
        max(1, round(crop_rgb.height * scale)),
    )
    scaled = crop_rgb.resize(new_size, Image.Resampling.LANCZOS)
    center_x = (x0 + x1) / 2.0
    paste_x = round(center_x - scaled.width / 2.0)
    paste_y = y1 - scaled.height
    canvas = Image.new("RGB", (rgb.shape[1], rgb.shape[0]), tuple(int(v) for v in background_rgb))
    canvas.paste(scaled.convert("RGB"), (paste_x, paste_y), scaled.getchannel("A"))

    placed = np.zeros(rgb.shape[:2], dtype=bool)
    placed_alpha = np.asarray(scaled.getchannel("A"), dtype=np.uint8) > 0
    placed[paste_y : paste_y + scaled.height, paste_x : paste_x + scaled.width] = placed_alpha
    metadata = {
        "source_group_bbox": [x0, y0, x1, y1],
        "final_group_bbox": [paste_x, paste_y, paste_x + scaled.width, paste_y + scaled.height],
        "scale": scale,
    }
    return canvas, metadata, placed


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--cat-mask", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--qa-crop", type=Path)
    parser.add_argument("--source-qa-crop", type=Path)
    parser.add_argument("--scale", type=float, default=0.82)
    args = parser.parse_args()

    source_image = Image.open(args.input).convert("RGB")
    source = np.asarray(source_image, dtype=np.uint8)
    if args.source_qa_crop:
        source_qa = source_image.crop((875, 465, 975, 535))
        source_qa = source_qa.resize(
            (source_qa.width * 4, source_qa.height * 4), Image.Resampling.NEAREST
        )
        args.source_qa_crop.parent.mkdir(parents=True, exist_ok=True)
        source_qa.save(args.source_qa_crop, format="PNG", optimize=True)
    cat_mask = np.asarray(Image.open(args.cat_mask).convert("L"), dtype=np.uint8)
    border = np.concatenate([source[0], source[-1], source[:, 0], source[:, -1]], axis=0)
    background = np.median(border, axis=0).astype(np.uint8)
    distance = np.linalg.norm(source.astype(np.int16) - background.astype(np.int16), axis=2)
    foreground = largest_component(distance > 12.0)

    wood_edit, _ = recolor_platform_in_place(source, foreground, cat_mask)
    tail_edit, tail_report, tail_allowed = warp_tail_cap_rows(wood_edit, cat_mask)

    tail_box = tail_allowed
    cat_core = cat_mask > 250
    protected = cat_core & ~tail_box
    protected_change = np.any(tail_edit != source, axis=2) & protected
    protected_changed_pixels = int(np.count_nonzero(protected_change))

    final, scale_report, placed_mask = scale_whole_group(tail_edit, background, args.scale)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    final.save(args.output, format="PNG", optimize=True)

    if args.qa_crop:
        group_x0, group_y0, _, _ = scale_report["source_group_bbox"]
        final_x0, final_y0, _, _ = scale_report["final_group_bbox"]
        crop_box = (
            round(final_x0 + (875 - group_x0) * args.scale),
            round(final_y0 + (465 - group_y0) * args.scale),
            round(final_x0 + (975 - group_x0) * args.scale),
            round(final_y0 + (535 - group_y0) * args.scale),
        )
        qa = final.crop(crop_box)
        qa = qa.resize((qa.width * 4, qa.height * 4), Image.Resampling.NEAREST)
        args.qa_crop.parent.mkdir(parents=True, exist_ok=True)
        qa.save(args.qa_crop, format="PNG", optimize=True)

    final_np = np.asarray(final, dtype=np.uint8)
    clean = np.empty_like(final_np)
    clean[:] = background
    changed = np.any(final_np != clean, axis=2)
    changed_outside = int(np.count_nonzero(changed & ~placed_mask))
    outside_colors = int(np.unique(final_np[~placed_mask], axis=0).shape[0])

    report = {
        "input": args.input.as_posix(),
        "output": args.output.as_posix(),
        "canvas": [source_image.width, source_image.height],
        "background_rgb": [int(v) for v in background],
        "tail": tail_report,
        "scale": scale_report,
        "protected_cat_core_changed_before_scale": protected_changed_pixels,
        "background_unique_colors_outside_group": outside_colors,
        "changed_pixels_outside_final_group": changed_outside,
        "exact_lock_pass": protected_changed_pixels == 0 and changed_outside == 0,
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

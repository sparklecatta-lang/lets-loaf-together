from __future__ import annotations

import argparse
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageFilter


def recolor_platform(
    image: Image.Image,
    foreground_mask: np.ndarray,
    cat_mask_path: Path,
) -> tuple[Image.Image, np.ndarray]:
    rgb = np.asarray(image.convert("RGB"), dtype=np.uint8)
    height, width = rgb.shape[:2]

    cat_mask = np.asarray(Image.open(cat_mask_path).convert("L"), dtype=np.uint8)
    cat_mask = np.asarray(
        Image.fromarray(cat_mask).filter(ImageFilter.MaxFilter(3)), dtype=np.uint8
    ) > 127

    yy, xx = np.indices((height, width))
    platform_mask = foreground_mask & (yy >= 452) & ~cat_mask

    # Keep the source geometry and line work; only remap its pale platform palette.
    source_luma = (
        rgb[..., 0].astype(np.float32) * 0.299
        + rgb[..., 1].astype(np.float32) * 0.587
        + rgb[..., 2].astype(np.float32) * 0.114
    )
    top_face = yy < 525
    top_base = np.array([83.0, 52.0, 35.0], dtype=np.float32)
    front_base = np.array([50.0, 29.0, 20.0], dtype=np.float32)
    base = np.where(top_face[..., None], top_base, front_base)

    # Long, restrained grain follows the board instead of looking like noise.
    grain = (
        5.0 * np.sin(xx * 0.030 + np.sin(yy * 0.18) * 0.7)
        + 2.0 * np.sin(xx * 0.083 + yy * 0.11)
        + 1.5 * np.sin(xx * 0.013 - yy * 0.31)
    )
    shading = 0.82 + 0.28 * (source_luma / 255.0)
    wood = base * shading[..., None] + grain[..., None]

    # Preserve the dark outline as a warm brown outline.
    dark_line = source_luma < 150
    wood[dark_line] = np.array([30.0, 18.0, 13.0], dtype=np.float32)
    wood = np.clip(wood, 0, 255).astype(np.uint8)

    result = rgb.copy()
    result[platform_mask] = wood[platform_mask]
    return Image.fromarray(result, mode="RGB"), platform_mask


def reshape_tail_tip_before_scale(
    image: Image.Image,
    cat_mask_path: Path,
) -> tuple[Image.Image, dict[str, object]]:
    arr = np.asarray(image.convert("RGB"), dtype=np.uint8).copy()
    original = arr.copy()
    height, width = arr.shape[:2]
    cat_mask = np.asarray(Image.open(cat_mask_path).convert("L"), dtype=np.uint8) > 96
    yy, xx = np.indices((height, width))

    roi = (
        (xx >= int(width * 0.59))
        & (xx <= int(width * 0.68))
        & (yy >= int(height * 0.42))
        & (yy <= int(height * 0.51))
    )
    white_tip = (
        roi
        & cat_mask
        & (arr[..., 0] > 195)
        & (arr[..., 1] > 155)
        & (arr[..., 2] > 125)
        & ((arr[..., 0].astype(np.int16) - arr[..., 1].astype(np.int16)) < 85)
    )
    white_y, white_x = np.nonzero(white_tip)
    if white_x.size == 0:
        raise RuntimeError("Source white tail tip was not found")

    white_x0, white_x1 = int(white_x.min()), int(white_x.max())
    white_y0, white_y1 = int(white_y.min()), int(white_y.max())
    apex_x = max(0, white_x0 - 2)
    base_x = min(width - 1, white_x1 + 1)
    center_y = round((white_y0 + white_y1) / 2.0)
    top_y = max(0, white_y0 - 2)
    bottom_y = min(height - 1, white_y1 + 2)
    point_neck_x = min(base_x, apex_x + max(10, round((base_x - apex_x) * 0.24)))

    top_curve: list[tuple[int, int]] = []
    bottom_curve: list[tuple[int, int]] = []
    point_span = max(1, point_neck_x - apex_x)
    for x in range(apex_x, point_neck_x + 1):
        progress = (x - apex_x) / point_span
        eased = progress ** 0.72
        top_curve.append((x, round(center_y + (top_y - center_y) * eased)))
        bottom_curve.append((x, round(center_y + (bottom_y - center_y) * eased)))

    outer_mask = np.zeros((height, width), dtype=np.uint8)
    outer_polygon = np.array(
        top_curve
        + [(base_x, top_y), (base_x, bottom_y)]
        + list(reversed(bottom_curve)),
        dtype=np.int32,
    )
    cv2.fillPoly(outer_mask, [outer_polygon], 255, lineType=cv2.LINE_AA)
    interior_mask = cv2.erode(
        outer_mask,
        np.ones((3, 3), dtype=np.uint8),
        iterations=1,
    )

    # Remove only the old rounded cap rectangle, reconstructing the dark board
    # from a cat-free sample at the same vertical coordinate.
    clear_mask = (
        (xx >= apex_x - 2)
        & (xx <= base_x)
        & (yy >= top_y - 2)
        & (yy <= bottom_y + 2)
    )
    safe_sample_x = max(0, apex_x - 260)
    clear_y, clear_x = np.nonzero(clear_mask)
    arr[clear_y, clear_x] = arr[clear_y, safe_sample_x]

    # Unwrap the original white shading column-by-column into the new short-point
    # silhouette. No flat replacement color is introduced.
    source_columns: dict[int, tuple[int, int]] = {}
    for sx in range(white_x0, white_x1 + 1):
        column_y = np.nonzero(white_tip[:, sx])[0]
        if column_y.size:
            source_columns[sx] = (int(column_y.min()), int(column_y.max()))
    if not source_columns:
        raise RuntimeError("White tail-tip texture columns were not found")

    target_y, target_x = np.nonzero(interior_mask > 96)
    target_width = max(1, base_x - apex_x)
    for ty, tx in zip(target_y, target_x, strict=True):
        tx_norm = (tx - apex_x) / target_width
        source_norm = 0.18 + 0.82 * tx_norm
        sx = round(white_x0 + source_norm * (white_x1 - white_x0))
        sx = min(source_columns, key=lambda key: abs(key - sx))
        source_top, source_bottom = source_columns[sx]
        target_half = max(1.0, min(center_y - top_y, bottom_y - center_y))
        ty_norm = np.clip((ty - center_y) / target_half, -1.0, 1.0)
        sy_center = (source_top + source_bottom) / 2.0
        sy_half = max(1.0, (source_bottom - source_top) / 2.0)
        sy = int(round(sy_center + ty_norm * sy_half))
        sy = int(np.clip(sy, source_top, source_bottom))
        arr[ty, tx] = original[sy, sx]

    outline = (91, 49, 24)
    cv2.polylines(
        arr,
        [np.array(top_curve + [(base_x, top_y)], dtype=np.int32)],
        False,
        outline,
        1,
        lineType=cv2.LINE_AA,
    )
    cv2.polylines(
        arr,
        [np.array(bottom_curve + [(base_x, bottom_y)], dtype=np.int32)],
        False,
        outline,
        1,
        lineType=cv2.LINE_AA,
    )
    metadata = {
        "source_white_tip_bbox": [white_x0, white_y0, white_x1 + 1, white_y1 + 1],
        "point_apex": [apex_x, center_y],
        "point_neck_x": point_neck_x,
        "tail_cap_base_x": base_x,
        "source_white_pixels": int(np.count_nonzero(white_tip)),
        "target_textured_pixels": int(target_x.size),
    }
    return Image.fromarray(arr, mode="RGB"), metadata


def minimally_point_tail_tip_before_scale(
    image: Image.Image,
    cat_mask_path: Path,
) -> tuple[Image.Image, dict[str, object]]:
    arr = np.asarray(image.convert("RGB"), dtype=np.uint8).copy()
    original = arr.copy()
    height, width = arr.shape[:2]
    cat_mask = np.asarray(Image.open(cat_mask_path).convert("L"), dtype=np.uint8) > 64
    yy, xx = np.indices((height, width))
    roi = (
        (xx >= int(width * 0.59))
        & (xx <= int(width * 0.68))
        & (yy >= int(height * 0.42))
        & (yy <= int(height * 0.51))
    )
    white_tip = (
        roi
        & cat_mask
        & (arr[..., 0] > 195)
        & (arr[..., 1] > 155)
        & (arr[..., 2] > 125)
        & ((arr[..., 0].astype(np.int16) - arr[..., 1].astype(np.int16)) < 85)
    )
    wy, wx = np.nonzero(white_tip)
    if wx.size == 0:
        raise RuntimeError("Source white tail tip was not found")

    white_x0, white_x1 = int(wx.min()), int(wx.max())
    white_y0, white_y1 = int(wy.min()), int(wy.max())
    apex_x = max(0, white_x0 - 2)
    neck_x = min(white_x1, apex_x + 9)
    profile_x = min(white_x1, neck_x + 3)
    profile_y = np.nonzero(white_tip[:, profile_x])[0]
    if profile_y.size == 0:
        profile_y = wy
    top_y = max(0, int(profile_y.min()) - 1)
    bottom_y = min(height - 1, int(profile_y.max()) + 1)
    center_y = round((top_y + bottom_y) / 2.0)
    span = max(1, neck_x - apex_x)

    top_curve: list[tuple[int, int]] = []
    bottom_curve: list[tuple[int, int]] = []
    for x in range(apex_x, neck_x + 1):
        progress = (x - apex_x) / span
        eased = progress ** 0.82
        top_curve.append((x, round(center_y + (top_y - center_y) * eased)))
        bottom_curve.append((x, round(center_y + (bottom_y - center_y) * eased)))

    point_mask = np.zeros((height, width), dtype=np.uint8)
    polygon = np.array(top_curve + list(reversed(bottom_curve)), dtype=np.int32)
    cv2.fillPoly(point_mask, [polygon], 255, lineType=cv2.LINE_AA)
    terminal_box = (
        (xx >= apex_x - 2)
        & (xx <= neck_x)
        & (yy >= top_y - 2)
        & (yy <= bottom_y + 2)
    )
    removed = terminal_box & (point_mask < 96)
    sample_x = max(0, apex_x - 260)
    removed_y, removed_x = np.nonzero(removed)
    arr[removed_y, removed_x] = arr[removed_y, sample_x]

    point_pixels = point_mask > 0
    interior_y, interior_x = np.nonzero(point_pixels)
    texture_x = min(white_x1, white_x0 + 15)
    texture_column_y = np.nonzero(white_tip[:, texture_x])[0]
    if texture_column_y.size == 0:
        texture_column_y = wy
    texture_top = int(texture_column_y.min())
    texture_bottom = int(texture_column_y.max())
    for py, px in zip(interior_y, interior_x, strict=True):
        norm = np.clip((py - top_y) / max(1, bottom_y - top_y), 0.0, 1.0)
        sy = round(texture_top + norm * (texture_bottom - texture_top))
        alpha = point_mask[py, px] / 255.0
        texture = original[sy, texture_x].astype(np.float32)
        arr[py, px] = np.clip(
            texture * alpha + arr[py, px].astype(np.float32) * (1.0 - alpha),
            0,
            255,
        ).astype(np.uint8)

    lost_white = white_tip & removed
    lost_count = int(np.count_nonzero(lost_white))
    compensation_domain = (
        cat_mask
        & (xx >= white_x1 + 1)
        & (xx <= white_x1 + 4)
        & (yy >= white_y0)
        & (yy <= white_y1)
    )
    cy, cx = np.nonzero(compensation_domain)
    compensated = 0
    if lost_count > 0 and cx.size > 0:
        order = np.lexsort((np.abs(cy - center_y), cx))
        selected = order[:lost_count]
        source_x = max(white_x0, white_x1 - 2)
        source_column_y = np.nonzero(white_tip[:, source_x])[0]
        if source_column_y.size == 0:
            source_column_y = wy
        source_top = int(source_column_y.min())
        source_bottom = int(source_column_y.max())
        for py, px in zip(cy[selected], cx[selected], strict=True):
            norm = np.clip((py - white_y0) / max(1, white_y1 - white_y0), 0.0, 1.0)
            sy = round(source_top + norm * (source_bottom - source_top))
            arr[py, px] = original[sy, source_x]
        compensated = int(selected.size)

    metadata = {
        "source_white_tip_bbox": [white_x0, white_y0, white_x1 + 1, white_y1 + 1],
        "point_apex": [apex_x, center_y],
        "point_neck_x": neck_x,
        "source_white_pixels": int(np.count_nonzero(white_tip)),
        "white_pixels_removed_at_round_edge": lost_count,
        "white_pixels_compensated_at_inner_edge": compensated,
        "white_texture_pixels_mapped_into_point": int(interior_x.size),
        "terminal_pixels_cleared": int(np.count_nonzero(removed)),
    }
    return Image.fromarray(arr, mode="RGB"), metadata


def sharpen_tail_tip(
    image: Image.Image,
    cat_mask_path: Path,
    source_bbox: tuple[int, int, int, int],
    scaled_size: tuple[int, int],
    paste_xy: tuple[int, int],
) -> tuple[Image.Image, dict[str, object]]:
    x0, y0, x1, y1 = source_bbox
    paste_x, paste_y = paste_xy
    cat_source = Image.open(cat_mask_path).convert("L").crop((x0, y0, x1, y1))
    cat_scaled = cat_source.resize(scaled_size, Image.Resampling.LANCZOS)
    cat_canvas = np.zeros((image.height, image.width), dtype=np.uint8)
    cat_canvas[
        paste_y : paste_y + cat_scaled.height,
        paste_x : paste_x + cat_scaled.width,
    ] = np.asarray(cat_scaled, dtype=np.uint8)

    arr = np.asarray(image, dtype=np.uint8).copy()
    yy, xx = np.indices(cat_canvas.shape)
    roi = (
        (xx >= int(image.width * 0.58))
        & (xx <= int(image.width * 0.66))
        & (yy >= int(image.height * 0.44))
        & (yy <= int(image.height * 0.51))
    )
    white_tip = (
        roi
        & (cat_canvas > 96)
        & (arr[..., 0] > 190)
        & (arr[..., 1] > 150)
        & (arr[..., 2] > 120)
    )
    tip_y, tip_x = np.nonzero(white_tip)
    if tip_x.size == 0:
        raise RuntimeError("White tail tip was not found in the expected region")

    tip_x0, tip_x1 = int(tip_x.min()), int(tip_x.max())
    tip_y0, tip_y1 = int(tip_y.min()), int(tip_y.max())
    apex = (tip_x0, round((tip_y0 + tip_y1) / 2.0))
    base_x = tip_x1 + 2
    center_y = apex[1]
    top_y = tip_y0 - 1
    bottom_y = tip_y1 + 1
    point_neck_x = min(base_x, apex[0] + max(8, round((base_x - apex[0]) * 0.30)))
    span = max(1, point_neck_x - apex[0])
    top_curve: list[tuple[int, int]] = []
    bottom_curve: list[tuple[int, int]] = []
    for x in range(apex[0], point_neck_x + 1):
        progress = (x - apex[0]) / span
        eased = progress ** 0.72
        top_curve.append((x, round(center_y + (top_y - center_y) * eased)))
        bottom_curve.append((x, round(center_y + (bottom_y - center_y) * eased)))

    point_shape = np.zeros(cat_canvas.shape, dtype=np.uint8)
    polygon = np.array(
        top_curve
        + [(base_x, top_y), (base_x, bottom_y)]
        + list(reversed(bottom_curve)),
        dtype=np.int32,
    )
    cv2.fillPoly(point_shape, [polygon], 255, lineType=cv2.LINE_AA)
    terminal = (
        (xx >= tip_x0)
        & (xx <= point_neck_x)
        & (yy >= tip_y0 - 4)
        & (yy <= tip_y1 + 4)
    )
    removed = terminal & (point_shape < 96)

    removed_y, removed_x = np.nonzero(removed)
    sample_x = max(0, tip_x0 - 200)
    arr[removed_y, removed_x] = arr[removed_y, sample_x]

    # Keep the original white-tip area and carry the same white into the short
    # point. This avoids a dark wedge in front of an otherwise round white cap.
    original_white_count = int(np.count_nonzero(white_tip))
    surviving_white = white_tip & ~removed
    point_interior = (
        (point_shape > 96)
        & (xx >= tip_x0)
        & (xx <= point_neck_x)
        & (yy >= top_y)
        & (yy <= bottom_y)
    )
    white_color = np.median(arr[white_tip], axis=0).astype(np.uint8)
    new_white_pixels = int(np.count_nonzero(point_interior & ~surviving_white))
    arr[point_interior] = white_color
    final_white_count = int(np.count_nonzero(surviving_white | point_interior))

    outline = (104, 55, 25)
    cv2.polylines(
        arr,
        [np.array(top_curve, dtype=np.int32)],
        False,
        outline,
        1,
        lineType=cv2.LINE_AA,
    )
    cv2.polylines(
        arr,
        [np.array(bottom_curve, dtype=np.int32)],
        False,
        outline,
        1,
        lineType=cv2.LINE_AA,
    )

    metadata = {
        "original_white_tip_bbox": [tip_x0, tip_y0, tip_x1 + 1, tip_y1 + 1],
        "point_apex": [apex[0], apex[1]],
        "point_neck": [point_neck_x, top_y, bottom_y],
        "white_tip_pixels_before": original_white_count,
        "white_tip_pixels_after": final_white_count,
        "white_tip_pixels_added_into_point": new_white_pixels,
        "removed_round_tip_pixels": int(np.count_nonzero(removed)),
    }
    return Image.fromarray(arr, mode="RGB"), metadata


def shift_cap_and_add_short_point(
    image: Image.Image,
    cat_mask_path: Path,
    source_bbox: tuple[int, int, int, int],
    scaled_size: tuple[int, int],
    paste_xy: tuple[int, int],
) -> tuple[Image.Image, dict[str, object]]:
    x0, y0, x1, y1 = source_bbox
    paste_x, paste_y = paste_xy
    cat_source = Image.open(cat_mask_path).convert("L").crop((x0, y0, x1, y1))
    cat_scaled = cat_source.resize(scaled_size, Image.Resampling.LANCZOS)
    cat_canvas = np.zeros((image.height, image.width), dtype=np.uint8)
    cat_canvas[
        paste_y : paste_y + cat_scaled.height,
        paste_x : paste_x + cat_scaled.width,
    ] = np.asarray(cat_scaled, dtype=np.uint8)

    arr = np.asarray(image, dtype=np.uint8).copy()
    original = arr.copy()
    yy, xx = np.indices(cat_canvas.shape)
    roi = (
        (xx >= int(image.width * 0.58))
        & (xx <= int(image.width * 0.66))
        & (yy >= int(image.height * 0.44))
        & (yy <= int(image.height * 0.51))
    )
    white_tip = (
        roi
        & (cat_canvas > 96)
        & (arr[..., 0] > 190)
        & (arr[..., 1] > 150)
        & (arr[..., 2] > 120)
        & ((arr[..., 0].astype(np.int16) - arr[..., 1].astype(np.int16)) < 85)
    )
    wy, wx = np.nonzero(white_tip)
    if wx.size == 0:
        raise RuntimeError("Scaled white tail tip was not found")
    white_x0, white_x1 = int(wx.min()), int(wx.max())
    white_y0, white_y1 = int(wy.min()), int(wy.max())
    center_y = round((white_y0 + white_y1) / 2.0)

    cap_mask = cv2.dilate(
        white_tip.astype(np.uint8),
        np.ones((5, 5), dtype=np.uint8),
        iterations=1,
    ).astype(bool)
    cap_mask &= cat_canvas > 24
    cap_mask &= xx <= white_x1 + 2
    cap_y, cap_x = np.nonzero(cap_mask)
    cap_x0, cap_x1 = int(cap_x.min()), int(cap_x.max())
    cap_y0, cap_y1 = int(cap_y.min()), int(cap_y.max())

    shift_x = 7
    sample_x = max(0, cap_x0 - 220)
    arr[cap_y, cap_x] = arr[cap_y, sample_x]

    dest_x = cap_x + shift_x
    valid = dest_x < image.width
    arr[cap_y[valid], dest_x[valid]] = original[cap_y[valid], cap_x[valid]]

    apex = (cap_x0, center_y)
    base_x = cap_x0 + shift_x + 2
    point_half_height = max(5, round((white_y1 - white_y0 + 1) * 0.28))
    top = (base_x, center_y - point_half_height)
    bottom = (base_x, center_y + point_half_height)
    point_mask = np.zeros(cat_canvas.shape, dtype=np.uint8)
    cv2.fillConvexPoly(
        point_mask,
        np.array([apex, top, bottom], dtype=np.int32),
        255,
        lineType=cv2.LINE_AA,
    )
    point_y, point_x = np.nonzero(point_mask > 96)
    texture_x = min(white_x1, white_x0 + 5)
    source_column = original[white_y0 : white_y1 + 1, texture_x]
    for py, px in zip(point_y, point_x, strict=True):
        norm = np.clip(
            (py - (center_y - point_half_height)) / max(1, point_half_height * 2),
            0.0,
            1.0,
        )
        sy = min(source_column.shape[0] - 1, round(norm * (source_column.shape[0] - 1)))
        arr[py, px] = source_column[sy]

    outline = (91, 49, 24)
    cv2.line(arr, apex, top, outline, 1, lineType=cv2.LINE_AA)
    cv2.line(arr, apex, bottom, outline, 1, lineType=cv2.LINE_AA)

    metadata = {
        "white_cap_bbox_before": [white_x0, white_y0, white_x1 + 1, white_y1 + 1],
        "cap_pixels_moved_without_resizing": int(cap_x.size),
        "cap_shift_x": shift_x,
        "point_apex": [apex[0], apex[1]],
        "point_base": [base_x, top[1], bottom[1]],
        "white_pixels_before": int(np.count_nonzero(white_tip)),
        "point_pixels_added": int(point_x.size),
    }
    return Image.fromarray(arr, mode="RGB"), metadata


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--cat-mask", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--scale", type=float, default=0.82)
    parser.add_argument("--point-tail-tip", action="store_true")
    args = parser.parse_args()

    source = Image.open(args.input).convert("RGB")
    source_np = np.asarray(source, dtype=np.int16)
    bg = np.median(
        np.concatenate(
            [
                source_np[0, :, :],
                source_np[-1, :, :],
                source_np[:, 0, :],
                source_np[:, -1, :],
            ],
            axis=0,
        ),
        axis=0,
    ).astype(np.uint8)

    color_distance = np.linalg.norm(source_np - bg.astype(np.int16), axis=2)
    foreground_mask = color_distance > 12.0
    count, labels, stats, _ = cv2.connectedComponentsWithStats(
        foreground_mask.astype(np.uint8), connectivity=8
    )
    if count < 2:
        raise RuntimeError("No foreground component found")
    largest = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
    foreground_mask = labels == largest

    recolored, platform_mask = recolor_platform(
        source, foreground_mask, args.cat_mask
    )
    tail_metadata: dict[str, object] | None = None
    if args.point_tail_tip:
        recolored, tail_metadata = minimally_point_tail_tip_before_scale(
            recolored,
            args.cat_mask,
        )

    ys, xs = np.nonzero(foreground_mask)
    x0, x1 = int(xs.min()), int(xs.max()) + 1
    y0, y1 = int(ys.min()), int(ys.max()) + 1
    crop_rgb = recolored.crop((x0, y0, x1, y1))
    crop_alpha = Image.fromarray((foreground_mask[y0:y1, x0:x1] * 255).astype(np.uint8))
    crop_rgba = crop_rgb.convert("RGBA")
    crop_rgba.putalpha(crop_alpha)

    new_size = (
        max(1, round(crop_rgba.width * args.scale)),
        max(1, round(crop_rgba.height * args.scale)),
    )
    scaled = crop_rgba.resize(new_size, Image.Resampling.LANCZOS)

    # Keep the group's original horizontal center and baseline.
    original_center_x = (x0 + x1) / 2.0
    paste_x = round(original_center_x - scaled.width / 2.0)
    paste_y = y1 - scaled.height
    # Use an exact clean chroma plate so the removed larger silhouette cannot
    # leave a faint color-variation ghost in the green screen.
    canvas_np = np.empty_like(np.asarray(source, dtype=np.uint8))
    canvas_np[:] = bg
    canvas = Image.fromarray(canvas_np, mode="RGB")
    canvas.paste(scaled.convert("RGB"), (paste_x, paste_y), scaled.getchannel("A"))

    args.output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(args.output, format="PNG", optimize=True)

    output_np = np.asarray(canvas, dtype=np.int16)
    placed_subject_mask = np.zeros(foreground_mask.shape, dtype=bool)
    scaled_alpha = np.asarray(scaled.getchannel("A"), dtype=np.uint8) > 0
    placed_subject_mask[
        paste_y : paste_y + scaled.height,
        paste_x : paste_x + scaled.width,
    ] = scaled_alpha
    allowed_change = foreground_mask | placed_subject_mask
    clean_plate = np.empty_like(output_np)
    clean_plate[:] = bg
    changed = np.any(clean_plate != output_np, axis=2)
    changed_outside = int(np.count_nonzero(changed & ~placed_subject_mask))
    outside_pixels = output_np[~placed_subject_mask]
    background_unique = int(np.unique(outside_pixels, axis=0).shape[0])

    report = {
        "input": str(args.input),
        "output": str(args.output),
        "canvas": [source.width, source.height],
        "scale": args.scale,
        "source_background_rgb": [int(v) for v in bg],
        "source_foreground_bbox": [x0, y0, x1, y1],
        "output_foreground_bbox": [
            paste_x,
            paste_y,
            paste_x + scaled.width,
            paste_y + scaled.height,
        ],
        "platform_recolored_pixels": int(np.count_nonzero(platform_mask)),
        "background_unique_colors_outside_subject": background_unique,
        "changed_pixels_outside_allowed_mask": changed_outside,
        "exact_lock_pass": changed_outside == 0,
        "tail_tip_edit": tail_metadata,
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

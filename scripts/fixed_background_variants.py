from __future__ import annotations

import argparse
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont


SIZE = (1448, 1086)
PLATFORM_COLOR = np.array([254, 240, 225], dtype=np.float32)
LEFT_GLASS = (475, 0, 841, 442)
RIGHT_GLASS = (855, 0, 1221, 442)
WINDOW_OUTER = (437, 0, 1259, 477)
CABINET = (160, 548, 1448, 974)
CABINET_FRONT = (174, 558, 1448, 974)
BASEBOARD_Y = 875
CABINET_BOTTOM_Y = 973


VARIANTS = {
    1: {"floor": (218, 168, 92), "frame": (246, 240, 230), "hardware": (154, 142, 130)},
    2: {"floor": (183, 170, 151), "frame": (218, 224, 226), "hardware": (73, 78, 82)},
    3: {"floor": (151, 96, 58), "frame": (181, 125, 75), "hardware": (176, 128, 48)},
    4: {"floor": (202, 192, 174), "frame": (247, 246, 241), "hardware": (132, 138, 142)},
    5: {"floor": (205, 161, 98), "frame": (240, 232, 210), "hardware": (116, 102, 76)},
    6: {"floor": (183, 137, 84), "frame": (210, 172, 118), "hardware": (132, 101, 58)},
    7: {"floor": (116, 82, 58), "frame": (126, 91, 62), "hardware": (61, 64, 61)},
    8: {"floor": (102, 83, 74), "frame": (210, 218, 222), "hardware": (49, 54, 63)},
    9: {"floor": (169, 112, 62), "frame": (120, 78, 50), "hardware": (99, 69, 45)},
    10: {"floor": (212, 181, 129), "frame": (203, 166, 108), "hardware": (91, 81, 65)},
}


def cover_resize(image: Image.Image, size=SIZE) -> Image.Image:
    target_w, target_h = size
    source_ratio = image.width / image.height
    target_ratio = target_w / target_h
    if source_ratio > target_ratio:
        crop_w = round(image.height * target_ratio)
        left = (image.width - crop_w) // 2
        image = image.crop((left, 0, left + crop_w, image.height))
    else:
        crop_h = round(image.width / target_ratio)
        top = (image.height - crop_h) // 2
        image = image.crop((0, top, image.width, top + crop_h))
    return image.resize(size, Image.Resampling.LANCZOS)


def tint_neutral_material(array: np.ndarray, region: tuple[int, int, int, int], target: np.ndarray) -> None:
    x1, y1, x2, y2 = region
    crop = array[y1:y2, x1:x2].astype(np.float32)
    chroma = crop.max(axis=2) - crop.min(axis=2)
    luminance = crop.mean(axis=2)
    mask = (chroma < 34) & (luminance > 155)
    if not np.any(mask):
        return
    median = float(np.median(luminance[mask]))
    delta = np.clip(luminance - median, -58, 34)
    tinted = np.clip(target[None, None, :] + delta[:, :, None], 0, 255)
    crop[mask] = tinted[mask]
    array[y1:y2, x1:x2] = np.rint(crop).astype(np.uint8)


def tint_region_luminance(array: np.ndarray, mask: np.ndarray, target: tuple[int, int, int]) -> None:
    pixels = array.astype(np.float32)
    luminance = pixels.mean(axis=2)
    base = float(np.median(luminance[mask])) if np.any(mask) else 128.0
    delta = np.clip(luminance - base, -75, 65)
    target_arr = np.array(target, dtype=np.float32)
    tinted = np.clip(target_arr[None, None, :] + delta[:, :, None], 0, 255)
    pixels[mask] = tinted[mask]
    array[:] = np.rint(pixels).astype(np.uint8)


def draw_fixed_cabinet(array: np.ndarray, variant_id: int, hardware: tuple[int, int, int]) -> None:
    image = Image.fromarray(array, "RGB")
    draw = ImageDraw.Draw(image)
    body = tuple(int(v) for v in PLATFORM_COLOR)
    seam = (216, 199, 181)
    shadow = (232, 216, 199)
    toe = (240, 225, 209)

    # Exact projected cabinet body: top/front at y=558, bottom at y=973.
    draw.rectangle((174, 558, 1447, 929), fill=body)
    draw.rectangle((160, 558, 173, 973), fill=shadow, outline=(196, 178, 160), width=2)
    draw.rectangle((174, 930, 1447, 973), fill=toe, outline=(203, 185, 167), width=2)
    draw.line((174, 558, 1447, 558), fill=(198, 181, 164), width=3)
    draw.line((174, 973, 1447, 973), fill=(181, 163, 147), width=3)

    bounds = [174, 422, 678, 939, 1198, 1447]
    for x in bounds[1:-1]:
        draw.line((x, 558, x, 930), fill=seam, width=2)

    inset_modes = {
        1: "shaker",
        2: "flat",
        3: "double",
        4: "narrow",
        5: "beadboard",
        6: "frame",
        7: "flat",
        8: "fine",
        9: "double",
        10: "frame",
    }
    mode = inset_modes[variant_id]
    for left, right in zip(bounds[:-1], bounds[1:]):
        if mode == "flat":
            continue
        margin = 24 if mode in {"narrow", "fine"} else 18
        rect = (left + margin, 585, right - margin, 902)
        line_color = (225, 209, 192) if mode in {"narrow", "fine"} else seam
        draw.rectangle(rect, outline=line_color, width=2)
        if mode == "double":
            draw.rectangle((rect[0] + 6, rect[1] + 6, rect[2] - 6, rect[3] - 6), outline=(232, 217, 201), width=2)
        if mode == "beadboard":
            for x in range(rect[0] + 18, rect[2], 24):
                draw.line((x, rect[1] + 2, x, rect[3] - 2), fill=(226, 210, 194), width=2)

    handle_x = (404, 441, 660, 698, 920, 958, 1180, 1218)
    dark_hardware = tuple(max(0, int(v) - 38) for v in hardware)
    if variant_id == 5:
        for x in handle_x:
            draw.ellipse((x - 6, 724, x + 6, 736), fill=hardware, outline=dark_hardware, width=2)
    else:
        handle_width = 7 if variant_id in {2, 7, 8, 10} else 9
        for x in handle_x:
            draw.rounded_rectangle((x - handle_width // 2, 706, x + handle_width // 2, 756), radius=4, fill=hardware, outline=dark_hardware, width=2)

    array[:] = np.asarray(image)


def build_template(accepted_path: Path, output_path: Path, report_path: Path) -> None:
    accepted = cover_resize(Image.open(accepted_path).convert("RGB"))
    source = accepted.copy()

    # Equalize pane width by shifting the center mullion one pixel left.
    left_source = source.crop((475, 0, 842, 442)).resize((366, 442), Image.Resampling.LANCZOS)
    right_source = source.crop((856, 0, 1221, 442)).resize((366, 442), Image.Resampling.LANCZOS)
    mullion = source.crop((842, 0, 856, 442)).resize((14, 442), Image.Resampling.LANCZOS)
    accepted.paste(left_source, (475, 0))
    accepted.paste(mullion, (841, 0))
    accepted.paste(right_source, (855, 0))

    array = np.asarray(accepted).copy()
    tint_neutral_material(array, CABINET, PLATFORM_COLOR)
    output = Image.fromarray(array, "RGB")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output.save(output_path, compress_level=6)

    report = {
        "size": list(SIZE),
        "left_glass": list(LEFT_GLASS),
        "right_glass": list(RIGHT_GLASS),
        "left_glass_area": (LEFT_GLASS[2] - LEFT_GLASS[0]) * (LEFT_GLASS[3] - LEFT_GLASS[1]),
        "right_glass_area": (RIGHT_GLASS[2] - RIGHT_GLASS[0]) * (RIGHT_GLASS[3] - RIGHT_GLASS[1]),
        "equal_glass_area": True,
        "cabinet_target_rgb": PLATFORM_COLOR.astype(int).tolist(),
        "baseboard_y": BASEBOARD_Y,
        "cabinet_bottom_y": CABINET_BOTTOM_Y,
        "platform_display_height": CABINET_BOTTOM_Y - BASEBOARD_Y,
    }
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


def finalize(template_path: Path, candidate_path: Path, variant_id: int, output_path: Path) -> None:
    cfg = VARIANTS[variant_id]
    template = np.asarray(Image.open(template_path).convert("RGB")).copy()
    candidate = np.asarray(cover_resize(Image.open(candidate_path).convert("RGB"))).copy()
    final = template.copy()
    height, width = final.shape[:2]
    yy, xx = np.mgrid[0:height, 0:width]

    # Variable side walls and their decor, clipped away from all locked geometry.
    wall_mask = (((xx < WINDOW_OUTER[0]) | (xx >= WINDOW_OUTER[2])) & (yy < 548))
    wall_mask |= ((yy >= 477) & (yy < 548))
    wall_mask |= ((xx < CABINET[0]) & (yy >= 548) & (yy < BASEBOARD_Y))
    final[wall_mask] = candidate[wall_mask]

    # Variable outdoor view, fitted into two exactly equal glass apertures.
    for rect in (LEFT_GLASS, RIGHT_GLASS):
        x1, y1, x2, y2 = rect
        scene = Image.fromarray(candidate[y1:y2, x1:x2], "RGB").resize((x2 - x1, y2 - y1), Image.Resampling.LANCZOS)
        final[y1:y2, x1:x2] = np.asarray(scene)

    # Restore invariant window frame geometry and apply a material tint.
    frame_mask = (
        (xx >= WINDOW_OUTER[0])
        & (xx < WINDOW_OUTER[2])
        & (yy >= WINDOW_OUTER[1])
        & (yy < WINDOW_OUTER[3])
    )
    for rect in (LEFT_GLASS, RIGHT_GLASS):
        gx1, gy1, gx2, gy2 = rect
        frame_mask &= ~((xx >= gx1) & (xx < gx2) & (yy >= gy1) & (yy < gy2))
    fixed_frame = template.copy()
    tint_region_luminance(fixed_frame, frame_mask, cfg["frame"])
    final[frame_mask] = fixed_frame[frame_mask]

    # Cabinet geometry and main color are hard-rendered locally. Variants change
    # only panel design and hardware; the body color is exactly the platform RGB.
    draw_fixed_cabinet(final, variant_id, cfg["hardware"])

    # Floor material changes while the approved board perspective and seams remain fixed.
    floor_mask = yy >= BASEBOARD_Y
    floor_mask &= ~((xx >= CABINET[0]) & (yy < CABINET_BOTTOM_Y + 1))
    fixed_floor = template.copy()
    tint_region_luminance(fixed_floor, floor_mask, cfg["floor"])
    final[floor_mask] = fixed_floor[floor_mask]

    output_path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(final, "RGB").save(output_path, compress_level=6)


def make_contact_sheet(paths: list[Path], output_path: Path, columns=2, thumb=(724, 543)) -> None:
    rows = (len(paths) + columns - 1) // columns
    sheet = Image.new("RGB", (columns * thumb[0], rows * (thumb[1] + 42)), "#202124")
    draw = ImageDraw.Draw(sheet)
    font_path = Path(r"C:\Windows\Fonts\msyhbd.ttc")
    font = ImageFont.truetype(str(font_path), 24)
    for index, path in enumerate(paths):
        image = Image.open(path).convert("RGB").resize(thumb, Image.Resampling.LANCZOS)
        x = (index % columns) * thumb[0]
        y = (index // columns) * (thumb[1] + 42)
        sheet.paste(image, (x, y + 42))
        draw.text((x + 14, y + 7), f"{index + 1:02d}  {path.stem}", font=font, fill="white")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output_path, compress_level=6)


def qa_variants(paths: list[Path], verify_reports: list[Path], output_path: Path) -> None:
    results = []
    target = PLATFORM_COLOR.astype(np.uint8)
    for path in paths:
        image = np.asarray(Image.open(path).convert("RGB"))
        crop = image[600:900, 210:1390]
        chroma = crop.max(axis=2).astype(np.int16) - crop.min(axis=2).astype(np.int16)
        luma = crop.mean(axis=2)
        neutral = (chroma < 40) & (luma > 180)
        median = np.rint(np.median(crop[neutral], axis=0)).astype(int) if np.any(neutral) else np.array([-1, -1, -1])
        exact_count = int(np.count_nonzero(np.all(crop == target[None, None, :], axis=2)))
        results.append(
            {
                "file": path.name,
                "size": [int(image.shape[1]), int(image.shape[0])],
                "cabinet_neutral_median_rgb": median.tolist(),
                "cabinet_exact_target_pixels": exact_count,
            }
        )

    lock_reports = [json.loads(path.read_text(encoding="utf-8")) for path in verify_reports]
    summary = {
        "variant_count": len(paths),
        "all_sizes_1448x1086": all(item["size"] == [1448, 1086] for item in results),
        "left_glass": list(LEFT_GLASS),
        "right_glass": list(RIGHT_GLASS),
        "left_glass_area": (LEFT_GLASS[2] - LEFT_GLASS[0]) * (LEFT_GLASS[3] - LEFT_GLASS[1]),
        "right_glass_area": (RIGHT_GLASS[2] - RIGHT_GLASS[0]) * (RIGHT_GLASS[3] - RIGHT_GLASS[1]),
        "glass_areas_equal": True,
        "platform_and_cabinet_base_rgb": target.astype(int).tolist(),
        "all_composites_exact_foreground_lock": all(
            item.get("changed_pixels_outside_mask") == 0 and item.get("exact_foreground_lock_pass") is True
            for item in lock_reports
        ),
        "baseboard_y": BASEBOARD_Y,
        "cabinet_bottom_y": CABINET_BOTTOM_Y,
        "platform_display_height": CABINET_BOTTOM_Y - BASEBOARD_Y,
        "fixed_floor_geometry_source": "fixed-geometry-template.png",
        "variants": results,
    }
    output_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, indent=2))


def main() -> None:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)

    template_parser = sub.add_parser("template")
    template_parser.add_argument("--accepted", required=True, type=Path)
    template_parser.add_argument("--output", required=True, type=Path)
    template_parser.add_argument("--report", required=True, type=Path)

    finalize_parser = sub.add_parser("finalize")
    finalize_parser.add_argument("--template", required=True, type=Path)
    finalize_parser.add_argument("--candidate", required=True, type=Path)
    finalize_parser.add_argument("--variant-id", required=True, type=int, choices=range(1, 11))
    finalize_parser.add_argument("--output", required=True, type=Path)

    sheet_parser = sub.add_parser("contact")
    sheet_parser.add_argument("--inputs", nargs="+", required=True, type=Path)
    sheet_parser.add_argument("--output", required=True, type=Path)

    qa_parser = sub.add_parser("qa")
    qa_parser.add_argument("--inputs", nargs="+", required=True, type=Path)
    qa_parser.add_argument("--verify-reports", nargs="+", required=True, type=Path)
    qa_parser.add_argument("--output", required=True, type=Path)

    args = parser.parse_args()
    if args.command == "template":
        build_template(args.accepted, args.output, args.report)
    elif args.command == "finalize":
        finalize(args.template, args.candidate, args.variant_id, args.output)
    elif args.command == "contact":
        make_contact_sheet(args.inputs, args.output)
    else:
        qa_variants(args.inputs, args.verify_reports, args.output)


if __name__ == "__main__":
    main()

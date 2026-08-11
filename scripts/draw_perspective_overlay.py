from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont


def line_intersection(a1, a2, b1, b2):
    x1, y1 = a1
    x2, y2 = a2
    x3, y3 = b1
    x4, y4 = b2
    denominator = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
    px = (
        (x1 * y2 - y1 * x2) * (x3 - x4)
        - (x1 - x2) * (x3 * y4 - y3 * x4)
    ) / denominator
    py = (
        (x1 * y2 - y1 * x2) * (y3 - y4)
        - (y1 - y2) * (x3 * y4 - y3 * x4)
    ) / denominator
    return round(px), round(py)


def dashed_line(draw, points, fill, width=3, dash=16, gap=10):
    (x1, y1), (x2, y2) = points
    dx, dy = x2 - x1, y2 - y1
    length = (dx * dx + dy * dy) ** 0.5
    if length == 0:
        return
    ux, uy = dx / length, dy / length
    distance = 0.0
    while distance < length:
        end = min(distance + dash, length)
        draw.line(
            (x1 + ux * distance, y1 + uy * distance, x1 + ux * end, y1 + uy * end),
            fill=fill,
            width=width,
        )
        distance += dash + gap


def label(draw, xy, text, font, fill=(255, 255, 255, 255), bg=(20, 24, 31, 220), pad=7):
    x, y = xy
    box = draw.textbbox((x, y), text, font=font)
    rect = (box[0] - pad, box[1] - pad, box[2] + pad, box[3] + pad)
    draw.rounded_rectangle(rect, radius=7, fill=bg)
    draw.text((x, y), text, font=font, fill=fill)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--background-mask", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    args = parser.parse_args()

    source = Image.open(args.source).convert("RGBA")
    overlay = Image.new("RGBA", source.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay, "RGBA")
    font = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 25)
    small = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 20)
    bold = ImageFont.truetype(r"C:\Windows\Fonts\msyhbd.ttc", 28)

    # Source-derived depth edges.
    desk_depth = ((589, 568), (456, 769))
    platform_depth = ((1374, 460), (1444, 523))
    vp = line_intersection(*desk_depth, *platform_depth)

    # Proposed window is a wall-plane rectangle; its lower edge is locked to the
    # rear edge of the platform, not inferred from the generated background.
    window = (465, 65, 1235, 460)
    platform_top = [(154, 460), (1374, 460), (1444, 523), (1444, 557), (174, 557)]
    desk_top = [(589, 568), (1447, 568), (1447, 803), (456, 803)]

    # The lower green-screen region is the floor plane, beginning immediately
    # behind the platform. Draw its construction only on background pixels so
    # the guides correctly disappear behind the chair, desks, and legs.
    background_mask = Image.open(args.background_mask).convert("L")
    floor_mask = Image.new("L", source.size, 0)
    ImageDraw.Draw(floor_mask).rectangle((0, 558, source.width, source.height), fill=255)
    floor_mask = ImageChops.multiply(background_mask, floor_mask)
    floor_layer = Image.new("RGBA", source.size, (0, 0, 0, 0))
    floor_draw = ImageDraw.Draw(floor_layer, "RGBA")
    floor_draw.rectangle((0, 558, source.width, source.height), fill=(255, 190, 30, 56))
    for bottom_x in (0, 220, 470, 720, 970, 1220, 1447):
        floor_draw.line((vp[0], vp[1], bottom_x, source.height), fill=(255, 211, 62, 220), width=4)
    for seam_y in (640, 745, 875, 1035):
        floor_draw.line((0, seam_y, source.width, seam_y), fill=(255, 225, 105, 190), width=3)
    floor_alpha = ImageChops.multiply(floor_layer.getchannel("A"), floor_mask)
    floor_layer.putalpha(floor_alpha)
    source = Image.alpha_composite(source, floor_layer)

    # Suggested window opening.
    draw.rectangle(window, fill=(79, 196, 255, 42), outline=(20, 210, 130, 255), width=6)
    draw.line((window[0], window[3], window[2], window[3]), fill=(20, 255, 150, 255), width=9)
    label(draw, (600, 93), "候选窗洞：位于猫正后方", bold, bg=(8, 96, 67, 225))
    label(draw, (609, 417), "窗下沿 = 平台后沿  y≈460", small, bg=(8, 96, 67, 225))

    # Planes visible in the source.
    draw.polygon(platform_top, fill=(255, 174, 46, 50), outline=(255, 155, 31, 255))
    draw.line((154, 460, 1374, 460), fill=(255, 205, 60, 255), width=7)
    label(draw, (226, 500), "后方平台顶面", font, bg=(133, 76, 8, 225))
    draw.polygon(desk_top, fill=(52, 146, 255, 42), outline=(43, 136, 255, 255))
    label(draw, (850, 730), "前桌面", font, bg=(18, 70, 145, 225))

    # Extend the two measured depth edges to their intersection.
    red = (255, 56, 56, 255)
    draw.line((vp[0], vp[1], desk_depth[1][0], desk_depth[1][1]), fill=red, width=4)
    draw.line((vp[0], vp[1], platform_depth[1][0], platform_depth[1][1]), fill=red, width=4)
    dashed_line(draw, ((0, vp[1]), (source.width, vp[1])), fill=(255, 86, 86, 230), width=3)
    radius = 12
    draw.ellipse((vp[0] - radius, vp[1] - radius, vp[0] + radius, vp[1] + radius), fill=(255, 245, 70, 255), outline=red, width=4)
    draw.line((vp[0] - 22, vp[1], vp[0] + 22, vp[1]), fill=red, width=3)
    draw.line((vp[0], vp[1] - 22, vp[0], vp[1] + 22), fill=red, width=3)
    label(draw, (962, 22), f"消失点 VP≈({vp[0]}, {vp[1]})", small, bg=(125, 20, 20, 230))
    label(draw, (30, 57), f"视平线 y≈{vp[1]}（由两条原图纵深边求交）", small, bg=(125, 20, 20, 230))

    draw.line((0, 558, source.width, 558), fill=(255, 215, 60, 235), width=4)
    label(draw, (210, 602), "地板平面：从平台前沿 y≈558 向镜头展开", small, bg=(128, 87, 5, 230))
    label(draw, (68, 1016), "黄色纵线全部汇聚到同一消失点；横向板缝保持水平", small, bg=(128, 87, 5, 230))

    # Explicitly mark the forbidden zone for window glass.
    draw.rectangle((465, 461, 1235, 557), fill=(255, 48, 70, 40), outline=(255, 68, 78, 220), width=3)
    label(draw, (856, 529), "这里是平台，不应再出现玻璃/窗台", small, bg=(128, 22, 34, 225))

    output = Image.alpha_composite(source, overlay).convert("RGB")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    output.save(args.output, compress_level=6)

    report = {
        "canvas": list(source.size),
        "source_derived": {
            "desk_depth_edge": desk_depth,
            "platform_depth_edge": platform_depth,
            "vanishing_point": vp,
            "horizon_y": vp[1],
            "platform_rear_edge_y": 460,
            "platform_front_edge_y": 557,
            "front_desk_rear_edge_y": 568,
            "front_desk_front_edge_y": 803,
        },
        "proposed": {
            "window_opening": window,
            "window_bottom_y": 460,
            "floor_visible_start_y": 558,
            "floor_depth_lines_converge_to": vp,
        },
    }
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

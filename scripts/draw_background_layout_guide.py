from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    width, height = 1448, 1086
    vp = (927, 58)
    window = (465, -24, 1235, 460)
    platform_top_y = 460
    platform_bottom_y = 558
    platform_display_height = platform_bottom_y - platform_top_y
    baseboard_y = 875
    cabinet_front_bottom_y = baseboard_y + platform_display_height
    cabinet_front = (174, platform_bottom_y, 1448, cabinet_front_bottom_y)

    image = Image.new("RGB", (width, height), "#efe0cf")
    draw = ImageDraw.Draw(image)

    # Tall window: top continues beyond the canvas; no top rail is visible.
    draw.rectangle(window, fill="#bfe3f3")
    draw.line((window[0], 0, window[0], window[3]), fill="#f7f0e6", width=22)
    draw.line((window[2], 0, window[2], window[3]), fill="#f7f0e6", width=22)
    draw.line((window[0], window[3], window[2], window[3]), fill="#f7f0e6", width=20)
    draw.line(((window[0] + window[2]) // 2, 0, (window[0] + window[2]) // 2, window[3]), fill="#f7f0e6", width=12)

    # Left-side floating shelves and right-side photo grouping.
    for y, x1, x2 in ((165, 185, 405), (290, 235, 430)):
        draw.rounded_rectangle((x1, y, x2, y + 20), radius=4, fill="#b78354")
    draw.rectangle((255, 205, 335, 270), fill="#d6b58d", outline="#856247", width=6)
    draw.rectangle((1290, 175, 1390, 305), fill="#caa77d", outline="#806147", width=7)
    draw.rectangle((1260, 340, 1350, 435), fill="#d8b891", outline="#806147", width=7)

    # Baseboard center is locked to the line circled by the user.
    draw.rectangle((0, baseboard_y - 10, width, baseboard_y + 10), fill="#f8f2e9", outline="#cbbbaa", width=3)

    # Floor exists only below the baseboard. Long seams converge to the source VP.
    draw.rectangle((0, baseboard_y + 11, width, height), fill="#dca85c")
    for bottom_x in (0, 220, 470, 720, 970, 1220, 1447):
        floor_top = baseboard_y + 11
        t = (floor_top - vp[1]) / (height - vp[1])
        top_x = round(vp[0] + (bottom_x - vp[0]) * t)
        draw.line((top_x, floor_top, bottom_x, height), fill="#a87539", width=3)
    for y in (945, 1030):
        draw.line((0, y, width, y), fill="#ae7d42", width=3)

    # The cabinet projects in front of the wall. Its front bottom is lower than
    # the wall baseboard by exactly the platform's displayed height (98 px).
    # Draw it last so it correctly occludes the baseboard and floor behind it.
    draw.rectangle(cabinet_front, fill="#f7f4ef", outline="#d7cec3", width=5)
    for x in (430, 685, 940, 1195):
        draw.line((x, cabinet_front[1] + 8, x, cabinet_front[3] - 34), fill="#d8d0c7", width=3)
    for x in (410, 450, 665, 705, 920, 960, 1175, 1215):
        draw.rounded_rectangle((x, 725, x + 9, 770), radius=4, fill="#b8afa7")
    draw.rectangle(
        (cabinet_front[0] + 12, cabinet_front[3] - 30, cabinet_front[2], cabinet_front[3]),
        fill="#e8e1d9",
        outline="#cfc5bb",
        width=3,
    )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    image.save(args.output, compress_level=6)


if __name__ == "__main__":
    main()

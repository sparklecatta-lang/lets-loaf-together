from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
CAT_FOOD_DIR = ROOT / "assets" / "props" / "floor" / "cat_food_bag"
SOURCE = CAT_FOOD_DIR / "黄猫猫粮袋_品红绿幕生成原图.png"
LABELLED = CAT_FOOD_DIR / "黄猫猫粮袋_精确文字品红绿幕.png"
TRANSPARENT = CAT_FOOD_DIR / "黄猫猫粮袋_透明原尺寸.png"
FINAL = CAT_FOOD_DIR / "黄猫猫粮袋_游戏尺寸.png"
SHADOW_DIR = ROOT / "assets" / "props" / "shadows"
ROSE_SHADOW = SHADOW_DIR / "月季花盆_桌面接触阴影.png"
CAT_FOOD_SHADOW = SHADOW_DIR / "猫粮袋_地面接触阴影.png"
FONT = Path(r"C:\Windows\Fonts\msyhbd.ttc")


def add_exact_label() -> None:
    image = Image.open(SOURCE).convert("RGB")
    draw = ImageDraw.Draw(image)
    text = "黄猫猫粮"
    font_size = 104
    font = ImageFont.truetype(str(FONT), font_size)
    panel = (370, 890, 855, 1135)
    center = ((panel[0] + panel[2]) // 2, (panel[1] + panel[3]) // 2 + 2)
    draw.text(
        center,
        text,
        font=font,
        fill=(31, 86, 98),
        stroke_width=2,
        stroke_fill=(245, 218, 143),
        anchor="mm",
    )
    image.save(LABELLED, optimize=True)
    print(f"Wrote exact label to {LABELLED}")


def make_shadow(size: tuple[int, int], box: tuple[int, int, int, int], blur: float) -> Image.Image:
    shadow = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(shadow)
    draw.ellipse(box, fill=(65, 48, 52, 78))
    return shadow.filter(ImageFilter.GaussianBlur(blur))


def finalize_assets() -> None:
    image = Image.open(TRANSPARENT).convert("RGBA")
    alpha_box = image.getchannel("A").getbbox()
    if alpha_box is None:
        raise RuntimeError("The cat-food source has no visible pixels")
    left, top, right, bottom = alpha_box
    padding = 12
    crop = image.crop(
        (
            max(0, left - padding),
            max(0, top - padding),
            min(image.width, right + padding),
            min(image.height, bottom + padding),
        )
    )
    crop.thumbnail((128, 198), Image.Resampling.LANCZOS)
    output = Image.new("RGBA", (136, 204), (0, 0, 0, 0))
    output.alpha_composite(crop, ((output.width - crop.width) // 2, (output.height - crop.height) // 2))
    output.save(FINAL, optimize=True)

    SHADOW_DIR.mkdir(parents=True, exist_ok=True)
    make_shadow((184, 46), (12, 14, 172, 32), 7.0).save(ROSE_SHADOW, optimize=True)
    make_shadow((154, 38), (9, 10, 145, 29), 5.5).save(CAT_FOOD_SHADOW, optimize=True)
    print(f"Wrote {FINAL} size={output.size} bbox={output.getbbox()}")
    print(f"Wrote {ROSE_SHADOW} and {CAT_FOOD_SHADOW}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("stage", choices=("label", "finalize"))
    args = parser.parse_args()
    if args.stage == "label":
        add_exact_label()
    else:
        finalize_assets()


if __name__ == "__main__":
    main()

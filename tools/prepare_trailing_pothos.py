from __future__ import annotations

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "props" / "shelf_plants" / "trailing_pothos" / "垂吊绿萝_透明原尺寸.png"
OUTPUT = ROOT / "assets" / "props" / "shelf_plants" / "trailing_pothos" / "垂吊绿萝_书架尺寸.png"
TARGET_SIZE = (104, 184)
CONTENT_SIZE = (96, 178)


def main() -> None:
    image = Image.open(SOURCE).convert("RGBA")
    alpha_box = image.getchannel("A").getbbox()
    if alpha_box is None:
        raise RuntimeError("The pothos source has no visible pixels")
    left, top, right, bottom = alpha_box
    padding = 14
    crop = image.crop(
        (
            max(0, left - padding),
            max(0, top - padding),
            min(image.width, right + padding),
            min(image.height, bottom + padding),
        )
    )
    crop.thumbnail(CONTENT_SIZE, Image.Resampling.LANCZOS)
    output = Image.new("RGBA", TARGET_SIZE, (0, 0, 0, 0))
    position = ((TARGET_SIZE[0] - crop.width) // 2, (TARGET_SIZE[1] - crop.height) // 2)
    output.alpha_composite(crop, position)
    output.save(OUTPUT, optimize=True)
    print(f"Wrote {OUTPUT} size={output.size} content={crop.size} bbox={output.getbbox()}")


if __name__ == "__main__":
    main()

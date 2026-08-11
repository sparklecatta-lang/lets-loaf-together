from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True)
    parser.add_argument("--scene", required=True)
    parser.add_argument("--output-asset", required=True)
    parser.add_argument("--output-preview", required=True)
    parser.add_argument("--output-mask", required=True)
    parser.add_argument("--report", required=True)
    parser.add_argument("--height", type=int, default=118)
    parser.add_argument("--center-x", type=int, default=970)
    parser.add_argument("--bottom-y", type=int, default=402)
    args = parser.parse_args()

    source_path = Path(args.source).resolve()
    scene_path = Path(args.scene).resolve()
    source = Image.open(source_path).convert("RGBA")
    source_array = np.asarray(source)
    ys, xs = np.nonzero(source_array[:, :, 3] > 8)
    if xs.size == 0:
        raise ValueError("Figurine alpha is empty")

    pad = 4
    x1 = max(0, int(xs.min()) - pad)
    y1 = max(0, int(ys.min()) - pad)
    x2 = min(source.width, int(xs.max()) + 1 + pad)
    y2 = min(source.height, int(ys.max()) + 1 + pad)
    cropped = source.crop((x1, y1, x2, y2))
    width = max(1, round(cropped.width * args.height / cropped.height))
    asset = cropped.resize((width, args.height), Image.Resampling.LANCZOS)

    output_asset = Path(args.output_asset).resolve()
    output_preview = Path(args.output_preview).resolve()
    output_mask = Path(args.output_mask).resolve()
    report_path = Path(args.report).resolve()
    for path in (output_asset, output_preview, output_mask, report_path):
        path.parent.mkdir(parents=True, exist_ok=True)
    asset.save(output_asset)

    scene = Image.open(scene_path).convert("RGBA")
    left = args.center_x - asset.width // 2
    top = args.bottom_y - asset.height
    if left < 0 or top < 0 or left + asset.width > scene.width or top + asset.height > scene.height:
        raise ValueError("Placed figurine falls outside scene")

    preview = scene.copy()
    preview.alpha_composite(asset, (left, top))
    preview.save(output_preview)

    mask = Image.new("L", scene.size, 0)
    mask.paste(asset.getchannel("A"), (left, top))
    mask.save(output_mask)

    report = {
        "ok": True,
        "source": str(source_path),
        "source_sha256": sha256(source_path),
        "scene": str(scene_path),
        "output_asset": str(output_asset),
        "output_asset_sha256": sha256(output_asset),
        "output_preview": str(output_preview),
        "source_crop": [x1, y1, x2, y2],
        "asset_size": list(asset.size),
        "placement": {"left": left, "top": top, "center_x": args.center_x, "bottom_y": args.bottom_y},
        "visible_pixels": int(np.count_nonzero(np.asarray(asset.getchannel("A")) > 8)),
    }
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()

from __future__ import annotations

import json
import math
import subprocess
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont


VIDEO = Path(
    r"D:\Downloads\jimeng-2026-08-06-1794-2D 游戏场景，保留绿幕，唯一机位，固定焦距无缩放。无音乐。按照参考图顺序：1.....mp4"
)
ROOT = Path(r"I:\codex-made\watercolor-desk-companion\qa\alpha_aware_despill_test_20260807")
FFMPEG = Path(r"I:\FF\bin\ffmpeg.exe")
REALESRGAN = Path(r"E:\sprite-video-lab-work\tools\realesrgan-ncnn-vulkan\realesrgan-ncnn-vulkan.exe")
REALESRGAN_MODELS = REALESRGAN.parent / "models"
MODEL = "realesrgan-x4plus-anime"
TIMESTAMPS = (0.30, 1.25, 2.25, 3.55)
SOURCE_SIZE = (1112, 834)


def run(command: list[str]) -> None:
    subprocess.run(command, check=True)


def srgb_to_linear(rgb: np.ndarray) -> np.ndarray:
    rgb = np.clip(rgb, 0.0, 1.0)
    return np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)


def linear_to_srgb(rgb: np.ndarray) -> np.ndarray:
    rgb = np.clip(rgb, 0.0, 1.0)
    return np.where(rgb <= 0.0031308, rgb * 12.92, 1.055 * (rgb ** (1.0 / 2.4)) - 0.055)


def estimate_background(rgb_u8: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Return a smooth local green-screen plate and the global key colour."""
    rgb = rgb_u8.astype(np.float32)
    height, width = rgb.shape[:2]
    border = max(12, min(height, width) // 30)
    border_mask = np.zeros((height, width), dtype=bool)
    border_mask[:border] = True
    border_mask[-border:] = True
    border_mask[:, :border] = True
    border_mask[:, -border:] = True

    excess = rgb[..., 1] - np.maximum(rgb[..., 0], rgb[..., 2])
    green_border = border_mask & (excess > 24.0) & (rgb[..., 1] > 65.0)
    samples = rgb[green_border]
    if samples.size == 0:
        raise RuntimeError("Could not estimate the green-screen colour from the frame border")
    global_key = np.median(samples, axis=0).astype(np.float32)

    distance = np.linalg.norm(rgb - global_key[None, None, :], axis=2)
    screen_samples = (excess > 22.0) & (rgb[..., 1] > 60.0) & (distance < 105.0)
    weights = screen_samples.astype(np.float32)

    # A normalized Gaussian convolution gives every edge pixel a nearby estimate
    # of the actual screen, including the video gradient and compression noise.
    sigma = 18.0
    weight_blur = cv2.GaussianBlur(weights, (0, 0), sigmaX=sigma, sigmaY=sigma)
    local = np.empty_like(rgb)
    for channel in range(3):
        weighted = cv2.GaussianBlur(rgb[..., channel] * weights, (0, 0), sigmaX=sigma, sigmaY=sigma)
        local[..., channel] = np.where(
            weight_blur > 1e-4,
            weighted / np.maximum(weight_blur, 1e-4),
            global_key[channel],
        )
    return np.clip(local, 0.0, 255.0), global_key


def build_alpha(rgb_u8: np.ndarray, background: np.ndarray) -> np.ndarray:
    """Estimate alpha from green excess, with the local plate as the reference."""
    rgb = rgb_u8.astype(np.float32)
    screen_excess = rgb[..., 1] - np.maximum(rgb[..., 0], rgb[..., 2])
    background_excess = background[..., 1] - np.maximum(background[..., 0], background[..., 2])

    foreground_floor = 2.0
    screen_fraction = (screen_excess - foreground_floor) / np.maximum(
        background_excess - foreground_floor, 12.0
    )
    alpha = 1.0 - np.clip(screen_fraction, 0.0, 1.0)

    # Exact background-colour proximity is additional evidence for transparency;
    # it stabilizes the matte in low-texture green areas without shrinking edges.
    distance = np.linalg.norm(rgb - background, axis=2)
    proximity_alpha = np.clip((distance - 3.5) / 53.0, 0.0, 1.0)
    alpha = np.minimum(alpha, proximity_alpha)
    alpha = cv2.GaussianBlur(alpha.astype(np.float32), (0, 0), sigmaX=0.42, sigmaY=0.42)
    alpha[alpha < 0.025] = 0.0
    alpha[alpha > 0.988] = 1.0

    # ESRGAN can turn compressed screen grain into isolated opaque flecks.  Keep
    # actual foreground components (girl, desk, monitor and props), but discard
    # tiny disconnected islands so matte noise cannot masquerade as despill.
    binary = (alpha > 0.025).astype(np.uint8)
    component_count, labels, stats, _ = cv2.connectedComponentsWithStats(binary, connectivity=8)
    keep = np.zeros_like(binary, dtype=bool)
    for label in range(1, component_count):
        if int(stats[label, cv2.CC_STAT_AREA]) >= 80:
            keep |= labels == label
    alpha[~keep] = 0.0
    return np.clip(alpha, 0.0, 1.0)


def alpha_aware_despill(
    rgb_u8: np.ndarray,
    alpha: np.ndarray,
    background_u8: np.ndarray,
) -> np.ndarray:
    """Undo green-screen compositing in linear light while preserving alpha."""
    observed = srgb_to_linear(rgb_u8.astype(np.float32) / 255.0)
    background = srgb_to_linear(background_u8.astype(np.float32) / 255.0)
    safe_alpha = np.maximum(alpha[..., None], 0.055)
    recovered = (observed - (1.0 - alpha[..., None]) * background) / safe_alpha
    recovered = np.clip(recovered, 0.0, 1.0)

    # Very low-alpha colours are numerically unstable and visually negligible.
    # Fade the physical solution in smoothly instead of inventing bright edge pixels.
    confidence = np.clip((alpha - 0.035) / 0.16, 0.0, 1.0)[..., None]
    cleaned = observed * (1.0 - confidence) + recovered * confidence

    # Remove any residual green-only excess at semi-transparent edges.  This is
    # alpha weighted, so fully opaque cyan/blue artwork and all interior pixels stay intact.
    cleaned_srgb = linear_to_srgb(cleaned)
    edge_weight = np.where((alpha > 0.0) & (alpha < 1.0), (1.0 - alpha) ** 0.60, 0.0)
    green_excess = np.maximum(
        0.0,
        cleaned_srgb[..., 1] - np.maximum(cleaned_srgb[..., 0], cleaned_srgb[..., 2]),
    )
    cleaned_srgb[..., 1] -= green_excess * edge_weight * 0.78
    return np.clip(np.rint(cleaned_srgb * 255.0), 0, 255).astype(np.uint8)


def checker(size: tuple[int, int], cell: int = 24) -> Image.Image:
    width, height = size
    yy, xx = np.indices((height, width))
    values = np.where(((xx // cell) + (yy // cell)) % 2 == 0, 226, 184).astype(np.uint8)
    rgb = np.stack((values, values, values), axis=2)
    return Image.fromarray(rgb, "RGB")


def composite_on_checker(rgba: Image.Image) -> Image.Image:
    return Image.alpha_composite(checker(rgba.size).convert("RGBA"), rgba.convert("RGBA")).convert("RGB")


def load_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for candidate in (
        Path(r"C:\Windows\Fonts\msyh.ttc"),
        Path(r"C:\Windows\Fonts\simhei.ttf"),
    ):
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size=size)
    return ImageFont.load_default()


def labelled_tile(image: Image.Image, label: str, size: tuple[int, int]) -> Image.Image:
    body = image.convert("RGB").resize(size, Image.Resampling.LANCZOS)
    tile = Image.new("RGB", (size[0], size[1] + 42), (32, 35, 40))
    tile.paste(body, (0, 42))
    draw = ImageDraw.Draw(tile)
    draw.text((12, 8), label, fill=(245, 245, 245), font=load_font(22))
    return tile


def make_pipeline_sheet(records: list[dict], output: Path) -> None:
    tile_size = (389, 292)
    columns = [
        ("original", "① 原视频抽帧"),
        ("restored", "② ESRGAN 4× 后缩回原尺寸"),
        ("baseline", "③ 仅抠透明（无 despill）"),
        ("despill", "④ 同 alpha + alpha-aware despill"),
    ]
    rows: list[Image.Image] = []
    for record in records:
        row = Image.new("RGB", (tile_size[0] * len(columns), tile_size[1] + 42), (24, 26, 30))
        for column, (key, title) in enumerate(columns):
            image = Image.open(record[key])
            if key in {"baseline", "despill"}:
                image = composite_on_checker(image)
            label = f"{title}  t={record['timestamp']:.2f}s"
            row.paste(labelled_tile(image, label, tile_size), (column * tile_size[0], 0))
        rows.append(row)
    sheet = Image.new("RGB", (rows[0].width, rows[0].height * len(rows)), (18, 20, 24))
    for index, row in enumerate(rows):
        sheet.paste(row, (0, index * row.height))
    sheet.save(output, quality=96)


def make_hair_sheet(records: list[dict], output: Path) -> None:
    crop_box = (105, 0, 535, 380)
    display_size = (645, 570)
    rows: list[Image.Image] = []
    for record in records:
        row = Image.new("RGB", (display_size[0] * 2, display_size[1] + 42), (24, 26, 30))
        for column, (key, title) in enumerate(
            (("baseline", "仅抠透明：绿边基线"), ("despill", "alpha-aware：同一 alpha"))
        ):
            rgba = Image.open(record[key]).convert("RGBA").crop(crop_box)
            preview = composite_on_checker(rgba)
            label = f"{title}  t={record['timestamp']:.2f}s"
            row.paste(labelled_tile(preview, label, display_size), (column * display_size[0], 0))
        rows.append(row)
    sheet = Image.new("RGB", (rows[0].width, rows[0].height * len(rows)), (18, 20, 24))
    for index, row in enumerate(rows):
        sheet.paste(row, (0, index * row.height))
    sheet.save(output, quality=97)


def frame_metrics(before_rgba: np.ndarray, after_rgba: np.ndarray) -> dict:
    alpha_before = before_rgba[..., 3]
    alpha_after = after_rgba[..., 3]
    rgb_before = before_rgba[..., :3].astype(np.int16)
    rgb_after = after_rgba[..., :3].astype(np.int16)
    edge = (alpha_before > 0) & (alpha_before < 255)
    opaque = alpha_before == 255
    delta = np.abs(rgb_after - rgb_before)
    before_excess = np.maximum(0, rgb_before[..., 1] - np.maximum(rgb_before[..., 0], rgb_before[..., 2]))
    after_excess = np.maximum(0, rgb_after[..., 1] - np.maximum(rgb_after[..., 0], rgb_after[..., 2]))
    changed = np.any(delta > 0, axis=2)
    return {
        "alpha_max_abs_diff": int(np.max(np.abs(alpha_after.astype(np.int16) - alpha_before.astype(np.int16)))),
        "semi_transparent_pixels": int(edge.sum()),
        "changed_visible_pixels": int((changed & (alpha_before > 0)).sum()),
        "changed_opaque_pixels": int((changed & opaque).sum()),
        "edge_mean_rgb_abs_delta": round(float(delta[edge].mean()) if edge.any() else 0.0, 3),
        "edge_green_excess_before_mean": round(float(before_excess[edge].mean()) if edge.any() else 0.0, 3),
        "edge_green_excess_after_mean": round(float(after_excess[edge].mean()) if edge.any() else 0.0, 3),
    }


def main() -> None:
    for required in (VIDEO, FFMPEG, REALESRGAN, REALESRGAN_MODELS / f"{MODEL}.param"):
        if not required.exists():
            raise FileNotFoundError(required)

    dirs = {
        "original": ROOT / "01_original_video_frames",
        "upscaled": ROOT / "02_esrgan_x4",
        "restored": ROOT / "03_downscaled_to_original",
        "baseline": ROOT / "04_keyed_alpha_no_despill",
        "despill": ROOT / "05_alpha_aware_despill",
        "comparison": ROOT / "comparison",
    }
    for directory in dirs.values():
        directory.mkdir(parents=True, exist_ok=True)

    records: list[dict] = []
    for index, timestamp in enumerate(TIMESTAMPS, start=1):
        stem = f"sample_{index:02d}_{timestamp:.2f}s"
        original_path = dirs["original"] / f"{stem}.png"
        upscaled_path = dirs["upscaled"] / f"{stem}_x4.png"
        restored_path = dirs["restored"] / f"{stem}_x4_downscaled.png"
        baseline_path = dirs["baseline"] / f"{stem}_alpha_only.png"
        despill_path = dirs["despill"] / f"{stem}_alpha_aware_despill.png"

        run(
            [
                str(FFMPEG),
                "-hide_banner",
                "-loglevel",
                "error",
                "-y",
                "-ss",
                f"{timestamp:.3f}",
                "-i",
                str(VIDEO),
                "-frames:v",
                "1",
                str(original_path),
            ]
        )
        run(
            [
                str(REALESRGAN),
                "-i",
                str(original_path),
                "-o",
                str(upscaled_path),
                "-n",
                MODEL,
                "-m",
                str(REALESRGAN_MODELS),
                "-f",
                "png",
                "-s",
                "4",
            ]
        )

        with Image.open(upscaled_path) as upscaled:
            if upscaled.size != (SOURCE_SIZE[0] * 4, SOURCE_SIZE[1] * 4):
                raise RuntimeError(f"Unexpected ESRGAN output size: {upscaled.size}")
            restored = upscaled.convert("RGB").resize(SOURCE_SIZE, Image.Resampling.LANCZOS)
            restored.save(restored_path, optimize=True, compress_level=9)

        rgb = np.asarray(restored, dtype=np.uint8)
        local_background, key_rgb = estimate_background(rgb)
        alpha = build_alpha(rgb, local_background)
        alpha_u8 = np.clip(np.rint(alpha * 255.0), 0, 255).astype(np.uint8)

        baseline_rgb = rgb.copy()
        baseline_rgb[alpha_u8 == 0] = 0
        baseline_rgba = np.dstack((baseline_rgb, alpha_u8))
        Image.fromarray(baseline_rgba, "RGBA").save(baseline_path, optimize=True, compress_level=9)

        cleaned_rgb = alpha_aware_despill(rgb, alpha, local_background)
        cleaned_rgb[alpha_u8 == 0] = 0
        despill_rgba = np.dstack((cleaned_rgb, alpha_u8))
        Image.fromarray(despill_rgba, "RGBA").save(despill_path, optimize=True, compress_level=9)

        metrics = frame_metrics(baseline_rgba, despill_rgba)
        if metrics["alpha_max_abs_diff"] != 0:
            raise RuntimeError("Despill unexpectedly changed alpha")
        if metrics["changed_opaque_pixels"] != 0:
            raise RuntimeError("Despill unexpectedly changed fully opaque pixels")

        records.append(
            {
                "timestamp": timestamp,
                "original": str(original_path),
                "upscaled": str(upscaled_path),
                "restored": str(restored_path),
                "baseline": str(baseline_path),
                "despill": str(despill_path),
                "source_size": list(Image.open(original_path).size),
                "esrgan_size": list(Image.open(upscaled_path).size),
                "restored_size": list(Image.open(restored_path).size),
                "estimated_key_rgb": [round(float(value), 2) for value in key_rgb],
                "metrics": metrics,
            }
        )

    pipeline_sheet = dirs["comparison"] / "四阶段完整对比.png"
    hair_sheet = dirs["comparison"] / "发梢透明边缘放大对比.png"
    make_pipeline_sheet(records, pipeline_sheet)
    make_hair_sheet(records, hair_sheet)

    summary = {
        "source_video": str(VIDEO),
        "pipeline": [
            "extract exact video frames",
            f"Real-ESRGAN {MODEL} 4x",
            "Lanczos downscale to 1112x834",
            "green-screen alpha matte",
            "linear-light alpha-aware foreground recovery with identical alpha",
        ],
        "timestamps": list(TIMESTAMPS),
        "records": records,
        "comparisons": [str(pipeline_sheet), str(hair_sheet)],
    }
    (ROOT / "test_report.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

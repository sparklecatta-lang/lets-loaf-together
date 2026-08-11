from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path

import cv2
import numpy as np


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def frame_key(profile_id: str, animation_id: str, index: int) -> str:
    return f"{profile_id}/{animation_id}:{index}"


def attachment_signature(items: list[dict]) -> str:
    visible = []
    for item in items:
        visible.append(
            {
                "path": item.get("path", ""),
                "assetHash": item.get("assetHash", ""),
                "layer": item.get("layer", "above"),
                "layerOrder": item.get("layerOrder", 1),
                "transform": item.get("transform", {}),
            }
        )
    visible.sort(key=lambda value: json.dumps(value, sort_keys=True, ensure_ascii=False))
    return json.dumps(visible, sort_keys=True, ensure_ascii=False, separators=(",", ":"))


def load_preview(path: Path, width: int = 278) -> tuple[np.ndarray, np.ndarray]:
    rgba = cv2.imread(str(path), cv2.IMREAD_UNCHANGED)
    if rgba is None or rgba.ndim != 3 or rgba.shape[2] != 4:
        raise ValueError(f"Expected RGBA PNG: {path}")
    rgba = cv2.cvtColor(rgba, cv2.COLOR_BGRA2RGBA)
    height = max(1, round(rgba.shape[0] * width / rgba.shape[1]))
    resized = cv2.resize(rgba, (width, height), interpolation=cv2.INTER_AREA).astype(np.float32)
    alpha = resized[..., 3:4] / 255.0
    premultiplied = np.concatenate((resized[..., :3] * alpha, resized[..., 3:4]), axis=2)
    return premultiplied, resized[..., 3]


def difference(a: tuple[np.ndarray, np.ndarray], b: tuple[np.ndarray, np.ndarray]) -> dict:
    pixels_a, alpha_a = a
    pixels_b, alpha_b = b
    visible = (alpha_a > 8.0) | (alpha_b > 8.0)
    if not np.any(visible):
        return {"mae": 0.0, "changed_ratio_8": 0.0, "changed_ratio_16": 0.0, "p95": 0.0}
    per_pixel = np.max(np.abs(pixels_a - pixels_b), axis=2)[visible]
    return {
        "mae": round(float(np.mean(per_pixel)), 6),
        "changed_ratio_8": round(float(np.mean(per_pixel > 8.0)), 8),
        "changed_ratio_16": round(float(np.mean(per_pixel > 16.0)), 8),
        "p95": round(float(np.percentile(per_pixel, 95)), 6),
    }


def similar(metric: dict, args: argparse.Namespace) -> bool:
    return (
        metric["mae"] <= args.max_mae
        and metric["changed_ratio_8"] <= args.max_changed_ratio
        and metric["p95"] <= args.max_p95
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--project", default="Watercolor_Desk_Companion")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--max-mae", type=float, default=1.25)
    parser.add_argument("--max-changed-ratio", type=float, default=0.035)
    parser.add_argument("--max-p95", type=float, default=5.0)
    args = parser.parse_args()

    data_root = args.project_root / "xsxb_frame_tuner/data/projects" / args.project
    manifest = load_json(data_root / "animation_manifest.json")
    tuning = load_json(data_root / "animation_tuning.json")
    audio = load_json(data_root / "frame_audio_bindings.json")
    attachments = load_json(data_root / "frame_image_attachments.json")
    playback = tuning.get("frame_playback_overrides", {})
    visual = tuning.get("frame_visual_overrides", {})
    boxes = tuning.get("frame_box_overrides", {})

    audio_keys = {str(item.get("key", "")) for item in audio}
    attachments_by_key: dict[str, list[dict]] = defaultdict(list)
    for item in attachments:
        attachments_by_key[str(item.get("frameKey", item.get("key", "")))].append(item)

    report = {
        "thresholds": {
            "max_mae": args.max_mae,
            "max_changed_ratio_8": args.max_changed_ratio,
            "max_p95": args.max_p95,
        },
        "animations": [],
    }

    for profile in manifest.get("profiles", []):
        profile_id = str(profile.get("id", ""))
        for animation in profile.get("animations", []):
            animation_id = str(animation.get("id", ""))
            animation_key = f"{profile_id}/{animation_id}"
            frames = animation.get("frames", [])
            fps = float(playback.get(f"{animation_key}:__group", {}).get("fps", animation.get("fps", 12.0)))
            previews = []
            entries = []
            for index, frame in enumerate(frames):
                key = frame_key(profile_id, animation_id, index)
                frame_path = args.project_root / str(frame.get("path", ""))
                previews.append(load_preview(frame_path))
                override = playback.get(key, {})
                entries.append(
                    {
                        "index": index,
                        "file": frame_path.name,
                        "duration_units": float(override.get("duration", frame.get("duration", 1.0))),
                        "duration_ms": 0.0 if override.get("disabled", False) else 1000.0
                        * float(override.get("duration", frame.get("duration", 1.0)))
                        / fps,
                        "disabled": bool(override.get("disabled", False)),
                        "audio": key in audio_keys,
                        "attachment_signature": attachment_signature(attachments_by_key.get(key, [])),
                        "visual_signature": json.dumps(visual.get(key, {}), sort_keys=True, ensure_ascii=False),
                        "box_signature": json.dumps(boxes.get(key, {}), sort_keys=True, ensure_ascii=False),
                    }
                )

            pairs = []
            for index in range(1, len(frames)):
                metric = difference(previews[index - 1], previews[index])
                pairs.append({"from": index - 1, "to": index, **metric})

            groups = []
            index = 0
            while index < len(entries):
                if entries[index]["disabled"]:
                    groups.append({"keep": index, "members": [index], "reason": "disabled"})
                    index += 1
                    continue
                keep = index
                members = [index]
                index += 1
                while index < len(entries):
                    current = entries[index]
                    if current["disabled"] or current["audio"]:
                        break
                    if current["attachment_signature"] != entries[keep]["attachment_signature"]:
                        break
                    if current["visual_signature"] != entries[keep]["visual_signature"]:
                        break
                    if current["box_signature"] != entries[keep]["box_signature"]:
                        break
                    adjacent_metric = difference(previews[index - 1], previews[index])
                    cumulative_metric = difference(previews[keep], previews[index])
                    if not similar(adjacent_metric, args) or not similar(cumulative_metric, args):
                        break
                    members.append(index)
                    index += 1
                groups.append({
                    "keep": keep,
                    "members": members,
                    "duration_ms": round(sum(entries[i]["duration_ms"] for i in members), 6),
                    "protected_audio": entries[keep]["audio"],
                })

            merged_groups = [group for group in groups if len(group["members"]) > 1]
            report["animations"].append(
                {
                    "key": animation_key,
                    "fps": fps,
                    "frames_before": len(entries),
                    "frames_after_candidate": len(groups),
                    "removable_candidate": len(entries) - len(groups),
                    "audio_frames": sum(entry["audio"] for entry in entries),
                    "attachment_frames": sum(bool(entry["attachment_signature"] != "[]") for entry in entries),
                    "disabled_frames": sum(entry["disabled"] for entry in entries),
                    "entries": entries,
                    "adjacent_pairs": pairs,
                    "groups": groups,
                    "merged_groups": merged_groups,
                }
            )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    total_before = sum(item["frames_before"] for item in report["animations"])
    total_after = sum(item["frames_after_candidate"] for item in report["animations"])
    print(f"animations={len(report['animations'])} frames={total_before}->{total_after} removable={total_before-total_after}")
    for item in report["animations"]:
        print(
            f"{item['key']}: {item['frames_before']}->{item['frames_after_candidate']} "
            f"remove={item['removable_candidate']} audio={item['audio_frames']} "
            f"attachments={item['attachment_frames']} disabled={item['disabled_frames']}"
        )
    print(args.output)


if __name__ == "__main__":
    main()

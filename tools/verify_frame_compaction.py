from __future__ import annotations

import argparse
import json
from pathlib import Path

from apply_frame_compaction import (
    DATA_FILES,
    animation_duration,
    animation_from_binding,
    frame_start_times,
    index_manifest,
    load_json,
    sha256,
)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--tuner-root", type=Path, required=True)
    parser.add_argument("--project", default="Watercolor_Desk_Companion")
    parser.add_argument("--backup", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()

    sides = {
        "game": {
            "root": args.project_root,
            "data": args.project_root / "xsxb_frame_tuner/data/projects" / args.project,
            "assets": args.project_root / "xsxb_frame_tuner/workspace/projects" / args.project / "assets",
        },
        "tuner": {
            "root": args.tuner_root,
            "data": args.tuner_root / "data/projects" / args.project,
            "assets": args.tuner_root / "workspace/projects" / args.project / "assets",
        },
    }

    current = {}
    previous = {}
    for side_name, side in sides.items():
        current[side_name] = {name: load_json(side["data"] / name) for name in DATA_FILES}
        previous[side_name] = {
            name: load_json(args.backup / side_name / "data" / name) for name in DATA_FILES
        }

    game_manifest = index_manifest(current["game"]["animation_manifest.json"])
    tuner_manifest = index_manifest(current["tuner"]["animation_manifest.json"])
    if set(game_manifest) != set(tuner_manifest):
        raise ValueError("Game/Tuner animation sets differ")

    animations = []
    total_frames = 0
    for key in sorted(game_manifest):
        profile_id, animation_id = key.split("/", 1)
        game_frames = game_manifest[key].get("frames", [])
        tuner_frames = tuner_manifest[key].get("frames", [])
        game_names = [Path(str(frame.get("path", ""))).name for frame in game_frames]
        tuner_names = [Path(str(frame.get("path", ""))).name for frame in tuner_frames]
        if game_names != tuner_names:
            raise ValueError(f"Game/Tuner frame order differs for {key}")
        expected_names = set(game_names)
        for side_name, side in sides.items():
            animation_dir = side["assets"] / profile_id / animation_id
            actual_names = {path.name for path in animation_dir.glob("*.png")}
            if actual_names != expected_names:
                raise ValueError(f"{side_name} asset set differs from manifest for {key}")
        for name in game_names:
            game_path = sides["game"]["assets"] / profile_id / animation_id / name
            tuner_path = sides["tuner"]["assets"] / profile_id / animation_id / name
            if sha256(game_path) != sha256(tuner_path):
                raise ValueError(f"Retained image differs between Game/Tuner: {key}/{name}")
        total_frames += len(game_frames)
        animations.append({"key": key, "frames": len(game_frames)})

    duration_checks = []
    audio_checks = []
    before_manifest = index_manifest(previous["game"]["animation_manifest.json"])
    before_playback = previous["game"]["animation_tuning.json"].get("frame_playback_overrides", {})
    after_playback = current["game"]["animation_tuning.json"].get("frame_playback_overrides", {})
    before_audio = previous["game"]["frame_audio_bindings.json"]
    after_audio = current["game"]["frame_audio_bindings.json"]
    if len(before_audio) != len(after_audio):
        raise ValueError("Audio binding count changed")

    for key in sorted(game_manifest):
        old_duration = animation_duration(before_manifest[key], before_playback, key)
        new_duration = animation_duration(game_manifest[key], after_playback, key)
        delta = new_duration - old_duration
        if abs(delta) > 0.00001:
            raise ValueError(f"Duration changed for {key}: {delta}")
        duration_checks.append(
            {"key": key, "duration_ms": round(new_duration * 1000.0, 6), "delta_ms": round(delta * 1000.0, 9)}
        )

    starts_before = {
        key: frame_start_times(before_manifest[key], before_playback, key) for key in before_manifest
    }
    starts_after = {key: frame_start_times(game_manifest[key], after_playback, key) for key in game_manifest}
    for old_item, new_item in zip(before_audio, after_audio):
        key = animation_from_binding(old_item)
        if key != animation_from_binding(new_item):
            raise ValueError("Audio animation changed")
        if str(old_item.get("path", "")) != str(new_item.get("path", "")):
            raise ValueError("Audio asset path changed")
        old_time = starts_before[key][int(old_item.get("frame", 0))]
        new_time = starts_after[key][int(new_item.get("frame", 0))]
        if abs(old_time - new_time) > 0.00001:
            raise ValueError(f"Audio timing changed: {old_item.get('path')}")
        resource_path = str(new_item.get("path", ""))
        if resource_path.startswith("res://"):
            local_path = args.project_root / resource_path.removeprefix("res://")
            if not local_path.is_file():
                raise FileNotFoundError(local_path)
        audio_checks.append(
            {
                "animation": key,
                "old_frame": int(old_item.get("frame", 0)),
                "new_frame": int(new_item.get("frame", 0)),
                "time_ms": round(new_time * 1000.0, 6),
                "path_unchanged": True,
            }
        )

    valid_frame_keys = {
        f"{key}:{index}" for key, animation in game_manifest.items() for index in range(len(animation.get("frames", [])))
    }
    attachments = current["game"]["frame_image_attachments.json"]
    invalid_attachment_keys = sorted(
        {str(item.get("frameKey", item.get("key", ""))) for item in attachments} - valid_frame_keys
    )
    if invalid_attachment_keys:
        raise ValueError(f"Invalid attachment frame keys: {invalid_attachment_keys[:5]}")
    invalid_audio_keys = sorted({str(item.get("key", "")) for item in after_audio} - valid_frame_keys)
    if invalid_audio_keys:
        raise ValueError(f"Invalid audio frame keys: {invalid_audio_keys[:5]}")

    report = {
        "ok": True,
        "total_frames": total_frames,
        "animations": animations,
        "duration_checks": duration_checks,
        "audio_binding_count": len(after_audio),
        "audio_checks": audio_checks,
        "attachment_count": len(attachments),
        "invalid_attachment_keys": invalid_attachment_keys,
        "invalid_audio_keys": invalid_audio_keys,
        "game_tuner_assets_match": True,
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        f"ok=true animations={len(animations)} frames={total_frames} audio={len(after_audio)} "
        f"attachments={len(attachments)} durations_exact=true audio_times_exact=true assets_match=true"
    )
    print(args.report)


if __name__ == "__main__":
    main()

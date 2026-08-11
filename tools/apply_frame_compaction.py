from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import shutil
from collections import defaultdict
from pathlib import Path


DATA_FILES = (
    "animation_manifest.json",
    "animation_tuning.json",
    "frame_audio_bindings.json",
    "frame_image_attachments.json",
)


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def write_json_atomic(path: Path, value) -> None:
    temporary = path.with_name(path.name + ".xsxb-compaction.tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(temporary, path)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def index_manifest(manifest: dict) -> dict[str, dict]:
    result = {}
    for profile in manifest.get("profiles", []):
        profile_id = str(profile.get("id", ""))
        for animation in profile.get("animations", []):
            result[f"{profile_id}/{animation.get('id', '')}"] = animation
    return result


def animation_from_binding(binding: dict) -> str:
    return str(binding.get("animation", ""))


def remap_source_key(value: str, new_index: int) -> str:
    prefix, separator, _ = value.rpartition(":")
    return f"{prefix}:{new_index}" if separator else value


def frame_start_times(animation: dict, playback: dict, animation_key: str) -> list[float]:
    fps = float(playback.get(f"{animation_key}:__group", {}).get("fps", animation.get("fps", 12.0)))
    elapsed = 0.0
    starts = []
    for index, frame in enumerate(animation.get("frames", [])):
        starts.append(elapsed)
        override = playback.get(f"{animation_key}:{index}", {})
        if override.get("disabled", False):
            elapsed += 0.001
        else:
            elapsed += float(override.get("duration", frame.get("duration", 1.0))) / fps
    return starts


def animation_duration(animation: dict, playback: dict, animation_key: str) -> float:
    fps = float(playback.get(f"{animation_key}:__group", {}).get("fps", animation.get("fps", 12.0)))
    duration = 0.0
    for index, frame in enumerate(animation.get("frames", [])):
        override = playback.get(f"{animation_key}:{index}", {})
        if override.get("disabled", False):
            continue
        duration += float(override.get("duration", frame.get("duration", 1.0))) / fps
    return duration


def validate_audit(audit: dict) -> dict[str, dict]:
    plans = {}
    for animation in audit.get("animations", []):
        key = str(animation["key"])
        frame_count = int(animation["frames_before"])
        groups = animation.get("groups", [])
        covered = []
        for group in groups:
            members = [int(value) for value in group["members"]]
            if not members or int(group["keep"]) != members[0]:
                raise ValueError(f"Invalid keeper in {key}: {group}")
            if len(members) > 1 and any(animation["entries"][index]["disabled"] for index in members):
                raise ValueError(f"Disabled frame included in a merge for {key}: {members}")
            if len(members) > 1 and any(animation["entries"][index]["audio"] for index in members[1:]):
                raise ValueError(f"Audio frame would be removed in {key}: {members}")
            covered.extend(members)
        if covered != list(range(frame_count)):
            raise ValueError(f"Audit groups do not exactly cover {key}")
        plans[key] = animation
    return plans


def remap_override_map(source: dict, plans: dict[str, dict], map_name: str) -> dict:
    result = {}
    handled_prefixes = tuple(f"{key}:" for key in plans)
    for key, value in source.items():
        if not key.startswith(handled_prefixes):
            result[key] = copy.deepcopy(value)
    for animation_key, plan in plans.items():
        group_key = f"{animation_key}:__group"
        if group_key in source:
            result[group_key] = copy.deepcopy(source[group_key])
        entries = plan["entries"]
        for new_index, group in enumerate(plan["groups"]):
            keep = int(group["keep"])
            old_key = f"{animation_key}:{keep}"
            new_key = f"{animation_key}:{new_index}"
            if map_name == "frame_playback_overrides" and len(group["members"]) > 1:
                value = copy.deepcopy(source.get(old_key, {}))
                value["duration"] = sum(float(entries[int(index)]["duration_units"]) for index in group["members"])
                value["disabled"] = False
                result[new_key] = value
            elif old_key in source:
                result[new_key] = copy.deepcopy(source[old_key])
    return result


def transform_side(side: dict, plans: dict[str, dict]) -> tuple[dict, dict]:
    data_root: Path = side["data_root"]
    documents = {name: load_json(data_root / name) for name in DATA_FILES}
    before = copy.deepcopy(documents)
    manifest_index = index_manifest(documents["animation_manifest.json"])

    for animation_key, plan in plans.items():
        animation = manifest_index.get(animation_key)
        if animation is None:
            raise ValueError(f"{side['name']} manifest misses {animation_key}")
        frames = animation.get("frames", [])
        if len(frames) != int(plan["frames_before"]):
            raise ValueError(f"{side['name']} {animation_key} frame count drifted")
        expected_names = [entry["file"] for entry in plan["entries"]]
        actual_names = [Path(str(frame.get("path", ""))).name for frame in frames]
        if actual_names != expected_names:
            raise ValueError(f"{side['name']} {animation_key} frame order differs from audit")
        animation["frames"] = [copy.deepcopy(frames[int(group["keep"])]) for group in plan["groups"]]

    tuning = documents["animation_tuning.json"]
    for map_name in ("frame_visual_overrides", "frame_playback_overrides", "frame_box_overrides"):
        tuning[map_name] = remap_override_map(tuning.get(map_name, {}), plans, map_name)

    group_lookup = {}
    for animation_key, plan in plans.items():
        for new_index, group in enumerate(plan["groups"]):
            for old_index in group["members"]:
                group_lookup[(animation_key, int(old_index))] = (new_index, int(group["keep"]))

    remapped_audio = []
    for original in documents["frame_audio_bindings.json"]:
        item = copy.deepcopy(original)
        animation_key = animation_from_binding(item)
        if animation_key in plans:
            old_index = int(item.get("frame", 0))
            new_index, keeper = group_lookup[(animation_key, old_index)]
            if old_index != keeper:
                raise ValueError(f"Audio frame would be removed: {animation_key}:{old_index}")
            item["frame"] = new_index
            item["displayFrame"] = new_index
            item["key"] = f"{animation_key}:{new_index}"
            item["sourceKey"] = remap_source_key(str(item.get("sourceKey", "")), new_index)
        remapped_audio.append(item)
    documents["frame_audio_bindings.json"] = remapped_audio

    remapped_attachments = []
    dropped_attachments = 0
    for original in documents["frame_image_attachments.json"]:
        item = copy.deepcopy(original)
        metadata = item.get("metadata", {})
        animation_key = str(metadata.get("animation", ""))
        if animation_key in plans:
            old_index = int(metadata.get("frame", 0))
            new_index, keeper = group_lookup[(animation_key, old_index)]
            if old_index != keeper:
                dropped_attachments += 1
                continue
            new_key = f"{animation_key}:{new_index}"
            item["key"] = new_key
            item["frameKey"] = new_key
            item["metadata"]["frame"] = new_index
            item["metadata"]["displayFrame"] = new_index
            item["sourceKey"] = remap_source_key(str(item.get("sourceKey", "")), new_index)
        remapped_attachments.append(item)
    documents["frame_image_attachments.json"] = remapped_attachments

    return before, {"documents": documents, "dropped_attachments": dropped_attachments}


def verify_transformation(before: dict, after: dict, plans: dict[str, dict], side_name: str) -> list[dict]:
    before_manifest = index_manifest(before["animation_manifest.json"])
    after_manifest = index_manifest(after["documents"]["animation_manifest.json"])
    before_playback = before["animation_tuning.json"].get("frame_playback_overrides", {})
    after_playback = after["documents"]["animation_tuning.json"].get("frame_playback_overrides", {})
    before_audio = before["frame_audio_bindings.json"]
    after_audio = after["documents"]["frame_audio_bindings.json"]
    if len(before_audio) != len(after_audio):
        raise ValueError(f"{side_name} audio binding count changed")
    results = []
    for animation_key, plan in plans.items():
        old_animation = before_manifest[animation_key]
        new_animation = after_manifest[animation_key]
        before_duration = animation_duration(old_animation, before_playback, animation_key)
        after_duration = animation_duration(new_animation, after_playback, animation_key)
        if abs(before_duration - after_duration) > 0.00001:
            raise ValueError(
                f"{side_name} duration drift for {animation_key}: {before_duration} -> {after_duration}"
            )
        old_starts = frame_start_times(old_animation, before_playback, animation_key)
        new_starts = frame_start_times(new_animation, after_playback, animation_key)
        audio_checks = []
        for old_item, new_item in zip(before_audio, after_audio):
            if animation_from_binding(old_item) != animation_key:
                continue
            if str(old_item.get("path", "")) != str(new_item.get("path", "")):
                raise ValueError(f"{side_name} audio binding order or path changed")
            old_time = old_starts[int(old_item.get("frame", 0))]
            new_time = new_starts[int(new_item.get("frame", 0))]
            if abs(old_time - new_time) > 0.00001:
                raise ValueError(
                    f"{side_name} audio timing drift for {old_item.get('path')}: {old_time} -> {new_time}"
                )
            audio_checks.append(
                {
                    "name": old_item.get("name", ""),
                    "old_frame": int(old_item.get("frame", 0)),
                    "new_frame": int(new_item.get("frame", 0)),
                    "time_ms": round(old_time * 1000.0, 6),
                }
            )
        results.append(
            {
                "key": animation_key,
                "frames_before": len(old_animation.get("frames", [])),
                "frames_after": len(new_animation.get("frames", [])),
                "duration_ms_before": round(before_duration * 1000.0, 6),
                "duration_ms_after": round(after_duration * 1000.0, 6),
                "audio": audio_checks,
            }
        )
    return results


def resolved_inside(path: Path, root: Path) -> bool:
    try:
        path.resolve().relative_to(root.resolve())
        return True
    except ValueError:
        return False


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--tuner-root", type=Path, required=True)
    parser.add_argument("--project", default="Watercolor_Desk_Companion")
    parser.add_argument("--audit", type=Path, required=True)
    parser.add_argument("--backup", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    audit = load_json(args.audit)
    plans = validate_audit(audit)
    sides = [
        {
            "name": "game",
            "data_root": args.project_root / "xsxb_frame_tuner/data/projects" / args.project,
            "asset_root": args.project_root / "xsxb_frame_tuner/workspace/projects" / args.project / "assets",
        },
        {
            "name": "tuner",
            "data_root": args.tuner_root / "data/projects" / args.project,
            "asset_root": args.tuner_root / "workspace/projects" / args.project / "assets",
        },
    ]

    transformed = {}
    verification = {}
    for side in sides:
        before, after = transform_side(side, plans)
        transformed[side["name"]] = {"before": before, "after": after}
        verification[side["name"]] = verify_transformation(before, after, plans, side["name"])

    removed_files = []
    retained_hashes = {}
    for animation_key, plan in plans.items():
        profile_id, animation_id = animation_key.split("/", 1)
        keep_indices = {int(group["keep"]) for group in plan["groups"]}
        names = [entry["file"] for entry in plan["entries"]]
        for side in sides:
            animation_dir = side["asset_root"] / profile_id / animation_id
            if not resolved_inside(animation_dir, side["asset_root"]):
                raise ValueError(f"Unsafe animation directory: {animation_dir}")
            for name in names:
                path = animation_dir / name
                if not path.is_file():
                    raise FileNotFoundError(path)
            for index, name in enumerate(names):
                path = animation_dir / name
                if index in keep_indices:
                    retained_hashes.setdefault((animation_key, name), {})[side["name"]] = sha256(path)
                else:
                    removed_files.append({"side": side["name"], "path": path, "animation": animation_key})
    for (animation_key, name), hashes in retained_hashes.items():
        if hashes.get("game") != hashes.get("tuner"):
            raise ValueError(f"Game/Tuner retained frame mismatch: {animation_key}/{name}")

    report = {
        "audit": str(args.audit),
        "thresholds": audit.get("thresholds", {}),
        "applied": bool(args.apply),
        "frames_before": sum(int(plan["frames_before"]) for plan in plans.values()),
        "frames_after": sum(len(plan["groups"]) for plan in plans.values()),
        "frames_removed": sum(int(plan["frames_before"]) - len(plan["groups"]) for plan in plans.values()),
        "audio_bindings_before": len(transformed["game"]["before"]["frame_audio_bindings.json"]),
        "audio_bindings_after": len(transformed["game"]["after"]["documents"]["frame_audio_bindings.json"]),
        "attachments_before": len(transformed["game"]["before"]["frame_image_attachments.json"]),
        "attachments_after": len(transformed["game"]["after"]["documents"]["frame_image_attachments.json"]),
        "verification": verification["game"],
        "removed_assets_per_side": len(removed_files) // 2,
    }

    if args.apply:
        if args.backup.exists():
            raise FileExistsError(f"Backup already exists: {args.backup}")
        args.backup.mkdir(parents=True)
        for side in sides:
            backup_data = args.backup / side["name"] / "data"
            backup_data.mkdir(parents=True)
            for name in DATA_FILES:
                shutil.copy2(side["data_root"] / name, backup_data / name)
        for side in sides:
            documents = transformed[side["name"]]["after"]["documents"]
            for name in DATA_FILES:
                write_json_atomic(side["data_root"] / name, documents[name])
        for item in removed_files:
            source: Path = item["path"]
            side = item["side"]
            side_root = next(value["asset_root"] for value in sides if value["name"] == side)
            relative = source.relative_to(side_root)
            destination = args.backup / side / "removed_assets" / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(source), str(destination))
            import_sidecar = source.with_name(source.name + ".import")
            if import_sidecar.exists():
                sidecar_destination = destination.with_name(destination.name + ".import")
                shutil.move(str(import_sidecar), str(sidecar_destination))
        report["backup"] = str(args.backup)

    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        f"frames={report['frames_before']}->{report['frames_after']} removed={report['frames_removed']} "
        f"audio={report['audio_bindings_before']}->{report['audio_bindings_after']} "
        f"attachments={report['attachments_before']}->{report['attachments_after']} apply={args.apply}"
    )
    print(args.report)


if __name__ == "__main__":
    main()

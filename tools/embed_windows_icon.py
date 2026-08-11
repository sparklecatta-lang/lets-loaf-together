from __future__ import annotations

import argparse
import ctypes
import shutil
import struct
from pathlib import Path


RT_ICON = 3
RT_GROUP_ICON = 14
LANGUAGES = (0, 1033)


def parse_ico(path: Path) -> list[tuple[bytes, int, int, int, int, int]]:
    payload = path.read_bytes()
    reserved, image_type, count = struct.unpack_from("<HHH", payload, 0)
    if reserved != 0 or image_type != 1 or count < 1:
        raise ValueError(f"Invalid ICO header: {path}")

    images: list[tuple[bytes, int, int, int, int, int]] = []
    for index in range(count):
        offset = 6 + index * 16
        width, height, colors, _reserved, planes, bits, size, data_offset = struct.unpack_from(
            "<BBBBHHII", payload, offset
        )
        image = payload[data_offset:data_offset + size]
        if len(image) != size:
            raise ValueError(f"ICO image {index} is truncated")
        images.append((image, width, height, colors, planes, bits))
    return images


def integer_resource(value: int) -> ctypes.c_void_p:
    return ctypes.c_void_p(value)


def update_resource(handle: int, resource_type: int, resource_id: int,
                    language: int, payload: bytes) -> None:
    buffer = ctypes.create_string_buffer(payload)
    ok = ctypes.windll.kernel32.UpdateResourceW(
        handle,
        integer_resource(resource_type),
        integer_resource(resource_id),
        language,
        ctypes.cast(buffer, ctypes.c_void_p),
        len(payload),
    )
    if not ok:
        raise ctypes.WinError(ctypes.get_last_error())


def embed_icon(executable: Path, ico_path: Path) -> None:
    images = parse_ico(ico_path)
    kernel32 = ctypes.windll.kernel32
    kernel32.BeginUpdateResourceW.argtypes = (ctypes.c_wchar_p, ctypes.c_bool)
    kernel32.BeginUpdateResourceW.restype = ctypes.c_void_p
    kernel32.UpdateResourceW.argtypes = (
        ctypes.c_void_p,
        ctypes.c_void_p,
        ctypes.c_void_p,
        ctypes.c_ushort,
        ctypes.c_void_p,
        ctypes.c_uint32,
    )
    kernel32.UpdateResourceW.restype = ctypes.c_bool
    kernel32.EndUpdateResourceW.argtypes = (ctypes.c_void_p, ctypes.c_bool)
    kernel32.EndUpdateResourceW.restype = ctypes.c_bool

    handle = kernel32.BeginUpdateResourceW(str(executable), False)
    if not handle:
        raise ctypes.WinError(ctypes.get_last_error())

    committed = False
    try:
        group_entries = bytearray(struct.pack("<HHH", 0, 1, len(images)))
        for index, (image, width, height, colors, planes, bits) in enumerate(images, start=1):
            resource_id = index
            for language in LANGUAGES:
                update_resource(handle, RT_ICON, resource_id, language, image)
            group_entries.extend(struct.pack(
                "<BBBBHHIH",
                width,
                height,
                colors,
                0,
                planes,
                bits,
                len(image),
                resource_id,
            ))
        for language in LANGUAGES:
            update_resource(handle, RT_GROUP_ICON, 1, language, bytes(group_entries))
        if not kernel32.EndUpdateResourceW(handle, False):
            raise ctypes.WinError(ctypes.get_last_error())
        committed = True
    finally:
        if not committed:
            kernel32.EndUpdateResourceW(handle, True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-exe", required=True, type=Path)
    parser.add_argument("--icon", required=True, type=Path)
    parser.add_argument("--output-exe", required=True, type=Path)
    args = parser.parse_args()

    args.output_exe.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(args.input_exe, args.output_exe)
    embed_icon(args.output_exe.resolve(), args.icon.resolve())
    print(f"Embedded {args.icon} into {args.output_exe}")


if __name__ == "__main__":
    main()

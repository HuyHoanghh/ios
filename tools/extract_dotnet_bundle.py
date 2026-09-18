#!/usr/bin/env python3
"""Extract files from a .NET single-file bundle."""

from __future__ import annotations

import argparse
import struct
import zlib
from pathlib import Path, PurePosixPath


SIGNATURE = bytes.fromhex(
    "8b1202b96a612038727b930214d7a03213f5b9e6efae3318ee3b2dce24b36aae"
)


def read_7bit(data: bytes, position: int) -> tuple[int, int]:
    value = 0
    shift = 0
    while True:
        current = data[position]
        position += 1
        value |= (current & 0x7F) << shift
        if current & 0x80 == 0:
            return value, position
        shift += 7
        if shift >= 35:
            raise ValueError("Invalid 7-bit encoded integer")


def read_string(data: bytes, position: int) -> tuple[str, int]:
    length, position = read_7bit(data, position)
    end = position + length
    return data[position:end].decode("utf-8"), end


def extract(bundle: Path, destination: Path) -> None:
    data = bundle.read_bytes()
    signature_offset = data.find(SIGNATURE)
    if signature_offset < 8:
        raise ValueError(".NET bundle signature was not found")

    (header_offset,) = struct.unpack_from("<q", data, signature_offset - 8)
    position = header_offset
    major, minor, file_count = struct.unpack_from("<IIi", data, position)
    position += 12
    bundle_id, position = read_string(data, position)

    if major >= 2:
        position += 40  # deps/runtimeconfig offsets and sizes, then flags

    print(f"Bundle {bundle_id}, format {major}.{minor}, {file_count} files")
    destination.mkdir(parents=True, exist_ok=True)

    for _ in range(file_count):
        offset, size = struct.unpack_from("<qq", data, position)
        position += 16
        compressed_size = 0
        if major >= 6:
            (compressed_size,) = struct.unpack_from("<q", data, position)
            position += 8
        file_type = data[position]
        position += 1
        relative_path, position = read_string(data, position)

        relative = PurePosixPath(relative_path)
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError(f"Unsafe path in bundle: {relative_path}")

        stored_size = compressed_size or size
        payload = data[offset : offset + stored_size]
        if compressed_size:
            payload = zlib.decompress(payload, -zlib.MAX_WBITS)
        if len(payload) != size:
            raise ValueError(f"Unexpected size for {relative_path}")

        output = destination.joinpath(*relative.parts)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(payload)
        print(f"{file_type}: {relative_path} ({size} bytes)")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("bundle", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    extract(args.bundle, args.destination)


if __name__ == "__main__":
    main()

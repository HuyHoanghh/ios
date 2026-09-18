#!/usr/bin/env python3
"""Print the #US heap strings from a managed assembly."""

import argparse

import dnfile


def compressed_uint(data: bytes, position: int) -> tuple[int, int]:
    first = data[position]
    if first & 0x80 == 0:
        return first, position + 1
    if first & 0xC0 == 0x80:
        return ((first & 0x3F) << 8) | data[position + 1], position + 2
    return (
        ((first & 0x1F) << 24)
        | (data[position + 1] << 16)
        | (data[position + 2] << 8)
        | data[position + 3],
        position + 4,
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("assembly")
    args = parser.parse_args()
    heap = dnfile.dnPE(args.assembly).net.user_strings.__data__
    position = 1
    while position < len(heap):
        offset = position
        size, payload_start = compressed_uint(heap, position)
        if size == 0:
            position = payload_start
            continue
        payload = heap[payload_start : payload_start + size - 1]
        print(f"0x{offset:04x}\t{payload.decode('utf-16le', errors='replace')}")
        position = payload_start + size


if __name__ == "__main__":
    main()

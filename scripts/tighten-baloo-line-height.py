#!/usr/bin/env python3
"""Sets Baloo 2's line height to 1.3 times the font size, from the 1.6 it ships with.

Baloo 2 reserves room for Devanagari, so its lines are far apart for the Latin text the app shows:
a wrapped title or caption looks double-spaced, and a single line carries a wide empty band above
and below. SwiftUI can't tighten a custom font's lines (negative lineSpacing and .leading(.tight)
do nothing), so the font's own metrics change instead. The same amount comes off the top and the
bottom, as Material's line heights do on Android, where Baloo 2 lines are 1.22 to 1.33 times the
size.

Edits the hhea and OS/2 typo ascender, descender and line gap, then the checksums. Running it again
changes nothing. The licence (SIL OFL, no reserved font name) allows modified copies.

Usage: scripts/tighten-baloo-line-height.py "Cats&Dogs/Resources/Fonts/Baloo2.ttf"
"""

import struct
import sys

LINE_HEIGHT = 1.3


def checksum(data: bytes) -> int:
    data += b"\0" * (-len(data) % 4)
    return sum(struct.unpack(f">{len(data) // 4}I", data)) & 0xFFFFFFFF


def main(path: str) -> None:
    font = bytearray(open(path, "rb").read())
    count = struct.unpack(">H", font[4:6])[0]
    tables = {}
    for i in range(count):
        entry = 12 + 16 * i
        tag, _, offset, length = struct.unpack(">4sIII", font[entry:entry + 16])
        tables[tag.decode()] = (entry, offset, length)

    head = tables["head"][1]
    hhea = tables["hhea"][1]
    os2 = tables["OS/2"][1]
    units_per_em = struct.unpack(">H", font[head + 18:head + 20])[0]
    ascender, descender, line_gap = struct.unpack(">hhh", font[hhea + 4:hhea + 10])

    target = round(LINE_HEIGHT * units_per_em)
    trim = (ascender - descender + line_gap - target) // 2
    if trim == 0:
        print(f"Already {LINE_HEIGHT} em: ascender {ascender}, descender {descender}")
        return
    ascender -= trim
    descender += trim
    font[hhea + 4:hhea + 10] = struct.pack(">hhh", ascender, descender, 0)
    font[os2 + 68:os2 + 74] = struct.pack(">hhh", ascender, descender, 0)

    for tag in ("hhea", "OS/2"):
        entry, offset, length = tables[tag]
        font[entry + 4:entry + 8] = struct.pack(">I", checksum(bytes(font[offset:offset + length])))
    font[head + 8:head + 12] = b"\0\0\0\0"
    entry, offset, length = tables["head"]
    font[entry + 4:entry + 8] = struct.pack(">I", checksum(bytes(font[offset:offset + length])))
    font[head + 8:head + 12] = struct.pack(">I", (0xB1B0AFBA - checksum(bytes(font))) & 0xFFFFFFFF)

    open(path, "wb").write(font)
    print(f"Line height {LINE_HEIGHT} em: ascender {ascender}, descender {descender}, line gap 0")


if __name__ == "__main__":
    main(sys.argv[1])

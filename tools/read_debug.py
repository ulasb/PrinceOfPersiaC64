#!/usr/bin/env python3
"""Decode the debug HUD cells from a VICE screenshot.

The TESTSCRIPT build fills 4x8-pixel cells in the HUD strip with raw state
bytes (dbg_dump in main.s). Each byte shows as 4 multicolor pixels; colors
map back to bit pairs: black 00, white 01, orange 10, blue 11.

Usage: read_debug.py shot.png [shot2.png ...]
"""

import struct
import sys
import zlib

FIELDS = ["frame", "action", "x_lo", "x_hi", "y_lo", "y_hi",
          "row", "seq_lo", "seq_hi", "input"]


def read_png(path):
    d = open(path, "rb").read()
    pos, w, h, ct, idat = 8, None, None, None, b""
    while pos < len(d):
        ln = struct.unpack(">I", d[pos:pos + 4])[0]
        typ = d[pos + 4:pos + 8]
        if typ == b"IHDR":
            w, h, _bd, ct = struct.unpack(">IIBB", d[pos + 8:pos + 18])
        elif typ == b"IDAT":
            idat += d[pos + 8:pos + 8 + ln]
        pos += 12 + ln
    raw = zlib.decompress(idat)
    bpp = 3 if ct == 2 else 4
    stride = 1 + w * bpp
    def px(x, y):
        o = y * stride + 1 + x * bpp
        return raw[o], raw[o + 1], raw[o + 2]
    return w, h, px


def classify(rgb):
    r, g, b = rgb
    if r > 200 and g > 200 and b > 200:
        return 1                       # white
    if r > 100 and r > b + 30:
        return 2                       # orange/brown
    if b > 100 and b > r + 30:
        return 3                       # blue
    return 0                           # black


def main():
    for path in sys.argv[1:]:
        w, h, px = read_png(path)
        ox = (w - 320) // 2
        # locate the screen top: first row with any non-black pixel
        oy = None
        for yy in range(0, h):
            if any(classify(px(ox + x, yy)) for x in range(0, 320, 2)):
                oy = yy
                break
        if oy is None:
            print(f"{path}: blank screen")
            continue
        y = oy + 3                     # mid-height of the top cell row
        vals = []
        for cell in range(len(FIELDS)):
            v = 0
            for p in range(4):
                c = classify(px(ox + (30 + cell) * 8 + p * 2, y))
                v = (v << 2) | c
            vals.append(v)
        x = vals[2] | (vals[3] << 8)
        yy_ = vals[4] | (vals[5] << 8)
        seq = vals[7] | (vals[8] << 8)
        row = vals[6] if vals[6] < 128 else vals[6] - 256
        print(f"{path}: frame={vals[0]} action={vals[1]} x={x} y={yy_} "
              f"row={row} seq={seq} input={vals[9]:05b}")


if __name__ == "__main__":
    main()

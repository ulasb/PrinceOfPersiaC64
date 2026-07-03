#!/usr/bin/env python3
"""Convert original Apple II image tables to C64 multicolor piece archives.

Decodes IMG.CHTAB*/IMG.BGTAB* binaries (7 bits per byte, bit 7 = palette,
rows bottom-up; see PrinceOfPersiaPy/src/tools/extract_images.py) straight
to 2bpp at game resolution: an Apple II 140-mode pixel is one bit PAIR,
which maps 1:1 onto a C64 multicolor pixel:

    pair 00 -> 0 transparent/black
    pair 11 -> 1 white
    pair 01/10 -> a color:
        background pieces: by pair phase (10 cool/blue, 01 warm/orange),
            matching NTSC artifact position rules;
        characters: by the byte's palette bit (1 warm, 0 cool), so body
            part colors don't depend on screen position.

Archive format (little-endian):
    u8  count            number of image slots
    u16 offset[count]    from archive start; 0 = no image
    per image:
        u8 wbytes        row width in bytes (4 px each, MSB-first)
        u8 height
        u8 data[wbytes*height]   rows top to bottom
"""

import struct
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
IMAGES = (HERE.parent / "PrinceOfPersiaPy" / "source_reference"
          / "01 POP Source" / "Images")
OUT = HERE / "assets" / "gfx"

sys.path.insert(0, str(HERE.parent / "PrinceOfPersiaPy" / "src"))
from data import framedefs  # noqa: E402


def reachable_bg(table_bit7):
    """Piece ids reachable from the BGDATA tables (dungeon set)."""
    sys.path.insert(0, str(HERE.parent / "PrinceOfPersiaPy" / "src"))
    from graphics import bgdata as BG
    used = set()
    for name in ["PIECEA", "PIECEB", "PIECEC", "PIECED", "FRONTI", "BSTRIPE",
                 "GATE8B", "GATE8C", "SPIKEA", "SPIKEB", "LOOSEA", "LOOSED",
                 "SLICERTOP", "SLICERBOT", "SLICERFRNT", "BLOCKB", "BLOCKC",
                 "BLOCKD", "BLOCKFR", "PANELB", "PANELC", "SPACEB", "FLOORB",
                 "TORCHFLAME"]:
        used.update(getattr(BG, name))
    for c in ["GATEBOT_STA", "GATEBOT_ORA", "GATE_B1", "EXIT_STAIRS",
              "EXIT_DOOR", "EXIT_TOP", "LOOSE_B", "SPECIALFLASK",
              "SWORDGLEAM0", "SWORDGLEAM1"]:
        used.add(getattr(BG, c))
    used.discard(0)
    if table_bit7:
        return {u & 0x7F for u in used if u & 0x80}
    return {u for u in used if not (u & 0x80)}


def ch5_kid_images():
    """CHTAB5 images used by kid MAIN frames (combat stances, deaths,
    potions) — the guard-only bulk of CHTAB5 stays out."""
    used = set()
    for f, (img, sword, _dx, _dy, _chk) in framedefs.MAIN.items():
        table = ((img & 0x80) >> 5) | ((sword & 0xC0) >> 6)
        if table == 4:
            used.add(img & 0x7F)
    return used


def bg1_reachable():
    return reachable_bg(False)


def bg2_reachable():
    return reachable_bg(True)


def col_major(d: bytes, wb: int, h: int) -> bytes:
    """Reorder image bytes column-major: character art runs vertically,
    which RLE-compresses ~40% better than row order."""
    return bytes(d[r * wb + c] for c in range(wb) for r in range(h))


def rle(data: bytes) -> bytes:
    """Byte RLE: ctrl < $80 = ctrl+1 literals follow; ctrl >= $80 =
    repeat next byte (ctrl & $7f) + 2 times."""
    out = bytearray()
    i = 0
    n = len(data)
    while i < n:
        run = 1
        while i + run < n and data[i + run] == data[i] and run < 129:
            run += 1
        if run >= 2:
            out.append(0x80 | (run - 2))
            out.append(data[i])
            i += run
            continue
        j = i + 1
        while j < n and (j + 1 >= n or data[j + 1] != data[j]) \
                and j - i < 128:
            j += 1
        out.append(j - i - 1)
        out += data[i:j]
        i = j
    return bytes(out)

WARM, COOL, WHITE = 2, 3, 1

# Pieces the game always draws at an odd Apple II byte offset (torch
# flames, some foreground fronts: BGDATA byte_dx 1 or 3). Their 140-px
# pair grid is shifted one hi-res pixel, so decode them odd-aligned.
ODD_ALIGNED = {
    "IMG.BGTAB1.DUN": {0x0f, 0x13, 0x45, 0x46, 0x48, 0x49,
                       0x52, 0x53, 0x54, 0x55, 0x56, 0x61, 0x62, 0x63, 0x64},
    "IMG.BGTAB1.PAL": {0x0f, 0x13, 0x45, 0x46, 0x48, 0x49,
                       0x52, 0x53, 0x54, 0x55, 0x56, 0x61, 0x62, 0x63, 0x64},
    "IMG.BGTAB2.DUN": {0x28, 0x2e},
    "IMG.BGTAB2.PAL": {0x28, 0x2e},
}


def count_valid(data: bytes, base: int) -> int:
    count = 0
    for n in range(1, 192):
        off = n * 2 - 1
        if off + 1 >= len(data):
            break
        ptr = data[off] | (data[off + 1] << 8)
        o = ptr - base
        if not (0 <= o < len(data) - 2):
            continue
        w, h = data[o], data[o + 1]
        if 1 <= w <= 40 and 1 <= h <= 192 and o + 2 + w * h <= len(data):
            count += 1
    return count


def detect_base(data: bytes) -> int:
    candidates = [0x6000, 0xA000, 0x2000, 0x4000, 0x8000, 0xB000, 0x1000]
    return max(candidates, key=lambda b: count_valid(data, b))


def decode_image(data: bytes, offset: int, palette_hue: bool,
                 odd_align: bool = False):
    """One image -> (wbytes, height, packed 2bpp rows top-down), or None."""
    width, height = data[offset], data[offset + 1]
    if not (1 <= width <= 40 and 1 <= height <= 192):
        return None
    if offset + 2 + width * height > len(data):
        return None
    bitmap = data[offset + 2: offset + 2 + width * height]

    wm = (width * 7 + 1 + odd_align) // 2   # game pixels per row
    wb = (wm + 3) // 4                 # packed bytes per row
    out = bytearray(wb * height)
    for row in range(height):
        bits, pals = ([0], [0]) if odd_align else ([], [])
        for bx in range(width):
            byte = bitmap[row * width + bx]
            pal = (byte >> 7) & 1
            for b in range(7):
                bits.append((byte >> b) & 1)
                pals.append(pal)
        bits.append(0)                 # even out the last pair
        pals.append(pals[-1])
        y = height - 1 - row           # source rows are bottom-up
        for i in range(wm):
            b0, b1 = bits[2 * i], bits[2 * i + 1]
            if b0 and b1:
                code = WHITE
            elif b0 or b1:
                if palette_hue:
                    code = WARM if pals[2 * i if b0 else 2 * i + 1] else COOL
                else:
                    code = COOL if b0 else WARM
            else:
                continue
            out[y * wb + i // 4] |= code << (6 - 2 * (i % 4))
    return wb, height, bytes(out)


def build_archive(table_name: str, out_name: str, palette_hue: bool) -> int:
    data = (IMAGES / table_name).read_bytes()
    base = detect_base(data)
    images = {}
    for n in range(1, 192):
        off = n * 2 - 1
        if off + 1 >= len(data):
            break
        ptr = data[off] | (data[off + 1] << 8)
        if ptr == 0:
            continue
        o = ptr - base
        if not (0 <= o < len(data) - 2):
            continue
        img = decode_image(data, o, palette_hue,
                           odd_align=n in ODD_ALIGNED.get(table_name, ()))
        if img:
            images[n] = img
    count = max(images) + 1
    header = 1 + 2 * count
    blob = bytearray()
    offsets = []
    for i in range(count):
        if i in images:
            wb, h, d = images[i]
            offsets.append(header + len(blob))
            blob += struct.pack("<BB", wb, h) + d
        else:
            offsets.append(0)
    payload = struct.pack("<B", count)
    payload += b"".join(struct.pack("<H", o) for o in offsets)
    payload += blob
    (OUT / out_name).write_bytes(payload)
    print(f"{out_name}: {len(images)} images, {len(payload)} bytes "
          f"(base ${base:04x})")
    return len(payload)


def load_table(table_name: str, palette_hue: bool):
    """Decode a whole image table -> {n: (wb, h, data)}."""
    data = (IMAGES / table_name).read_bytes()
    base = detect_base(data)
    images = {}
    for n in range(1, 192):
        off = n * 2 - 1
        if off + 1 >= len(data):
            break
        ptr = data[off] | (data[off + 1] << 8)
        if ptr == 0:
            continue
        o = ptr - base
        if not (0 <= o < len(data) - 2):
            continue
        img = decode_image(data, o, palette_hue,
                           odd_align=n in ODD_ALIGNED.get(table_name, ()))
        if img:
            images[n] = img
    return images


# C64 RAM windows around VIC bank 2 (matrix $8c00, bitmap $a000-$bf3f).
# GFXH loads into the bitmap hole in the PRG and is copied to $e000 at init;
# $f000+ holds the blit tables and character buffers (see pop.inc).
WINDOWS = [("GFX1", 0x5000, 0x8A80), ("GFX9", 0x9000, 0xA000),
           ("GFXC", 0xC000, 0xD000), ("GFXH", 0xE000, 0xF000)]

# demo set: dungeon backgrounds + kid/guard tables. Character archives are
# RLE-compressed (decompressed per frame at draw time); CHTAB5 (deaths,
# potions, princess) still doesn't fit — see PLAN.md.
PACK_SET = [("BG1", "IMG.BGTAB1.DUN", False, bg1_reachable, True),
            ("BG2", "IMG.BGTAB2.DUN", False, bg2_reachable, True),
            ("CH1", "IMG.CHTAB1", True, None, True),
            ("CH2", "IMG.CHTAB2", True, None, True),
            ("CH3", "IMG.CHTAB3", True, None, True),
            ("CH4", "IMG.CHTAB4.GD", True, None, True),
            ("CH5", "IMG.CHTAB5", True, ch5_kid_images, True)]


def pack_windows():
    """Allocate all demo images into the RAM windows; emit per-window blobs
    and src/data/gfxindex.s with absolute lo/hi address tables per archive."""
    blobs = {name: bytearray() for name, _, _ in WINDOWS}
    tables = {}
    for label, table_name, hue, keep, compress in PACK_SET:
        images = load_table(table_name, hue)
        if keep is not None:
            keep_set = keep()
            images = {n: im for n, im in images.items() if n in keep_set}
        if compress:
            images = {n: (wb, h, rle(col_major(d, wb, h)))
                      for n, (wb, h, d) in images.items()}
        count = max(images) + 1
        addrs = [0] * count
        for n in sorted(images):
            wb, h, d = images[n]
            rec = struct.pack("<BB", wb, h) + d
            for wname, wstart, wend in WINDOWS:
                blob = blobs[wname]
                if wstart + len(blob) + len(rec) <= wend:
                    addrs[n] = wstart + len(blob)
                    blob += rec
                    break
            else:
                raise SystemExit(f"out of window space at {label} #{n}")
        tables[label] = addrs

    for wname, wstart, wend in WINDOWS:
        (OUT / f"gfx_{wname.lower()}.bin").write_bytes(blobs[wname])
        print(f"gfx_{wname.lower()}.bin: {len(blobs[wname])} bytes "
              f"(${wstart:04x}-${wstart + len(blobs[wname]) - 1:04x}, "
              f"{wend - wstart - len(blobs[wname])} free)")

    lines = ["; Generated by tools/convert_gfx.py. Do not edit.",
             "; Absolute addresses of packed images: 0 = no image.",
             ""]
    for label, addrs in tables.items():
        lines.append(f"        .export IMG_{label}_LO, IMG_{label}_HI")
        lines.append(f"IMG_{label}_COUNT = {len(addrs)}")
        lines.append(f"        .segment \"RODATA\"")
        lines.append(f"IMG_{label}_LO:")
        lines.append("        .byte " + ",".join(
            f"${a & 0xff:02x}" for a in addrs))
        lines.append(f"IMG_{label}_HI:")
        lines.append("        .byte " + ",".join(
            f"${a >> 8:02x}" for a in addrs))
    (HERE / "src" / "data" / "gfxindex.s").write_text("\n".join(lines) + "\n")
    print("wrote src/data/gfxindex.s")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    # standalone archives (host-side preview tools)
    total = 0
    total += build_archive("IMG.BGTAB1.DUN", "bgtab1_dun.bin", False)
    total += build_archive("IMG.BGTAB2.DUN", "bgtab2_dun.bin", False)
    total += build_archive("IMG.BGTAB1.PAL", "bgtab1_pal.bin", False)
    total += build_archive("IMG.BGTAB2.PAL", "bgtab2_pal.bin", False)
    total += build_archive("IMG.CHTAB1", "chtab1.bin", True)
    total += build_archive("IMG.CHTAB2", "chtab2.bin", True)
    total += build_archive("IMG.CHTAB3", "chtab3.bin", True)
    total += build_archive("IMG.CHTAB4.GD", "chtab4_gd.bin", True)
    print(f"total: {total} bytes")
    # packed windows for the C64 build
    pack_windows()


if __name__ == "__main__":
    main()

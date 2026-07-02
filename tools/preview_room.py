#!/usr/bin/env python3
"""Render a room from the converted C64 assets — reference for the asm renderer.

Implements the exact drawing model planned for src/render.s (C/B/A/D block
sections from BGDATA tables, masked blits of 2bpp pieces, 140px playfield
at x offset 10 on a 160x200 mc screen), reading the .bin archives produced
by convert_gfx.py and the original level blueprints. Dynamic tiles are drawn
in their rest state (gates closed, spikes retracted, torch flame frame 0).

Usage: preview_room.py [level] [room] [out.png]
"""

import struct
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE.parent / "PrinceOfPersiaPy" / "src"))
from graphics import bgdata as BG  # noqa: E402

SCREEN_W, SCREEN_H = 160, 200
PLAYFIELD_X = 10
TILE_W, ROW_H = 14, 63

# C64 colors for codes 0-3 (VICE Pepto palette approximations)
C64_RGB = {0: (0, 0, 0), 1: (255, 255, 255), 2: (0x8e, 0x50, 0x29),
           3: (0x77, 0x71, 0xfc)}

BLOCK, PANELWIF, PANELWOF, GATE, SLICER = 20, 7, 12, 4, 18
SPIKES, LOOSE, FLOOR, SPACE, TORCH = 2, 11, 1, 0, 19
EXIT, EXIT2, FLASK, SWORD = 16, 17, 18, 22  # EXIT2=17, SLICER=18 fix below
EXIT, EXIT2, SLICER, FLASK, SWORD = 16, 17, 18, 10, 22


class Archive:
    def __init__(self, path: Path):
        d = path.read_bytes()
        n = d[0]
        self.images = {}
        for i in range(n):
            off = struct.unpack_from("<H", d, 1 + 2 * i)[0]
            if off:
                wb, h = d[off], d[off + 1]
                self.images[i] = (wb, h, d[off + 2:off + 2 + wb * h])

    def get(self, i):
        return self.images.get(i)


class Screen:
    def __init__(self):
        self.px = [[0] * SCREEN_W for _ in range(SCREEN_H)]

    def blit_ll(self, img, x, bottom):
        """Masked lower-left blit; x/bottom in mc px, code 0 transparent."""
        if img is None:
            return
        wb, h, data = img
        top = bottom - h + 1
        for ry in range(h):
            y = top + ry
            if not 0 <= y < SCREEN_H:
                continue
            for bx in range(wb):
                b = data[ry * wb + bx]
                for p in range(4):
                    code = (b >> (6 - 2 * p)) & 3
                    if code == 0:
                        continue
                    xx = x + bx * 4 + p
                    if 0 <= xx < SCREEN_W:
                        self.px[y][xx] = code

    def save_png(self, path):
        import zlib
        raw = b"".join(
            b"\x00" + b"".join(bytes(C64_RGB[c]) for c in row)
            for row in self.px)
        def chunk(t, d):
            c = t + d
            return struct.pack(">I", len(d)) + c + struct.pack(
                ">I", zlib.crc32(c))
        png = (b"\x89PNG\r\n\x1a\n"
               + chunk(b"IHDR", struct.pack(">IIBBBBB", SCREEN_W, SCREEN_H,
                                            8, 2, 0, 0, 0))
               + chunk(b"IDAT", zlib.compress(raw))
               + chunk(b"IEND", b""))
        Path(path).write_bytes(png)


class Level:
    def __init__(self, path: Path):
        self.d = path.read_bytes()

    def link(self, room, direction):
        i = "left right up down".split().index(direction)
        return self.d[1952 + (room - 1) * 4 + i]

    def _resolve(self, room, col, row):
        if col < 0:
            room = self.link(room, "left")
            col += 10
        elif col > 9:
            room = self.link(room, "right")
            col -= 10
        if row < 0 and room:
            room = self.link(room, "up")
            row += 3
        elif row > 2 and room:
            room = self.link(room, "down")
            row -= 3
        return room, col, row

    def tile(self, room, col, row):
        room, col, row = self._resolve(room, col, row)
        if room == 0:
            return BLOCK  # out of the map reads as wall
        return self.d[(room - 1) * 30 + row * 10 + col] & 0x1F

    def spec(self, room, col, row):
        room, col, row = self._resolve(room, col, row)
        if room == 0:
            return 0
        return self.d[720 + (room - 1) * 30 + row * 10 + col]

    @property
    def kid(self):
        info = self.d[2048:]
        return {"room": info[64], "block": info[65],
                "face": -1 if info[66] == 0xFF else 1}


class RoomRenderer:
    def __init__(self, level, bg1, bg2):
        self.level = level
        self.bg1, self.bg2 = bg1, bg2
        self.scr = Screen()

    def img(self, image_id):
        if image_id == 0:
            return None
        arc = self.bg2 if image_id & 0x80 else self.bg1
        return arc.get(image_id & 0x7F)

    def piece(self, image_id, col, bottom, byte_dx=0):
        # col in blocks; byte_dx in Apple II bytes (3.5 game px, floored)
        x = PLAYFIELD_X + col * TILE_W + (byte_dx * 7) // 2
        self.scr.blit_ll(self.img(image_id), x, bottom)

    @staticmethod
    def block_bot(row):
        return 65 + ROW_H * row

    @staticmethod
    def block_top(row):
        return 3 + ROW_H * row

    def draw_room(self, room):
        for row in range(-1, 3):
            for col in range(-1, 11):
                self.draw_block(room, col, row)

    def draw_block(self, room, col, row):
        L, BGd = self.level, BG
        ay = self.block_bot(row) - 3
        dy = self.block_bot(row)
        t = L.tile(room, col, row)

        # C-section of the piece below-left
        tc = L.tile(room, col - 1, row + 1)
        if tc == BLOCK:
            sc = L.spec(room, col - 1, row + 1)
            self.piece(BGd.BLOCKC[sc if sc < len(BGd.BLOCKC) else 0], col, dy)
        elif tc in (PANELWIF, PANELWOF):
            sc = L.spec(room, col - 1, row + 1)
            if sc < len(BGd.PANELC):
                self.piece(BGd.PANELC[sc], col, dy)
        elif tc == GATE:
            self.draw_gate_c(col, dy, row)
        elif tc == SLICER:
            pass
        else:
            self.piece(BGd.PIECEC[tc], col, dy)

        # B-section of the piece to the left
        tb = L.tile(room, col - 1, row)
        sb = L.spec(room, col - 1, row)
        if t != BLOCK:
            if tb == BLOCK:
                self.piece(BGd.BLOCKB[sb if sb < len(BGd.BLOCKB) else 0],
                           col, ay + 2)
            elif tb in (PANELWIF, PANELWOF):
                if sb < len(BGd.PANELB):
                    self.piece(BGd.PANELB[sb], col, ay + 3)
            elif tb == SPIKES:
                self.piece(BGd.SPIKEB[0], col, ay)
            elif tb == LOOSE:
                self.piece(BGd.LOOSE_B, col, ay - 1)
            elif tb == GATE:
                self.draw_gate_b(col, ay, row)
            elif tb == FLOOR:
                idx = sb if sb < len(BGd.FLOORB) else 0
                self.piece(BGd.FLOORB[idx], col, ay)
            elif tb == SPACE:
                if 0 < sb < len(BGd.SPACEB):
                    self.piece(BGd.SPACEB[sb], col, ay + BGd.SPACEBY[sb])
            else:
                self.piece(BGd.PIECEB[tb], col, ay + BGd.PIECEBY[tb])

        # A-section
        if t == BLOCK:
            sf = L.spec(room, col, row)
            self.piece(BGd.BLOCKFR[sf if sf < len(BGd.BLOCKFR) else 0],
                       col, ay)
        elif t == SPIKES:
            self.piece(BGd.SPIKEA[0], col, ay)
        elif t == LOOSE:
            self.piece(BGd.LOOSEA[0], col, ay)
        elif t == TORCH:
            self.piece(BGd.PIECEA[t], col, ay + BGd.PIECEAY[t])
            self.piece(BGd.TORCHFLAME[0], col + 1, ay - 43, byte_dx=1)
        elif t in (EXIT, EXIT2):
            self.draw_exit(col, ay, t)
        elif t == SLICER:
            self.piece(BGd.PIECEA[FLOOR], col, ay)
            self.piece(BGd.SLICERBOT[0], col, ay)
            self.piece(BGd.PIECED[FLOOR], col, dy)
        elif t == FLASK:
            self.piece(BGd.PIECEA[FLOOR], col, ay)
            self.piece(BGd.SPECIALFLASK, col, ay - 14, byte_dx=2)
        elif t == SWORD:
            self.piece(BGd.SWORDGLEAM0, col, ay)
        else:
            self.piece(BGd.PIECEA[t], col, ay + BGd.PIECEAY[t])

        # D-section
        if t == BLOCK:
            sd = L.spec(room, col, row)
            self.piece(BGd.BLOCKD[sd if sd < len(BGd.BLOCKD) else 0], col, dy)
        elif t == LOOSE:
            self.piece(BGd.LOOSED[0], col, dy)
        elif t == SLICER:
            pass
        else:
            self.piece(BGd.PIECED[t], col, dy)

    def draw_gate_b(self, at_col, ay, row, pos=0):
        bottom = self.block_bot(row) - 16 - (pos * 44 // 188)
        top = self.block_top(row) - 8
        img = self.img(BG.GATE8B[7])
        seg_h = img[1] if img else 8
        y = bottom
        while y > top:
            self.scr.blit_ll(img, PLAYFIELD_X + at_col * TILE_W, y)
            y -= seg_h
        self.piece(BG.GATEBOT_ORA, at_col, bottom + 4)

    def draw_gate_c(self, at_col, dy, row_above, pos=0):
        row = row_above  # called with the gate's row + 1 ... keep simple
        bottom = self.block_bot(row - 1) - 16
        img = self.img(BG.GATE8C[0])
        if img is None:
            return
        y = min(bottom, self.block_top(row - 1) + 2)
        top_of_above = self.block_top(row - 1) - 10
        seg_h = img[1]
        while y > top_of_above:
            self.scr.blit_ll(img, PLAYFIELD_X + at_col * TILE_W, y)
            y -= seg_h

    def draw_exit(self, col, ay, t):
        self.piece(BG.PIECEA[FLOOR], col, ay)
        if t == EXIT:
            self.piece(BG.EXIT_STAIRS, col, ay)
        else:
            self.piece(BG.EXIT_DOOR, col, ay)
            self.piece(BG.EXIT_TOP, col, ay - 48)

    def draw_foreground(self, room):
        for row in range(-1, 3):
            for col in range(-1, 11):
                t = self.level.tile(room, col, row)
                ay = self.block_bot(row) - 3
                if t == SLICER:
                    self.piece(BG.SLICERFRNT[0], col, ay)
                    continue
                if t == BLOCK:
                    continue
                fi = BG.FRONTI[t]
                if fi:
                    self.piece(fi, col, ay + BG.FRONTY[t],
                               byte_dx=BG.FRONTX[t])
                if t == GATE:
                    self.draw_gate_b(col + 1, ay, row)


def main():
    level_n = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    lv = Level(HERE / "assets" / "levels" / f"level{level_n:02d}.bin")
    room = int(sys.argv[2]) if len(sys.argv) > 2 else lv.kid["room"]
    out = sys.argv[3] if len(sys.argv) > 3 else str(
        HERE / "build" / f"preview_l{level_n}_r{room}.png")
    bg1 = Archive(HERE / "assets" / "gfx" / "bgtab1_dun.bin")
    bg2 = Archive(HERE / "assets" / "gfx" / "bgtab2_dun.bin")
    r = RoomRenderer(lv, bg1, bg2)
    r.draw_room(room)
    r.draw_foreground(room)
    r.scr.save_png(out)
    print(f"level {level_n} room {room} (kid starts in room "
          f"{lv.kid['room']}) -> {out}")


if __name__ == "__main__":
    main()

# Prince of Persia — Commodore 64 Port

Port of the Python reimplementation at `../PrinceOfPersiaPy` (itself a faithful
port of Jordan Mechner's Apple II original, driven by the original game data)
to the Commodore 64, written in 6502 assembly (ca65/ld65).

## Why this is tractable

- The original game was 6502 assembly. The Python port preserved the original
  **data tables verbatim**: SEQTABLE animation bytecode (~2.5KB), FRAMEDEF
  frame definitions (240 entries), the 2304-byte level format, LINKLOC/LINKMAP
  gate wiring. These run unchanged on a C64.
- The Apple II game logic lives in a 140×192 coordinate space (14px blocks ×10,
  63px rows ×3). C64 **multicolor bitmap mode is 160×200** — the geometry
  constants transfer 1:1, with 10px margins left/right and 8px for the HUD.
- The Python code (~4,000 lines, `src/`) is the readable spec for the engine
  logic: sequence interpreter (`entities/char.py`), control layer
  (`entities/player.py`), guard AI (`entities/guard.py`), tile machinery
  (`levels/level.py`), collision/simulation (`game/game.py`).

## Target architecture

| Concern | Decision |
| --- | --- |
| Language | 6502 asm, ca65 + ld65 (installed, v2.19) |
| Distribution | `.prg` + `.d64` disk first; EasyFlash `.crt` if 14-level data outgrows disk loading (cartconv available) |
| Video | Multicolor bitmap 160×200 for rooms; playfield 140 wide centered |
| Characters | Hardware sprites, stacked/multiplexed; current animation frame unpacked on demand from packed CHTAB-style data (~12 fps game tick makes this cheap) |
| Game tick | 12.5/sec on PAL = every 4th frame (original: 12/sec) |
| Sound | SID versions of the 19 synthesized effects |
| Input | Joystick port 2 (+ keyboard fallback mapped like the Python port) |

### Memory budget (per level, resident)

| Item | Est. size |
| --- | --- |
| Engine code | 12–16 KB |
| SEQTABLE + FRAMEDEF + misc tables | ~5 KB |
| Level (original packed format) | 2.3 KB |
| Kid image tables (CHTAB1+2 packed) | ~18 KB |
| Objects/sword (CHTAB3, CHTAB5 subset) | ~8 KB |
| Guard variant for level (one of CHTAB4.*) | 5–9 KB |
| BG tileset (BGTAB1+2, DUN or PAL) | ~14 KB |
| Bitmap + screen matrix | 9 KB (double-buffer decision in Phase 2) |

Tight but feasible with per-level loading; kid-only Level 1 fits easily.
Original Apple II binary sizes measured from `source_reference/01 POP Source/Images/`.

## Asset pipeline (`tools/`, Python, runs on host)

Converts from `../PrinceOfPersiaPy/assets/` + `source_reference/`:

1. `convert_levels.py` — level JSON → packed binary (original-format-derived)
2. `convert_bgtab.py` — background piece PNGs → C64 multicolor cell data + fixed palette mapping
3. `convert_chtab.py` — character frame PNGs → packed sprite-convertible frames
4. `convert_anim.py` — SEQTABLE/FRAMEDEF → `.s` include files (nearly verbatim)

Palette: Apple II artifact colors (black/white/orange/blue + green/purple) map
onto the C64 fixed multicolor set per 4×8 cell — needs experimentation in Phase 1.

## Phases

- [x] **0. Walking skeleton** — ca65+VICE toolchain, Makefile, headless
      screenshot smoke test (`make test`)
- [x] **1. Asset pipeline** — converters for levels/bgtab/chtab/anim data;
      palette experiments; measure real converted sizes
- [x] **2. Room renderer** — draw Level 1 Room 1 from BGDATA piece tables into
      the bitmap; port the C/B/A/D block-section drawing model; room-to-room
      redraw; screenshot-compare against the Python renderer
- [x] **3. Kid animation** — sequence interpreter (14 opcodes) + FRAMEDEF frame
      advance; sprite compositing/multiplex; stand/turn/run on one screen
- [x] **4. Movement & collision** — full control layer (jumps, climbs, hang,
      falls, damage thresholds), barrier collision, room transitions with
      camera cuts
- [ ] **5. Tile machinery** — plates→gates wiring, exit door, loose floors,
      spikes, slicers, potions, sword pickup
- [ ] **6. Guards & combat** — guard AI (skill table), engarde, strike/parry/
      block, health, per-level guard variants
- [ ] **7. Game flow** — title, HUD (health/level/time), death/restart, level
      progression, 60-minute limit
- [ ] **8. Sound** — SID effect equivalents of the 19 synthesized effects
- [ ] **9. Ship it** — all 14 levels + demo, disk mastering (or EasyFlash),
      loading between levels, playtest pass

## Test strategy

Mirror the Python project's harness approach:
- `make test` — headless VICE (`-console -warp -limitcycles -exitscreenshot`)
  produces a PNG per run; compare against expected screenshots
- Scripted input via VICE monitor/keybuf injection for movement scenarios
- The Python port's recordings (`recordings/`, `state.jsonl` per tick) are
  ground truth for simulation behavior — same seed inputs should produce the
  same tile/position traces

## Reference map (Python → C64)

| Python module | C64 target |
| --- | --- |
| `game/constants.py` | `src/constants.inc` |
| `data/seqdata.py`, `data/framedefs.py` | generated `src/data/*.s` |
| `entities/char.py` | `src/char.s` (sequence interpreter) |
| `entities/player.py` | `src/player.s` |
| `entities/guard.py` | `src/guard.s` |
| `levels/level.py` | `src/level.s` |
| `graphics/render.py`, `graphics/bgdata.py` | `src/render.s` |
| `game/game.py` | `src/game.s`, `src/main.s` |
| `game/sound.py` | `src/sound.s` (SID) |

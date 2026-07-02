# Prince of Persia — Commodore 64

A port of [PrinceOfPersiaPy](../PrinceOfPersiaPy) (a faithful Python
reimplementation of the 1989 Apple II original, driven by the original game
data) to the Commodore 64, in 6502 assembly.

**Status: playable demo.** Level 1 renders from the original level data in
multicolor bitmap mode; the kid is fully controllable — running, turning,
standing and running jumps, careful steps, crouching, climbing up and down,
hanging from ledges, falling with the original damage thresholds, wall and
gate collision — all driven by the original SEQTABLE animation bytecode and
FRAMEDEF frame tables. See [PLAN.md](PLAN.md) for architecture and roadmap.

## Building

Requires `cc65` and `vice` (`brew install cc65 vice`), plus the sibling
`../PrinceOfPersiaPy` checkout (with `source_reference/`) to regenerate
assets.

```bash
make assets   # regenerate data tables + graphics from ../PrinceOfPersiaPy
make          # build build/pop.prg
make run      # build and launch in VICE (x64sc)
make d64      # master build/pop.d64
make test     # headless smoke test, screenshot to build/test_shot.png
```

## Controls (joystick port 2)

| Input | Action |
| --- | --- |
| left / right | turn, run |
| up | jump, climb up |
| down | crouch, climb down over an edge |
| fire + direction | careful step |
| fire (while falling) | grab a ledge |
| fire (while hanging) | keep holding on |

## Debugging & testing

- `make ASFLAGS=-DTESTSCRIPT` builds with a scripted input feed
  (`tscript` in `src/main.s`) instead of the joystick — deterministic
  headless runs for verification.
- VICE remote monitor is the state channel:
  `x64sc -remotemonitor -remotemonitoraddress 127.0.0.1:6510 ...`, then
  `echo "m 0050 0060" | nc 127.0.0.1 6510` dumps the kid struct
  (see `src/pop.inc` for the zeropage layout).
- `tools/read_debug.py` decodes the on-screen debug cells from
  screenshots taken of TESTSCRIPT builds.

## Legal

The original Prince of Persia is © Jordan Mechner; the franchise belongs to
Ubisoft. This port is for educational and preservation purposes only and must
not be distributed commercially.

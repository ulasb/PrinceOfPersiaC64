# Prince of Persia — Commodore 64

A port of [PrinceOfPersiaPy](../PrinceOfPersiaPy) (a faithful Python
reimplementation of the 1989 Apple II original, driven by the original game
data) to the Commodore 64, in 6502 assembly.

See [PLAN.md](PLAN.md) for architecture and roadmap.

## Building

Requires `cc65` and `vice` (`brew install cc65 vice`).

```bash
make          # build build/pop.prg
make run      # build and launch in VICE (x64sc)
make test     # headless smoke test, screenshot to build/test_shot.png
```

## Legal

The original Prince of Persia is © Jordan Mechner; the franchise belongs to
Ubisoft. This port is for educational and preservation purposes only and must
not be distributed commercially.

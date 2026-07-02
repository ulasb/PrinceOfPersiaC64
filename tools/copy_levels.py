#!/usr/bin/env python3
"""Copy the original 2304-byte LEVEL blueprints into assets/levels/.

The original Apple II binary level format (BLUETYPE/BLUESPEC/LINKLOC/LINKMAP/
MAP/INFO — see PrinceOfPersiaPy/src/tools/export_levels.py) is used on the
C64 unchanged; no conversion needed.
"""

import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[1]
SRC = HERE.parent / "PrinceOfPersiaPy" / "source_reference" / "01 POP Source" / "Levels"
OUT = HERE / "assets" / "levels"

BLUEPRINT_SIZE = 2304


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    ok = True
    for n in range(15):
        src = SRC / f"LEVEL{n}"
        if not src.exists():
            print(f"missing: {src}")
            ok = False
            continue
        size = src.stat().st_size
        if size != BLUEPRINT_SIZE:
            print(f"bad size {size}: {src}")
            ok = False
            continue
        shutil.copy(src, OUT / f"level{n:02d}.bin")
    print(f"copied {15 if ok else '<15'} levels to assets/levels/ "
          f"({BLUEPRINT_SIZE} bytes each)")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

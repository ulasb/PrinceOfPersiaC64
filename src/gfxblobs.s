; Packed graphics windows produced by tools/convert_gfx.py.
; GFX1/GFX2 run in place; GFXH loads in the VIC hole and is copied to $e000.

        .export gfxh_start, gfxh_end

        .segment "GFX1"
        .incbin "../assets/gfx/gfx_gfx1.bin"

        .segment "GFX2"
        .incbin "../assets/gfx/gfx_gfx2.bin"

        .segment "GFXH"
gfxh_start:
        .incbin "../assets/gfx/gfx_gfxh.bin"
gfxh_end:

; Packed graphics windows produced by tools/convert_gfx.py.
; GFX1/GFX9/GFXC run in place; GFXH loads in the bitmap hole and is
; copied to $e000 at init.

        .export gfxh_start, gfxh_end

        .segment "GFX1"
        .incbin "../assets/gfx/gfx_gfx1.bin"

        .segment "GFX9"
        .incbin "../assets/gfx/gfx_gfx9.bin"

        .segment "GFXC"
        .incbin "../assets/gfx/gfx_gfxc.bin"

        .segment "GFXH"
gfxh_start:
        .incbin "../assets/gfx/gfx_gfxh.bin"
gfxh_end:

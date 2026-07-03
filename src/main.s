; Prince of Persia C64 — startup and main loop.

        .include "pop.inc"

        .import blit_init, draw_room, draw_foreground
        .import LEVEL
        .import gfxh_start, gfxh_end
        .import char_init, kid_draw, kid_restore, spr_hide
        .import game_tick, kid_spawn, kid_getcol
        .import tiles_init, tiles_reset, tiles_redraw, draw_falling

        .segment "LOADADDR"
        .addr   $0801

; BASIC stub: 10 SYS 2062
        .segment "EXEHDR"
        .word   next_line
        .word   10
        .byte   $9e
        .byte   "2062"
        .byte   0
next_line:
        .word   0

        .segment "STARTUP"
entry:
        sei
        ldx #$ff
        txs
        lda #$35                ; RAM everywhere but I/O
        sta $01

        ; hardware vectors in RAM (KERNAL is banked out for good)
        lda #<int_stub
        sta $fffa
        sta $fffe
        lda #>int_stub
        sta $fffb
        sta $ffff

        ; silence the CIAs
        lda #$7f
        sta $dc0d
        sta $dd0d
        lda $dc0d
        lda $dd0d

        ; move graphics destined above the KERNAL area: $5c00 -> $e000
        lda #<gfxh_start
        sta zp_src
        lda #>gfxh_start
        sta zp_src+1
        lda #<$e000
        sta zp_dst
        lda #>$e000
        sta zp_dst+1
        ldx #>(gfxh_end - gfxh_start)   ; whole pages
        inx                             ; + partial page
        ldy #0
@copy:  lda (zp_src),y
        sta (zp_dst),y
        iny
        bne @copy
        inc zp_src+1
        inc zp_dst+1
        dex
        bne @copy

        ; VIC: bank 2 ($8000), bitmap $a000, matrix $8c00, multicolor
        lda $dd02
        ora #$03
        sta $dd02
        lda $dd00
        and #$fc
        ora #$01
        sta $dd00
        lda #$3b                ; bitmap mode on
        sta $d011
        lda #$d8                ; multicolor
        sta $d016
        lda #$38                ; matrix $8c00, bitmap $a000
        sta $d018
        lda #0
        sta $d020
        sta $d021

        ; cell colors: %01 white, %10 orange (matrix), %11 light blue (color RAM)
        ldx #0
@cols:  lda #$18
        sta VIC_MATRIX,x
        sta VIC_MATRIX+$100,x
        sta VIC_MATRIX+$200,x
        sta VIC_MATRIX+$2e8,x
        lda #14
        sta $d800,x
        sta $d900,x
        sta $da00,x
        sta $dae8,x
        inx
        bne @cols

        ; kid = sprites 0-5: multicolor, colors map the 2bpp codes directly
        lda #%00111111
        sta $d01c               ; multicolor on
        lda #0
        sta $d017               ; no expansion
        sta $d01d
        sta $d015               ; hidden until the first frame
        sta $d01b               ; sprites in front of the bitmap
        sta $d010
        lda #1                  ; %01 = white
        sta $d025
        lda #14                 ; %11 = light blue
        sta $d026
        ldx #5
        lda #8                  ; %10 = orange
@sprc:  sta $d027,x
        dex
        bpl @sprc
        ldx #5
@sprp:  txa
        clc
        adc #SPRBLK
        sta SPRPTR,x
        dex
        bpl @sprp

        ; CIA port A as input for joystick 2
        lda #0
        sta $dc02

        jsr blit_init
        jsr char_init
        jsr tiles_init
        lda #0
        sta zp_frame
        sta zp_previn
        sta zp_vskip
        sta zp_lvdone
        lda #4
        sta zp_tcnt
.ifdef TESTSCRIPT
        lda #0
        sta script_idx
        sta script_left
        sta script_val
.endif
        jsr kid_spawn

; ---------------------------------------------------------- main loop
mainloop:
        ; wait for the vblank raster line
@wait:  lda $d012
        cmp #251
        bne @wait
@wait2: lda $d012
        cmp #251
        beq @wait2              ; make sure we pass it only once
        inc zp_frame
        dec zp_tcnt
        beq @tick
        jmp mainloop
@tick:  lda #4                  ; game tick every 4th frame = 12.5/s (PAL)
        sta zp_tcnt
        jsr read_input
        lda zp_previn
        eor #$ff
        and zp_input
        sta zp_inedge
        lda zp_input
        sta zp_previn

        jsr game_tick

        ; reached the exit: flash and restart the level
        lda zp_lvdone
        beq @notdone
        jsr victory_flash
        lda #0
        sta zp_lvdone
        jsr tiles_reset
        jsr kid_spawn
@notdone:
        ; room change: full redraw
        lda zp_moved
        beq @noredraw
        lda #0
        sta zp_moved
        lda zp_visroom
        sta zp_room
        jsr draw_room
        jsr draw_foreground
        jmp @drawkid
@noredraw:
        jsr tiles_redraw
        jsr draw_falling
@drawkid:
        lda kid_room
        cmp zp_visroom
        beq :+
        jsr spr_hide
        jmp @nokid
:       jsr kid_draw
@nokid:
.ifdef TESTSCRIPT
        jsr dbg_dump
.endif
        jmp mainloop

; white border flourish on finishing the level
victory_flash:
        ldx #0
@fl:    lda #1
        sta $d020
        ldy #0
@d1:    dey
        bne @d1
        lda #0
        sta $d020
        ldy #0
@d2:    dey
        bne @d2
        inx
        cpx #150
        bne @fl
        rts

.ifdef TESTSCRIPT
; dump kid state into the HUD strip as raw bitmap bytes (each state byte
; fills one 4x8 cell; tools/read_debug.py decodes them from screenshots)
DBGROW = BITMAP + 30*8       ; top row, cells 30-39
dbg_dump:
        ldx #0                  ; X = entry index * 2
@next:  lda dbgsrc,x
        sta zp_ptr
        lda dbgsrc+1,x
        sta zp_ptr+1
        ldy #0
        lda (zp_ptr),y
        sta zp_tmp
        txa
        pha
        asl
        asl                     ; cell offset = (x/2)*8 = x*4
        tay
        lda zp_tmp
        ldx #8
@f8:    sta DBGROW,y
        iny
        dex
        bne @f8
        pla
        tax
        inx
        inx
        cpx #(dbgsrc_end - dbgsrc)
        bcc @next
        rts
dbgsrc: .addr kid_frame, kid_action, kid_x, kid_x+1, kid_y, kid_y+1
        .addr kid_row, kid_seq, kid_seq+1, zp_input
dbgsrc_end:

; scripted input for headless runs: (tick count, input byte) pairs.
; count 0 ends the script; count $fe = seek: careful-step until the kid
; stands on column <value>, then advance (closed-loop positioning).
read_input:
        lda script_left
        bne @feed
        ldx script_idx
        lda tscript,x
        beq @off                ; terminator
        cmp #$fe
        beq @seek
        sta script_left
        lda tscript+1,x
        sta script_val
        inx
        inx
        stx script_idx
@feed:  dec script_left
        lda script_val
        sta zp_input
        rts
@off:   lda #0
        sta zp_input
        rts
@seek:  ; only act from a standing frame; otherwise idle this tick
        lda kid_frame
        cmp #15
        beq :+
        lda #0
        sta zp_input
        rts
:       jsr kid_getcol
        ldx script_idx
        cmp tscript+1,x
        bne @step
        inx                     ; arrived: consume the entry
        inx
        stx script_idx
        lda #0
        sta zp_input
        rts
@step:  ; one careful step toward the target
        bcc @right              ; kid col < target
        lda #IN_SHIFT|IN_LEFT
        sta zp_input
        rts
@right: lda #IN_SHIFT|IN_RIGHT
        sta zp_input
        rts

tscript:
        .byte 6, 0              ; entry drop
        .byte 40, IN_RIGHT      ; to the bottom row, over the loose tile
        .byte 24, 0             ; loose floor breaks
        .byte 20, IN_LEFT       ; into the hole, fall to room 2
        .byte 16, 0
        .byte 200, IN_RIGHT     ; rooms 2 -> 3 -> 9, bump the right wall
        .byte 12, 0
        .byte $fe, 1            ; seek the column beside the plate pillar
        .byte 4, 0
        .byte 30, IN_UP|IN_SHIFT ; climb onto the pressure plate
        .byte 10, 0
        .byte 30, IN_UP|IN_SHIFT ; (second try if the first grab slipped)
        .byte 40, 0             ; stand on the plate; exit door opens
        .byte 14, IN_RIGHT      ; run off the plate, drop to the corridor
        .byte 14, 0
        .byte $fe, 3            ; seek the exit stairs tile
        .byte 4, 0
        .byte 12, IN_UP         ; up the stairs!
        .byte 20, 0
        .byte $fe, 4            ; (or the second door tile)
        .byte 4, 0
        .byte 12, IN_UP
        .byte 150, 0            ; victory
        .byte 0

        .segment "BSS"
script_idx:  .res 1
script_left: .res 1
script_val:  .res 1
        .segment "CODE"
.else
; joystick 2 (active low): bits 0-4 = up dn lt rt fire
read_input:
        lda $dc00
        eor #$ff
        and #$1f
        sta zp_input
        rts
.endif

int_stub:
        rti

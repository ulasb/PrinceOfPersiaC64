; Prince of Persia C64 — startup and main loop.

        .include "pop.inc"

        .import blit_init, draw_room, draw_foreground, draw_front_block
        .import LEVEL
        .import gfxh_start, gfxh_end
        .import char_init, kid_draw, kid_restore
        .import game_tick, kid_spawn, kid_getcol

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

        ; CIA port A as input for joystick 2
        lda #0
        sta $dc02

        jsr blit_init
        jsr char_init
        lda #0
        sta zp_frame
        sta zp_previn
        lda #3
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
@tick:  lda #3                  ; game tick every 3rd frame (PAL)
        sta zp_tcnt
        jsr read_input
        lda zp_previn
        eor #$ff
        and zp_input
        sta zp_inedge
        lda zp_input
        sta zp_previn

        jsr game_tick

        ; room change: full redraw
        lda zp_moved
        beq @noredraw
        lda #0
        sta zp_moved
        jsr invalidate_save
        lda zp_visroom
        sta zp_room
        jsr draw_room
        jsr draw_foreground
        jmp @drawkid
@noredraw:
        jsr kid_restore
@drawkid:
        lda kid_room
        cmp zp_visroom
        bne @nokid
        jsr kid_draw
        jsr fronts_near_kid
@nokid:
.ifdef TESTSCRIPT
        jsr dbg_dump
.endif
        jmp mainloop

invalidate_save:
        lda #0
        sta $79                 ; sv_valid (char.s)
        rts

; redraw foreground pieces on the 3x3 blocks around the kid so he appears
; behind posts, gates and pillar fronts
fronts_near_kid:
        lda zp_visroom
        sta zp_rm
        jsr kid_getcol
        sec
        sbc #1
        sta zp_fcol             ; start col
        lda kid_row
        sec
        sbc #1
        sta zp_frow             ; start row
        ldx #0
@rowl:  txa
        clc
        adc zp_frow
        cmp #$ff                ; -1 is a valid row
        beq @rowok
        cmp #3
        bcs @nextrow
@rowok: sta zp_drow
        ldy #0
@coll:  tya
        clc
        adc zp_fcol
        cmp #$ff                ; -1 is a valid col
        beq @colok
        cmp #11
        bcs @nextcol
@colok: sta zp_dcol
        tya
        pha
        txa
        pha
        jsr draw_front_block
        pla
        tax
        pla
        tay
@nextcol:
        iny
        cpy #3
        bne @coll
@nextrow:
        inx
        cpx #3
        bne @rowl
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

; scripted input for headless runs: (tick count, input byte) pairs,
; count 0 ends the script (input stays 0)
read_input:
        lda script_left
        bne @feed
        ldx script_idx
        lda tscript,x
        beq @off                ; terminator
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

tscript:
        .byte 6, 0              ; settle (entry drop)
        .byte 40, IN_RIGHT      ; off the ledge to the bottom corridor
        .byte 12, 0
        .byte 200, IN_LEFT      ; run left through the room link
        .byte 30, 0
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

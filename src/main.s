; Prince of Persia C64 — startup and main loop.

        .include "pop.inc"

        .import blit_init, draw_room, draw_foreground, LEVEL
        .import gfxh_start, gfxh_end

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

        ; VIC: bank 1 ($4000), bitmap $6000, matrix $5c00, multicolor
        lda $dd02
        ora #$03
        sta $dd02
        lda $dd00
        and #$fc
        ora #$02
        sta $dd00
        lda #$3b                ; bitmap mode on
        sta $d011
        lda #$d8                ; multicolor
        sta $d016
        lda #$78                ; matrix $5c00, bitmap $6000
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

        jsr blit_init

        ; draw the kid's starting room
        lda LEVEL+LV_INFO+64
        sta zp_room
        jsr draw_room
        jsr draw_foreground

hang:   jmp hang

int_stub:
        rti

; Prince of Persia C64 — walking skeleton
; Sets up a stable raster loop and proves the build pipeline works.

        .include "c64.inc"

        .export _main := entry

        .segment "LOADADDR"
        .addr   $0801           ; PRG load address

; BASIC stub: 10 SYS 2062
        .segment "EXEHDR"
        .word   next_line
        .word   10              ; line number
        .byte   $9e             ; SYS token
        .byte   "2062"
        .byte   0
next_line:
        .word   0

        .segment "STARTUP"
entry:
        sei
        lda #$35                ; RAM + I/O, no BASIC/KERNAL ROM
        sta $01

        lda #$00
        sta VIC_BORDERCOLOR
        sta VIC_BG_COLOR0

        ; clear screen
        ldx #$00
        lda #$20                ; space
clr:    sta $0400,x
        sta $0500,x
        sta $0600,x
        sta $06e8,x
        inx
        bne clr

        ; write "POP C64" via screen codes at row 12, col 16
        ldx #0
msg_loop:
        lda message,x
        beq main_loop
        sta $0400 + 12*40 + 16,x
        lda #$01                ; white
        sta $d800 + 12*40 + 16,x
        inx
        bne msg_loop

main_loop:
        ; simple frame-synced border flash to prove we're alive
wait_raster:
        lda VIC_HLINE
        cmp #$ff
        bne wait_raster
        inc frame_count
        jmp main_loop

message:
        .byte 16, 15, 16, 32, 3, 54, 52, 0   ; "POP C64" screen codes

        .segment "BSS"
frame_count:
        .res 1

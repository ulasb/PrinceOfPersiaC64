; Character engine: the original SEQTABLE bytecode interpreter (ANIMCHAR),
; FRAMEDEF frame decoding, and kid rendering (runtime mirror into a compose
; buffer + masked blit with save-under restore).

        .include "pop.inc"

        .export kid_animate, kid_draw, kid_restore, kid_start_seq
        .export char_init, kid_frame_chk
        .import SEQTABLE
        .import FD_MAIN_IMAGE, FD_MAIN_SWORD, FD_MAIN_DX, FD_MAIN_DY
        .import FD_MAIN_CHK
        .import IMG_CH1_LO, IMG_CH1_HI, IMG_CH2_LO, IMG_CH2_HI
        .import IMG_CH3_LO, IMG_CH3_HI
        .import blit_ll

; local zeropage
zp_guard  = $70
zp_fimg   = $71
zp_fsw    = $72
zp_fdx    = $73             ; s8, hi-res half pixels
zp_fdy    = $74             ; s8
zp_ftab   = $75
zp_fx     = $76             ; 2  s16 hi-res x
zp_i      = $78
sv_valid  = $79
sv_bc     = $7a             ; first saved byte column
sv_ncols  = $7b
sv_ytop   = $7c
sv_nrows  = $7d
sv_ptr    = $7e             ; 2  walking SAVEBUF pointer
zp_ycur2  = $8f             ; row walker for capture/restore

        .segment "CODE"

char_init:
        ; TAB_REV: reverse the four 2-bit pairs of a byte
        ldx #0
@rev:   txa
        and #$03
        asl
        asl
        asl
        asl
        asl
        asl
        sta zp_tmp
        txa
        and #$0c
        asl
        asl
        ora zp_tmp
        sta zp_tmp
        txa
        and #$30
        lsr
        lsr
        ora zp_tmp
        sta zp_tmp
        txa
        and #$c0
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        ora zp_tmp
        sta TAB_REV,x
        inx
        bne @rev
        lda #0
        sta sv_valid
        rts

; ----------------------------------------------------- start a sequence
; in: A/X = lo/hi of the sequence offset
kid_start_seq:
        sta kid_seq
        stx kid_seq+1
        rts

; ------------------------------------------------- sequence interpreter
; fetch next bytecode byte -> A; advances kid_seq
seq_fetch:
        clc
        lda #<SEQTABLE
        adc kid_seq
        sta zp_ptr
        lda #>SEQTABLE
        adc kid_seq+1
        sta zp_ptr+1
        ldy #0
        lda (zp_ptr),y
        inc kid_seq
        bne :+
        inc kid_seq+1
:       rts

kid_animate:
        lda #100
        sta zp_guard
anim_loop:
        dec zp_guard
        beq @out
        jsr seq_fetch
        cmp #$f1
        bcs @op
        sta kid_frame           ; display frame (incl. blank 0)
@out:   rts
@op:    sec
        sbc #$f1
        asl
        tax
        lda OPTBL,x
        sta zp_tmp
        lda OPTBL+1,x
        sta zp_tmp+1
        jmp (zp_tmp)

OPTBL:  .addr op_nextlevel, op_tap, op_effect, op_jard, op_jaru
        .addr op_die, op_ifwtless, op_setfall, op_act, op_chy
        .addr op_chx, op_down, op_up, op_aboutface, op_goto2

op_goto2:
        jsr seq_fetch           ; lo
        sta zp_tmp+2
        jsr seq_fetch           ; hi (absolute address in the $3000 space)
        sec
        sbc #$30
        sta kid_seq+1
        lda zp_tmp+2
        sta kid_seq
        jmp anim_loop
op_aboutface:
        sec
        lda #0
        sbc kid_face
        sta kid_face
        jmp anim_loop
op_up:
        dec kid_row
        jmp anim_loop
op_down:
        inc kid_row
        jmp anim_loop
op_chx:
        jsr seq_fetch           ; signed delta, applied along facing
        ldx kid_face
        bmi @back
        jsr addx_signed
        jmp anim_loop
@back:  jsr subx_signed
        jmp anim_loop
op_chy:
        jsr seq_fetch
        tax
        clc
        adc kid_y
        sta kid_y
        txa
        bmi @n
        lda kid_y+1
        adc #0
        sta kid_y+1
        jmp anim_loop
@n:     lda kid_y+1
        adc #$ff
        sta kid_y+1
        jmp anim_loop
op_act:
        jsr seq_fetch
        sta kid_action
        jmp anim_loop
op_setfall:
        jsr seq_fetch
        sta kid_xvel
        jsr seq_fetch
        sta kid_yvel
        jmp anim_loop
op_ifwtless:
        jsr seq_fetch           ; no float potions yet: skip the target
        jsr seq_fetch
        jmp anim_loop
op_die:
        lda #0
        sta kid_alive
        lda kid_events
        ora #1
        sta kid_events
        jmp anim_loop
op_jaru:
        lda kid_events
        ora #4
        sta kid_events
        jmp anim_loop
op_jard:
        lda kid_events
        ora #8
        sta kid_events
        jmp anim_loop
op_effect:
        jsr seq_fetch           ; effect argument unused for now
        jmp anim_loop
op_tap:
        jsr seq_fetch           ; tap sound id unused for now
        jmp anim_loop
op_nextlevel:
        lda kid_events
        ora #2
        sta kid_events
        jmp anim_loop

; x += sext(A) / x -= sext(A)
addx_signed:
        tax
        clc
        adc kid_x
        sta kid_x
        txa
        bmi @n
        lda kid_x+1
        adc #0
        sta kid_x+1
        rts
@n:     lda kid_x+1
        adc #$ff
        sta kid_x+1
        rts
subx_signed:
        tax
        sec
        eor #$ff
        clc
        adc #1                  ; A = -delta
        jmp addx_signed

; ------------------------------------------------------ frame check byte
; out: A = Fcheck byte of the current frame (0 for blank)
kid_frame_chk:
        ldx kid_frame
        beq @blank
        dex
        lda FD_MAIN_CHK,x
        rts
@blank: lda #0
        rts

; ------------------------------------------------------------- kid_draw
; Decode the current frame, compose (mirror if facing right), capture the
; save-under rect and blit. Uses the original positioning rules:
;   fx = 2*x + dx*face (hi-res); mirrored blit x = fx - (w - 7)
kid_draw:
        lda kid_frame
        bne :+
        rts
:       tax
        dex
        lda FD_MAIN_IMAGE,x
        sta zp_fimg
        lda FD_MAIN_SWORD,x
        sta zp_fsw
        lda FD_MAIN_DX,x
        sta zp_fdx
        lda FD_MAIN_DY,x
        sta zp_fdy
        ; table = ((img & $80) >> 5) | ((sword & $c0) >> 6)
        lda zp_fimg
        and #$80
        lsr
        lsr
        lsr
        lsr
        lsr
        sta zp_ftab
        lda zp_fsw
        rol                     ; c = bit7
        rol
        rol
        and #$03
        ora zp_ftab
        sta zp_ftab
        ; image pointer
        lda zp_fimg
        and #$7f
        tax
        lda zp_ftab
        beq @ch1
        cmp #1
        beq @ch2
        cmp #2
        beq @ch3
        rts                     ; table not resident (special frames)
@ch1:   lda IMG_CH1_LO,x
        sta zp_img
        lda IMG_CH1_HI,x
        sta zp_img+1
        jmp @have
@ch2:   lda IMG_CH2_LO,x
        sta zp_img
        lda IMG_CH2_HI,x
        sta zp_img+1
        jmp @have
@ch3:   lda IMG_CH3_LO,x
        sta zp_img
        lda IMG_CH3_HI,x
        sta zp_img+1
@have:  lda zp_img
        ora zp_img+1
        bne :+
        rts
:
        ; fx = 2*kid_x + dx*face   (hi-res, s16)
        lda kid_x
        asl
        sta zp_fx
        lda kid_x+1
        rol
        sta zp_fx+1
        lda zp_fdx
        ldx kid_face
        bmi @dxneg
        jsr add_fx_signed
        jmp @dxdone
@dxneg: eor #$ff
        clc
        adc #1
        jsr add_fx_signed
@dxdone:
        ; bottom = kid_y + sext(fdy)
        lda kid_y
        sta zp_by
        lda kid_y+1
        sta zp_by+1
        lda zp_fdy
        tax
        clc
        adc zp_by
        sta zp_by
        txa
        bmi @dyn
        lda zp_by+1
        adc #0
        sta zp_by+1
        jmp @dydone
@dyn:   lda zp_by+1
        adc #$ff
        sta zp_by+1
@dydone:
        ; facing right = mirrored (images face left)
        lda kid_face
        bmi @noflip
        jsr compose_flip        ; zp_img -> COMPOSE, sets zp_wb
        ; x_mc = ((fx+6)>>1) - 4*wb + 1
        clc
        lda zp_fx
        adc #6
        sta zp_fx
        lda zp_fx+1
        adc #0
        sta zp_fx+1
        jsr fx_half
        ; subtract 4*wb - 1
        lda zp_wb
        asl
        asl
        sta zp_tmp
        sec
        lda zp_bx
        sbc zp_tmp
        sta zp_bx
        lda zp_bx+1
        sbc #0
        sta zp_bx+1
        inc zp_bx
        bne :+
        inc zp_bx+1
:       jmp @place
@noflip:
        jsr fx_half
@place:
        ; playfield margin
        clc
        lda zp_bx
        adc #PLAYFIELD_X
        sta zp_bx
        lda zp_bx+1
        adc #0
        sta zp_bx+1
        jsr save_capture
        jmp blit_ll

add_fx_signed:
        tax
        clc
        adc zp_fx
        sta zp_fx
        txa
        bmi @n
        lda zp_fx+1
        adc #0
        sta zp_fx+1
        rts
@n:     lda zp_fx+1
        adc #$ff
        sta zp_fx+1
        rts

; zp_bx = zp_fx >> 1 (arithmetic)
fx_half:
        lda zp_fx+1
        cmp #$80
        ror
        sta zp_bx+1
        lda zp_fx
        ror
        sta zp_bx
        rts

; ---------------------------------------------------------- compose_flip
; Mirror the image at zp_img into COMPOSE (header + reversed rows);
; leaves zp_img -> COMPOSE, zp_wb = width bytes.
compose_flip:
        ldy #0
        lda (zp_img),y
        sta zp_wb
        sta COMPOSE
        iny
        lda (zp_img),y
        sta zp_h
        sta COMPOSE+1
        ; src = img+2, dst walks COMPOSE+2 row by row
        clc
        lda zp_img
        adc #2
        sta zp_src
        lda zp_img+1
        adc #0
        sta zp_src+1
        lda #<(COMPOSE+2)
        sta zp_dst
        lda #>(COMPOSE+2)
        sta zp_dst+1
        ldx zp_h
@row:   ldy zp_wb
        dey
        sty zp_i                ; dst index runs wb-1 .. 0
        ldy #0
@byte:  lda (zp_src),y
        sty zp_tmp
        tay
        lda TAB_REV,y
        ldy zp_i
        sta (zp_dst),y
        dec zp_i
        ldy zp_tmp
        iny
        cpy zp_wb
        bne @byte
        ; advance both pointers one row
        clc
        lda zp_src
        adc zp_wb
        sta zp_src
        bcc :+
        inc zp_src+1
:       clc
        lda zp_dst
        adc zp_wb
        sta zp_dst
        bcc :+
        inc zp_dst+1
:       dex
        bne @row
        lda #<COMPOSE
        sta zp_img
        lda #>COMPOSE
        sta zp_img+1
        rts

; --------------------------------------------------------- save-under
; capture the bitmap under the blit described by zp_img/zp_bx/zp_by
save_capture:
        ; geometry: cols bc0..bc0+wb (inclusive), rows top..bottom
        ldy #0
        lda (zp_img),y
        sta zp_wb
        iny
        lda (zp_img),y
        sta zp_h
        ; first byte column (signed >> 2)
        lda zp_bx+1
        bmi @negx
        lda zp_bx
        lsr
        lsr
        jmp @gotbc
@negx:  lda zp_bx
        lsr
        lsr
        ora #$c0
@gotbc: sta sv_bc
        ; ncols = wb+1 clipped to [0,40)
        lda zp_wb
        clc
        adc #1
        sta sv_ncols
        lda sv_bc
        bpl @bcok
        ; clip left: bc<0
        clc
        adc sv_ncols            ; cols remaining right of 0
        bmi @none
        beq @none
        sta sv_ncols
        lda #0
        sta sv_bc
@bcok:  ; clip right
        lda sv_bc
        cmp #40
        bcs @none
        clc
        adc sv_ncols
        cmp #41
        bcc @cols_ok
        lda #40
        sec
        sbc sv_bc
        sta sv_ncols
@cols_ok:
        ; rows: top = by - (h-1), clip to [0,191]
        ldx zp_h
        dex
        stx zp_tmp
        sec
        lda zp_by
        sbc zp_tmp
        sta zp_tmp              ; top lo
        lda zp_by+1
        sbc #0
        bmi @topclip
        bne @none               ; top >= 256: off screen
        lda zp_tmp
        cmp #192
        bcs @none
        sta sv_ytop
        jmp @bot
@topclip:
        lda #0
        sta sv_ytop
@bot:   ; bottom row = min(by, 191)
        lda zp_by+1
        bmi @none
        bne @b191
        lda zp_by
        cmp #192
        bcc @gotbot
@b191:  lda #191
@gotbot:
        sec
        sbc sv_ytop
        bcc @none
        clc
        adc #1
        sta sv_nrows
        ; colx8 = sv_bc * 8 (16-bit)
        lda #0
        sta colx8hi
        lda sv_bc
        asl
        rol colx8hi
        asl
        rol colx8hi
        asl
        rol colx8hi
        sta colx8lo
        jmp @copy
@none:  lda #0
        sta sv_valid
        rts
@copy:  ; copy rect -> SAVEBUF
        lda #<SAVEBUF
        sta sv_ptr
        lda #>SAVEBUF
        sta sv_ptr+1
        lda sv_ytop
        sta zp_ycur2
        ldx sv_nrows
@rows:  txa
        pha
        ldx zp_ycur2
        clc
        lda ROWLO,x
        adc colx8lo
        sta zp_dst
        lda ROWHI,x
        adc colx8hi
        sta zp_dst+1
        ldy #0
        sty zp_i
@col:   lda zp_i
        asl
        asl
        asl
        tay
        lda (zp_dst),y
        ldy zp_i
        sta (sv_ptr),y
        inc zp_i
        lda zp_i
        cmp sv_ncols
        bne @col
        ; advance save pointer
        clc
        lda sv_ptr
        adc sv_ncols
        sta sv_ptr
        bcc :+
        inc sv_ptr+1
:       inc zp_ycur2
        pla
        tax
        dex
        bne @rows
        lda #1
        sta sv_valid
        rts

; sv_bc*8 as a 16-bit constant pair, refreshed before each copy loop
colx8lo:.byte 0
colx8hi:.byte 0

; restore the previously saved rect
kid_restore:
        lda sv_valid
        bne :+
        rts
:       lda #<SAVEBUF
        sta sv_ptr
        lda #>SAVEBUF
        sta sv_ptr+1
        lda sv_ytop
        sta zp_ycur2
        ldx sv_nrows
@rows:  txa
        pha
        ldx zp_ycur2
        clc
        lda ROWLO,x
        adc colx8lo
        sta zp_dst
        lda ROWHI,x
        adc colx8hi
        sta zp_dst+1
        ldy #0
        sty zp_i
@col:   ldy zp_i
        lda (sv_ptr),y
        pha
        lda zp_i
        asl
        asl
        asl
        tay
        pla
        sta (zp_dst),y
        inc zp_i
        lda zp_i
        cmp sv_ncols
        bne @col
        clc
        lda sv_ptr
        adc sv_ncols
        sta sv_ptr
        bcc :+
        inc sv_ptr+1
:       inc zp_ycur2
        pla
        tax
        dex
        bne @rows
        lda #0
        sta sv_valid
        rts

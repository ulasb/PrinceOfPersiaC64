; Character engine: the original SEQTABLE bytecode interpreter (ANIMCHAR),
; FRAMEDEF frame decoding, and kid rendering (runtime mirror into a compose
; buffer + masked blit with save-under restore).

        .include "pop.inc"

        .export kid_animate, kid_draw, kid_restore, kid_start_seq
        .export save_invalidate
        .export char_init, kid_frame_chk, spr_hide, sword_hide
        .export frame_def, rle_decode
        .import SEQTABLE
        .import FD_MAIN_IMAGE, FD_MAIN_SWORD, FD_MAIN_DX, FD_MAIN_DY
        .import FD_MAIN_CHK
        .import FD_ALT1_IMAGE, FD_ALT1_SWORD, FD_ALT1_DX, FD_ALT1_DY
        .import FD_ALT1_CHK
        .import SWORDTAB_F0, SWORDTAB_F1, SWORDTAB_F2
        .import IMG_CH1_LO, IMG_CH1_HI, IMG_CH2_LO, IMG_CH2_HI
        .import IMG_CH3_LO, IMG_CH3_HI, IMG_CH4_LO, IMG_CH4_HI
        .import IMG_CH5_LO, IMG_CH5_HI
        .import blit_ll

; local zeropage
zp_swfx   = $6f             ; 2? no: fx snapshot lo (hi in zp_swfx2)
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
        ; SPRROW tables: grid row gr (0..62) -> SPRBUF + (gr/21)*128 + (gr%21)*3
        lda #<SPRBUF
        sta zp_ptr
        lda #>SPRBUF
        sta zp_ptr+1
        ldx #0                  ; gr
        ldy #0                  ; row within sprite
@srow:  lda zp_ptr
        sta SPRROWL,x
        lda zp_ptr+1
        sta SPRROWH,x
        clc
        lda zp_ptr
        adc #3
        sta zp_ptr
        bcc :+
        inc zp_ptr+1
:       iny
        cpy #21
        bne @snext
        ; next sprite row: skip the right-column block (+128-63 = +65)
        clc
        lda zp_ptr
        adc #65
        sta zp_ptr
        lda zp_ptr+1
        adc #0
        sta zp_ptr+1
        ldy #0
@snext: inx
        cpx #63
        bne @srow
        rts

; ------------------------------------------------------- rle decoder
; Character images are stored column-major RLE (ctrl < $80: ctrl+1
; literals; ctrl >= $80: repeat next byte (ctrl&$7f)+2 times).
; in: zp_img -> compressed; out: DECOMP holds the raw image, zp_img -> DECOMP
rle_decode:
        ; already decoded? (DECOMP still holds the last image)
        lda zp_img
        cmp rc_last
        bne @miss
        lda zp_img+1
        cmp rc_last+1
        bne @miss
        jmp @hit
@miss:  lda zp_img
        sta rc_last
        lda zp_img+1
        sta rc_last+1
        ldy #0
        lda (zp_img),y
        sta DECOMP
        sta zp_wb
        iny
        lda (zp_img),y
        sta DECOMP+1
        sta zp_h
        clc
        lda zp_img
        adc #2
        sta zp_src
        lda zp_img+1
        adc #0
        sta zp_src+1
        lda #<(DECOMP+2)
        sta zp_t0
        sta zp_dst
        lda #>(DECOMP+2)
        sta zp_t0+1
        sta zp_dst+1
        lda zp_h
        sta zp_t0+2             ; rows left in this column
        lda zp_wb
        sta zp_t0+3             ; columns left
        ldy #0
@loop:  lda (zp_src),y          ; control byte
        inc zp_src
        bne :+
        inc zp_src+1
:       tax
        bmi @run
        ; literal: X+1 bytes follow
        inx
        stx zp_t0+4
@lit:   lda (zp_src),y
        inc zp_src
        bne :+
        inc zp_src+1
:       sta (zp_dst),y
        lda zp_dst
        clc
        adc zp_wb
        sta zp_dst
        bcc :+
        inc zp_dst+1
:       dec zp_t0+2
        beq @lcol
@lnext: dec zp_t0+4
        bne @lit
        beq @loop
@lcol:  jsr next_col
        bcc @lnext
        jmp @hit                ; all columns done
@run:   txa
        and #$7f
        clc
        adc #2
        sta zp_t0+4
        lda (zp_src),y          ; run value
        inc zp_src
        bne :+
        inc zp_src+1
:       sta zp_t0+5
@rn:    lda zp_t0+5
        sta (zp_dst),y
        lda zp_dst
        clc
        adc zp_wb
        sta zp_dst
        bcc :+
        inc zp_dst+1
:       dec zp_t0+2
        beq @rcol
@rnext: dec zp_t0+4
        bne @rn
        beq @loop
@rcol:  jsr next_col
        bcc @rnext
        jmp @hit
@hit:   lda #<DECOMP
        sta zp_img
        lda #>DECOMP
        sta zp_img+1
        rts

; advance to the next output column; carry set when the image is done
next_col:
        lda zp_h
        sta zp_t0+2
        inc zp_t0
        bne :+
        inc zp_t0+1
:       lda zp_t0
        sta zp_dst
        lda zp_t0+1
        sta zp_dst+1
        dec zp_t0+3
        beq @done
        clc
        rts
@done:  sec
        rts

        .segment "BSS"
rc_last:.res 2              ; image pointer currently in DECOMP
        .segment "CODE"

; invalidate the decode cache (level restart safety)
        .export rle_cache_clear
rle_cache_clear:
        lda #0
        sta rc_last
        sta rc_last+1
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
        ldx #$34                ; the table lives under the I/O area
        stx $01
        lda (zp_ptr),y
        ldx #$35
        stx $01
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
        jsr seq_fetch           ; argument unused; flag the event
        lda kid_events
        ora #16
        sta kid_events
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

; -------------------------------------------------- frame definition
; Look up the current frame for the active character (zp_chid): guards
; remap falling frames 102-106 (+70) and take 150-189 from ALTSET1.
; out: zp_fimg/zp_fsw/zp_fdx/zp_fdy loaded, A = Fcheck byte
frame_def:
        ldx kid_frame
        bne :+
        lda #0
        rts
:       lda zp_chid
        beq @main
        cpx #102
        bcc @gnorm
        cpx #107
        bcs @gnorm
        txa
        clc
        adc #70
        tax
@gnorm: cpx #150
        bcc @main
        cpx #190
        bcs @main
        txa
        sec
        sbc #150                ; FD_ALT1 covers frames 150-189
        tax
        lda FD_ALT1_IMAGE,x
        sta zp_fimg
        lda FD_ALT1_SWORD,x
        sta zp_fsw
        lda FD_ALT1_DX,x
        sta zp_fdx
        lda FD_ALT1_DY,x
        sta zp_fdy
        lda FD_ALT1_CHK,x
        rts
@main:  dex
        lda FD_MAIN_IMAGE,x
        sta zp_fimg
        lda FD_MAIN_SWORD,x
        sta zp_fsw
        lda FD_MAIN_DX,x
        sta zp_fdx
        lda FD_MAIN_DY,x
        sta zp_fdy
        lda FD_MAIN_CHK,x
        rts

; out: A = Fcheck byte of the current frame (0 for blank)
kid_frame_chk:
        jmp frame_def

; ------------------------------------------------------------- kid_draw
; Decode the current frame, compose (mirror if facing right), capture the
; save-under rect and blit. Uses the original positioning rules:
;   fx = 2*x + dx*face (hi-res); mirrored blit x = fx - (w - 7)
kid_draw:
        lda kid_frame
        bne :+
        jmp char_hide
:       jsr frame_def
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
        cmp #3
        beq @ch4
        cmp #4
        beq @ch5
        jmp char_hide           ; table not resident
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
        jmp @have
@ch4:   lda IMG_CH4_LO,x
        sta zp_img
        lda IMG_CH4_HI,x
        sta zp_img+1
        jmp @have
@ch5:   lda IMG_CH5_LO,x
        sta zp_img
        lda IMG_CH5_HI,x
        sta zp_img+1
@have:  lda zp_img
        ora zp_img+1
        bne :+
        jmp char_hide
:       jsr rle_decode

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
        lda zp_fx
        sta zp_swfx             ; sword overlay anchors at the raw fx
        lda zp_fx+1
        sta zp_gr+1             ; (borrow: zp_gr+1 unused between frames)
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
        lda zp_chid
        beq :+
        jsr save_capture        ; guards: software blit with save-under
        jmp blit_ll
:       jmp kid_sprites

; hide whichever character failed to resolve a frame
char_hide:
        lda zp_chid
        bne :+
        jmp spr_hide
:       rts

; ------------------------------------------------- kid as hardware sprites
; Pack the image at zp_img into the 6-sprite grid (24x63, bottom-anchored)
; and position/enable the sprites at (zp_bx, zp_by).
kid_sprites:
        ldy #0
        lda (zp_img),y
        sta zp_wb
        cmp #7
        bcc :+
        lda #6                  ; wider frames lose their trailing edge
:       sta zp_cw
        iny
        lda (zp_img),y
        sta zp_h
        cmp #64
        bcc :+
        jmp spr_hide            ; defensive
:       clc
        lda zp_img
        adc #2
        sta zp_src
        lda zp_img+1
        adc #0
        sta zp_src+1
        ; clear the sprite blocks
        lda #0
        ldx #0
@clr:   sta SPRBUF,x
        sta SPRBUF+$80,x
        sta SPRBUF+$100,x
        inx
        bpl @clr                ; 128 bytes each
        ; first grid row = 63 - h
        lda #63
        sec
        sbc zp_h
        sta zp_gr
@row:   ; stage up to 6 source bytes (rest stay zero)
        lda #0
        sta zp_t0
        sta zp_t0+1
        sta zp_t0+2
        sta zp_t0+3
        sta zp_t0+4
        sta zp_t0+5
        ldy #0
        ldx #0
@fetch: cpx zp_cw
        bcs @stage
        lda (zp_src),y
        sta zp_t0,x
        iny
        inx
        bne @fetch
@stage: ldx zp_gr
        lda SPRROWL,x
        sta zp_dst
        lda SPRROWH,x
        sta zp_dst+1
        ldy #0
        lda zp_t0
        sta (zp_dst),y
        iny
        lda zp_t0+1
        sta (zp_dst),y
        iny
        lda zp_t0+2
        sta (zp_dst),y
        ldy #64
        lda zp_t0+3
        sta (zp_dst),y
        iny
        lda zp_t0+4
        sta (zp_dst),y
        iny
        lda zp_t0+5
        sta (zp_dst),y
        ; next source row
        clc
        lda zp_src
        adc zp_wb
        sta zp_src
        bcc :+
        inc zp_src+1
:       inc zp_gr
        lda zp_gr
        cmp #63
        bne @row

; position: sprite y = 50 + (by - 62) = by - 12; x = 24 + 2*bx
        sec
        lda zp_by
        sbc #12
        tax                     ; y of the top sprite row
        lda zp_by+1
        sbc #0
        bmi spr_hide            ; too high up: transient, just hide
        txa
        sta $d001
        sta $d003
        clc
        adc #21
        sta $d005
        sta $d007
        adc #21
        sta $d009
        sta $d00b
        ; x: 16-bit
        lda zp_bx
        asl
        sta zp_t0
        lda zp_bx+1
        rol
        sta zp_t0+1
        clc
        lda zp_t0
        adc #24
        sta zp_t0
        lda zp_t0+1
        adc #0
        sta zp_t0+1             ; sx16
        clc
        lda zp_t0
        adc #24
        sta zp_t0+2
        lda zp_t0+1
        adc #0
        sta zp_t0+3             ; sx16 + 24 (right column)
        lda zp_t0
        sta $d000
        sta $d004
        sta $d008
        lda zp_t0+2
        sta $d002
        sta $d006
        sta $d00a
        ; x msb bits: sprites 0,2,4 = left col; 1,3,5 = right col
        ldx #0
        lda zp_t0+1
        beq :+
        ldx #%00010101
:       lda zp_t0+3
        beq :+
        txa
        ora #%00101010
        tax
:       stx $d010
        lda $d015
        ora #%00111111
        sta $d015
        rts

spr_hide:
        lda $d015
        and #%11000000
        sta $d015
        rts

sword_hide:
        lda $d015
        and #%00111111
        sta $d015
        rts

; ---------------------------------------------------- kid sword overlay
; Draw the sword as sprites 6-7 (2 wide x 1 tall, bottom-anchored 21).
; Call right after kid_draw: zp_fsw/zp_swfx/face/kid_y are still valid.
        .export kid_sword_draw
kid_sword_draw:
        lda zp_fsw
        and #$3f
        bne :+
        jmp sword_hide
:       tax
        lda SWORDTAB_F0,x
        bne :+
        jmp sword_hide
:       sta zp_tmp
        lda SWORDTAB_F1,x
        sta zp_fdx              ; sword dx (hi-res, signed)
        lda SWORDTAB_F2,x
        sta zp_fdy              ; sword dy (signed)
        ldx zp_tmp
        lda IMG_CH3_LO,x
        sta zp_img
        lda IMG_CH3_HI,x
        sta zp_img+1
        ora zp_img
        bne :+
        jmp sword_hide
:       jsr rle_decode
        ; sx = swfx + sdx*face
        lda zp_swfx
        sta zp_fx
        lda zp_gr+1
        sta zp_fx+1
        lda zp_fdx
        ldx kid_face
        bmi @neg
        jsr add_fx_signed
        jmp @sx
@neg:   eor #$ff
        clc
        adc #1
        jsr add_fx_signed
@sx:    ; bottom = kid_y + sext(sdy)
        lda kid_y
        sta zp_by
        lda kid_y+1
        sta zp_by+1
        lda zp_fdy
        jsr add_by_signed
        ; mirror when facing right, then x math as for the kid
        lda kid_face
        bmi @nof
        jsr compose_flip
        clc
        lda zp_fx
        adc #6
        sta zp_fx
        lda zp_fx+1
        adc #0
        sta zp_fx+1
        jsr fx_half
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
:       jmp @pl
@nof:   jsr fx_half
@pl:    clc
        lda zp_bx
        adc #PLAYFIELD_X
        sta zp_bx
        lda zp_bx+1
        adc #0
        sta zp_bx+1
        ; pack into the 2 sword sprite blocks (24x21 grid)
        ldy #0
        lda (zp_img),y
        sta zp_wb
        cmp #7
        bcc :+
        lda #6
:       sta zp_cw
        iny
        lda (zp_img),y
        sta zp_h
        clc
        lda zp_img
        adc #2
        sta zp_src
        lda zp_img+1
        adc #0
        sta zp_src+1
        ; clip images taller than 21: skip their top rows
        lda zp_h
        cmp #22
        bcc @hok
        sec
        sbc #21
        tax                     ; rows to skip
@skip:  clc
        lda zp_src
        adc zp_wb
        sta zp_src
        bcc :+
        inc zp_src+1
:       dex
        bne @skip
        lda #21
        sta zp_h
@hok:   ; clear both blocks
        lda #0
        ldx #63
@sclr:  sta SWSPR,x
        sta SWSPR+64,x
        dex
        bpl @sclr
        ; rows, bottom-anchored in the 21-row grid
        lda #21
        sec
        sbc zp_h
        sta zp_gr
@srow:  lda #0
        sta zp_t0
        sta zp_t0+1
        sta zp_t0+2
        sta zp_t0+3
        sta zp_t0+4
        sta zp_t0+5
        ldy #0
        ldx #0
@sf:    cpx zp_cw
        bcs @sst
        lda (zp_src),y
        sta zp_t0,x
        iny
        inx
        bne @sf
@sst:   ; dst = SWSPR + gr*3 (left) / +64 (right)
        lda zp_gr
        asl
        clc
        adc zp_gr               ; *3
        tax
        lda zp_t0
        sta SWSPR,x
        lda zp_t0+1
        sta SWSPR+1,x
        lda zp_t0+2
        sta SWSPR+2,x
        lda zp_t0+3
        sta SWSPR+64,x
        lda zp_t0+4
        sta SWSPR+65,x
        lda zp_t0+5
        sta SWSPR+66,x
        clc
        lda zp_src
        adc zp_wb
        sta zp_src
        bcc :+
        inc zp_src+1
:       inc zp_gr
        lda zp_gr
        cmp #21
        bne @srow
        ; position sprites 6-7: y = 50 + (by - 20)
        sec
        lda zp_by
        sbc #<-30
        clc
        lda zp_by
        clc
        adc #30
        sta $d00d
        sta $d00f
        ; x = 24 + 2*bx
        lda zp_bx
        asl
        sta zp_t0
        lda zp_bx+1
        rol
        sta zp_t0+1
        clc
        lda zp_t0
        adc #24
        sta zp_t0
        lda zp_t0+1
        adc #0
        sta zp_t0+1
        lda zp_t0
        sta $d00c
        clc
        adc #24
        sta $d00e
        php
        ; msb bits 6-7
        lda $d010
        and #%00111111
        sta zp_tmp
        lda zp_t0+1
        beq :+
        lda zp_tmp
        ora #%01000000
        sta zp_tmp
:       plp
        lda zp_t0+1
        adc #0                  ; carry from the +24
        beq :+
        lda zp_tmp
        ora #%10000000
        sta zp_tmp
:       lda zp_tmp
        sta $d010
        lda $d015
        ora #%11000000
        sta $d015
        rts

; zp_by += sext(A) (shared)
add_by_signed:
        tax
        clc
        adc zp_by
        sta zp_by
        txa
        bmi @n
        lda zp_by+1
        adc #0
        sta zp_by+1
        rts
@n:     lda zp_by+1
        adc #$ff
        sta zp_by+1
        rts

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
save_invalidate:
        lda #0
        sta sv_valid
        rts

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

; Masked software blitter for 2bpp piece images.
;
; Images: u8 wbytes, u8 height, rows top-down, 4 px/byte MSB-first,
; pixel code 0 = transparent. Blits are lower-left anchored like the
; original engine, clipped to the 160x192 playfield, at any x (the two
; low bits of x select a 2/4/6-bit shift done via lookup tables).

        .include "pop.inc"

        .export blit_init, blit_ll

; extra zeropage (local to the blitter)
zp_b      = $18
zp_jmin   = $19
zp_ycur   = $1a
zp_colofs = $1b             ; 2  bc0*8, s16
zp_jend   = $1d             ; jmax+1

        .segment "CODE"

; ---------------------------------------------------------------- init
blit_init:
        ; ROWLO/ROWHI: bitmap address of scanline y (0..199)
        lda #<BITMAP
        sta zp_tmp
        lda #>BITMAP
        sta zp_tmp+1
        ldx #0
@charrow:
        ldy #0
@scan:  tya
        clc
        adc zp_tmp
        sta ROWLO,x
        lda zp_tmp+1
        adc #0
        sta ROWHI,x
        inx
        iny
        cpy #8
        bne @scan
        lda zp_tmp
        clc
        adc #<320
        sta zp_tmp
        lda zp_tmp+1
        adc #>320
        sta zp_tmp+1
        cpx #200
        bcc @charrow

        ; shift tables
        ldx #0
@sh:    txa
        lsr
        lsr
        sta TAB_SHR2,x
        lsr
        lsr
        sta TAB_SHR4,x
        lsr
        lsr
        sta TAB_SHR6,x
        txa
        asl
        asl
        sta TAB_SHL2,x
        asl
        asl
        sta TAB_SHL4,x
        asl
        asl
        sta TAB_SHL6,x
        inx
        bne @sh

        ; TAB_MASK: $c0/$30/$0c/$03 where the data pair is 00
        ldx #0
@mk:    lda #0
        sta zp_tmp
        txa
        and #$c0
        bne :+
        lda #$c0
        sta zp_tmp
:       txa
        and #$30
        bne :+
        lda zp_tmp
        ora #$30
        sta zp_tmp
:       txa
        and #$0c
        bne :+
        lda zp_tmp
        ora #$0c
        sta zp_tmp
:       txa
        and #$03
        bne :+
        lda zp_tmp
        ora #$03
        sta zp_tmp
:       lda zp_tmp
        sta TAB_MASK,x
        inx
        bne @mk
        rts

; -------------------------------------------------------------- blit_ll
; in: zp_img -> image, zp_bx s16 x (mc px), zp_by s16 bottom y
blit_ll:
        ldy #0
        lda (zp_img),y
        bne :+                  ; defensive: zero-width record
        rts
:       sta zp_wb
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

        ; top = by - (h-1); clip top
        ldx zp_h
        dex
        stx zp_tmp
        sec
        lda zp_by
        sbc zp_tmp
        sta zp_ytop
        lda zp_by+1
        sbc #0
        sta zp_ytop+1
        lda #0
        sta zp_srow
        lda zp_ytop+1
        bpl @topok
        sec                     ; top < 0: srow = -top (h<=192 so 8 bits)
        lda #0
        sbc zp_ytop
        sta zp_srow
        lda #0
        sta zp_ytop
        sta zp_ytop+1
@topok:
        ; clip bottom to 191
        lda zp_by+1
        bmi @off0               ; fully above? (bottom < 0)
        bne @clipb
        lda zp_by
        cmp #192
        bcc @byok
@clipb: lda #191
        sta zp_by
        lda #0
        sta zp_by+1
@byok:
        lda zp_ytop+1
        bne @off0
        lda zp_ytop
        cmp #192
        bcs @off0
        ; nrows = by - top + 1
        sec
        lda zp_by
        sbc zp_ytop
        bcc @off0
        clc
        adc #1
        sta zp_nrows
        ; src += srow * wb
        ldx zp_srow
        beq @noskip
@mul:   clc
        lda zp_src
        adc zp_wb
        sta zp_src
        bcc :+
        inc zp_src+1
:       dex
        bne @mul
@noskip:
        ; shift & byte column
        lda zp_bx
        and #3
        sta zp_shift
        lda zp_bx+1
        bmi @negx
        lda zp_bx
        lsr
        lsr
        sta zp_bc0
        jmp @bcok
@off0:  rts
@negx:  lda zp_bx
        lsr
        lsr
        ora #$c0                ; arithmetic >>2 for x in -16..-1
        sta zp_bc0
@bcok:
        ; jmin = max(0, -bc0); jend = min(wb, 39-bc0) + 1
        lda #0
        sta zp_jmin
        lda zp_bc0
        bpl :+
        eor #$ff
        clc
        adc #1
        sta zp_jmin
:       lda #39
        sec
        sbc zp_bc0
        cmp zp_wb               ; out bytes run 0..wb inclusive
        bcc :+
        lda zp_wb
:       clc
        adc #1
        sta zp_jend
        cmp zp_jmin
        bcc @off0
        beq @off0
        ; colofs = bc0 * 8 (sign extended)
        lda zp_bc0
        sta zp_colofs
        and #$80
        beq :+
        lda #$ff
:       sta zp_colofs+1
        ldx #3
@x8:    asl zp_colofs
        rol zp_colofs+1
        dex
        bne @x8
        lda zp_ytop
        sta zp_ycur

; ------------------------------------------------------------- row loop
@row:
        ; phase A: shift source row into ROWBUF[0..wb]
        lda #0
        sta zp_prev
        ldy #0
        ldx zp_shift
        bne :+
        jmp @copyrow
:       cpx #2
        beq @sh4
        bcc @sh2
; shift by 6 bits (x&3 == 3)
@sh6:   cpy zp_wb
        bcc :+
        jmp @last6
:
        lda (zp_src),y
        sta zp_b
        tax
        lda TAB_SHR6,x
        sta zp_val
        ldx zp_prev
        lda TAB_SHL2,x
        ora zp_val
        sta ROWBUF,y
        lda zp_b
        sta zp_prev
        iny
        jmp @sh6
@last6: ldx zp_prev
        lda TAB_SHL2,x
        sta ROWBUF,y
        jmp @phaseb
; shift by 2 bits
@sh2:   cpy zp_wb
        bcs @last2
        lda (zp_src),y
        sta zp_b
        tax
        lda TAB_SHR2,x
        sta zp_val
        ldx zp_prev
        lda TAB_SHL6,x
        ora zp_val
        sta ROWBUF,y
        lda zp_b
        sta zp_prev
        iny
        jmp @sh2
@last2: ldx zp_prev
        lda TAB_SHL6,x
        sta ROWBUF,y
        jmp @phaseb
; shift by 4 bits
@sh4:   cpy zp_wb
        bcs @last4
        lda (zp_src),y
        sta zp_b
        tax
        lda TAB_SHR4,x
        sta zp_val
        ldx zp_prev
        lda TAB_SHL4,x
        ora zp_val
        sta ROWBUF,y
        lda zp_b
        sta zp_prev
        iny
        jmp @sh4
@last4: ldx zp_prev
        lda TAB_SHL4,x
        sta ROWBUF,y
        jmp @phaseb
; no shift
@copyrow:
        cpy zp_wb
        bcs @cr0
        lda (zp_src),y
        sta ROWBUF,y
        iny
        jmp @copyrow
@cr0:   lda #0
        sta ROWBUF,y

@phaseb:
        ; dst = ROW[ycur] + colofs
        ldx zp_ycur
        clc
        lda ROWLO,x
        adc zp_colofs
        sta zp_dst
        lda ROWHI,x
        adc zp_colofs+1
        sta zp_dst+1
        ldx zp_jmin
@wr:    lda ROWBUF,x
        beq @skip
        sta zp_val
        stx zp_j
        txa
        asl
        asl
        asl
        tay
        ldx zp_val
        lda (zp_dst),y
        and TAB_MASK,x
        ora zp_val
        sta (zp_dst),y
        ldx zp_j
@skip:  inx
        cpx zp_jend
        bne @wr

        ; next row
        clc
        lda zp_src
        adc zp_wb
        sta zp_src
        bcc :+
        inc zp_src+1
:       inc zp_ycur
        dec zp_nrows
        beq :+
        jmp @row
:       rts

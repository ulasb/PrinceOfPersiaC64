; Level blueprint access (original 2304-byte format, loaded verbatim).
;
; Queries take room in zp_rm and signed col/row in zp_tc/zp_tr (col may be
; -1..10, row -1..3); neighbours resolve through the MAP link table. Out
; of the map reads as solid wall.

        .include "pop.inc"

        .export lv_tile, lv_spec, lv_link, LEVEL

        .segment "RODATA"
LEVEL:  .incbin "../assets/levels/level01.bin"

; (room-1)*30 for rooms 1..24
ROOM30LO:
        .repeat 24, I
        .byte <(I*30)
        .endrepeat
ROOM30HI:
        .repeat 24, I
        .byte >(I*30)
        .endrepeat
ROW10:  .byte 0, 10, 20

        .segment "CODE"

; in: A = room (1..24), X = direction (0 left, 1 right, 2 up, 3 down)
; out: A = neighbour room (0 = none); preserves X
lv_link:
        tay
        dey
        tya
        asl
        asl
        sta zp_tmp
        txa
        clc
        adc zp_tmp
        tay
        lda LEVEL+LV_MAP,y
        rts

; resolve (zp_rm, zp_tc, zp_tr) -> zp_rrm, zp_rc, zp_rr
lv_resolve:
        lda zp_rm
        sta zp_rrm
        lda zp_tc
        sta zp_rc
        lda zp_tr
        sta zp_rr
        ; horizontal
        lda zp_rc
        bpl @notleft
        clc
        adc #10
        sta zp_rc
        lda zp_rrm
        beq @vert
        ldx #0                  ; left
        jsr lv_link
        sta zp_rrm
        jmp @vert
@notleft:
        cmp #10
        bcc @vert
        sec
        sbc #10
        sta zp_rc
        lda zp_rrm
        beq @vert
        ldx #1                  ; right
        jsr lv_link
        sta zp_rrm
@vert:
        lda zp_rrm
        beq @done
        lda zp_rr
        bpl @notup
        clc
        adc #3
        sta zp_rr
        lda zp_rrm
        ldx #2                  ; up
        jsr lv_link
        sta zp_rrm
        jmp @done
@notup:
        cmp #3
        bcc @done
        sec
        sbc #3
        sta zp_rr
        lda zp_rrm
        ldx #3                  ; down
        jsr lv_link
        sta zp_rrm
@done:  rts

; point zp_ptr at LEVEL + base(A/X = lo/hi) + (rrm-1)*30, Y = rr*10+rc
lv_calc:
        clc
        adc #<LEVEL
        sta zp_ptr
        txa
        adc #>LEVEL
        sta zp_ptr+1
        ldx zp_rrm
        dex
        clc
        lda zp_ptr
        adc ROOM30LO,x
        sta zp_ptr
        lda zp_ptr+1
        adc ROOM30HI,x
        sta zp_ptr+1
        ldx zp_rr
        lda ROW10,x
        clc
        adc zp_rc
        tay
        rts

; tile at (zp_rm, zp_tc, zp_tr) -> A (also zp_tile)
lv_tile:
        jsr lv_resolve
        lda zp_rrm
        bne @in
        lda #T_BLOCK
        sta zp_tile
        rts
@in:    lda #<LV_BLUETYPE
        ldx #>LV_BLUETYPE
        jsr lv_calc
        lda (zp_ptr),y
        and #$1f
        sta zp_tile
        rts

; spec at (zp_rm, zp_tc, zp_tr) -> A (also zp_spec)
lv_spec:
        jsr lv_resolve
        lda zp_rrm
        bne @in
        lda #0
        sta zp_spec
        rts
@in:    lda #<LV_BLUESPEC
        ldx #>LV_BLUESPEC
        jsr lv_calc
        lda (zp_ptr),y
        sta zp_spec
        rts

; Room renderer — port of the original drawing model (FRAMEADV.S via the
; Python port's render.py): every block draws the C-section of the piece
; below-left, the B-section of the piece to the left, then its own A- and
; D-sections. Foreground fronts are drawn over characters afterwards.
;
; Dynamic tiles are drawn in rest state for now (gates closed, spikes in,
; loose floors still, torch flame frame 0).

        .include "pop.inc"

        .export draw_room, draw_foreground, draw_front_block, piece_at
        .import blit_ll, lv_tile, lv_spec
        .import IMG_BG1_LO, IMG_BG1_HI, IMG_BG2_LO, IMG_BG2_HI
        .import BG_PIECEA, BG_PIECEAY, BG_PIECEB, BG_PIECEBY, BG_PIECEC
        .import BG_PIECED, BG_FRONTI, BG_FRONTY, BG_FRONTX
        .import BG_GATE8B, BG_GATE8C, BG_SPIKEA, BG_SPIKEB
        .import BG_LOOSEA, BG_LOOSEBY, BG_LOOSED
        .import BG_SLICERBOT, BG_SLICERFRNT
        .import BG_BLOCKB, BG_BLOCKC, BG_BLOCKD, BG_BLOCKFR
        .import BG_PANELB, BG_PANELC, BG_SPACEB, BG_SPACEBY, BG_FLOORB
        .import BG_TORCHFLAME

; local zeropage
zp_tb     = $36             ; B-section neighbour tile
zp_gcol   = $37             ; gate draw column index
zp_segh   = $38             ; gate segment height

        .segment "RODATA"
; x = PLAYFIELD_X + col*TILE_W for col -1..12 (index col+1)
COLXLO: .repeat 14, I
        .byte <(PLAYFIELD_X + (I-1)*TILE_W)
        .endrepeat
COLXHI: .repeat 14, I
        .byte >(PLAYFIELD_X + (I-1)*TILE_W)
        .endrepeat
; byte_dx 0..3 -> mc px offset (Apple II byte = 3.5 px, floored)
BDXO:   .byte 0, 3, 7, 10
; block_bot / block_top for rows -1..3 (index row+1)
BBOTLO: .repeat 5, I
        .byte <(65 + (I-1)*ROW_H)
        .endrepeat
BBOTHI: .repeat 5, I
        .byte >(65 + (I-1)*ROW_H)
        .endrepeat
BTOPLO: .repeat 5, I
        .byte <(3 + (I-1)*ROW_H)
        .endrepeat
BTOPHI: .repeat 5, I
        .byte >(3 + (I-1)*ROW_H)
        .endrepeat

        .segment "CODE"

; ---------------------------------------------------------------- piece_at
; Blit piece A=image id (0 = none, bit7 = BGTAB2) at column index X
; (block col + 1), byte_dx Y; zp_by holds the bottom scanline (s16).
piece_at:
        cmp #0
        bne :+
        rts
:       sta zp_pid
        lda COLXLO,x
        clc
        adc BDXO,y
        sta zp_bx
        lda COLXHI,x
        adc #0
        sta zp_bx+1
        lda zp_pid
        bmi @bg2
        tax
        lda IMG_BG1_LO,x
        sta zp_img
        lda IMG_BG1_HI,x
        sta zp_img+1
        jmp @chk
@bg2:   and #$7f
        tax
        lda IMG_BG2_LO,x
        sta zp_img
        lda IMG_BG2_HI,x
        sta zp_img+1
@chk:   lda zp_img
        ora zp_img+1
        beq @none
        jmp blit_ll
@none:  rts

; helpers: load zp_by from the block anchors
set_by_dy:
        lda zp_dy
        sta zp_by
        lda zp_dy+1
        sta zp_by+1
        rts
set_by_ay:
        lda zp_ay
        sta zp_by
        lda zp_ay+1
        sta zp_by+1
        rts
; zp_by += sign-extended A
add_by:
        tax
        clc
        adc zp_by
        sta zp_by
        txa
        bmi @neg
        lda zp_by+1
        adc #0
        sta zp_by+1
        rts
@neg:   lda zp_by+1
        adc #$ff
        sta zp_by+1
        rts

; ---------------------------------------------------------------- rooms
; zp_room = room to draw; clears the playfield and draws all blocks
draw_room:
        jsr clear_playfield
        lda zp_room
        sta zp_rm
        lda #$ff                ; row -1
        sta zp_drow
@rowl:  lda #$ff                ; col -1
        sta zp_dcol
@coll:  jsr draw_block
        inc zp_dcol
        lda zp_dcol
        cmp #11
        bne @coll
        inc zp_drow
        lda zp_drow
        cmp #3
        bne @rowl
        rts

draw_foreground:
        lda zp_room
        sta zp_rm
        lda #$ff
        sta zp_drow
@rowl:  lda #$ff
        sta zp_dcol
@coll:  jsr draw_front_block
        inc zp_dcol
        lda zp_dcol
        cmp #11
        bne @coll
        inc zp_drow
        lda zp_drow
        cmp #3
        bne @rowl
        rts

clear_playfield:
        lda #<BITMAP
        sta zp_ptr
        lda #>BITMAP
        sta zp_ptr+1
        ldx #30                 ; 30 pages = 7680 bytes = 192 lines
        lda #0
        tay
@pg:    sta (zp_ptr),y
        iny
        bne @pg
        inc zp_ptr+1
        dex
        bne @pg
        rts

; --------------------------------------------------------------- anchors
set_anchors:
        ldx zp_drow
        inx
        lda BBOTLO,x
        sta zp_dy
        lda BBOTHI,x
        sta zp_dy+1
        sec
        lda zp_dy
        sbc #3
        sta zp_ay
        lda zp_dy+1
        sbc #0
        sta zp_ay+1
        rts

; ------------------------------------------------------------ draw_block
; Each section dispatches through a small handler chain; handlers are
; separate routines (jsr/rts) so branch ranges stay short.
draw_block:
        jsr set_anchors
        lda zp_dcol
        sta zp_tc
        lda zp_drow
        sta zp_tr
        jsr lv_tile
        sta zp_t
        jsr sect_c
        jsr sect_b
        jsr sect_a
        jmp sect_d

; ---- C-section: piece below-left (dcol-1, drow+1), anchored at dy
sect_c:
        lda zp_dcol
        sec
        sbc #1
        sta zp_tc
        lda zp_drow
        clc
        adc #1
        sta zp_tr
        jsr lv_tile
        cmp #T_BLOCK
        beq @c_block
        cmp #T_PANELWIF
        beq @c_panel
        cmp #T_PANELWOF
        beq @c_panel
        cmp #T_GATE
        beq @c_gate
        cmp #T_SLICER
        beq @c_none
        tax
        lda BG_PIECEC,x
        jmp piece_c_at
@c_block:
        jsr lv_spec
        cmp #2
        bcc :+
        lda #0
:       tax
        lda BG_BLOCKC,x
        jmp piece_c_at
@c_panel:
        jsr lv_spec
        cmp #3
        bcs @c_none
        tax
        lda BG_PANELC,x
        jmp piece_c_at
@c_gate:
        jmp gate_c
@c_none:
        rts

; ---- B-section: piece to the left (dcol-1, drow), anchor line ay
sect_b:
        lda zp_t
        cmp #T_BLOCK            ; hidden behind a solid block
        bne :+
        rts
:       lda zp_dcol
        sec
        sbc #1
        sta zp_tc
        lda zp_drow
        sta zp_tr
        jsr lv_tile
        sta zp_tb
        jsr lv_spec             ; zp_spec = sb
        lda zp_tb
        cmp #T_BLOCK
        beq @b_block
        cmp #T_PANELWIF
        beq @b_panel
        cmp #T_PANELWOF
        beq @b_panel
        cmp #T_SPIKES
        beq @b_spikes
        cmp #T_LOOSE
        beq @b_loose
        cmp #T_GATE
        beq @b_gate
        cmp #T_FLOOR
        beq @b_floor
        cmp #T_SPACE
        beq @b_space
        ; default: PIECEB + signed PIECEBY
        tax
        lda BG_PIECEB,x
        sta zp_pid
        jsr set_by_ay
        lda BG_PIECEBY,x
        jsr add_by
        jmp @b_draw
@b_block:
        lda zp_spec
        cmp #2
        bcc :+
        lda #0
:       tax
        lda BG_BLOCKB,x
        sta zp_pid
        jsr set_by_ay
        lda #2
        jsr add_by
        jmp @b_draw
@b_panel:
        lda zp_spec
        cmp #3
        bcs @b_none
        tax
        lda BG_PANELB,x
        sta zp_pid
        jsr set_by_ay
        lda #3
        jsr add_by
        jmp @b_draw
@b_spikes:
        ldx #0                  ; rest state
        lda BG_SPIKEB,x
        sta zp_pid
        jsr set_by_ay
        jmp @b_draw
@b_loose:
        lda #$1b                ; LOOSE_B
        sta zp_pid
        jsr set_by_ay
        lda #<-1
        jsr add_by
        jmp @b_draw
@b_gate:
        ldx zp_dcol             ; drawn into this block
        inx
        stx zp_gcol
        jmp gate_b
@b_floor:
        lda zp_spec
        cmp #4
        bcc :+
        lda #0
:       tax
        lda BG_FLOORB,x
        sta zp_pid
        jsr set_by_ay
        jmp @b_draw
@b_space:
        lda zp_spec
        beq @b_none
        cmp #4
        bcs @b_none
        tax
        lda BG_SPACEB,x
        sta zp_pid
        jsr set_by_ay
        lda BG_SPACEBY,x
        jsr add_by
@b_draw:
        lda zp_pid
        ldx zp_dcol
        inx
        ldy #0
        jmp piece_at
@b_none:
        rts

; ---- A-section (this block), anchor line ay
sect_a:
        lda zp_dcol
        sta zp_tc
        lda zp_drow
        sta zp_tr
        lda zp_t
        cmp #T_BLOCK
        beq @a_block
        cmp #T_SPIKES
        beq @a_spikes
        cmp #T_LOOSE
        beq @a_loose
        cmp #T_TORCH
        beq @a_torch
        cmp #T_EXIT
        beq @a_exit
        cmp #T_EXIT2
        beq @a_exit2
        cmp #T_SLICER
        bne :+
        jmp @a_slicer
:       cmp #T_FLASK
        bne :+
        jmp @a_flask
:       cmp #T_SWORD
        bne :+
        jmp @a_sword
:
        ; default: PIECEA + signed PIECEAY
        tax
        lda BG_PIECEA,x
        sta zp_pid
        jsr set_by_ay
        lda BG_PIECEAY,x
        jsr add_by
        lda zp_pid
        ldx zp_dcol
        inx
        ldy #0
        jmp piece_at
@a_block:
        jsr lv_spec
        cmp #2
        bcc :+
        lda #0
:       tax
        lda BG_BLOCKFR,x
        jmp piece_a_at
@a_spikes:
        ldx #0
        lda BG_SPIKEA,x
        jmp piece_a_at
@a_loose:
        ldx #0
        lda BG_LOOSEA,x
        jmp piece_a_at
@a_torch:
        ldx #T_TORCH
        lda BG_PIECEA,x
        jsr piece_a_at
        ; flame at (col+1, ay-43), one Apple byte right
        ldx #0
        lda BG_TORCHFLAME,x
        sta zp_pid
        jsr set_by_ay
        lda #<-43
        jsr add_by
        lda zp_pid
        ldx zp_dcol
        inx
        inx
        ldy #1
        jmp piece_at
@a_exit:
        ldx #T_FLOOR
        lda BG_PIECEA,x
        jsr piece_a_at
        lda #$6b                ; EXIT_STAIRS
        jmp piece_a_at
@a_exit2:
        ldx #T_FLOOR
        lda BG_PIECEA,x
        jsr piece_a_at
        lda #$6c                ; EXIT_DOOR (closed)
        jsr piece_a_at
        lda #$6e                ; EXIT_TOP
        sta zp_pid
        jsr set_by_ay
        lda #<-48
        jsr add_by
        lda zp_pid
        ldx zp_dcol
        inx
        ldy #0
        jmp piece_at
@a_slicer:
        ldx #T_FLOOR
        lda BG_PIECEA,x
        jsr piece_a_at
        ldx #0
        lda BG_SLICERBOT,x
        jmp piece_a_at
@a_flask:
        ldx #T_FLOOR
        lda BG_PIECEA,x
        jsr piece_a_at
        lda #$95                ; SPECIALFLASK
        sta zp_pid
        jsr set_by_ay
        lda #<-14
        jsr add_by
        lda zp_pid
        ldx zp_dcol
        inx
        ldy #2
        jmp piece_at
@a_sword:
        lda #$99                ; SWORDGLEAM0
        jmp piece_a_at

; ---- D-section (this block), anchored at dy
sect_d:
        lda zp_t
        cmp #T_BLOCK
        beq @d_block
        cmp #T_LOOSE
        beq @d_loose
        cmp #T_SLICER
        beq @d_slicer           ; slicer already drew its floor D
        tax
        lda BG_PIECED,x
        jmp piece_d_at
@d_block:
        lda zp_dcol
        sta zp_tc
        lda zp_drow
        sta zp_tr
        jsr lv_spec
        cmp #2
        bcc :+
        lda #0
:       tax
        lda BG_BLOCKD,x
        jmp piece_d_at
@d_loose:
        ldx #0
        lda BG_LOOSED,x
        jmp piece_d_at
@d_slicer:
        ldx #T_FLOOR
        lda BG_PIECED,x
        jmp piece_d_at

; small wrappers: piece at own column with ay/dy anchors
piece_a_at:
        sta zp_pid
        jsr set_by_ay
        lda zp_pid
        ldx zp_dcol
        inx
        ldy #0
        jmp piece_at
piece_d_at:
        sta zp_pid
        jsr set_by_dy
        lda zp_pid
        ldx zp_dcol
        inx
        ldy #0
        jmp piece_at
piece_c_at:
        sta zp_pid
        jsr set_by_dy
        lda zp_pid
        ldx zp_dcol
        inx
        ldy #0
        jmp piece_at

; ------------------------------------------------------------------ gates
; Closed gate (pos 0). B-strip: segments from block_bot(drow)-16 up to
; block_top(drow)-8, then the bottom piece. Draw column = zp_gcol.
gate_b:
        ldx zp_drow
        inx
        sec
        lda BBOTLO,x
        sbc #16
        sta zp_gy
        lda BBOTHI,x
        sbc #0
        sta zp_gy+1
        sec
        lda BTOPLO,x
        sbc #8
        sta zp_gtop
        lda BTOPHI,x
        sbc #0
        sta zp_gtop+1
        jsr gate_segments_b
        ; bottom piece at gy+4 (zp_gy is back at the strip bottom)
        ldx zp_drow
        inx
        sec
        lda BBOTLO,x
        sbc #16-4
        sta zp_by
        lda BBOTHI,x
        sbc #0
        sta zp_by+1
        lda #$44                ; GATEBOT_ORA
        ldx zp_gcol
        ldy #0
        jmp piece_at

; segment walker: draws GATE8B[7] every seg-height from zp_gy up to zp_gtop
gate_segments_b:
        lda BG_GATE8B+7
        sta zp_pid
        jmp gate_segments
gate_segments_c:
        lda BG_GATE8C
        sta zp_pid
gate_segments:
        ; seg height from the image header
        ldx zp_pid
        lda IMG_BG1_LO,x
        sta zp_ptr
        lda IMG_BG1_HI,x
        sta zp_ptr+1
        ora zp_ptr
        beq @done
        ldy #1
        lda (zp_ptr),y
        sta zp_segh
@loop:  ; while gy > gtop
        sec
        lda zp_gy
        sbc zp_gtop
        sta zp_tmp
        lda zp_gy+1
        sbc zp_gtop+1
        bmi @done
        ora zp_tmp
        beq @done
        lda zp_gy
        sta zp_by
        lda zp_gy+1
        sta zp_by+1
        lda zp_pid
        ldx zp_gcol
        ldy #0
        jsr piece_at
        sec
        lda zp_gy
        sbc zp_segh
        sta zp_gy
        lda zp_gy+1
        sbc #0
        sta zp_gy+1
        jmp @loop
@done:  rts

; C-strip of a gate at (dcol-1, drow+1): the bars visible in this block.
gate_c:
        ldx zp_drow
        inx
        inx                     ; gate row index (drow+1)+1
        sec
        lda BBOTLO,x
        sbc #16
        sta zp_gy
        lda BBOTHI,x
        sbc #0
        sta zp_gy+1
        ; y = min(bottom, block_top(gate row)+2)
        clc
        lda BTOPLO,x
        adc #2
        sta zp_tmp
        lda BTOPHI,x
        adc #0
        sta zp_tmp+1
        ; if gy > tmp -> gy = tmp
        sec
        lda zp_tmp
        sbc zp_gy
        lda zp_tmp+1
        sbc zp_gy+1
        bpl :+                  ; tmp >= gy, keep gy
        lda zp_tmp
        sta zp_gy
        lda zp_tmp+1
        sta zp_gy+1
:       sec
        lda BTOPLO,x
        sbc #10
        sta zp_gtop
        lda BTOPHI,x
        sbc #0
        sta zp_gtop+1
        ldx zp_dcol
        inx
        stx zp_gcol
        jmp gate_segments_c

; --------------------------------------------------------- foreground
draw_front_block:
        jsr set_anchors
        lda zp_dcol
        sta zp_tc
        lda zp_drow
        sta zp_tr
        jsr lv_tile
        sta zp_t
        cmp #T_BLOCK
        beq @done
        cmp #T_SLICER
        beq @slicer
        tax
        lda BG_FRONTI,x
        beq @gate_chk
        sta zp_pid
        jsr set_by_ay
        ldx zp_t
        lda BG_FRONTY,x
        jsr add_by
        ldx zp_t
        lda BG_FRONTX,x
        tay
        lda zp_pid
        ldx zp_dcol
        inx
        jsr piece_at
@gate_chk:
        lda zp_t
        cmp #T_GATE
        bne @done
        ldx zp_dcol
        inx
        inx                     ; bars drawn into the block to the right
        stx zp_gcol
        jsr gate_b
@done:  rts
@slicer:
        ldx #0
        lda BG_SLICERFRNT,x
        jsr piece_a_at
        rts

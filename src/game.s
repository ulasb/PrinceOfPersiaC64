; Per-tick simulation: gravity, falling, collision, landings, room
; normalization and spawn — ported from game.py (_post_move, _check_barrier,
; _unwall, _check_landing, _land) and char.py (apply_gravity, add_fall,
; normalize). Kid only; guards come later.

        .include "pop.inc"

        .export game_tick, kid_spawn
        .export kid_getcol, div14, mul14, k_tile, k_isfloor, k_isbarrier
        .export floor_y_row, row_from_y16
        .import lv_tile, lv_spec, lv_link, LEVEL
        .import kid_animate, kid_start_seq, kid_frame_chk
        .import kid_control
        .import tiles_tick, tiles_reset, shake_loose, press_plate
        .import SEQ_stand, SEQ_stepfall, SEQ_hardbump, SEQ_bump
        .import SEQ_softland, SEQ_medland, SEQ_hardland
        .import SEQ_runjump, SEQEND_runjump, SEQ_standjump, SEQEND_standjump
        .import SEQ_testfoot, SEQEND_testfoot
        .import SEQ_jumphangMed, SEQEND_hangdrop

; local zeropage
zp_bodyc  = $80             ; body column
zp_footc  = $81             ; foot column
zp_rowa   = $82
zp_rowb   = $83
zp_x16    = $84             ; 2  scratch x for div14/mul14
zp_vel    = $86

        .segment "RODATA"
; tile -> has floor (NO_FLOOR = space, pillartop, panelwof, block, archtops)
FLOORFLAG:
        .byte 0,1,1,1,1,1,1,1,1,0, 1,1,0,1,1,1, 1,1,1,1, 0,1,1,1,1,1, 0,0,0,0
; tile -> blocks horizontal movement (gates count as closed for now)
BARRFLAG:
        .byte 0,0,0,0,1,0,0,1,0,0, 0,0,1,1,0,0, 0,0,0,0, 1,0,0,0,0,0, 0,0,0,0
; col*14 for col -1..11 (index col+1)
M14LO:  .repeat 13, I
        .byte <((I-1)*14)
        .endrepeat
M14HI:  .repeat 13, I
        .byte >((I-1)*14)
        .endrepeat
; floor_y (55+63r) for rows -1..5 (index row+1)
FYLO:   .repeat 7, I
        .byte <(55 + (I-1)*63)
        .endrepeat
FYHI:   .repeat 7, I
        .byte >(55 + (I-1)*63)
        .endrepeat

        .segment "CODE"

; ------------------------------------------------------------- helpers
; tile at (A=col, X=row) in the kid's room -> A (zp_tile also set)
k_tile:
        sta zp_tc
        stx zp_tr
        lda kid_room
        sta zp_rm
        jmp lv_tile

; carry set if (A=col, X=row) has floor
k_isfloor:
        jsr k_tile
        tax
        lda FLOORFLAG,x
        cmp #1                  ; carry = flag
        rts

; carry set if (A=col, X=row) is a barrier
k_isbarrier:
        jsr k_tile
        cmp #T_GATE
        beq @gate
        tax
        lda BARRFLAG,x
        cmp #1
        rts
@gate:  jsr lv_spec             ; gate position; passable from 112 up
        cmp #112
        bcc @barr
        clc
        rts
@barr:  sec
        rts

; divide zp_x16 (s16) by 14 -> A = col (s8), zp_xrem = remainder
div14:
        lda zp_x16+1
        bmi @neg
        lda zp_x16
        ldx zp_x16+1
        beq :+
        lda #168                ; clamp transients >= 256
:       ldx #0
@loop:  cmp #14
        bcc @done
        sbc #14                 ; carry known set
        inx
        bne @loop
@done:  sta zp_xrem
        txa
        rts
@neg:   lda zp_x16              ; assume -14..-1
        clc
        adc #14
        sta zp_xrem
        lda #$ff
        rts

; column of kid_x -> A (also zp_xrem)
kid_getcol:
        lda kid_x
        sta zp_x16
        lda kid_x+1
        sta zp_x16+1
        jmp div14

; A = col (s8, -1..11) -> zp_x16 = col*14
mul14:
        clc
        adc #1
        tax
        lda M14LO,x
        sta zp_x16
        lda M14HI,x
        sta zp_x16+1
        rts

; A = row (s8, -1..5) -> zp_x16 = floor_y(row)
floor_y_row:
        clc
        adc #1
        tax
        lda FYLO,x
        sta zp_x16
        lda FYHI,x
        sta zp_x16+1
        rts

; row for feet y in zp_x16 -> A = row s8   ((y+7)/63)
row_from_y16:
        clc
        lda zp_x16
        adc #7
        sta zp_x16
        lda zp_x16+1
        adc #0
        sta zp_x16+1
        bmi @neg
        ldx #0
@loop:  ; while x16 >= 63
        lda zp_x16+1
        bne @ge
        lda zp_x16
        cmp #63
        bcc @done
@ge:    sec
        lda zp_x16
        sbc #63
        sta zp_x16
        lda zp_x16+1
        sbc #0
        sta zp_x16+1
        inx
        bne @loop
@done:  txa
        rts
@neg:   lda #$ff
        rts

; --------------------------------------------------------------- spawn
kid_spawn:
        lda LEVEL+LV_INFO+64
        sta kid_room
        sta zp_visroom
        ; block -> row, col
        lda LEVEL+LV_INFO+65
        ldx #0
@div10: cmp #10
        bcc @got
        sec
        sbc #10
        inx
        bne @div10
@got:   stx kid_row
        ; x = col*14 + 7
        jsr mul14
        clc
        lda zp_x16
        adc #7
        sta kid_x
        lda zp_x16+1
        adc #0
        sta kid_x+1
        ; y = floor_y(row)
        lda kid_row
        jsr floor_y_row
        lda zp_x16
        sta kid_y
        lda zp_x16+1
        sta kid_y+1
        ; face: $ff in the data means left
        lda LEVEL+LV_INFO+66
        cmp #$ff
        beq :+
        lda #1
:       sta kid_face
        lda #ACT_STAND
        sta kid_action
        lda #1
        sta kid_alive
        lda #3
        sta kid_hp
        lda #0
        sta kid_xvel
        sta kid_yvel
        sta kid_events
        sta kid_hangt
        sta zp_dead_t
        SEQSET SEQ_stand
        jsr kid_animate
        lda #1
        sta zp_moved
        rts

; ---------------------------------------------------------------- tick
game_tick:
        lda kid_alive
        bne @alive
        inc zp_dead_t
        lda zp_dead_t
        cmp #30
        bcc @cont               ; play out the death animation
        jsr tiles_reset         ; restore the level, then respawn
        jmp kid_spawn
@alive: lda #0
        sta zp_dead_t
@cont:  jsr kid_control
        lda kid_y
        sta kid_prevy
        lda kid_y+1
        sta kid_prevy+1
        jsr kid_animate
        ; gravity (freefall only)
        lda kid_action
        cmp #ACT_FREEFALL
        bne @nofall
        lda kid_yvel
        clc
        adc #GRAVITY
        bmi :+
        cmp #TERMVEL+1
        bcc :+
        lda #TERMVEL
:       sta kid_yvel
        ; x += xvel * face
        lda kid_xvel
        ldx kid_face
        bmi @xf_neg
        jsr add_x16
        jmp @yadd
@xf_neg:
        eor #$ff
        clc
        adc #1
        jsr add_x16
@yadd:  ; y += yvel (signed)
        lda kid_yvel
        tax
        clc
        adc kid_y
        sta kid_y
        txa
        bmi @yn
        lda kid_y+1
        adc #0
        sta kid_y+1
        jmp @nofall
@yn:    lda kid_y+1
        adc #$ff
        sta kid_y+1
@nofall:
        jsr post_move
        jsr normalize
        ; fell past the last row with no room below
        lda kid_row
        bmi @rows_ok
        cmp #3
        bcc @rows_ok
        lda kid_alive
        beq @rows_ok
        lda #0
        sta kid_alive
        sta kid_hp
        SEQSET SEQ_hardland
@rows_ok:
        ; sequence events: floor jars and reaching the exit
        lda kid_events
        and #2                  ; nextlevel
        beq :+
        lda #1
        sta zp_lvdone
:       lda kid_events
        and #4                  ; jaru: rattle loose floors above
        beq :+
        lda kid_row
        sec
        sbc #1
        jsr jar_floors
:       lda kid_events
        and #8                  ; jard: rattle this row
        beq :+
        lda kid_row
        jsr jar_floors
:       jsr check_plates
        jsr tiles_tick
        lda #0
        sta kid_events
        lda kid_room
        beq @done
        cmp zp_visroom
        beq @done
        sta zp_visroom
        lda #1
        sta zp_moved
@done:  rts

; rattle every loose floor on row A of the kid's room (jaru/jard)
jar_floors:
        sta zp_tmp+3
        lda #0
        sta zp_tmp+2            ; col
@loop:  lda kid_room
        sta zp_rm
        lda zp_tmp+2
        sta zp_tc
        lda zp_tmp+3
        sta zp_tr
        jsr shake_loose
        inc zp_tmp+2
        lda zp_tmp+2
        cmp #10
        bne @loop
        rts

; feet on the ground press plates and shake loose floors (check bit set)
check_plates:
        jsr kid_frame_chk
        and #$40
        bne :+
        rts
:       lda kid_action
        cmp #ACT_STAND
        beq @on
        cmp #ACT_MOVE
        beq @on
        cmp #ACT_BUMPED
        beq @on
        rts
@on:    jsr kid_getcol
        sta zp_tc
        lda kid_room
        sta zp_rm
        lda kid_row
        sta zp_tr
        jsr lv_tile
        cmp #T_PRESS
        beq @plate
        cmp #T_UPRESS
        beq @plate
        cmp #T_DPRESS
        beq @plate
        cmp #T_LOOSE
        bne @done
        lda kid_action
        cmp #ACT_MOVE
        bne @done
        jmp shake_loose
@plate: jmp press_plate
@done:  rts

; kid_x += sext(A)
add_x16:
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

; ------------------------------------------------------------ post_move
post_move:
        ; hang/climb sequences manage their own position
        SEQGE SEQ_jumphangMed
        bcc @notseq
        SEQGE SEQEND_hangdrop
        bcs @notseq
        rts
@notseq:
        lda kid_action
        cmp #ACT_STAND
        beq @grounded
        cmp #ACT_MOVE
        beq @grounded
        cmp #ACT_BUMPED
        beq @bumped
        cmp #ACT_TURN
        beq @turning
        cmp #ACT_MIDAIR
        beq @air
        cmp #ACT_FREEFALL
        beq @air
        rts
@bumped:
        jmp check_barrier
@turning:
        jsr gate_knock
        jmp floor_check
@grounded:
        jsr check_barrier
        jmp floor_check
@air:
        jsr unwall
        lda kid_action
        cmp #ACT_FREEFALL
        beq @land
        lda kid_frame           ; guard falling frames 102..106
        cmp #102
        bcc @no
        cmp #107
        bcs @no
@land:  jmp check_landing
@no:    rts

; walking off an edge (frames with check marks only)
floor_check:
        lda kid_action
        cmp #ACT_STAND
        bne :+
        lda kid_frame
        cmp #15
        bne :+
        lda kid_row             ; re-align feet with the floor
        jsr floor_y_row
        lda zp_x16
        sta kid_y
        lda zp_x16+1
        sta kid_y+1
:       jsr kid_frame_chk
        and #$40
        bne :+
        rts                     ; airborne frame
:       ; jump arcs sail over gaps
        SEQGE SEQ_runjump
        bcc :+
        SEQGE SEQEND_runjump
        bcs :+
        lda kid_frame
        cmp #36
        bcc :+
        cmp #44
        bcs :+
        rts
:       SEQGE SEQ_standjump
        bcc :+
        SEQGE SEQEND_standjump
        bcs :+
        lda kid_frame
        cmp #18
        bcc :+
        cmp #26
        bcs :+
        rts
:       SEQGE SEQ_testfoot
        bcc :+
        SEQGE SEQEND_testfoot
        bcs :+
        rts
:       jsr kid_getcol
        sta zp_bodyc
        ; foot_x = x - face * (foot_dx/2)
        jsr kid_frame_chk
        and #$1f
        lsr
        ldx kid_face
        bmi @foot_add
        eor #$ff                ; subtract
        clc
        adc #1
@foot_add:
        tax
        clc
        adc kid_x
        sta zp_x16
        txa
        bmi @fn
        lda kid_x+1
        adc #0
        sta zp_x16+1
        jmp @fdiv
@fn:    lda kid_x+1
        adc #$ff
        sta zp_x16+1
@fdiv:  jsr div14
        sta zp_footc
        ; supported?
        lda zp_bodyc
        ldx kid_row
        jsr k_isfloor
        bcs @supported
        ; toe overhang: foot on the neighbour column keeps us up within 5px
        lda zp_footc
        cmp zp_bodyc
        beq @falls
        ldx kid_row
        jsr k_isfloor
        bcc @falls
        ; edge = body_col*14 (facing right) or (body_col+1)*14
        lda kid_face
        bmi @eleft
        lda zp_bodyc
        jmp @eget
@eleft: lda zp_bodyc
        clc
        adc #1
@eget:  jsr mul14
        ; |kid_x - edge| <= 5 ?
        sec
        lda kid_x
        sbc zp_x16
        sta zp_tmp
        lda kid_x+1
        sbc zp_x16+1
        bpl @abs_done
        ; negate
        sec
        lda #0
        sbc zp_tmp
        sta zp_tmp
@abs_done:
        lda zp_tmp
        cmp #6
        bcc @supported
@falls: lda kid_room
        beq @supported
        lda #0
        sta kid_xvel
        sta kid_yvel
        SEQSET SEQ_stepfall
        jmp kid_animate
@supported:
        rts

; ---------------------------------------------------------- barriers
check_barrier:
        jsr kid_getcol
        sta zp_bodyc
        ldx kid_row
        jsr k_isbarrier
        bcs :+
        rts
:       lda zp_tile
        cmp #T_GATE
        bne @push
        lda zp_xrem
        cmp #12
        bcs @plane
        jmp gate_knock          ; inside the open doorway part
@plane: lda kid_face
        bmi @pl
        lda zp_bodyc
        jsr mul14
        lda #11
        jsr setx_plus
        jmp @bump
@pl:    lda zp_bodyc
        clc
        adc #1
        jsr mul14
        lda #1
        jsr setx_plus
        jmp @bump
@push:  lda kid_face
        bmi @pu
        lda zp_bodyc
        jsr mul14
        sec
        lda zp_x16
        sbc #1
        sta kid_x
        lda zp_x16+1
        sbc #0
        sta kid_x+1
        jmp @bump
@pu:    lda zp_bodyc
        clc
        adc #1
        jsr mul14
        lda #1
        jsr setx_plus
@bump:  ; bump sequence
        lda kid_action
        cmp #ACT_MOVE
        bne @b2
        lda kid_frame
        cmp #1
        bcc @b2
        cmp #15
        bcs @b2
        SEQSET SEQ_hardbump
        rts
@b2:    lda kid_frame
        cmp #15
        beq @done
        SEQSET SEQ_bump
@done:  rts

; kid_x = zp_x16 + A (unsigned small offset)
setx_plus:
        clc
        adc zp_x16
        sta kid_x
        lda zp_x16+1
        adc #0
        sta kid_x+1
        rts

; a closed gate shoves a character standing inside its tile
gate_knock:
        jsr kid_getcol
        sta zp_bodyc
        ldx kid_row
        jsr k_tile
        cmp #T_GATE
        beq :+
        rts
:       lda kid_action
        cmp #ACT_TURN
        beq @go
        lda kid_frame
        cmp #15
        beq @go
        cmp #108
        bcc @no
        cmp #111
        bcs @no
@go:    lda zp_xrem
        cmp #7
        bcs @right
        sec
        lda kid_x
        sbc #5
        sta kid_x
        lda kid_x+1
        sbc #0
        sta kid_x+1
        rts
@right: clc
        lda kid_x
        adc #5
        sta kid_x
        lda kid_x+1
        adc #0
        sta kid_x+1
@no:    rts

; a falling character can't pass through a wall column
unwall:
        lda kid_y
        sta zp_x16
        lda kid_y+1
        sta zp_x16+1
        jsr row_from_y16
        sta zp_rowa
        jsr kid_getcol
        sta zp_bodyc
        ldx zp_rowa
        jsr k_tile
        cmp #T_BLOCK
        beq :+
        rts
:       lda zp_bodyc
        sec
        sbc #1
        ldx zp_rowa
        jsr k_tile
        cmp #T_BLOCK
        php                     ; z set = left blocked
        lda zp_bodyc
        clc
        adc #1
        ldx zp_rowa
        jsr k_tile
        cmp #T_BLOCK
        beq @right_blocked
        ; right clear
        plp
        bne @use_left_or_off    ; left clear too: choose by offset
        jmp @use_right
@use_left_or_off:
        lda zp_xrem
        cmp #8
        bcc @use_left
        jmp @use_right
@right_blocked:
        plp
        beq @stuck              ; both blocked: leave it
@use_left:
        lda zp_bodyc
        jsr mul14
        sec
        lda zp_x16
        sbc #1
        sta kid_x
        lda zp_x16+1
        sbc #0
        sta kid_x+1
        rts
@use_right:
        lda zp_bodyc
        clc
        adc #1
        jsr mul14
        clc
        lda zp_x16
        adc #1
        sta kid_x
        lda zp_x16+1
        adc #0
        sta kid_x+1
@stuck: rts

; ----------------------------------------------------------- landings
check_landing:
        ; only when moving down: kid_y > kid_prevy
        sec
        lda kid_prevy
        sbc kid_y
        lda kid_prevy+1
        sbc kid_y+1
        bmi :+
        rts                     ; prev >= y
:       lda kid_prevy
        sta zp_x16
        lda kid_prevy+1
        sta zp_x16+1
        jsr row_from_y16
        sta zp_rowa
        lda kid_y
        sta zp_x16
        lda kid_y+1
        sta zp_x16+1
        jsr row_from_y16
        sta zp_rowb
@loop:  lda zp_rowa
        cmp zp_rowb
        beq :+
        bpl @below              ; rowa > rowb: done scanning
:       lda zp_rowa
        jsr floor_y_row         ; zp_x16 = fy
        ; prev_y < fy <= y ?
        sec
        lda kid_prevy
        sbc zp_x16
        lda kid_prevy+1
        sbc zp_x16+1
        bpl @next               ; prev >= fy
        sec
        lda kid_y
        sbc zp_x16
        lda kid_y+1
        sbc zp_x16+1
        bmi @next               ; y < fy
        ; floor here?
        jsr kid_getcol
        ldx zp_rowa
        jsr k_isfloor
        bcc @next
        ; land!
        lda zp_rowa
        sta kid_row
        jsr floor_y_row
        lda zp_x16
        sta kid_y
        lda zp_x16+1
        sta kid_y+1
        jmp land
@next:  inc zp_rowa
        jmp @loop
@below: lda zp_rowb
        cmp #3
        bcc @done
        sta kid_row
@done:  rts

land:
        lda kid_yvel
        sta zp_vel
        lda #0
        sta kid_xvel
        sta kid_yvel
        lda #ACT_BUMPED
        sta kid_action
        ; landing on a loose floor rattles it
        jsr kid_getcol
        sta zp_tc
        lda kid_room
        sta zp_rm
        lda kid_row
        sta zp_tr
        jsr shake_loose
        lda zp_vel
        cmp #OOF_VEL
        bcs @hard1
        SEQSET SEQ_softland
        rts
@hard1: cmp #TERMVEL
        bcs @fatal
        dec kid_hp
        beq @fatal
        bmi @fatal
        SEQSET SEQ_medland
        rts
@fatal: lda #0
        sta kid_alive
        sta kid_hp
        SEQSET SEQ_hardland
        rts

; ------------------------------------------------------- normalization
normalize:
        lda kid_room
        bne :+
        rts
:
@xleft: lda kid_x+1
        bpl @xright
        lda kid_room
        ldx #0
        jsr lv_link
        bne @gol
        lda #0
        sta kid_x
        sta kid_x+1
        jmp @xright
@gol:   sta kid_room
        clc
        lda kid_x
        adc #140
        sta kid_x
        lda kid_x+1
        adc #0
        sta kid_x+1
        jmp @xleft
@xright:
        lda kid_x+1
        bne @over
        lda kid_x
        cmp #140
        bcc @rows
@over:  lda kid_room
        ldx #1
        jsr lv_link
        bne @gor
        lda #139
        sta kid_x
        lda #0
        sta kid_x+1
        jmp @rows
@gor:   sta kid_room
        sec
        lda kid_x
        sbc #140
        sta kid_x
        lda kid_x+1
        sbc #0
        sta kid_x+1
        jmp @xright
@rows:  lda kid_row
        bpl @rdown
        lda kid_room
        ldx #2
        jsr lv_link
        beq @rdone
        sta kid_room
        lda kid_row
        clc
        adc #3
        sta kid_row
        clc
        lda kid_y
        adc #189
        sta kid_y
        lda kid_y+1
        adc #0
        sta kid_y+1
        jmp @rows
@rdown: cmp #3
        bcc @rdone
        lda kid_room
        ldx #3
        jsr lv_link
        beq @rdone
        sta kid_room
        lda kid_row
        sec
        sbc #3
        sta kid_row
        sec
        lda kid_y
        sbc #189
        sta kid_y
        lda kid_y+1
        sbc #0
        sta kid_y+1
        jmp @rows
@rdone: rts

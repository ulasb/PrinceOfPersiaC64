; Kid control layer — input to sequence decisions, ported from player.py
; (combat and pickups come with the guard build).

        .include "pop.inc"

        .export kid_control
        .import kid_start_seq, kid_animate
        .import kid_getcol, div14, mul14, k_tile, k_isfloor, k_isbarrier
        .import floor_y_row, row_from_y16
        .import SEQ_stand, SEQ_startrun, SEQ_turn, SEQ_standjump, SEQ_jumpup
        .import SEQ_runjump, SEQ_rdiveroll, SEQ_runturn, SEQ_runstop
        .import SEQ_stoop, SEQ_standup
        .import SEQ_jumphangMed, SEQ_climbup, SEQ_climbdown, SEQ_climbfail
        .import SEQ_hangdrop, SEQ_hangfall, SEQ_hangstraight, SEQ_fallhang
        .import SEQ_hang, SEQEND_hang1, SEQEND_hangstraight, SEQEND_hangdrop
        .import SEQ_testfoot, SEQ_fullstep
        .import SEQ_step1, SEQ_step2, SEQ_step3, SEQ_step4, SEQ_step5
        .import SEQ_step6, SEQ_step7, SEQ_step8, SEQ_step9, SEQ_step10
        .import SEQ_step11, SEQ_step12, SEQ_step13
        .import SEQ_climbstairs
        .import SEQ_engarde, SEQEND_engarde, SEQ_stabbed
        .import SEQ_strikeadv, SEQ_landengarde
        .import SEQ_turnengarde, SEQ_alertturn
        .import SEQ_resheathe, SEQ_fastsheathe, SEQ_faststrike
        .import SEQ_blocktostrike, SEQ_retreat, SEQ_advance
        .import SEQ_readyblock, SEQ_strikeblock, SEQ_pickupsword
        .import lv_tile, lv_spec

; local zeropage
zp_c      = $88             ; scratch column
zp_row2   = $89
zp_sdist  = $8a
zp_cand   = $8b
zp_x16b   = $8c             ; 2

        .segment "RODATA"
STEPLO: .byte <SEQ_step1, <SEQ_step2, <SEQ_step3, <SEQ_step4, <SEQ_step5
        .byte <SEQ_step6, <SEQ_step7, <SEQ_step8, <SEQ_step9, <SEQ_step10
        .byte <SEQ_step11, <SEQ_step12, <SEQ_step13
STEPHI: .byte >SEQ_step1, >SEQ_step2, >SEQ_step3, >SEQ_step4, >SEQ_step5
        .byte >SEQ_step6, >SEQ_step7, >SEQ_step8, >SEQ_step9, >SEQ_step10
        .byte >SEQ_step11, >SEQ_step12, >SEQ_step13

        .segment "CODE"

; direction input -> zp_d (1, $ff, 0)
dir_input:
        lda zp_input
        and #IN_LEFT
        beq @notleft
        lda zp_input
        and #IN_RIGHT
        bne @none
        lda #$ff
        sta zp_d
        rts
@notleft:
        lda zp_input
        and #IN_RIGHT
        beq @none
        lda #1
        sta zp_d
        rts
@none:  lda #0
        sta zp_d
        rts

kid_control:
        lda kid_alive
        bne :+
        rts
:       jsr dir_input
        ; hanging?
        lda kid_action
        cmp #ACT_HANG
        beq @hang
        cmp #ACT_HANGSTR
        beq @hang
        SEQGE SEQ_hang
        bcc @nothang
        SEQGE SEQEND_hangstraight
        bcs @nothang
@hang:  jmp control_hang
@nothang:
        lda kid_action
        cmp #ACT_MIDAIR
        beq @air
        cmp #ACT_FREEFALL
        bne @ground
@air:   jmp control_midair
@ground:
        lda kid_swd
        beq @nocmb
        SEQGE SEQ_engarde
        bcc @r1
        SEQGE SEQ_stabbed
        bcs @r1
        jmp control_combat
@r1:    SEQGE SEQ_strikeadv
        bcc @r2
        SEQGE SEQ_landengarde
        bcs @r2
        jmp control_combat
@r2:    SEQGE SEQ_turnengarde
        bcc @nocmb
        SEQGE SEQ_alertturn
        bcs @nocmb
        jmp control_combat
@nocmb: lda kid_frame
        cmp #109
        bne :+
        jmp control_crouch
:       cmp #15
        bne :+
        jmp control_stand
:       cmp #1
        bcc @out
        cmp #15
        bcs @out
        jmp control_run
@out:   rts

; ------------------------------------------------------------ standing
control_stand:
        ; auto draw when an armed opponent is near
        lda kid_hassw
        beq @noeng
        lda opp_ok
        beq @noeng
        lda opp_alive
        beq @noeng
        lda opp_room
        cmp kid_room
        bne @noeng
        lda opp_row
        cmp kid_row
        bne @noeng
        jsr opp_dist
        cmp #60
        bcs @noeng
        lda #1
        sta kid_swd
        SEQSET SEQ_engarde
        rts
@noeng: ; pick up a sword lying here (action button alone)
        lda zp_input
        and #IN_SHIFT
        beq @nopk
        lda zp_d
        bne @nopk
        lda zp_input
        and #IN_UP|IN_DOWN
        bne @nopk
        jsr kid_getcol
        sta zp_c
        jsr @trypk
        bcs @pkgo
        lda zp_c
        clc
        adc kid_face
        jsr @trypk
        bcc @nopk
@pkgo:  lda zp_rrm
        sta zp_pkrm
        lda zp_rc
        sta zp_pkc
        lda zp_rr
        sta zp_pkr
        lda #1
        sta zp_pickup
        SEQSET SEQ_pickupsword
        rts
@trypk: sta zp_tc
        lda kid_room
        sta zp_rm
        lda kid_row
        sta zp_tr
        jsr lv_tile
        cmp #T_SWORD
        beq :+
        clc
        rts
:       sec
        rts
@nopk:  lda zp_input
        and #IN_UP
        beq @notup
        ; an open exit here? walk up the stairs and out
        jsr kid_getcol
        sta zp_tc
        lda kid_room
        sta zp_rm
        lda kid_row
        sta zp_tr
        jsr lv_tile
        cmp #T_EXIT
        beq @exit
        cmp #T_EXIT2
        bne @noexit
@exit:  jsr lv_spec
        cmp #20                 ; door open enough
        bcc @noexit
        SEQSET SEQ_climbstairs
        rts
@noexit:
        ; up: climb if no direction, else standing jump
        lda zp_d
        bne @upjump
        jsr try_climb
        bcc @jumpup
        rts
@upjump:
        cmp kid_face
        beq :+
        sta kid_face
:       SEQSET SEQ_standjump
        rts
@jumpup:
        SEQSET SEQ_jumpup
        rts
@notup: lda zp_input
        and #IN_DOWN
        beq @notdown
        jsr try_climb_down
        bcc @stoop
        rts
@stoop: SEQSET SEQ_stoop
        rts
@notdown:
        lda zp_d
        bne :+
        rts
:       cmp kid_face
        beq @fwd
        SEQSET SEQ_turn
        rts
@fwd:   lda zp_input
        and #IN_SHIFT
        beq @run
        jmp careful_step
@run:   SEQSET SEQ_startrun
        rts

; ------------------------------------------------------------- running
control_run:
        lda kid_frame
        cmp #4
        bcs @committed_done
        ; run start frames 1-3: only up+forward breaks out
        lda zp_input
        and #IN_UP
        beq @out
        lda zp_d
        cmp kid_face
        bne @out
        SEQSET SEQ_standjump
@out:   rts
@committed_done:
        lda zp_input
        and #IN_UP
        beq :+
        SEQSET SEQ_runjump
        rts
:       lda zp_input
        and #IN_DOWN
        beq :+
        SEQSET SEQ_rdiveroll
        rts
:       lda zp_d
        beq @nod
        ; reversed?
        clc
        adc kid_face            ; 1 + $ff = 0 when opposite
        bne @out2
        SEQSET SEQ_runturn
        rts
@nod:   lda kid_frame
        cmp #7
        beq @stop
        cmp #11
        bne @out2
@stop:  SEQSET SEQ_runstop
@out2:  rts

; ------------------------------------------------------------ crouching
control_crouch:
        lda zp_input
        and #IN_DOWN
        bne :+
        SEQSET SEQ_standup
:       rts

; -------------------------------------------------------------- midair
control_midair:
        lda zp_input
        and #IN_SHIFT
        bne :+
        rts
:       ; a grab already in progress?
        SEQGE SEQ_jumphangMed
        bcc :+
        SEQGE SEQEND_hangdrop
        bcc @out
:       ; row at current feet y
        lda kid_y
        sta zp_x16b
        lda kid_y+1
        sta zp_x16b+1
        jsr xfer_row            ; zp_row2 = row_from_y(kid_y)
        ; try ledge columns col+face, col-face
        jsr kid_getcol
        sta zp_c
        clc
        adc kid_face
        sta zp_cand
        jsr @try
        bcs @out
        lda zp_c
        sec
        sbc kid_face
        sta zp_cand
        jsr @try
@out:   rts
@try:   ; ledge at (cand, row2-1)?
        ldx zp_row2
        dex
        lda zp_cand
        jsr k_isfloor
        bcs :+
        clc
        rts
:       ; |kid_y - floor_y(row2)| <= 15 and falling down
        lda kid_yvel
        bpl :+
        clc
        rts
:       lda zp_row2
        jsr floor_y_row_g
        sec
        lda kid_y
        sbc zp_x16b
        sta zp_sdist
        lda kid_y+1
        sbc zp_x16b+1
        bpl @abs
        sec
        lda #0
        sbc zp_sdist
        sta zp_sdist
@abs:   lda zp_sdist
        cmp #16
        bcc :+
        clc
        rts
:       ; grab it
        lda zp_cand
        cmp zp_c
        beq @facekeep
        bmi @faceleft
        lda #1
        bne @faceset
@faceleft:
        lda #$ff
@faceset:
        sta kid_face
@facekeep:
        jsr hang_x
        lda zp_row2
        sta kid_row
        lda zp_row2
        jsr floor_y_row_g
        lda zp_x16b
        sta kid_y
        lda zp_x16b+1
        sta kid_y+1
        lda #0
        sta kid_yvel
        sta kid_xvel
        sta kid_hangt
        SEQSET SEQ_fallhang
        sec
        rts

; row_from_y into zp_row2 (input in zp_x16b)
xfer_row:
        lda zp_x16b
        sta $84                 ; zp_x16 in game.s
        lda zp_x16b+1
        sta $85
        jsr row_from_y16
        sta zp_row2
        rts
; floor_y via game.s helper, result copied to zp_x16b
floor_y_row_g:
        jsr floor_y_row
        lda $84
        sta zp_x16b
        lda $85
        sta zp_x16b+1
        rts

; hang x position: ledge in zp_cand, facing set; body on the open side
hang_x:
        lda kid_face
        bmi @left
        ; x = ledge*14 - 3
        lda zp_cand
        jsr mul14
        sec
        lda $84
        sbc #3
        sta kid_x
        lda $85
        sbc #0
        sta kid_x+1
        rts
@left:  ; x = (ledge+1)*14 + 2
        lda zp_cand
        clc
        adc #1
        jsr mul14
        clc
        lda $84
        adc #2
        sta kid_x
        lda $85
        adc #0
        sta kid_x+1
        rts

; ------------------------------------------------------------- climbing
; carry set if a climb was started
try_climb:
        jsr kid_getcol
        sta zp_c
        ; up_here must have no floor
        ldx kid_row
        dex
        lda zp_c
        jsr k_isfloor
        bcc :+
        clc
        rts
:       ; candidate ledges: col+face then col-face
        lda zp_c
        clc
        adc kid_face
        sta zp_cand
        jsr @cand
        bcs @yes
        lda zp_c
        sec
        sbc kid_face
        sta zp_cand
        jsr @cand
        bcs @yes
        clc
@yes:   rts
@cand:  ldx kid_row
        dex
        lda zp_cand
        jsr k_isfloor
        bcs :+
        clc
        rts
:       ; face the ledge
        lda zp_cand
        cmp zp_c
        bmi @l
        lda #1
        bne @f
@l:     lda #$ff
@f:     sta kid_face
        jsr hang_x
        lda #0
        sta kid_hangt
        SEQSET SEQ_jumphangMed
        sec
        rts

; carry set if climbing down started
try_climb_down:
        jsr kid_getcol
        sta zp_c
        ldx kid_row
        jsr k_isfloor
        bcs :+
        clc
        rts
:       ; gap on facing side first, then behind
        lda kid_face
        sta zp_sdist             ; gap_dir
        jsr @gap
        bcs @yes
        sec
        lda #0
        sbc kid_face
        sta zp_sdist
        jsr @gap
@yes:   rts
@gap:   lda zp_c
        clc
        adc zp_sdist
        sta zp_cand
        ldx kid_row
        jsr k_isfloor
        bcc :+
        clc
        rts
:       lda zp_cand
        ldx kid_row
        jsr k_isbarrier
        bcc :+
        clc
        rts
:       ; back over the edge, facing away from the gap
        sec
        lda #0
        sbc zp_sdist
        sta kid_face
        lda zp_sdist
        bmi @gapleft
        ; x = (col+1)*14 - 2
        lda zp_c
        clc
        adc #1
        jsr mul14
        sec
        lda $84
        sbc #2
        sta kid_x
        lda $85
        sbc #0
        sta kid_x+1
        jmp @go
@gapleft:
        ; x = col*14 + 1
        lda zp_c
        jsr mul14
        clc
        lda $84
        adc #1
        sta kid_x
        lda $85
        adc #0
        sta kid_x+1
@go:    lda #0
        sta kid_hangt
        SEQSET SEQ_climbdown
        sec
        rts

; -------------------------------------------------------------- hanging
control_hang:
        ; only while in the hang loop itself
        SEQGE SEQ_hang
        bcs :+
        rts
:       SEQGE SEQEND_hangstraight
        bcc :+
        rts
:       inc kid_hangt
        ; up or forward: climb (unless blocked above the ledge)
        lda zp_input
        and #IN_UP
        bne @climb
        lda zp_d
        beq @noclimb
        cmp kid_face
        bne @noclimb
@climb: jsr kid_getcol
        sta zp_c
        clc
        adc kid_face
        sta zp_cand
        ldx kid_row
        dex
        lda zp_cand
        jsr k_isbarrier
        bcs @fail
        ; snap x onto the ledge edge and pull up
        lda kid_face
        bmi @snapl
        lda zp_cand
        jsr mul14
        lda #2
        jsr snap_setx
        jmp @up
@snapl: lda zp_cand
        clc
        adc #1
        jsr mul14
        sec
        lda $84
        sbc #3
        sta kid_x
        lda $85
        sbc #0
        sta kid_x+1
@up:    SEQSET SEQ_climbup
        rts
@fail:  SEQSET SEQ_climbfail
        rts
@noclimb:
        ; drop: down pressed, or shift released after a grace period
        lda zp_inedge
        and #IN_DOWN
        bne @drop
        lda zp_input
        and #IN_SHIFT
        bne @hold
        lda kid_hangt
        cmp #3
        bcc @out
@drop:  jsr kid_getcol
        ldx kid_row
        jsr k_isfloor
        bcs @floor
        SEQSET SEQ_hangfall
        rts
@floor: SEQSET SEQ_hangdrop
        rts
@hold:  ; settle into the still hang while holding on
        lda kid_hangt
        cmp #6
        bcc @out
        SEQGE SEQ_hang
        bcc @out
        SEQGE SEQEND_hang1
        bcs @out
        SEQSET SEQ_hangstraight
@out:   rts

snap_setx:
        clc
        adc $84
        sta kid_x
        lda $85
        adc #0
        sta kid_x+1
        rts

; --------------------------------------------------------- careful step
careful_step:
        jsr kid_getcol
        sta zp_c
        lda #14
        sta zp_sdist
        ldx #0                  ; ahead = 0..2
@scan:  stx zp_row2             ; reuse as loop counter
        txa
        ; col = c + ahead*face
        ldx kid_face
        bmi @behind
        clc
        adc zp_c
        jmp @have
@behind:
        sta zp_tmp
        lda zp_c
        sec
        sbc zp_tmp
@have:  sta zp_cand
        ldx kid_row
        jsr k_isbarrier
        bcs @edge
        lda zp_cand
        ldx kid_row
        jsr k_isfloor
        bcc @edge
        ldx zp_row2
        inx
        cpx #3
        bne @scan
        jmp @step               ; clear ahead: full step
@edge:  ; distance to the edge of the blocking column
        lda kid_face
        bmi @eleft
        ; dist = (cand*14 - x) - 1
        lda zp_cand
        jsr mul14
        sec
        lda $84
        sbc kid_x
        sta zp_sdist
        lda $85
        sbc kid_x+1
        bmi @neg                ; edge < x: already past it
        bne @clamp
        lda zp_sdist
        beq @neg                ; edge == x: dist -1
        dec zp_sdist
        jmp @step
@eleft: ; dist = x - (cand+1)*14
        lda zp_cand
        clc
        adc #1
        jsr mul14
        sec
        lda kid_x
        sbc $84
        sta zp_sdist
        lda kid_x+1
        sbc $85
        bmi @neg
        bne @clamp
        jmp @step
@neg:   lda #0
        sta zp_sdist
        jmp @step
@clamp: lda #14
        sta zp_sdist
@step:  lda zp_sdist
        bne :+
        SEQSET SEQ_testfoot     ; dist < 1: tap a foot over the edge
        rts
:       cmp #14
        bcc :+
        SEQSET SEQ_fullstep
        rts
:       tax
        dex
        lda STEPLO,x
        pha
        lda STEPHI,x
        tax
        pla
        jmp kid_start_seq

; ----------------------------------------------------------- combat
; |kid_x - opp_x| -> A (clamped 255)
opp_dist:
        lda kid_x
        sec
        sbc opp_x
        tax
        lda kid_x+1
        sbc opp_x+1
        beq @pos
        cmp #$ff
        beq @neg
        lda #255
        rts
@pos:   txa
        rts
@neg:   txa
        eor #$ff
        clc
        adc #1
        rts

; carry set when the kid is in a ready stance frame
kid_ready_frame:
        lda kid_frame
        cmp #158
        beq @y
        cmp #170
        beq @y
        cmp #171
        beq @y
        clc
        rts
@y:     sec
        rts

control_combat:
        lda opp_ok
        beq @sheathe
        lda opp_alive
        bne @have
@sheathe:
        jsr kid_ready_frame
        bcs :+
        rts
:       lda #0
        sta kid_swd
        SEQSET SEQ_resheathe
        rts
@have:  ; face the opponent from the ready stance
        jsr kid_ready_frame
        bcc @f161
        lda kid_x
        cmp opp_x
        lda kid_x+1
        sbc opp_x+1
        bmi @wr
        lda #$ff
        bne @wf
@wr:    lda #1
@wf:    cmp kid_face
        beq @f161
        sta kid_face
@f161:  lda kid_frame
        cmp #161
        bne @nodeflect
        ; just deflected: riposte or fall back
        lda zp_input
        and #IN_SHIFT
        beq @fallback
        SEQSET SEQ_blocktostrike
        rts
@fallback:
        SEQSET SEQ_retreat
        rts
@nodeflect:
        lda zp_inedge
        and #IN_SHIFT
        beq @nostrike
        lda kid_frame
        cmp #157
        beq @fstrike
        cmp #158
        beq @fstrike
        cmp #165
        beq @fstrike
        cmp #170
        beq @fstrike
        cmp #171
        beq @fstrike
        cmp #150
        beq @bstrike
        rts
@fstrike:
        SEQSET SEQ_faststrike
        rts
@bstrike:
        SEQSET SEQ_blocktostrike
        rts
@nostrike:
        lda zp_inedge
        and #IN_DOWN
        beq @noshth
        jsr kid_ready_frame
        bcc @noshth
        lda #0
        sta kid_swd
        SEQSET SEQ_fastsheathe
        rts
@noshth:
        lda zp_input
        and #IN_UP
        beq @noblock
        ; parry
        lda kid_frame
        cmp #167
        bne :+
        SEQSET SEQ_strikeblock
        rts
:       cmp #158
        beq @doblk
        cmp #165
        beq @doblk
        cmp #168
        beq @doblk
        cmp #170
        beq @doblk
        cmp #171
        beq @doblk
        rts
@doblk: lda opp_frame
        cmp #168                ; windup: one frame early, wait
        bne :+
        rts
:       SEQSET SEQ_readyblock
        lda opp_frame
        cmp #153                ; one frame late: skip the raise
        bne :+
        jsr kid_animate
:       rts
@noblock:
        jsr kid_ready_frame
        bcs :+
        rts
:       lda zp_d
        bne :+
        rts
:       cmp kid_face
        bne @back
        jsr opp_dist
        cmp #16
        bcc @done
        SEQSET SEQ_advance
        rts
@back:  clc
        adc kid_face            ; opposite directions sum to zero
        bne @done
        SEQSET SEQ_retreat
@done:  rts

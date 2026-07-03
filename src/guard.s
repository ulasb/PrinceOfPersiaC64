; Guards: spawn from the level INFO block, character-swap machinery (the
; shared kid_* routines run on whichever character sits in the zeropage
; struct, like the original's CharProfile swap), and the combat AI ported
; from guard.py.

        .include "pop.inc"

        .export guards_spawn, guard_swap_in, guard_swap_out, guard_control
        .export pick_opponent, guard_cache_opp, rnd
        .export NGUARD : absolute, g_used, g_state, g_skill, g_engaged, g_cool, g_jblk
        .export g_saved, g_hurtcd
        .import LEVEL, lv_tile, lv_spec
        .import kid_start_seq, kid_animate, kid_getcol
        .import k_isfloor, k_isbarrier
        .import SEQ_guardengarde, SEQ_blocktostrike, SEQ_retreat
        .import SEQ_readyblock, SEQ_advance, SEQ_strike
        .import SEQ_ready, SEQEND_ready, SEQEND_guardengarde
        .import SEQ_alertstand, SEQEND_alertstand

NGUARD    = 2

; combat tuning (AUTO.S via guard.py)
STRIKE_NEAR = 12
STRIKE_FAR  = 29
BLOCK_FAR   = 29
OFFGUARD    = 11
BLOCK_TIME  = 4

; local zeropage
zp_gi     = $bd             ; current guard slot
zp_rnd    = $be             ; LFSR state

        .segment "BSS"
g_used:   .res NGUARD       ; 1 = active slot
g_state:  .res NGUARD*CHRSIZE
g_skill:  .res NGUARD
g_engaged:.res NGUARD
g_cool:   .res NGUARD
g_jblk:   .res NGUARD
g_saved:  .res NGUARD       ; save-under valid for this guard
g_hurtcd: .res NGUARD       ; damage cooldown
kid_save: .res CHRSIZE      ; kid struct parked here during a swap

        .segment "CODE"

; 8-bit LFSR random
rnd:
        lda zp_rnd
        beq @seed
        asl
        bcc :+
        eor #$1d
:       sta zp_rnd
        rts
@seed:  lda #$5a
        sta zp_rnd
        rts

; --------------------------------------------------------------- spawn
guards_spawn:
        lda #0
        ldx #NGUARD-1
:       sta g_used,x
        sta g_saved,x
        dex
        bpl :-
        ; scan the 24 per-room guard entries, take the first NGUARD
        ldx #0                  ; room-1
        lda #0
        sta zp_gi
@scan:  lda LEVEL+LV_INFO+71,x  ; start block; >=30 means none
        cmp #30
        bcs @next
        jsr @spawn_one
        inc zp_gi
        lda zp_gi
        cmp #NGUARD
        bcs @done
@next:  inx
        cpx #24
        bne @scan
@done:  rts

; spawn guard zp_gi from room X+1 (clobbers the kid zp struct: caller
; must run this before kid_spawn or around a swap — we use kid slots
; as scratch then park them into the guard's state)
@spawn_one:
        txa
        pha
        ; park the current kid struct
        ldy #CHRSIZE-1
:       lda $50,y
        sta kid_save,y
        dey
        bpl :-
        ; fill kid slots with the guard
        inx
        stx kid_room
        pla
        pha
        tax
        lda LEVEL+LV_INFO+71,x  ; block
        ldy #0
@d10:   cmp #10
        bcc @got
        sec
        sbc #10
        iny
        bne @d10
@got:   sty kid_row
        ; x = col*14 + 7
        tay
        lda #7
@m14:   cpy #0
        beq @xdone
        clc
        adc #14
        dey
        bne @m14
@xdone: sta kid_x
        lda #0
        sta kid_x+1
        ; y = 55 + row*63
        lda #55
        ldy kid_row
        beq :+
@m63:   clc
        adc #63
        dey
        bne @m63
:       sta kid_y
        lda #0
        sta kid_y+1
        lda LEVEL+LV_INFO+95,x  ; face
        cmp #$ff
        beq :+
        lda #1
:       sta kid_face
        lda #ACT_STAND
        sta kid_action
        lda #0
        sta kid_xvel
        sta kid_yvel
        sta kid_events
        sta kid_hangt
        lda #1
        sta kid_alive
        ; skill/hp
        lda LEVEL+LV_INFO+167,x ; prog
        cmp #16
        bcc :+
        lda #0
:       ldy zp_gi
        sta g_skill,y
        cmp #8
        bcc :+
        lda #7
:       clc
        adc #3
        sta kid_hp
        lda #0
        sta g_engaged,y
        sta g_cool,y
        sta g_jblk,y
        lda #1
        sta g_used,y
        SEQSET SEQ_guardengarde
        lda #2
        sta zp_chid
        jsr kid_animate
        lda #0
        sta zp_chid
        ; move the filled struct into the guard's state
        ldy zp_gi
        jsr guard_state_ptr
        ldy #CHRSIZE-1
:       lda $50,y
        sta (zp_ptr),y
        dey
        bpl :-
        ; restore the kid
        ldy #CHRSIZE-1
:       lda kid_save,y
        sta $50,y
        dey
        bpl :-
        pla
        tax
        rts

; zp_ptr -> g_state of guard Y
guard_state_ptr:
        lda #<g_state
        sta zp_ptr
        lda #>g_state
        sta zp_ptr+1
        cpy #0
        beq @done
        clc
        lda zp_ptr
        adc #CHRSIZE
        sta zp_ptr
        bcc @done
        inc zp_ptr+1
@done:  rts

; ------------------------------------------------------------ swapping
; park the kid, load guard X into the zeropage struct, zp_chid = 2
guard_swap_in:
        stx zp_gi
        ldy #CHRSIZE-1
:       lda $50,y
        sta kid_save,y
        dey
        bpl :-
        ldy zp_gi
        jsr guard_state_ptr
        ldy #CHRSIZE-1
:       lda (zp_ptr),y
        sta $50,y
        dey
        bpl :-
        lda #2
        sta zp_chid
        rts

; store the zeropage struct back into guard zp_gi, restore the kid
guard_swap_out:
        ldy zp_gi
        jsr guard_state_ptr
        ldy #CHRSIZE-1
:       lda $50,y
        sta (zp_ptr),y
        dey
        bpl :-
        ldy #CHRSIZE-1
:       lda kid_save,y
        sta $50,y
        dey
        bpl :-
        lda #0
        sta zp_chid
        rts

; ------------------------------------------------- opponent selection
; cache the guard slots' room/x for the kid: pick the closest live guard
; in the kid's room -> opp_* and opp_idx
pick_opponent:
        lda #0
        sta opp_ok
        lda #$ff
        sta opp_idx
        sta zp_dist             ; best distance so far
        ldx #0
@loop:  cpx #NGUARD
        bcs @done
        lda g_used,x
        beq @next
        ; peek at the guard state without a full swap
        txa
        pha
        tay
        jsr guard_state_ptr
        ldy #13                 ; +13 = alive
        lda (zp_ptr),y
        beq @pop
        ldy #0                  ; +0 = room
        lda (zp_ptr),y
        cmp kid_room
        bne @pop
        ; |kid.x - g.x| (low bytes suffice in-room)
        ldy #1
        lda kid_x
        sec
        sbc (zp_ptr),y
        bcs :+
        eor #$ff
        clc
        adc #1
:       cmp zp_dist
        bcs @pop
        sta zp_dist
        pla
        pha
        sta opp_idx
@pop:   pla
        tax
@next:  inx
        bne @loop
@done:  lda opp_idx
        cmp #$ff
        beq @none
        ; fill the opp cache from the chosen guard
        tay
        jsr guard_state_ptr
        ldy #0
        lda (zp_ptr),y
        sta opp_room
        ldy #1
        lda (zp_ptr),y
        sta opp_x
        ldy #2
        lda (zp_ptr),y
        sta opp_x+1
        ldy #5
        lda (zp_ptr),y
        sta opp_row
        ldy #10
        lda (zp_ptr),y
        sta opp_frame
        ldy #13
        lda (zp_ptr),y
        sta opp_alive
        ldy #14
        lda (zp_ptr),y
        sta opp_hp
        lda #1
        sta opp_ok
@none:  rts

; cache the KID as the opponent (before a guard swap)
guard_cache_opp:
        lda kid_room
        sta opp_room
        lda kid_x
        sta opp_x
        lda kid_x+1
        sta opp_x+1
        lda kid_row
        sta opp_row
        lda kid_frame
        sta opp_frame
        lda kid_alive
        sta opp_alive
        lda kid_swd
        sta opp_swd
        lda #1
        sta opp_ok
        rts

; |kid_x(now guard) - opp_x| -> zp_dist (clamped 255)
calc_dist:
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
        sta zp_dist
        rts
@pos:   stx zp_dist
        rts
@neg:   txa
        eor #$ff
        clc
        adc #1
        sta zp_dist
        rts

; ----------------------------------------------------------------- AI
; runs with the guard swapped into the zeropage struct (zp_chid = 2);
; the kid is cached in opp_*. Guard slot in zp_gi.
guard_control:
        lda kid_alive
        bne :+
        rts
:       ldx zp_gi
        lda g_cool,x
        beq :+
        dec g_cool,x
:       lda g_jblk,x
        beq :+
        dec g_jblk,x
:       ; same arena?
        lda opp_alive
        bne :+
        rts
:       lda opp_room
        cmp kid_room
        beq :+
        rts
:       lda opp_row
        cmp kid_row
        beq :+
        rts
:
        ; want_face: kid right of guard -> 1 else $ff
        jsr calc_dist
        lda kid_x
        cmp opp_x
        lda kid_x+1
        sbc opp_x+1
        bmi @wr
        lda #$ff                ; guard is right of the kid: face left
        bne @wf
@wr:    lda #1
@wf:    sta zp_tmp+2            ; want_face
        ldx zp_gi
        lda g_engaged,x
        bne @engaged
        lda #1
        sta g_engaged,x
        lda zp_tmp+2
        sta kid_face
        SEQSET SEQ_guardengarde
        rts
@engaged:
        ; parried the kid: counter or fall back
        lda kid_frame
        cmp #161
        bne @notparry
        jsr rnd
        ldx zp_gi
        ldy g_skill,x
        lda #77                 ; 0.30
@csk:   cpy #0
        beq @cchk
        clc
        adc #18                 ; +0.07/skill
        dey
        bne @csk
@cchk:  cmp zp_rnd
        bcc @cretreat
        SEQSET SEQ_blocktostrike
        rts
@cretreat:
        SEQSET SEQ_retreat
        rts
@notparry:
        ; reactive block while the kid's strike is committed (frame 152)
        lda opp_swd
        beq @noblock
        lda opp_frame
        cmp #152
        bne @noblock
        lda zp_dist
        cmp #BLOCK_FAR
        bcs @noblock
        ldx zp_gi
        lda g_jblk,x
        bne @noblock
        jsr guard_ready_frame
        bcc @noblock
        jsr rnd
        ldx zp_gi
        ldy g_skill,x
        lda #64                 ; 0.25
@bsk:   cpy #0
        beq @bchk
        clc
        adc #20                 ; +0.08/skill
        dey
        bne @bsk
@bchk:  cmp zp_rnd
        bcc @noblock
        SEQSET SEQ_readyblock
        rts
@noblock:
        ; only decide anew from the ready stances
        SEQGE SEQ_ready
        bcc @midmove
        SEQGE SEQEND_ready
        bcs @midmove
        jmp @decide
@midmove:
        SEQGE SEQ_guardengarde
        bcc @mid2
        SEQGE SEQEND_guardengarde
        bcs @mid2
        jmp @decide
@mid2:  SEQGE SEQ_alertstand
        bcc @out
        SEQGE SEQEND_alertstand
        bcs @out
@decide:
        lda zp_tmp+2
        cmp kid_face
        beq @faced
        sta kid_face
        rts
@faced: lda opp_swd
        bne @armed
        ; defenseless kid: run him through
        lda zp_dist
        cmp #OFFGUARD+1
        bcc @stab
        jsr floor_ahead
        bcc @out
        SEQSET SEQ_advance
        rts
@stab:  ldx zp_gi
        lda g_cool,x
        bne @out
        SEQSET SEQ_strike
        ldx zp_gi
        lda #6
        sta g_cool,x
@out:   rts
@armed: lda zp_dist
        cmp #STRIKE_FAR-4
        bcc @near
        jsr floor_ahead
        bcc @out
        SEQSET SEQ_advance
        rts
@near:  cmp #STRIKE_NEAR
        bcs @range
        jsr floor_behind
        bcc @out
        SEQSET SEQ_retreat
        rts
@range: ldx zp_gi
        lda g_cool,x
        bne @out
        jsr rnd
        ldx zp_gi
        ldy g_skill,x
        lda #64                 ; 0.25
@ssk:   cpy #0
        beq @schk
        clc
        adc #15                 ; +0.06/skill
        dey
        bne @ssk
@schk:  cmp zp_rnd
        bcc @out
        SEQSET SEQ_strike
        ; cooldown = 4 + max(0, 6-skill)
        ldx zp_gi
        lda #6
        sec
        sbc g_skill,x
        bpl :+
        lda #0
:       clc
        adc #4
        sta g_cool,x
        rts

; carry set if the guard is in a ready stance frame
guard_ready_frame:
        lda kid_frame
        cmp #158
        beq @yes
        cmp #165
        beq @yes
        cmp #168
        beq @yes
        cmp #170
        beq @yes
        cmp #171
        beq @yes
        clc
        rts
@yes:   sec
        rts

; floor & no barrier one column ahead/behind (guard in the zp struct)
floor_ahead:
        jsr kid_getcol
        clc
        adc kid_face
        jmp floor_chk
floor_behind:
        jsr kid_getcol
        sec
        sbc kid_face
floor_chk:
        pha
        ldx kid_row
        jsr k_isfloor
        bcs :+
        pla
        clc
        rts
:       pla
        ldx kid_row
        jsr k_isbarrier
        bcc @ok
        clc
        rts
@ok:    sec
        rts

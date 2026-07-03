; Dynamic tile machinery — port of levels/level.py: pressure plates and the
; LINKLOC/LINKMAP button wiring, gate state machines, loose floors with
; falling debris, and opening exit doors.
;
; Mutable tile state lives directly in the LEVEL blueprint (as on the
; Apple II); the first mutation of each position is recorded in a backup
; list so tiles_reset can restore the pristine level on death/restart.
; Visible changes push (col,row) onto a dirty queue; the main loop calls
; tiles_redraw between the kid restore and the kid draw.

        .include "pop.inc"

        .export tiles_init, tiles_reset, tiles_tick, tiles_redraw
        .export shake_loose, press_plate, loose_state, draw_falling
        .import lv_tile, lv_spec, lv_resolve, lv_calc, lv_link, LEVEL
        .import draw_block, draw_front_block, clear_block_rect
        .import piece_at, set_room_ptr
        .import BG_LOOSEA, BG_LOOSED

; gate machinery constants
GATE_MAX      = 188
GATE_RISE     = 4
GATE_DROP     = 50
GATE_TIMERV   = 50          ; open countdown after fully risen
PP_TIMER      = 5
LOOSE_DETACH  = 10
FF_ACCEL      = 3
FF_TERMVEL    = 29

MAXGATE  = 6
MAXPLATE = 4
MAXLOOSE = 6
MAXFALL  = 3
MAXDIRTY = 12
MAXBK    = 64

; local zeropage
zp_trm    = $90             ; trigger scratch: room
zp_tcc    = $91             ;   col
zp_trr    = $92             ;   row
zp_ptype  = $93             ; plate type driving the trigger
zp_jam    = $94             ; 1 = jam gates (rubble on plate)
zp_li     = $95             ; link walker index
zp_ls     = $96             ; link walker guard counter
zp_slot   = $97             ; current slot index
zp_pos    = $98             ; gate position scratch
zp_yb     = $99             ; 2  falling floor scratch
zp_prow   = $9b             ; falling: row before move
zp_gmode  = $9c             ; gate mode scratch
zp_wide   = $9d             ; redraw spills into the row above

        .segment "BSS"
gate_rm:  .res MAXGATE      ; 0 = free slot
gate_c:   .res MAXGATE
gate_r:   .res MAXGATE
gate_md:  .res MAXGATE      ; 1 rise, 2 drop, 3 close, 4 open countdown
gate_tm:  .res MAXGATE
pl_rm:    .res MAXPLATE
pl_c:     .res MAXPLATE
pl_r:     .res MAXPLATE
pl_tm:    .res MAXPLATE
lo_rm:    .res MAXLOOSE
lo_c:     .res MAXLOOSE
lo_r:     .res MAXLOOSE
lo_ct:    .res MAXLOOSE
ff_rm:    .res MAXFALL
ff_c:     .res MAXFALL
ff_ylo:   .res MAXFALL
ff_yhi:   .res MAXFALL
ff_vel:   .res MAXFALL
ff_cr:    .res MAXFALL
ex_rm:    .res 2            ; opening exit doors
ex_c:     .res 2
ex_r:     .res 2
dq_c:     .res MAXDIRTY
dq_r:     .res MAXDIRTY
dq_n:     .res 1
bk_ofl:   .res MAXBK        ; backup: LEVEL offset of BLUETYPE byte
bk_ofh:   .res MAXBK
bk_ty:    .res MAXBK
bk_sp:    .res MAXBK
bk_n:     .res 1

        .segment "CODE"

; ---------------------------------------------------------------- init
tiles_init:
        lda #0
        sta bk_n
tiles_clear_state:
        lda #0
        ldx #MAXGATE-1
:       sta gate_rm,x
        dex
        bpl :-
        ldx #MAXPLATE-1
:       sta pl_rm,x
        dex
        bpl :-
        ldx #MAXLOOSE-1
:       sta lo_rm,x
        dex
        bpl :-
        ldx #MAXFALL-1
:       sta ff_rm,x
        dex
        bpl :-
        sta ex_rm
        sta ex_rm+1
        sta dq_n
        rts

; restore all mutated tiles and clear the machinery (level restart)
tiles_reset:
        ldx #0
        cpx bk_n
        beq @done
@loop:  lda bk_ofl,x
        sta zp_ptr
        lda bk_ofh,x
        clc
        adc #>LEVEL
        sta zp_ptr+1
        lda zp_ptr
        clc
        adc #<LEVEL
        sta zp_ptr
        bcc :+
        inc zp_ptr+1
:       ldy #0
        lda bk_ty,x
        sta (zp_ptr),y          ; BLUETYPE
        ; spec lives 720 bytes later
        clc
        lda zp_ptr
        adc #<720
        sta zp_ptr
        lda zp_ptr+1
        adc #>720
        sta zp_ptr+1
        lda bk_sp,x
        sta (zp_ptr),y
        inx
        cpx bk_n
        bne @loop
@done:  lda #0
        sta bk_n
        jmp tiles_clear_state

; --------------------------------------------------------- set/backup
; Point zp_ptr at the BLUETYPE byte of resolved (zp_rrm, zp_rc, zp_rr);
; also record the position's original type+spec on first touch.
; Preserves nothing. Y ends as the in-room index.
tile_ptr_backup:
        lda #<LV_BLUETYPE
        ldx #>LV_BLUETYPE
        jsr lv_calc             ; zp_ptr -> type byte (with Y index)
        ; absolute offset = ptr + Y - LEVEL for the backup key
        tya
        clc
        adc zp_ptr
        sta zp_tmp
        lda zp_ptr+1
        adc #0
        sta zp_tmp+1
        sec
        lda zp_tmp
        sbc #<LEVEL
        sta zp_tmp
        lda zp_tmp+1
        sbc #>LEVEL
        sta zp_tmp+1
        ; already recorded?
        ldx bk_n
        beq @record
        ldx #0
@find:  lda bk_ofl,x
        cmp zp_tmp
        bne @next
        lda bk_ofh,x
        cmp zp_tmp+1
        beq @have
@next:  inx
        cpx bk_n
        bne @find
@record:
        ldx bk_n
        cpx #MAXBK
        bcs @have               ; list full: give up on restore fidelity
        lda zp_tmp
        sta bk_ofl,x
        lda zp_tmp+1
        sta bk_ofh,x
        lda (zp_ptr),y
        sta bk_ty,x
        sty zp_tmp
        stx zp_tmp+1
        ; spec byte
        lda zp_ptr
        pha
        lda zp_ptr+1
        pha
        clc
        lda zp_ptr
        adc #<720
        sta zp_ptr
        lda zp_ptr+1
        adc #>720
        sta zp_ptr+1
        ldx zp_tmp+1
        lda (zp_ptr),y
        sta bk_sp,x
        pla
        sta zp_ptr+1
        pla
        sta zp_ptr
        ldy zp_tmp
        inc bk_n
@have:  rts

; set tile type A and spec X at resolved (zp_rrm, zp_rc, zp_rr)
set_tile:
        pha
        txa
        pha
        jsr tile_ptr_backup
        pla
        tax
        pla
        sta (zp_ptr),y          ; type
        clc
        lda zp_ptr
        adc #<720
        sta zp_ptr
        lda zp_ptr+1
        adc #>720
        sta zp_ptr+1
        txa
        sta (zp_ptr),y          ; spec
        jmp mark_dirty

; set only the spec byte (gate positions)
set_spec:
        pha
        jsr tile_ptr_backup
        clc
        lda zp_ptr
        adc #<720
        sta zp_ptr
        lda zp_ptr+1
        adc #>720
        sta zp_ptr+1
        pla
        sta (zp_ptr),y
        jmp mark_dirty

; ----------------------------------------------------------- dirty queue
; queue (zp_rc, zp_rr) of room zp_rrm for redraw if it's on screen
mark_dirty:
        lda zp_rrm
        cmp zp_visroom
        beq :+
        rts
:       ldx dq_n
        cpx #MAXDIRTY
        bcs @full
        ; dedupe
        ldx #0
        cpx dq_n
        beq @push
@scan:  lda dq_c,x
        cmp zp_rc
        bne @nx
        lda dq_r,x
        cmp zp_rr
        beq @done
@nx:    inx
        cpx dq_n
        bne @scan
@push:  ldx dq_n
        lda zp_rc
        sta dq_c,x
        lda zp_rr
        sta dq_r,x
        inc dq_n
@full:
@done:  rts

; redraw all queued tiles: clear the four affected block rects, then
; draw_block + fronts over the 3x3 neighbourhood (top-down order)
tiles_redraw:
        lda dq_n
        bne :+
        rts
:       lda #0
        sta zp_slot
@tile:  ldx zp_slot
        lda dq_c,x
        sta zp_tcc
        lda dq_r,x
        sta zp_trr
        jsr set_room_ptr        ; zp_rm = zp_visroom for lv queries
        ; gates and exits spill into the row above: full 4-rect clear and
        ; 3x3 repaint; everything else only touches its own row
        lda zp_tcc
        sta zp_tc
        lda zp_trr
        sta zp_tr
        jsr lv_tile
        cmp #T_GATE
        beq @wide
        cmp #T_EXIT
        beq @wide
        cmp #T_EXIT2
        beq @wide
        lda #0
        sta zp_wide
        beq @clears
@wide:  lda #1
        sta zp_wide
@clears:
        beq @clr2
        ; clear rects (c,r-1) (c+1,r-1)
        lda zp_tcc
        ldx zp_trr
        dex
        jsr clear_block_rect
        lda zp_tcc
        clc
        adc #1
        ldx zp_trr
        dex
        jsr clear_block_rect
@clr2:  lda zp_tcc
        ldx zp_trr
        jsr clear_block_rect
        lda zp_tcc
        clc
        adc #1
        ldx zp_trr
        jsr clear_block_rect
        ; redraw around (c,r), rows top-down (start at r-1 only when wide)
        lda zp_trr
        sec
        sbc zp_wide
        sta zp_drow
@rl:    lda zp_tcc
        sec
        sbc #1
        sta zp_dcol
@cl:    jsr in_range
        bcc @skipb
        jsr draw_block
@skipb: inc zp_dcol
        lda zp_dcol
        sec
        sbc zp_tcc
        cmp #2
        bne @cl
        inc zp_drow
        lda zp_drow
        sec
        sbc zp_trr
        cmp #2
        bne @rl
        ; foreground pass over the same blocks
        lda zp_trr
        sec
        sbc zp_wide
        sta zp_drow
@frl:   lda zp_tcc
        sec
        sbc #1
        sta zp_dcol
@fcl:   jsr in_range
        bcc @skipf
        jsr draw_front_block
@skipf: inc zp_dcol
        lda zp_dcol
        sec
        sbc zp_tcc
        cmp #2
        bne @fcl
        inc zp_drow
        lda zp_drow
        sec
        sbc zp_trr
        cmp #2
        bne @frl
        inc zp_slot
        lda zp_slot
        cmp dq_n
        beq :+
        jmp @tile
:       lda #0
        sta dq_n
        rts

; carry set if (zp_dcol, zp_drow) is a drawable block (-1..10, -1..2)
in_range:
        lda zp_dcol
        cmp #$ff
        beq @cok
        cmp #11
        bcs @no
@cok:   lda zp_drow
        cmp #$ff
        beq @rok
        cmp #3
        bcs @no
@rok:   sec
        rts
@no:    clc
        rts

; -------------------------------------------------------------- plates
; press the plate at (zp_rm, zp_tc, zp_tr); zp_jam preset (0 normally)
press_plate:
        jsr lv_tile             ; resolves into zp_rrm/rc/rr
        cmp #T_PRESS
        beq @ok
        cmp #T_UPRESS
        beq @ok
        cmp #T_DPRESS
        beq @ok
        rts
@ok:    ; plate type for the trigger: dpress acts like press
        cmp #T_DPRESS
        bne :+
        lda #T_PRESS
:       sta zp_ptype
        ; find or allocate a slot, refresh timer
        ldx #MAXPLATE-1
@find:  lda pl_rm,x
        beq @nx
        lda pl_rm,x
        cmp zp_rrm
        bne @nx
        lda pl_c,x
        cmp zp_rc
        bne @nx
        lda pl_r,x
        cmp zp_rr
        beq @slot
@nx:    dex
        bpl @find
        ; new slot
        ldx #MAXPLATE-1
@alloc: lda pl_rm,x
        beq @take
        dex
        bpl @alloc
        jmp @trigger            ; no slot: still trigger
@take:  lda zp_rrm
        sta pl_rm,x
        lda zp_rc
        sta pl_c,x
        lda zp_rr
        sta pl_r,x
@slot:  lda #PP_TIMER
        sta pl_tm,x
        ; pressed-down art
        lda zp_tile
        cmp #T_PRESS
        bne @trigger
        lda #T_DPRESS
        ldx zp_spec
        jsr set_tile
@trigger:
        ; link index = spec of the plate
        lda zp_rrm
        sta zp_rm
        lda zp_rc
        sta zp_tc
        lda zp_rr
        sta zp_tr
        jsr lv_spec
        sta zp_li
        ; walk the LINKLOC/LINKMAP chain
        lda #32
        sta zp_ls
@walk:  ldx zp_li
        lda LEVEL+LV_LINKLOC,x
        cmp #$ff
        bne :+
        rts
:       pha                     ; linkloc byte
        and #$1f
        tay                     ; loc 0..29
        ; col = loc % 10, row = loc / 10
        ldx #0
        tya
@dv:    cmp #10
        bcc @dvd
        sbc #10
        inx
        bne @dv
@dvd:   sta zp_tcc
        stx zp_trr
        ; screen = ((linkmap & $e0) >> 3) | ((linkloc & $60) >> 5)
        ldx zp_li
        lda LEVEL+LV_LINKMAP,x
        and #$e0
        lsr
        lsr
        lsr
        sta zp_trm
        pla
        pha
        and #$60
        lsr
        lsr
        lsr
        lsr
        lsr
        ora zp_trm
        sta zp_trm
        ; act on the target tile
        lda zp_trm
        sta zp_rm
        lda zp_tcc
        sta zp_tc
        lda zp_trr
        sta zp_tr
        jsr lv_tile
        cmp #T_GATE
        bne @notgate
        jsr trigger_gate
        jmp @chain
@notgate:
        cmp #T_EXIT
        beq @exit
        cmp #T_EXIT2
        beq @exit
        jmp @chain
@exit:  jsr open_exit
@chain: pla                     ; linkloc byte: bit7 = last link
        bmi @end
        inc zp_li
        dec zp_ls
        beq @end
        jmp @walk
@end:   rts

; tick the plate timers: expiry restores the raised art
plates_tick:
        ldx #MAXPLATE-1
@loop:  lda pl_rm,x
        beq @next
        dec pl_tm,x
        bne @next
        lda pl_rm,x
        sta zp_rm
        lda pl_c,x
        sta zp_tc
        lda pl_r,x
        sta zp_tr
        stx zp_slot
        jsr lv_tile
        cmp #T_DPRESS
        bne @free
        lda #T_PRESS
        ldx zp_spec
        jsr set_tile
@free:  ldx zp_slot
        lda #0
        sta pl_rm,x
@next:  dex
        bpl @loop
        rts

; --------------------------------------------------------------- gates
; trigger the gate at resolved (zp_rrm, zp_rc, zp_rr): raise for upress
; plates, drop for press plates; zp_jam set = jam permanently open
trigger_gate:
        jsr lv_spec             ; current position (coords still in zp_rm/tc/tr)
        lda zp_spec
        cmp #$ff                ; jammed: ignore
        bne :+
        rts
:       sta zp_pos
        lda zp_jam
        beq @notjam
        lda #T_GATE
        ldx #$ff
        jsr set_tile
        jmp free_gate_slot
@notjam:
        lda zp_ptype
        cmp #T_UPRESS
        beq @raise
        ; press plate: drop the gate fast if it's open at all
        lda zp_pos
        bne :+
        rts
:       lda #2                  ; dropping
        jmp gate_slot_set
@raise: lda zp_pos
        cmp #GATE_MAX
        bcc :+
        ; already fully open: refresh the countdown
        lda #4
        jmp gate_slot_set
:       lda #1                  ; rising
        jmp gate_slot_set

; put the gate at (zp_rrm/rc/rr) into mode A (finds or allocates a slot)
gate_slot_set:
        sta zp_gmode
        ldx #MAXGATE-1
@find:  lda gate_rm,x
        beq @nx
        cmp zp_rrm
        bne @nx
        lda gate_c,x
        cmp zp_rc
        bne @nx
        lda gate_r,x
        cmp zp_rr
        beq @have
@nx:    dex
        bpl @find
        ldx #MAXGATE-1
@alloc: lda gate_rm,x
        beq @take
        dex
        bpl @alloc
        rts                     ; out of slots
@take:  lda zp_rrm
        sta gate_rm,x
        lda zp_rc
        sta gate_c,x
        lda zp_rr
        sta gate_r,x
@have:  lda zp_gmode
        sta gate_md,x
        cmp #4
        bne :+
        lda #GATE_TIMERV
        sta gate_tm,x
:       rts

free_gate_slot:
        ldx #MAXGATE-1
@f:     lda gate_rm,x
        cmp zp_rrm
        bne @n
        lda gate_c,x
        cmp zp_rc
        bne @n
        lda gate_r,x
        cmp zp_rr
        bne @n
        lda #0
        sta gate_rm,x
@n:     dex
        bpl @f
        rts

gates_tick:
        ldx #MAXGATE-1
@loop:  lda gate_rm,x
        bne :+
        jmp @next
:       stx zp_slot
        sta zp_rm
        lda gate_c,x
        sta zp_tc
        lda gate_r,x
        sta zp_tr
        jsr lv_spec             ; zp_spec = pos, resolves rrm/rc/rr
        lda zp_spec
        sta zp_pos
        ldx zp_slot
        lda gate_md,x
        cmp #4
        beq @timing
        cmp #1
        beq @rise
        cmp #2
        beq @drop
        ; mode 3: creak shut
        dec zp_pos
        bne @store
        jmp @slam
@timing:
        dec gate_tm,x
        bne @next2
        lda #3                  ; countdown over: creak shut
        sta gate_md,x
        jmp @next2
@rise:  lda zp_pos
        clc
        adc #GATE_RISE
        cmp #GATE_MAX
        bcs @full
        sta zp_pos
        jmp @store
@full:  lda #GATE_MAX
        jsr set_spec
        ldx zp_slot
        lda #4                  ; open: start the countdown
        sta gate_md,x
        lda #GATE_TIMERV
        sta gate_tm,x
        jmp @next2
@drop:  lda zp_pos
        sec
        sbc #GATE_DROP
        bcc @slam
        beq @slam
        sta zp_pos
@store: lda zp_pos
        jsr set_spec
        jmp @next2
@slam:  lda #0
        jsr set_spec
        ldx zp_slot
        lda #0
        sta gate_rm,x
@next2: ldx zp_slot
@next:  dex
        bmi :+
        jmp @loop
:       rts

; --------------------------------------------------------------- exits
; a trigger opened the exit at resolved (zp_rrm/rc/rr): spec 0 -> 1 and
; register the door to slide open; open both halves of the pair
open_exit:
        jsr lv_spec
        lda zp_spec
        beq :+
        rts                     ; already opening/open
:       lda zp_tile
        ldx #1
        jsr set_tile            ; spec 1: starts sliding
        jsr exit_slot
        ; the neighbouring half of the door pair
        lda zp_rrm
        sta zp_rm
        lda zp_rc
        clc
        adc #1
        sta zp_tc
        lda zp_rr
        sta zp_tr
        jsr lv_tile
        cmp #T_EXIT
        beq @pair
        cmp #T_EXIT2
        beq @pair
        rts
@pair:  jsr lv_spec
        bne @done
        lda zp_tile
        ldx #1
        jsr set_tile
        jsr exit_slot
@done:  rts

exit_slot:
        ldx #1
@f:     lda ex_rm,x
        beq @take
        dex
        bpl @f
        rts
@take:  lda zp_rrm
        sta ex_rm,x
        lda zp_rc
        sta ex_c,x
        lda zp_rr
        sta ex_r,x
        rts

exits_tick:
        ldx #1
@loop:  lda ex_rm,x
        beq @next
        stx zp_slot
        sta zp_rm
        lda ex_c,x
        sta zp_tc
        lda ex_r,x
        sta zp_tr
        jsr lv_tile             ; refresh rrm/rc/rr + zp_tile
        jsr lv_spec
        clc
        adc #4
        cmp #48
        bcc :+
        lda #48
:       pha
        tax
        lda zp_tile
        jsr set_tile
        pla
        cmp #48
        bne @keep
        ldx zp_slot
        lda #0
        sta ex_rm,x
@keep:  ldx zp_slot
@next:  dex
        bpl @loop
        rts

; --------------------------------------------------------- loose floors
; start the loose floor at (zp_rm, zp_tc, zp_tr) wiggling
shake_loose:
        jsr lv_tile
        cmp #T_LOOSE
        beq :+
        rts
:       ldx #MAXLOOSE-1
@find:  lda lo_rm,x
        beq @nx
        cmp zp_rrm
        bne @nx
        lda lo_c,x
        cmp zp_rc
        bne @nx
        lda lo_r,x
        cmp zp_rr
        bne @nx
        rts                     ; already shaking
@nx:    dex
        bpl @find
        ldx #MAXLOOSE-1
@alloc: lda lo_rm,x
        beq @take
        dex
        bpl @alloc
        rts
@take:  lda zp_rrm
        sta lo_rm,x
        lda zp_rc
        sta lo_c,x
        lda zp_rr
        sta lo_r,x
        lda #0
        sta lo_ct,x
        rts

; wiggle state of resolved (zp_rm, zp_tc, zp_tr) -> A (0 = still)
loose_state:
        jsr lv_resolve
        ldx #MAXLOOSE-1
@find:  lda lo_rm,x
        beq @nx
        cmp zp_rrm
        bne @nx
        lda lo_c,x
        cmp zp_rc
        bne @nx
        lda lo_r,x
        cmp zp_rr
        bne @nx
        lda lo_ct,x
        rts
@nx:    dex
        bpl @find
        lda #0
        rts

loose_tick:
        ldx #MAXLOOSE-1
@loop:  lda lo_rm,x
        beq @next
        stx zp_slot
        inc lo_ct,x
        ; redraw the wiggle every tick
        sta zp_rm
        lda lo_c,x
        sta zp_tc
        lda lo_r,x
        sta zp_tr
        jsr lv_resolve
        jsr mark_dirty
        ldx zp_slot
        lda lo_ct,x
        cmp #LOOSE_DETACH
        bcc @next2
        ; detach: tile becomes empty space, debris starts falling
        lda #0
        sta lo_rm,x
        lda #T_SPACE
        ldx #0
        jsr set_tile
        ; falling slot
        ldx #MAXFALL-1
@alloc: lda ff_rm,x
        beq @take
        dex
        bpl @alloc
        jmp @next2
@take:  lda zp_rrm
        sta ff_rm,x
        lda zp_rc
        sta ff_c,x
        ; y = block_bot(row) - 3 = 62 + row*63
        lda zp_rr
        sta zp_tmp
        lda #62
        ldy zp_tmp
        beq :+
@mul:   clc
        adc #63
        dey
        bne @mul
:       sta ff_ylo,x
        lda #0
        sta ff_yhi,x
        sta ff_vel,x
        sta ff_cr,x
@next2: ldx zp_slot
@next:  dex
        bpl @loop
        rts

falling_tick:
        ldx #MAXFALL-1
@loop:  lda ff_rm,x
        bne :+
        jmp @next
:       stx zp_slot
        lda ff_cr,x
        beq @fall
        inc ff_cr,x
        lda ff_cr,x
        cmp #3
        bcc @nx2
        lda #0                  ; debris cleaned up (rubble tile remains)
        sta ff_rm,x
@nx2:   jmp @next2
@fall:  ; mark the old position dirty
        lda ff_rm,x
        sta zp_rm
        jsr ff_mark_dirty
        ldx zp_slot
        ; vel = min(vel + 3, 29)
        lda ff_vel,x
        clc
        adc #FF_ACCEL
        cmp #FF_TERMVEL+1
        bcc :+
        lda #FF_TERMVEL
:       sta ff_vel,x
        ; y += vel
        clc
        adc ff_ylo,x
        sta ff_ylo,x
        bcc :+
        inc ff_yhi,x
:       ; row of (y - VERT_DIST)
        jsr ff_row
        sta zp_prow
        cmp #3
        bcc @inroom
        ; passed the bottom: continue in the room below
        lda ff_rm,x
        ldx #3                  ; down
        jsr lv_link
        bne @below
        ldx zp_slot             ; fell out of the world
        lda #0
        sta ff_rm,x
        jmp @next2
@below: ldx zp_slot
        sta ff_rm,x
        ; y -= 189
        sec
        lda ff_ylo,x
        sbc #189
        sta ff_ylo,x
        lda ff_yhi,x
        sbc #0
        sta ff_yhi,x
        jsr ff_row
        sta zp_prow
@inroom:
        ; landed? floor at (col,row) and y >= block_bot(row)-3
        lda zp_prow
        bpl :+
        jmp @moved
:
        lda ff_rm,x
        sta zp_rm
        lda ff_c,x
        sta zp_tc
        lda zp_prow
        sta zp_tr
        jsr lv_tile
        tay                     ; tile under the debris
        ; is_floor?
        lda FLOORFLAG2,y
        beq @moved
        ; y >= 62 + row*63 ?
        lda zp_prow
        sta zp_tmp
        lda #62
        ldy zp_tmp
        beq :+
@m63:   clc
        adc #63
        dey
        bne @m63
:       sta zp_yb
        ldx zp_slot
        lda ff_ylo,x
        cmp zp_yb
        bcc @moved
        ; crash: knock the next loose floor / jam plates / leave rubble
        lda zp_tile
        cmp #T_LOOSE
        bne :+
        jsr shake_loose
        jmp @rubble
:       cmp #T_PRESS
        beq @jamplate
        cmp #T_UPRESS
        beq @jamplate
        cmp #T_DPRESS
        bne @rubble
@jamplate:
        lda #1
        sta zp_jam
        jsr press_plate
        lda #0
        sta zp_jam
@rubble:
        ldx zp_slot
        lda ff_rm,x
        sta zp_rm
        lda ff_c,x
        sta zp_tc
        lda zp_prow
        sta zp_tr
        jsr lv_resolve
        lda #T_RUBBLE
        ldx #0
        jsr set_tile
        ldx zp_slot
        lda zp_yb
        sta ff_ylo,x
        lda #0
        sta ff_yhi,x
        lda #1
        sta ff_cr,x
@moved: ldx zp_slot
        lda ff_rm,x
        sta zp_rm
        jsr ff_mark_dirty
@next2: ldx zp_slot
@next:  dex
        bmi :+
        jmp @loop
:       rts

; row of debris X at (y - VERT_DIST): ((y-10)+7)/63 -> A
ff_row:
        sec
        lda ff_ylo,x
        sbc #3                  ; -10+7
        sta zp_yb
        lda ff_yhi,x
        sbc #0
        bmi @neg
        sta zp_yb+1
        ldy #0
@dv:    lda zp_yb+1
        bne @ge
        lda zp_yb
        cmp #63
        bcc @done
@ge:    sec
        lda zp_yb
        sbc #63
        sta zp_yb
        lda zp_yb+1
        sbc #0
        sta zp_yb+1
        iny
        bne @dv
@done:  tya
        rts
@neg:   lda #$ff
        rts

; mark the debris' current and previous row blocks dirty (col preserved)
ff_mark_dirty:
        lda ff_c,x
        sta zp_rc
        jsr ff_row
        sta zp_rr
        lda zp_rm
        sta zp_rrm
        jsr mark_dirty
        ldx zp_slot
        lda ff_c,x
        sta zp_rc
        jsr ff_row
        sec
        sbc #1
        sta zp_rr
        lda zp_rm
        sta zp_rrm
        jsr mark_dirty
        ldx zp_slot
        rts

; draw active debris in the visible room (after tiles_redraw)
draw_falling:
        ldx #MAXFALL-1
@loop:  lda ff_rm,x
        beq @next
        cmp zp_visroom
        bne @next
        lda ff_cr,x
        bne @next               ; crashed: the rubble tile shows it
        stx zp_slot
        ; bottom y
        lda ff_ylo,x
        sta zp_by
        lda ff_yhi,x
        sta zp_by+1
        lda ff_c,x
        clc
        adc #1                  ; piece_at column index
        tax
        ldy #0
        lda BG_LOOSEA
        jsr piece_at
        ldx zp_slot
        lda ff_ylo,x
        clc
        adc #3
        sta zp_by
        lda ff_yhi,x
        adc #0
        sta zp_by+1
        lda ff_c,x
        clc
        adc #1
        tax
        ldy #0
        lda BG_LOOSED
        jsr piece_at
        ldx zp_slot
@next:  dex
        bpl @loop
        rts

; local floor table (mirrors game.s FLOORFLAG)
        .segment "RODATA"
FLOORFLAG2:
        .byte 0,1,1,1,1,1,1,1,1,0, 1,1,0,1,1,1, 1,1,1,1, 0,1,1,1,1,1, 0,0,0,0
        .segment "CODE"

; ---------------------------------------------------------------- tick
tiles_tick:
        lda #0
        sta zp_jam
        jsr gates_tick
        jsr plates_tick
        jsr loose_tick
        jsr falling_tick
        jmp exits_tick

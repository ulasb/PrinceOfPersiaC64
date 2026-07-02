; Prince of Persia C64 — shared constants, memory map, zeropage layout.

; ------------------------------------------------------------- geometry
TILE_W      = 14            ; game px per block
ROW_H       = 63            ; game px per row
ROOM_W      = 10
ROOM_H      = 3
SCREEN_W    = 140           ; playfield width in game px
PLAYFIELD_X = 10            ; left margin on the 160px mc screen
VERT_DIST   = 10

; tile ids
T_SPACE     = 0
T_FLOOR     = 1
T_SPIKES    = 2
T_POSTS     = 3
T_GATE      = 4
T_DPRESS    = 5
T_PRESS     = 6
T_PANELWIF  = 7
T_PILLARBOT = 8
T_PILLARTOP = 9
T_FLASK     = 10
T_LOOSE     = 11
T_PANELWOF  = 12
T_MIRROR    = 13
T_RUBBLE    = 14
T_UPRESS    = 15
T_EXIT      = 16
T_EXIT2     = 17
T_SLICER    = 18
T_TORCH     = 19
T_BLOCK     = 20
T_BONES     = 21
T_SWORD     = 22
T_ARCHBOT   = 25

; level blueprint offsets (2304-byte format)
LV_BLUETYPE = 0
LV_BLUESPEC = 720
LV_LINKLOC  = 1440
LV_LINKMAP  = 1696
LV_MAP      = 1952
LV_INFO     = 2048

; physics
GRAVITY     = 3
TERMVEL     = 33
OOF_VEL     = 22

; ------------------------------------------------------------ memory map
; $0400 ROWLO, $0500 ROWHI (bitmap row address tables, y 0..199)
; $0801-$37ff  code + tables + level     $3800-$8bff gfx window 1
; $8c00 VIC matrix (bank 2)              $9000-$9fff gfx window 9
; $a000-$bf3f  bitmap                    $c000-$cfff gfx window C
; $e000-$efff  gfx window H (copied at init from the bitmap load hole)
; $f000-$f8ff  blit tables               $f900-$fcff char buffers
ROWLO       = $0400
ROWHI       = $0500
VIC_MATRIX  = $8c00
BITMAP      = $a000
SAVEBUF     = $f900         ; $f900-$faff save-under (8 cols x 64 rows)
COMPOSE     = $fb00         ; $fb00-$fcff character frame compose buffer
TAB_SHR2    = $f000         ; >>2
TAB_SHR4    = $f100         ; >>4
TAB_SHR6    = $f200         ; >>6
TAB_SHL6    = $f300         ; <<6 (pairs with SHR2)
TAB_SHL4    = $f400         ; <<4
TAB_SHL2    = $f500         ; <<2
TAB_MASK    = $f600         ; AND-mask: 11 where 2px pair is 00
ROWBUF      = $f700         ; shifted row scratch (17 bytes used)
TAB_REV     = $f800         ; reverse the four 2px pairs in a byte

; ------------------------------------------------------------- zeropage
zp_img      = $02           ; 2  piece/image data pointer
zp_dst      = $04           ; 2  bitmap dest
zp_src      = $06           ; 2  walking source
zp_bx       = $08           ; 2  blit x, s16 (mc px incl. margin)
zp_by       = $0a           ; 2  blit bottom y, s16
zp_wb       = $0c           ; 1  image width bytes
zp_h        = $0d           ; 1  image height
zp_shift    = $0e           ; 1  x & 3
zp_prev     = $0f           ; 1  shift carry byte
zp_val      = $10           ; 1
zp_j        = $11           ; 1
zp_jmax     = $12           ; 1
zp_nrows    = $13           ; 1
zp_srow     = $14           ; 1  first source row after clip
zp_ytop     = $15           ; 2  clipped top y
zp_bc0      = $17           ; 1  leftmost byte column (signed)

zp_rm       = $20           ; 1  current room for tile queries
zp_tc       = $21           ; 1  col arg (signed -1..11)
zp_tr       = $22           ; 1  row arg (signed -1..3)
zp_tile     = $23           ; 1  resolved tile
zp_spec     = $24           ; 1  resolved spec
zp_rrm      = $25           ; 1  resolved room
zp_rc       = $26           ; 1  resolved col
zp_rr       = $27           ; 1  resolved row

zp_dcol     = $28           ; 1  draw block col (signed)
zp_drow     = $29           ; 1  draw block row (signed)
zp_ay       = $2a           ; 2  A/B anchor y (s16)
zp_dy       = $2c           ; 2  C/D anchor y (s16)
zp_t        = $2e           ; 1  tile at draw block
zp_room     = $2f           ; 1  room being drawn
zp_pid      = $30           ; 1  piece image id
zp_gy       = $31           ; 2  gate segment walker
zp_gtop     = $33           ; 2
zp_tmp      = $35           ; 4  scratch
zp_ptr      = $3a           ; 2  generic pointer

; character/tick state
zp_tick     = $40           ; 1  game tick counter
zp_frame    = $41           ; 1  frame counter (50Hz)
zp_input    = $42           ; 1  bits: 0=up 1=down 2=left 3=right 4=shift
zp_inedge   = $43           ; 1  newly pressed this tick (same bits)
zp_previn   = $44           ; 1

; the kid (Char struct)
kid_room    = $50           ; 1
kid_x       = $51           ; 2  s16 game px, room-local
kid_y       = $53           ; 2  s16 feet scanline
kid_row     = $55           ; 1  s8
kid_face    = $56           ; 1  1 or $ff
kid_action  = $57           ; 1
kid_xvel    = $58           ; 1  s8
kid_yvel    = $59           ; 1  s8
kid_frame   = $5a           ; 1
kid_seq     = $5b           ; 2  offset into SEQTABLE
kid_alive   = $5d           ; 1
kid_hp      = $5e           ; 1
kid_hangt   = $5f           ; 1  hang tick counter
kid_events  = $60           ; 1  bit0 die, bit1 nextlevel, bit2 jaru, bit3 jard
kid_prevy   = $61           ; 2  y before this tick's motion

; scratch for control/collision
zp_col      = $63           ; 1  s8 current column of kid_x
zp_xrem     = $64           ; 1  kid_x mod 14
zp_d        = $65           ; 1  direction input: 1, $ff or 0
zp_ledge    = $66           ; 1
zp_visroom  = $67           ; 1  room currently on screen
zp_dead_t   = $68           ; 1  respawn countdown after death
zp_moved    = $69           ; 1  bit0: room changed, redraw needed

; actions
ACT_STAND     = 0
ACT_MOVE      = 1
ACT_HANG      = 2
ACT_MIDAIR    = 3
ACT_FREEFALL  = 4
ACT_BUMPED    = 5
ACT_HANGSTR   = 6
ACT_TURN      = 7

; input bits
IN_UP    = 1
IN_DOWN  = 2
IN_LEFT  = 4
IN_RIGHT = 8
IN_SHIFT = 16

; start a named sequence (offsets from seqtable.s; import kid_start_seq)
.macro SEQSET name
        lda #<name
        ldx #>name
        jsr kid_start_seq
.endmacro

; carry set if kid_seq >= val (16-bit)
.macro SEQGE val
        lda kid_seq
        cmp #<val
        lda kid_seq+1
        sbc #>val
.endmacro

zp_tcnt     = $6a           ; frames until next game tick
zp_fcol     = $6b           ; fronts_near_kid scan origin
zp_frow     = $6c
zp_vskip    = $6d           ; blit: crop N rows off the image top (one-shot)
zp_lvdone   = $6e           ; nextlevel event latched

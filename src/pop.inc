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
; $4000-$5bff  gfx window 1        $5c00 VIC matrix   $6000 bitmap
; $8000-$cffd  gfx window 2        $e000-$e7ff gfx window H (copied at init)
; $e800-$efff  save-under buffers  $f000-$f7ff blit shift tables
ROWLO       = $0400
ROWHI       = $0500
VIC_MATRIX  = $5c00
BITMAP      = $6000
SAVEBUF     = $e800
TAB_SHR2    = $f000         ; >>2
TAB_SHR4    = $f100         ; >>4
TAB_SHR6    = $f200         ; >>6
TAB_SHL6    = $f300         ; <<6 (pairs with SHR2)
TAB_SHL4    = $f400         ; <<4
TAB_SHL2    = $f500         ; <<2
TAB_MASK    = $f600         ; AND-mask: 11 where 2px pair is 00
ROWBUF      = $f700         ; shifted row scratch (17 bytes used)
COMPOSE     = $e900         ; character frame compose buffer

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

; character/tick state (later modules)
zp_tick     = $40           ; 1  game tick counter
zp_frame    = $41           ; 1  frame counter (50Hz)
zp_input    = $42           ; 1  joystick bits: 0=up 1=down 2=left 3=right 4=btn

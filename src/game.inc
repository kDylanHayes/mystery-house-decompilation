; Constants for the game database: vocabulary, rule opcodes, object states.

ANY      = $FE    ; rule header: matches any room / verb / noun
CARRIED  = $FE    ; object room: in the inventory
NOWHERE  = $FD    ; object room: not in the game yet / gone
OMOVABLE = 0      ; object status (names from the original source)
OMOVED   = 1
OFIXED   = 2

; conditions (tbl_conditions)
C_OBJ_IN_ROOM      = 3    ; 2 operand(s)
C_TURNS_GT         = 5    ; 1 operand(s)
C_SWITCH_EQ        = 6    ; 2 operand(s)
C_VIEW_IS          = 9    ; 1 operand(s)
C_OBJ_PIC_IS       = 10    ; 2 operand(s)

; actions (tbl_actions; handler ACnn00 with nn = op + 10)
A_ADD_SWITCH       = 1    ; 2 operand(s)
A_SUB_SWITCH       = 2    ; 2 operand(s)
A_SET_SWITCH       = 3    ; 2 operand(s)
A_INVENTORY        = 4    ; 0 operand(s)
A_PUT_OBJ          = 5    ; 2 operand(s)
A_GOTO_ROOM        = 6    ; 1 operand(s)
A_SET_VIEW         = 7    ; 1 operand(s)
A_SET_BASE_VIEW    = 8    ; 1 operand(s)
A_MESSAGE          = 9    ; 1 operand(s)
A_LAMP_ON          = 10    ; 0 operand(s)
A_LAMP_OFF         = 11    ; 0 operand(s)
A_UNUSED_12        = 12    ; 0 operand(s)
A_QUIT             = 13    ; 0 operand(s)
A_UNUSED_14        = 14    ; 0 operand(s)
A_SAVE_GAME        = 15    ; 0 operand(s)
A_RESTORE_GAME     = 16    ; 0 operand(s)
A_GAME_OVER        = 17    ; 0 operand(s)
A_PLACE_OBJ        = 18    ; 4 operand(s)
A_SET_OBJ_PIC      = 19    ; 2 operand(s)
A_RESET_VIEW       = 20    ; 0 operand(s)
A_GO_N             = 21    ; 0 operand(s)
A_GO_S             = 22    ; 0 operand(s)
A_GO_E             = 23    ; 0 operand(s)
A_GO_W             = 24    ; 0 operand(s)
A_GO_U             = 25    ; 0 operand(s)
A_GO_D             = 26    ; 0 operand(s)
A_GET              = 27    ; 0 operand(s)
A_DROP             = 28    ; 0 operand(s)
A_SET_ROOM_VIEW    = 29    ; 2 operand(s)

; verbs (verb_table)
V_GO             = 1    ; GO, ENTER, RUN, EXIT, LEAVE, WALK
V_U              = 2    ; U, UP, CLIMB, ASCEND
V_D              = 3    ; D, DOWN, DESCEND
V_OPEN           = 4    ; OPEN
V_CLOSE          = 5    ; CLOSE, SHUT
V_UNLOCK         = 6    ; UNLOCK, UNLATCH
V_N              = 7    ; N, NORTH
V_S              = 8    ; S, SOUTH
V_E              = 9    ; E, EAST
V_W              = 10    ; W, WEST
V_BREAK          = 11    ; BREAK, TEAR, BUST
V_MOVE           = 12    ; MOVE, SLIDE, PUSH
V_LOOK           = 13    ; LOOK, EXAMINE
V_GET            = 14    ; GET, TAKE, LIFT
V_LIGHT          = 15    ; LIGHT, STRIKE
V_POUR           = 16    ; POUR, DUMP
V_DROP           = 17    ; DROP, SET, LEAVE
V_JUMP           = 18    ; JUMP, LEAP
V_READ           = 19    ; READ
V_TALK           = 20    ; TALK, SPEAK
V_KILL           = 21    ; KILL, SLAY
V_EAT            = 22    ; EAT, CONSUME
V_WIPE           = 23    ; WIPE, RUB, REMOVE
V_FLUSH          = 24    ; FLUSH
V_UNSCREW        = 25    ; UNSCREW, UNBOLT, LOOSEN
V_WITH           = 26    ; WITH, USE, SHOOT, FIRE
V_PRESS          = 27    ; PRESS, PUSH
V_TURN           = 28    ; TURN
V_FAUCET         = 29    ; FAUCET, TAP, WATER
V_WATER          = 30    ; WATER
V_ON             = 31    ; ON
V_OFF            = 32    ; OFF
V_UNLIGHT        = 33    ; UNLIGHT, OFF
V_SAVE           = 34    ; SAVE, STORE
V_RESTORE        = 35    ; RESTORE
V_QUIT           = 36    ; QUIT, BYE, STOP
V_HELP           = 37    ; HELP
V_INVENTOR       = 38    ; INVENTOR, INVEN, CARRYING, ?
V_PROFANITY      = 39    ; FUCK, SUCK, SHIT, CUNT
V_SCORE          = 40    ; SCORE
V_SLEEP          = 41    ; SLEEP, REST, RETIRE, LIE
V_DRINK          = 42    ; DRINK, SIP, TASTE
V_DONE           = 43    ; DONE

; nouns (noun_table)
N_DAISY          = 1    ; DAISY, FLOWER
N_BILL           = 2    ; BILL
N_JOE            = 3    ; JOE
N_SALLY          = 4    ; SALLY
N_SAM            = 5    ; SAM
N_TOM            = 6    ; TOM
N_DOCTOR         = 7    ; DOCTOR, GREEN, DR., DR.GREEN
N_DAGGER         = 8    ; DAGGER
N_GUN            = 9    ; GUN, PISTOL
N_NOTE           = 10    ; NOTE, MEMO, LETTER, PAPER
N_BLA            = 11    ; BLA, DOG
N_DOG            = 12    ; DOG
N_FOOD           = 13    ; FOOD, BREAD
N_LAST           = 14    ; LAST
N_BODY           = 15    ; BODY, CORPSE, CADAVER
N_TRAPDOOR       = 16    ; TRAPDOOR
N_KNIFE          = 17    ; KNIFE
N_BOLTS          = 18    ; BOLTS, SCREWS
N_BUTTERKN       = 19    ; BUTTERKN
N_PICTURE        = 20    ; PICTURE, PORTRAIT
N_BUTTON         = 21    ; BUTTON, KNOB
N_CRAWLSPA       = 22    ; CRAWLSPA
N_STAIRS         = 23    ; STAIRS, STAIRWAY, STEPS
N_WALL           = 24    ; WALL, WALLS
N_DOOR           = 25    ; DOOR, DOORS, DOORWAY
N_TABLE          = 26    ; TABLE, DESK
N_DRAWERS        = 27    ; DRAWERS
N_RUG            = 28    ; RUG, CARPET
N_WATER          = 29    ; WATER, LIQUID
N_TOILET         = 30    ; TOILET, POTTY, JOHN
N_TOWEL          = 31    ; TOWEL, CLOTH
N_SHOWER         = 32    ; SHOWER
N_SLEDGEHA       = 33    ; SLEDGEHA, HAMMER
N_WINDOW         = 34    ; WINDOW
N_BOXES          = 35    ; BOXES, BOX
N_TRUNK          = 36    ; TRUNK, CHEST
N_FENCE          = 37    ; FENCE
N_CANDLE         = 38    ; CANDLE
N_LAMP           = 39    ; LAMP
N_HOLE           = 40    ; HOLE
N_KEY            = 41    ; KEY
N_SHELVES        = 42    ; SHELVES, BOOKSHEL
N_FIREPLAC       = 43    ; FIREPLAC, CHIMNEY
N_COUCH          = 44    ; COUCH, SOFA, DAVENPOR, DIVAN
N_BED            = 45    ; BED, MATTRESS
N_FLOOR          = 46    ; FLOOR
N_ALGAE          = 47    ; ALGAE
N_BRICKS         = 48    ; BRICKS, BRICK
N_JEWELS         = 49    ; JEWELS, GEMS, TREASURE, DIAMONDS
N_JARS           = 50    ; JARS, JAR, BOTTLE, BOTTLES
N_GATE           = 51    ; GATE
N_TREE           = 52    ; TREE, TREES
N_TELESCOP       = 53    ; TELESCOP
N_PERSON         = 54    ; PERSON, MAN, WOMAN, PEOPLE
N_GRAVESTO       = 55    ; GRAVESTO, TOMBSTON
N_CABINET        = 56    ; CABINET, CUPBOARD
N_MATCHES        = 57    ; MATCHES, MATCH
N_REFRIGER       = 58    ; REFRIGER, FRIDGE, ICEBOX, REFRIDGE
N_PITCHER        = 59    ; PITCHER
N_STOVE          = 60    ; STOVE, RANGE
N_PORCH          = 61    ; PORCH
N_GRAVES         = 62    ; GRAVES, GRAVE
N_FAUCET         = 63    ; FAUCET, TAP
N_ON             = 64    ; ON
N_OFF            = 65    ; OFF
N_SINK           = 66    ; SINK, TUB
N_CRADLE         = 67    ; CRADLE, CRIB
N_CHAIR          = 68    ; CHAIR, ROCKER
N_SHOVEL         = 69    ; SHOVEL, SPADE
N_NONE           = 70    ; (blank)
N_ROOM           = 71    ; ROOM, AROUND
N_TUNNEL         = 72    ; TUNNEL
N_HOUSE          = 73    ; HOUSE, BUILDING, HOME
N_HALL           = 74    ; HALL, HALLWAY, CORRIDOR
N_LADDER         = 75    ; LADDER
N_FIRE           = 76    ; FIRE
N_DOTS           = 77    ; DOTS
N_X_S            = 78    ; X'S
N_WELCOME        = 79    ; WELCOME
N_LINE           = 80    ; LINE
N_N              = 81    ; N, NORTH
N_S              = 82    ; S, SOUTH
N_E              = 83    ; E, EAST
N_W              = 84    ; W, WEST
N_U              = 85    ; U, UP
N_D              = 86    ; D, DOWN
N_BOOKS          = 87    ; BOOKS, BOOK
N_GAME           = 88    ; GAME, ADVENTUR
N_DONE           = 89    ; DONE

; ---- record layouts (names in CAPITALS without a note are the original author's) ----
; room record, RTBLSIZ bytes at ROOMBASE + room * RTBLSIZ
RROOMNO  = 0
RMSG     = 1      ; description message
RN       = 2      ; exits: room number or 0
RS       = 3
RE       = 4
RW       = 5
RU       = 6
RD       = 7
RBASEPIC = 8      ; the room's permanent view
RCURPIC  = 9      ; the view shown now
RTBLSIZ  = 10
; object record at OBJBASE, variable length (ONEXT), table ends with HV
OBJECTNO = 0
ONOUN    = 1      ; noun number (name not in the surviving source)
OROOM    = 2      ; room, CARRYING or NOWHERE
OPIC     = 3      ; picture or shape number
OSHAPE   = 4      ; 1 = OPIC is a shape-table shape (name not in the surviving source)
OXCOORD  = 5
OYCOORD  = 6
OSTATUS  = 7      ; OMOVABLE, OMOVED or OFIXED
OMSG     = 8      ; inventory text
ONEXT    = 9      ; record length
ORPICKT  = 10     ; number of pictures the object appears in
ORPICSTA = 11     ; first of those picture numbers
HV       = $FF    ; end of the object table (and of the rule and word tables)
CARRYING = $FE    ; OROOM: in the inventory (CARRIED in the data tables)
; rule header (names not in the surviving source)
RULE_ROOM  = 0
RULE_VERB  = 1
RULE_NOUN  = 2
RULE_LEN   = 3
RULE_NCOND = 4
RULE_NACT  = 5
RULE_BODY  = 6    ; conditions, then actions
; operands of the current condition or action, as offsets from its opcode byte. The original
; source calls the first two X and Y (LDY #X / LDA (ZWORK),Y).
ARG_X    = 1
ARG_Y    = 2
ARG_3    = 3
ARG_4    = 4
; LAMPSTAT values (the source writes LDY #ON / LDY #OFF)
ON       = 0
OFF      = 1

; messages print_message handles itself
MSG_GETTING_DARK     = $07
MSG_DONT_UNDERSTAND  = $25
MSG_NOT_CARRYING     = $7F
MSG_CANT_GO          = $89
; messages from the MESSAGES file the engine prints directly
MSG_GOODBYE          = $8C
MSG_DOESNT_MOVE      = $97
MSG_DONT_SEE_IT      = $98

WORDLEN    = 8    ; only the first 8 letters of a word count
NSWITCH    = 20   ; size of SWITCH
NOT_FOUND  = $FF  ; word_id when a word is not in the dictionary
INPUT_END  = $FF  ; next_word: marker written after the typed line
; picture streams
PIC_NEWLINE = $00 ; 00 00: the next point starts a new line
PIC_END     = $FF ; FF FF: end of the picture
MAX_X       = $FF ; points are clamped to the 256 x 161 picture area
MAX_Y       = $A0
CACHE_SLOTS = 5   ; picture cache: slots of 4 bytes in pic_cache

; offsets of the Applesoft-style variables from applesoft_vars, as the relocated HPLOT/DRAW code
; reads them with LDA (fake_vartab),Y. get_var is given the offset of the high byte (the low
; byte is the one before it); get_var_x reads var_x low byte first, from VAR_X.
VAR_X      = $05  ; var_x, low byte
VAR_Y_HI   = $0D  ; var_y
VAR_HCOLOR = $16  ; var_hcolor
VAR_SHAPE  = $20  ; var_shape
VAR_ROT    = $28  ; var_rot

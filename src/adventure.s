; ADVENTURE - Hi-Res Adventure #1: Mystery House (On-Line Systems, 1980)
;
; The game engine and its database. DOS BRUNs this file at $0800. Assemble with
; tools/asm6502.py; build.sh checks the result against the original byte for byte.
;
; Memory map (all inside this file unless noted)
;   $0800  start, then the engine's variables (applesoft_vars, CURONO, SWITCH, ...)
;   $0900  OBJBASE           object table
;   $0D00  ROOMBASE          room table
;   $1700  noun_table
;   $2000  hi-res page 1     the 1980 title screen, shown while this file loads
;   $4000  verb_table
;   $4400  turn_rules        game logic run after every command
;   $4500  command_rules     game logic matched against the command
;   $5300  picture_directory
;   $5500  message_index
;   $5700  shape_table
;   $5A00  the engine        rules interpreter, parser, actions, graphics, messages
;   $7600  the macro library (operands inline after the JSR)
;   $7D00-$95FF              picture cache (not in the file)
;
; Names in CAPITALS are the original author's, from source fragments and a symbol table left
; in the binary (see original_source/). "leftover memory" is stale data saved with the file;
; nothing reads it, and it can be deleted to make room in front of a pinned (.org) table.

        .include "macros.inc"
        .include "apple2.inc"
        .include "game.inc"

; ---- addresses outside the image or inside other items ----
applesoft_vars           = $0800    ; variables read by the relocated HPLOT/DRAW code (overwrites start)
hgr_shape_ptr            = $001A    ; Applesoft $1A/$1B: shape pointer / HCLR fill pointer
hgr_bits                 = $001C    ; Applesoft $1C: current colour bit pattern
hgr_count_hi             = $001D    ; Applesoft $1D: HGLIN step counter (high)
hbasl                    = $0026    ; Applesoft HBASL/HBASH: hi-res row base address
hmask                    = $0030    ; Applesoft HMASK: pixel mask within the byte
prompt_char              = $0033    ; monitor prompt character for GETLN
fake_vartab              = $004A
hgr_dx                   = $0050    ; Applesoft line/shape temporaries $50-$55
hgr_dy                   = $0052
hgr_quadrant             = $0053
hgr_err                  = $0054
rt_operands              = $0071    ; rt_args: pointer to the caller's inline operands
picdir_index             = $0073    ; picture number * 3 while looking up the directory
picture_ptr              = $0075    ; current point in the picture being drawn
WORK                    = $0077    ; rule/parser cursor (word table walk; current condition)
rule_ptr                 = $0079    ; start of the rule being tested
counter                  = $007B    ; loop counter (conditions left / table slot)
rt_temp                  = $007C
rt_ptr1                  = $007D    ; library scratch pointer (also dispatch target)
found_obj                = $007F    ; object record found by find_object
rt_ptr2                  = $0081    ; library scratch pointer
CUROOM                   = $0083    ; record of the current room in ROOMBASE
ZWORK                    = $0085
ZAWORK                   = $0087    ; object-table cursor; also the action dispatch target
applesoft_errflg         = $00D8    ; Applesoft ONERR flag
applesoft_d9             = $00D9
input_buffer             = $0200    ; monitor GETLN input line
hgr_x                    = $0320    ; Applesoft HGR.X ($E0) relocated
hgr_y                    = $0322    ; Applesoft HGR.Y ($E2) relocated
hgr_saved_x              = $0323
hgr_color                = $0324    ; Applesoft HGR.COLOR ($E4) relocated
hgr_horiz                = $0325    ; Applesoft HGR.HORIZ ($E5) relocated: byte column
hgr_page                 = $0326    ; Applesoft HGR.PAGE ($E6) relocated: $20 = page 1
hgr_scale                = $0327    ; Applesoft HGR.SCALE ($E7) relocated
hgr_shape_table          = $0328    ; Applesoft HGR.SHAPE ($E8) relocated: shape table at $5700
hgr_collisions           = $032A    ; Applesoft HGR.COLLISIONS ($EA) relocated
dos_warm_start           = $03D0    ; DOS 3.3 warm start
var_x                    = $0805    ; X for HPLOT/DRAW (inside start, which it overwrites)
var_y                    = $080C    ; Y for HPLOT/DRAW
old_rt_copy              = $4A00
old_BUMPIT              = $4A03
old_BUMP16             = $4A06
old_rt_print             = $4A15
dos_error_vector         = $9D5A    ; DOS 3.3 error-handler vector
dos_language_flag        = $AAB6    ; DOS 3.3: $40 = Applesoft active


; ==== variables ======================================================================
; The values are whatever they were when the file was saved, mid-game; init_game resets the
; ones that matter. The odd bytes between the variables are leftovers of the Applesoft-style
; variable records that the relocated HPLOT/DRAW code reads from applesoft_vars.
        .org $0800

; BRUN entry point. Resets the stack, points fake_vartab at applesoft_vars ($0800) and enters
; main. These bytes are only executed once: the relocated HPLOT/DRAW code later keeps its X and
; Y in var_x ($0805) and var_y ($080C), on top of this code.
start:
        LDX #$FF
        TXS
        LDA #<applesoft_vars
        STA fake_vartab
        LDA #>applesoft_vars
        STA fake_vartab+1
        JMP main
        .byte $4F,$4E,$53,$20,$3A,$20,$02
var_hcolor:
        .byte $7F,$00
        .byte $20,$3B,$20,$44,$4F,$20,$54,$48
var_shape:
        .byte $00,$00
        .byte $41,$43,$54,$49,$4F,$4E
var_rot:
        .byte $00,$00
        .byte $4F,$4E,$20,$54,$48,$45,$20
cmd_unused:
        .byte $00
input_len:
        .byte $01
parse_pos:
        .byte $00
word_id:
        .byte $19
verb:
        .byte $01
noun:
        .byte $19
cond_actual:
        .byte $26
        .byte $0D
find_objectno:
        .byte $27
shown_picture:
        .byte $35
SWITCH:
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00
draw_dy:
        .byte $00
draw_dx:
        .byte $00
pen_up:
        .byte $00
cmp_result:
        .byte $FF
CURONO:
        .byte $01
turns:
        .byte $01,$00
verb_word:
        .byte $C7,$CF,$A0,$A0,$A0,$A0,$A0,$A0
noun_word:
        .byte $C4,$CF,$CF,$D2,$A0,$A0,$A0,$A0
done_word:
        .byte $C4,$CF,$CE,$C5,$A0,$A0,$A0,$A0
word_buf:
        .byte $C4,$CF,$CF,$D2,$A0,$A0,$A0,$A0
blank_word:
        .byte $A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0
scratch_word:
        .byte $D9,$CF
mul_multiplicand:
        .byte $00,$03
mul_result:
        .byte $A2,$00
mul_count:
        .byte $00
mul_carry:
        .byte $00
mul_dest:
        .byte $73,$00
room_offset:
        .byte $1E,$00
pic_block:
        .byte $0E
pic_offset:
        .byte $BE,$02
lru_turn:
        .byte $00,$00
floor_slot:
        .byte $00
        .byte $01
AWORK:
        .byte $14,$44
AWORK1:
        .byte $01
        .byte $4B
AWORK2:
        .byte $1E,$0D
AWORK3:
        .byte $1E,$00
actions_left:
        .byte $00
AX:
        .byte $20
AY:
        .byte $31
AX1:
        .byte $53
AY1:
        .byte $54
LAMPSTAT:
        .byte $00
saved_object_ptr:
        .byte $48,$09
msg_no_delay:
        .byte $54
pic_cache:
        .byte $49,$4F,$4E,$20,$41,$44,$44,$52,$45,$53,$53,$0D,$08,$D0,$01,$41
        .byte $57,$4F,$52,$4B
; leftover memory, not used: lines here can be deleted to make room
        .byte $0D,$0A,$CD,$01,$57,$4F,$52,$4B,$2B,$24,$31,$0D,$0B,$D0,$01,$41
        .byte $57,$4F,$52,$4B,$2B,$24,$31,$0D,$02,$3B,$0D,$19,$3B,$20,$47,$45
        .byte $54,$20,$23,$20,$4F,$46,$20,$41,$43,$54,$49,$4F,$4E,$53,$20,$54
        .byte $4F,$20,$44,$4F,$0D,$02,$3B,$0D,$17,$CF,$02,$23,$4C,$41,$43,$54
        .byte $4B,$54,$BB,$23,$20,$4F,$46,$20,$41,$43,$54

; ==== objects ========================================================================
; One record per object (layout in game.inc: OBJECTNO ... ORPICSTA). ONEXT is the record
; length; the table ends with HV. Starting state; STARTUP restores it on "play again".
        .assert * = $0900, error, "OBJBASE must be at $0900 (it is inside the saved state): the variables before it must end exactly there"
OBJBASE:
; id  noun  room  pic  shape  x  y  status  msg  length  npics  pics...
obj_01: .byte 1, N_TOM, 3, 52, 0, 41, 61, OFIXED, 0, obj_02-obj_01, 1, 53
obj_02: .byte 2, N_SAM, 3, 52, 0, 66, 63, OFIXED, 0, obj_03-obj_02, 1, 53
obj_03: .byte 3, N_SALLY, 3, 54, 0, 86, 66, OFIXED, 0, obj_04-obj_03, 1, 53
obj_04: .byte 4, N_DOCTOR, 3, 52, 0, 114, 66, OFIXED, 0, obj_05-obj_04, 1, 53
obj_05: .byte 5, N_JOE, 3, 52, 0, 132, 67, OFIXED, 0, obj_06-obj_05, 1, 53
obj_06: .byte 6, N_BILL, 3, 52, 0, 153, 67, OFIXED, 0, obj_07-obj_06, 1, 53
obj_07: .byte 7, N_DAISY, 3, 54, 0, 180, 67, OFIXED, 0, obj_08-obj_07, 1, 53
obj_08: .byte 8, N_DOOR, 3, 3, 1, 108, 150, OFIXED, 0, obj_09-obj_08, 3, 5, 4, 53
obj_09: .byte 9, N_NOTE, 3, 4, 1, 41, 126, OMOVABLE, 110, obj_10-obj_09, 3, 5, 4, 53
obj_10: .byte 10, N_CABINET, 4, 55, 0, 3, 77, OMOVABLE, 124, obj_11-obj_10, 2, 14, 13
obj_11: .byte 11, N_BRICKS, NOWHERE, 56, 0, 13, 82, OFIXED, 0, obj_12-obj_11, 2, 14, 13
obj_12: .byte 12, N_HOLE, NOWHERE, 57, 0, 7, 83, OFIXED, 0, obj_13-obj_12, 2, 14, 13
obj_13: .byte 13, N_MATCHES, 4, 6, 1, 94, 118, OMOVABLE, 109, obj_14-obj_13, 1, 12
obj_14: .byte 14, N_PITCHER, 4, 58, 0, 75, 107, OMOVABLE, 125, obj_15-obj_14, 1, 11
obj_15: .byte 15, N_PITCHER, NOWHERE, 59, 0, 0, 0, OMOVABLE, 126, obj_16-obj_15, 0
obj_16: .byte 16, N_BUTTERKN, 4, 60, 0, 125, 66, OMOVABLE, 108, obj_17-obj_16, 1, 10
obj_17: .byte 17, N_NOTE, 14, 4, 1, 61, 79, OMOVABLE, 110, obj_18-obj_17, 2, 7, 6
obj_18: .byte 18, N_CANDLE, NOWHERE, 61, 0, 0, 0, OMOVABLE, 115, obj_19-obj_18, 0
obj_19: .byte 19, N_CANDLE, 16, 62, 0, 102, 75, OMOVABLE, 116, obj_20-obj_19, 2, 29, 28
obj_20: .byte 20, N_FIRE, NOWHERE, 63, 0, 81, 92, OFIXED, 0, obj_21-obj_20, 2, 29, 28
obj_21: .byte 21, N_HOLE, NOWHERE, 64, 0, 79, 115, OFIXED, 0, obj_22-obj_21, 2, 29, 28
obj_22: .byte 22, N_KEY, 16, 65, 0, 107, 59, OMOVABLE, 112, obj_23-obj_22, 1, 49
obj_23: .byte 23, N_SAM, 17, 66, 0, 125, 89, OFIXED, 0, obj_24-obj_23, 4, 18, 17, 16, 15
obj_24: .byte 24, N_GRAVES, NOWHERE, 67, 0, 100, 59, OFIXED, 0, obj_25-obj_24, 2, 27, 26
obj_25: .byte 25, N_JOE, 18, 68, 0, 6, 83, OFIXED, 0, obj_26-obj_25, 2, 27, 26
obj_26: .byte 26, N_DOTS, 18, 69, 0, 27, 88, OFIXED, 0, obj_27-obj_26, 2, 27, 26
obj_27: .byte 27, N_X_S, NOWHERE, 70, 0, 25, 88, OFIXED, 0, obj_28-obj_27, 2, 27, 26
obj_28: .byte 28, N_SHOVEL, 18, 71, 0, 49, 97, OMOVABLE, 113, obj_29-obj_28, 2, 27, 26
obj_29: .byte 29, N_TOM, 21, 72, 0, 36, 63, OFIXED, 0, obj_30-obj_29, 1, 30
obj_30: .byte 30, N_KEY, 21, 73, 0, 175, 83, OMOVABLE, 111, obj_31-obj_30, 1, 30
obj_31: .byte 31, N_BRICKS, NOWHERE, 74, 0, 162, 27, OMOVABLE, 122, obj_32-obj_31, 1, 30
obj_32: .byte 32, N_JEWELS, NOWHERE, 75, 0, 162, 27, OMOVABLE, 123, obj_33-obj_32, 1, 30
obj_33: .byte 33, N_SALLY, 28, 76, 0, 72, 70, OFIXED, 0, obj_34-obj_33, 1, 39
obj_34: .byte 34, N_DOCTOR, 30, 77, 0, 97, 62, OFIXED, 0, obj_35-obj_34, 1, 37
obj_35: .byte 35, N_NOTE, 32, 4, 1, 91, 82, OMOVABLE, 110, obj_36-obj_35, 1, 35
obj_36: .byte 36, N_PICTURE, 35, 79, 0, 63, 10, OMOVABLE, 120, obj_37-obj_36, 1, 40
obj_37: .byte 37, N_BUTTON, NOWHERE, 80, 0, 103, 27, OFIXED, 0, obj_38-obj_37, 1, 40
obj_38: .byte 38, N_BILL, 38, 81, 0, 69, 66, OFIXED, 0, obj_39-obj_38, 1, 45
obj_39: .byte 39, N_TOWEL, 38, 82, 0, 127, 24, OMOVABLE, 121, obj_40-obj_39, 1, 45
obj_40: .byte 40, N_TRAPDOOR, NOWHERE, 83, 0, 200, 45, OFIXED, 0, obj_41-obj_40, 1, 42
obj_41: .byte 41, N_TRAPDOOR, NOWHERE, 84, 0, 200, 45, OFIXED, 0, obj_42-obj_41, 1, 42
obj_42: .byte 42, N_SLEDGEHA, 39, 85, 0, 102, 124, OMOVABLE, 114, obj_43-obj_42, 1, 42
obj_43: .byte 43, N_TRUNK, 40, 86, 0, 93, 45, OFIXED, 0, obj_44-obj_43, 1, 43
obj_44: .byte 44, N_TRUNK, NOWHERE, 87, 0, 93, 45, OFIXED, 0, obj_45-obj_44, 1, 43
obj_45: .byte 45, N_GUN, 40, 88, 0, 104, 61, OMOVABLE, 118, obj_46-obj_45, 1, 50
obj_46: .byte 46, N_DAISY, 41, 89, 0, 167, 62, OFIXED, 0, obj_47-obj_46, 1, 44
obj_47: .byte 47, N_DOTS, 41, 90, 0, 203, 65, OFIXED, 0, obj_48-obj_47, 1, 44
obj_48: .byte 48, N_X_S, NOWHERE, 91, 0, 201, 65, OFIXED, 0, obj_49-obj_48, 1, 44
obj_49: .byte 49, N_NOTE, 41, 4, 1, 99, 103, OMOVABLE, 110, obj_50-obj_49, 1, 44
obj_50: .byte 50, N_WELCOME, 2, 2, 1, 116, 120, OFIXED, 0, obj_51-obj_50, 2, 2, 1
obj_51: .byte 51, N_REFRIGER, 4, 93, 0, 155, 17, OFIXED, 0, obj_52-obj_51, 2, 14, 13
obj_52: .byte 52, N_REFRIGER, NOWHERE, 94, 0, 155, 17, OFIXED, 0, obj_53-obj_52, 2, 14, 13
obj_53: .byte 53, N_DAGGER, 26, 95, 0, 171, 86, OMOVABLE, 117, obj_54-obj_53, 1, 38
obj_54: .byte 54, N_LINE, 26, 96, 0, 73, 35, OFIXED, 0, obj_end-obj_54, 1, 38
obj_end: .byte $FF
fill_to_roombase:                      ; leftover memory up to ROOMBASE (shrinks as the objects grow)
        incbin_upto "data/adventure_0B9D.bin", 355, $0D00    ; $0B9D-$0CFF leftover memory, not used by the code (see NOTES.md)

; ==== rooms ==========================================================================
; RTBLSIZ bytes per room, indexed by room number (room 0 unused): RROOMNO, RMSG, the six
; exits RN RS RE RW RU RD (0 = none), RBASEPIC, RCURPIC.
        .assert * = $0D00, error, "ROOMBASE must be at $0D00 (it is inside the saved state)"
ROOMBASE:
;      no  msg  N  S  E  W  U  D  base cur
        .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0   ; 0 unused
        .byte 1, 99, 0, 0, 0, 0, 2, 0, 3, 3   ; 1 IN THE FRONT YARD OF A LARGE ABANDONED VICTORIA...
        .byte 2, 98, 0, 0, 0, 0, 0, 1, 1, 1   ; 2 ON THE PORCH
        .byte 3, 102, 2, 16, 14, 4, 24, 0, 53, 53   ; 3 IN AN ENTRY HALL
        .byte 4, 9, 0, 0, 3, 5, 0, 0, 13, 13   ; 4 IN THE KITCHEN
        .byte 5, 19, 12, 10, 6, 8, 4, 0, 20, 20   ; 5 IN A FOREST
        .byte 6, 19, 5, 8, 7, 9, 0, 0, 20, 20   ; 6 IN A FOREST
        .byte 7, 19, 6, 7, 8, 10, 0, 0, 20, 20   ; 7 IN A FOREST
        .byte 8, 19, 7, 5, 9, 6, 0, 0, 20, 20   ; 8 IN A FOREST
        .byte 9, 19, 8, 0, 10, 6, 0, 0, 20, 20   ; 9 IN A FOREST
        .byte 10, 19, 9, 7, 11, 5, 0, 0, 20, 20   ; 10 IN A FOREST
        .byte 11, 19, 10, 0, 12, 0, 0, 0, 20, 20   ; 11 IN A FOREST
        .byte 12, 19, 11, 0, 5, 0, 0, 0, 20, 20   ; 12 IN A FOREST
        .byte 13, 20, 0, 0, 0, 0, 23, 9, 19, 19   ; 13 THERE IS A VERY TALL PINE TREE IN FRONT OF YOU
        .byte 14, 104, 0, 0, 15, 3, 0, 0, 6, 6   ; 14 IN THE OLD, DUSTY LIBRARY
        .byte 15, 8, 0, 17, 0, 14, 0, 0, 9, 9   ; 15 IN THE SIDE YARD
        .byte 16, 41, 3, 17, 0, 0, 0, 0, 28, 28   ; 16 IN THE DINING ROOM
        .byte 17, 6, 15, 0, 0, 0, 0, 0, 15, 15   ; 17 IN THE FENCED BACK YARD
        .byte 18, 28, 0, 0, 0, 0, 0, 0, 27, 27   ; 18 IN A SMALL FENCED CEMETARY
        .byte 19, 26, 0, 0, 0, 0, 0, 20, 25, 25   ; 19 IN A SMALL PANTRY
        .byte 20, 25, 0, 21, 0, 0, 19, 0, 23, 23   ; 20 AT THE NORTH END OF A NARROW NORTH/SOUTH PASSAG...
        .byte 21, 49, 20, 0, 0, 0, 37, 0, 30, 30   ; 21 IN A MOIST BASEMENT
        .byte 22, 58, 13, 0, 0, 0, 0, 0, 31, 31   ; 22 AT THE SOUTH END OF A NORTH/SOUTH TUNNEL
        .byte 23, 21, 0, 0, 0, 0, 0, 13, 21, 21   ; 23 AT THE TOP OF A VERY TALL PINE TREE
        .byte 24, 60, 33, 0, 25, 29, 0, 3, 32, 32   ; 24 AT THE JUNCTION OF AN EAST/WEST HALLWAY AND A N...
        .byte 25, 62, 0, 0, 27, 24, 0, 0, 33, 33   ; 25 THERE IS A DOORWAY HERE
        .byte 26, 68, 0, 0, 0, 0, 0, 0, 38, 38   ; 26 IN A LARGE BEDROOM
        .byte 27, 62, 0, 0, 0, 25, 0, 0, 33, 33   ; 27 THERE IS A DOORWAY HERE
        .byte 28, 70, 0, 0, 0, 0, 0, 0, 39, 39   ; 28 IN A SMALL BEDROOM
        .byte 29, 62, 0, 0, 24, 31, 0, 0, 33, 33   ; 29 THERE IS A DOORWAY HERE
        .byte 30, 66, 0, 0, 0, 0, 0, 0, 37, 37   ; 30 IN AN OLD NURSERY
        .byte 31, 62, 0, 0, 29, 0, 0, 0, 33, 33   ; 31 THERE IS A DOORWAY HERE
        .byte 32, 64, 0, 0, 0, 0, 0, 0, 35, 35   ; 32 IN A BOYS BEDROOM
        .byte 33, 63, 34, 24, 0, 0, 39, 0, 34, 34   ; 33 AT A STAIRWAY
        .byte 34, 62, 0, 33, 0, 0, 0, 0, 33, 33   ; 34 THERE IS A DOORWAY HERE
        .byte 35, 72, 34, 0, 38, 0, 0, 0, 40, 40   ; 35 IN THE STUDY
        .byte 36, 94, 0, 0, 0, 0, 0, 37, 46, 46   ; 36 IN A MUSTY CRAWLSPACE
        .byte 37, 97, 0, 0, 0, 0, 36, 21, 47, 47   ; 37 ON A STAIRWAY
        .byte 38, 91, 0, 0, 0, 0, 0, 0, 45, 45   ; 38 IN THE BATHROOM
        .byte 39, 78, 0, 0, 0, 0, 0, 33, 42, 42   ; 39 IN THE ATTIC
        .byte 40, 81, 0, 0, 0, 0, 0, 0, 43, 43   ; 40 IN A STORAGE ROOM
        .byte 41, 85, 0, 0, 0, 0, 0, 0, 44, 44   ; 41 IN THE TOWER
        .assert * <= STATE_END, error, "the room table must end inside the saved state ($0830-$10FE)"
        .incbin "data/adventure_0EA4.bin"    ; $0EA4-$16FF leftover memory, not used by the code (see NOTES.md)

; ==== nouns ==========================================================================
; Word groups: head word, synonym count, synonyms; all WORDLEN characters, high-bit ASCII.
; The group number is the noun's id (N_* in game.inc). Ends with HV.
noun_table:
        hiasc "DAISY   "            ; N_DAISY = 1
        .byte 1
        hiasc "FLOWER  "
        hiasc "BILL    "            ; N_BILL = 2
        .byte 0
        hiasc "JOE     "            ; N_JOE = 3
        .byte 0
        hiasc "SALLY   "            ; N_SALLY = 4
        .byte 0
        hiasc "SAM     "            ; N_SAM = 5
        .byte 0
        hiasc "TOM     "            ; N_TOM = 6
        .byte 0
        hiasc "DOCTOR  "            ; N_DOCTOR = 7
        .byte 3
        hiasc "GREEN   "
        hiasc "DR.     "
        hiasc "DR.GREEN"
        hiasc "DAGGER  "            ; N_DAGGER = 8
        .byte 0
        hiasc "GUN     "            ; N_GUN = 9
        .byte 1
        hiasc "PISTOL  "
        hiasc "NOTE    "            ; N_NOTE = 10
        .byte 3
        hiasc "MEMO    "
        hiasc "LETTER  "
        hiasc "PAPER   "
        hiasc "BLA     "            ; N_BLA = 11
        .byte 1
        hiasc "DOG     "
        hiasc "DOG     "            ; N_DOG = 12
        .byte 0
        hiasc "FOOD    "            ; N_FOOD = 13
        .byte 1
        hiasc "BREAD   "
        hiasc "LAST    "            ; N_LAST = 14
        .byte 0
        hiasc "BODY    "            ; N_BODY = 15
        .byte 2
        hiasc "CORPSE  "
        hiasc "CADAVER "
        hiasc "TRAPDOOR"            ; N_TRAPDOOR = 16
        .byte 0
        hiasc "KNIFE   "            ; N_KNIFE = 17
        .byte 0
        hiasc "BOLTS   "            ; N_BOLTS = 18
        .byte 1
        hiasc "SCREWS  "
        hiasc "BUTTERKN"            ; N_BUTTERKN = 19
        .byte 0
        hiasc "PICTURE "            ; N_PICTURE = 20
        .byte 1
        hiasc "PORTRAIT"
        hiasc "BUTTON  "            ; N_BUTTON = 21
        .byte 1
        hiasc "KNOB    "
        hiasc "CRAWLSPA"            ; N_CRAWLSPA = 22
        .byte 0
        hiasc "STAIRS  "            ; N_STAIRS = 23
        .byte 2
        hiasc "STAIRWAY"
        hiasc "STEPS   "
        hiasc "WALL    "            ; N_WALL = 24
        .byte 1
        hiasc "WALLS   "
        hiasc "DOOR    "            ; N_DOOR = 25
        .byte 2
        hiasc "DOORS   "
        hiasc "DOORWAY "
        hiasc "TABLE   "            ; N_TABLE = 26
        .byte 1
        hiasc "DESK    "
        hiasc "DRAWERS "            ; N_DRAWERS = 27
        .byte 0
        hiasc "RUG     "            ; N_RUG = 28
        .byte 1
        hiasc "CARPET  "
        hiasc "WATER   "            ; N_WATER = 29
        .byte 1
        hiasc "LIQUID  "
        hiasc "TOILET  "            ; N_TOILET = 30
        .byte 2
        hiasc "POTTY   "
        hiasc "JOHN    "
        hiasc "TOWEL   "            ; N_TOWEL = 31
        .byte 1
        hiasc "CLOTH   "
        hiasc "SHOWER  "            ; N_SHOWER = 32
        .byte 0
        hiasc "SLEDGEHA"            ; N_SLEDGEHA = 33
        .byte 1
        hiasc "HAMMER  "
        hiasc "WINDOW  "            ; N_WINDOW = 34
        .byte 0
        hiasc "BOXES   "            ; N_BOXES = 35
        .byte 1
        hiasc "BOX     "
        hiasc "TRUNK   "            ; N_TRUNK = 36
        .byte 1
        hiasc "CHEST   "
        hiasc "FENCE   "            ; N_FENCE = 37
        .byte 0
        hiasc "CANDLE  "            ; N_CANDLE = 38
        .byte 0
        hiasc "LAMP    "            ; N_LAMP = 39
        .byte 0
        hiasc "HOLE    "            ; N_HOLE = 40
        .byte 0
        hiasc "KEY     "            ; N_KEY = 41
        .byte 0
        hiasc "SHELVES "            ; N_SHELVES = 42
        .byte 1
        hiasc "BOOKSHEL"
        hiasc "FIREPLAC"            ; N_FIREPLAC = 43
        .byte 1
        hiasc "CHIMNEY "
        hiasc "COUCH   "            ; N_COUCH = 44
        .byte 3
        hiasc "SOFA    "
        hiasc "DAVENPOR"
        hiasc "DIVAN   "
        hiasc "BED     "            ; N_BED = 45
        .byte 1
        hiasc "MATTRESS"
        hiasc "FLOOR   "            ; N_FLOOR = 46
        .byte 0
        hiasc "ALGAE   "            ; N_ALGAE = 47
        .byte 0
        hiasc "BRICKS  "            ; N_BRICKS = 48
        .byte 1
        hiasc "BRICK   "
        hiasc "JEWELS  "            ; N_JEWELS = 49
        .byte 3
        hiasc "GEMS    "
        hiasc "TREASURE"
        hiasc "DIAMONDS"
        hiasc "JARS    "            ; N_JARS = 50
        .byte 3
        hiasc "JAR     "
        hiasc "BOTTLE  "
        hiasc "BOTTLES "
        hiasc "GATE    "            ; N_GATE = 51
        .byte 0
        hiasc "TREE    "            ; N_TREE = 52
        .byte 1
        hiasc "TREES   "
        hiasc "TELESCOP"            ; N_TELESCOP = 53
        .byte 0
        hiasc "PERSON  "            ; N_PERSON = 54
        .byte 3
        hiasc "MAN     "
        hiasc "WOMAN   "
        hiasc "PEOPLE  "
        hiasc "GRAVESTO"            ; N_GRAVESTO = 55
        .byte 1
        hiasc "TOMBSTON"
        hiasc "CABINET "            ; N_CABINET = 56
        .byte 1
        hiasc "CUPBOARD"
        hiasc "MATCHES "            ; N_MATCHES = 57
        .byte 1
        hiasc "MATCH   "
        hiasc "REFRIGER"            ; N_REFRIGER = 58
        .byte 3
        hiasc "FRIDGE  "
        hiasc "ICEBOX  "
        hiasc "REFRIDGE"
        hiasc "PITCHER "            ; N_PITCHER = 59
        .byte 0
        hiasc "STOVE   "            ; N_STOVE = 60
        .byte 1
        hiasc "RANGE   "
        hiasc "PORCH   "            ; N_PORCH = 61
        .byte 0
        hiasc "GRAVES  "            ; N_GRAVES = 62
        .byte 1
        hiasc "GRAVE   "
        hiasc "FAUCET  "            ; N_FAUCET = 63
        .byte 1
        hiasc "TAP     "
        hiasc "ON      "            ; N_ON = 64
        .byte 0
        hiasc "OFF     "            ; N_OFF = 65
        .byte 0
        hiasc "SINK    "            ; N_SINK = 66
        .byte 1
        hiasc "TUB     "
        hiasc "CRADLE  "            ; N_CRADLE = 67
        .byte 1
        hiasc "CRIB    "
        hiasc "CHAIR   "            ; N_CHAIR = 68
        .byte 1
        hiasc "ROCKER  "
        hiasc "SHOVEL  "            ; N_SHOVEL = 69
        .byte 1
        hiasc "SPADE   "
        hiasc "        "            ; N_NONE = 70
        .byte 0
        hiasc "ROOM    "            ; N_ROOM = 71
        .byte 1
        hiasc "AROUND  "
        hiasc "TUNNEL  "            ; N_TUNNEL = 72
        .byte 0
        hiasc "HOUSE   "            ; N_HOUSE = 73
        .byte 2
        hiasc "BUILDING"
        hiasc "HOME    "
        hiasc "HALL    "            ; N_HALL = 74
        .byte 2
        hiasc "HALLWAY "
        hiasc "CORRIDOR"
        hiasc "LADDER  "            ; N_LADDER = 75
        .byte 0
        hiasc "FIRE    "            ; N_FIRE = 76
        .byte 0
        hiasc "DOTS    "            ; N_DOTS = 77
        .byte 0
        hiasc "X'S     "            ; N_X_S = 78
        .byte 0
        hiasc "WELCOME "            ; N_WELCOME = 79
        .byte 0
        hiasc "LINE    "            ; N_LINE = 80
        .byte 0
        hiasc "N       "            ; N_N = 81
        .byte 1
        hiasc "NORTH   "
        hiasc "S       "            ; N_S = 82
        .byte 1
        hiasc "SOUTH   "
        hiasc "E       "            ; N_E = 83
        .byte 1
        hiasc "EAST    "
        hiasc "W       "            ; N_W = 84
        .byte 1
        hiasc "WEST    "
        hiasc "U       "            ; N_U = 85
        .byte 1
        hiasc "UP      "
        hiasc "D       "            ; N_D = 86
        .byte 1
        hiasc "DOWN    "
        hiasc "BOOKS   "            ; N_BOOKS = 87
        .byte 1
        hiasc "BOOK    "
        hiasc "GAME    "            ; N_GAME = 88
        .byte 1
        hiasc "ADVENTUR"
        hiasc "DONE    "            ; N_DONE = 89
        .byte $FF
fill_to_hires:                         ; leftover memory up to the hi-res page (shrinks as the nouns grow)
        incbin_upto "data/adventure_1C61.bin", 927, $2000    ; $1C61-$1FFF leftover memory, not used by the code (see NOTES.md)
        .assert * = $2000, error, "the hi-res page must be at $2000"
title_1980:
        .incbin "data/title_1980.bin"    ; $2000-$3FFF 

; ==== verbs ==========================================================================
; Same layout as the nouns; ids are V_* in game.inc.
verb_table:
        hiasc "GO      "            ; V_GO = 1
        .byte 5
        hiasc "ENTER   "
        hiasc "RUN     "
        hiasc "EXIT    "
        hiasc "LEAVE   "
        hiasc "WALK    "
        hiasc "U       "            ; V_U = 2
        .byte 3
        hiasc "UP      "
        hiasc "CLIMB   "
        hiasc "ASCEND  "
        hiasc "D       "            ; V_D = 3
        .byte 2
        hiasc "DOWN    "
        hiasc "DESCEND "
        hiasc "OPEN    "            ; V_OPEN = 4
        .byte 0
        hiasc "CLOSE   "            ; V_CLOSE = 5
        .byte 1
        hiasc "SHUT    "
        hiasc "UNLOCK  "            ; V_UNLOCK = 6
        .byte 1
        hiasc "UNLATCH "
        hiasc "N       "            ; V_N = 7
        .byte 1
        hiasc "NORTH   "
        hiasc "S       "            ; V_S = 8
        .byte 1
        hiasc "SOUTH   "
        hiasc "E       "            ; V_E = 9
        .byte 1
        hiasc "EAST    "
        hiasc "W       "            ; V_W = 10
        .byte 1
        hiasc "WEST    "
        hiasc "BREAK   "            ; V_BREAK = 11
        .byte 2
        hiasc "TEAR    "
        hiasc "BUST    "
        hiasc "MOVE    "            ; V_MOVE = 12
        .byte 2
        hiasc "SLIDE   "
        hiasc "PUSH    "
        hiasc "LOOK    "            ; V_LOOK = 13
        .byte 1
        hiasc "EXAMINE "
        hiasc "GET     "            ; V_GET = 14
        .byte 2
        hiasc "TAKE    "
        hiasc "LIFT    "
        hiasc "LIGHT   "            ; V_LIGHT = 15
        .byte 1
        hiasc "STRIKE  "
        hiasc "POUR    "            ; V_POUR = 16
        .byte 1
        hiasc "DUMP    "
        hiasc "DROP    "            ; V_DROP = 17
        .byte 2
        hiasc "SET     "
        hiasc "LEAVE   "
        hiasc "JUMP    "            ; V_JUMP = 18
        .byte 1
        hiasc "LEAP    "
        hiasc "READ    "            ; V_READ = 19
        .byte 0
        hiasc "TALK    "            ; V_TALK = 20
        .byte 1
        hiasc "SPEAK   "
        hiasc "KILL    "            ; V_KILL = 21
        .byte 1
        hiasc "SLAY    "
        hiasc "EAT     "            ; V_EAT = 22
        .byte 1
        hiasc "CONSUME "
        hiasc "WIPE    "            ; V_WIPE = 23
        .byte 2
        hiasc "RUB     "
        hiasc "REMOVE  "
        hiasc "FLUSH   "            ; V_FLUSH = 24
        .byte 0
        hiasc "UNSCREW "            ; V_UNSCREW = 25
        .byte 2
        hiasc "UNBOLT  "
        hiasc "LOOSEN  "
        hiasc "WITH    "            ; V_WITH = 26
        .byte 3
        hiasc "USE     "
        hiasc "SHOOT   "
        hiasc "FIRE    "
        hiasc "PRESS   "            ; V_PRESS = 27
        .byte 1
        hiasc "PUSH    "
        hiasc "TURN    "            ; V_TURN = 28
        .byte 0
        hiasc "FAUCET  "            ; V_FAUCET = 29
        .byte 2
        hiasc "TAP     "
        hiasc "WATER   "
        hiasc "WATER   "            ; V_WATER = 30
        .byte 0
        hiasc "ON      "            ; V_ON = 31
        .byte 0
        hiasc "OFF     "            ; V_OFF = 32
        .byte 0
        hiasc "UNLIGHT "            ; V_UNLIGHT = 33
        .byte 1
        hiasc "OFF     "
        hiasc "SAVE    "            ; V_SAVE = 34
        .byte 1
        hiasc "STORE   "
        hiasc "RESTORE "            ; V_RESTORE = 35
        .byte 0
        hiasc "QUIT    "            ; V_QUIT = 36
        .byte 2
        hiasc "BYE     "
        hiasc "STOP    "
        hiasc "HELP    "            ; V_HELP = 37
        .byte 0
        hiasc "INVENTOR"            ; V_INVENTOR = 38
        .byte 3
        hiasc "INVEN   "
        hiasc "CARRYING"
        hiasc "?       "
        hiasc "FUCK    "            ; V_PROFANITY = 39
        .byte 3
        hiasc "SUCK    "
        hiasc "SHIT    "
        hiasc "CUNT    "
        hiasc "SCORE   "            ; V_SCORE = 40
        .byte 0
        hiasc "SLEEP   "            ; V_SLEEP = 41
        .byte 3
        hiasc "REST    "
        hiasc "RETIRE  "
        hiasc "LIE     "
        hiasc "DRINK   "            ; V_DRINK = 42
        .byte 2
        hiasc "SIP     "
        hiasc "TASTE   "
        hiasc "DONE    "            ; V_DONE = 43
        .byte $FF
        .incbin "data/adventure_4343.bin"    ; $4343-$43FF leftover memory, not used by the code (see NOTES.md)

; ==== turn rules =====================================================================
; Every matching rule runs after each command. Rule layout: room, verb, noun (ANY matches
; all), length, number of conditions, number of actions, conditions (C_*), actions (A_*).
turn_rules:

; always
rule_4400:
        .byte ANY, ANY, ANY, rule_440B-rule_4400, 1, 1
        .byte C_SWITCH_EQ, SW_MATCH_BURNING, 1     ; if SW_MATCH_BURNING == 1
        .byte A_MESSAGE, 130     ; say msg 130 "THE MATCH WENT OUT"

; always
rule_440B:
        .byte ANY, ANY, ANY, rule_4417-rule_440B, 1, 1
        .byte C_SWITCH_EQ, SW_MATCH_BURNING, 0     ; if SW_MATCH_BURNING == 0
        .byte A_SET_SWITCH, SW_MATCH_BURNING, 1     ; SW_MATCH_BURNING = 1

; always
rule_4417:
        .byte ANY, ANY, ANY, rule_4420-rule_4417, 0, 1
        .byte A_SUB_SWITCH, 1, SW_MATCH_BURNING     ; SW_MATCH_BURNING -= 1

; always
rule_4420:
        .byte ANY, ANY, ANY, rule_442C-rule_4420, 2, 1
        .byte C_TURNS_GT, 36     ; if turn > 36
        .byte C_SWITCH_EQ, SW_MATCH_BURNING, 0     ; if SW_MATCH_BURNING == 0
        .byte A_LAMP_OFF     ; light off

; always
rule_442C:
        .byte ANY, ANY, ANY, rule_443C-rule_442C, 3, 1
        .byte C_OBJ_IN_ROOM, 18, 253     ; if object 18 (CANDLE) is in nowhere
        .byte C_SWITCH_EQ, SW_MATCH_BURNING, 0     ; if SW_MATCH_BURNING == 0
        .byte C_TURNS_GT, 36     ; if turn > 36
        .byte A_MESSAGE, 42     ; say msg 42 "IT IS DARK, YOU CAN'T SEE"

; always
rule_443C:
        .byte ANY, ANY, ANY, rule_4446-rule_443C, 1, 1
        .byte C_OBJ_IN_ROOM, 18, 254     ; if object 18 (CANDLE) is in inventory
        .byte A_LAMP_ON     ; light on

; DROP
rule_4446:
        .byte ANY, V_DROP, ANY, rule_444D-rule_4446, 0, 1
        .byte A_RESET_VIEW     ; show the room view

; always
rule_444D:
        .byte ANY, ANY, ANY, rule_445A-rule_444D, 2, 1
        .byte C_TURNS_GT, 20     ; if turn > 20
        .byte C_SWITCH_EQ, SW_DARK_WARNED, 0     ; if SW_DARK_WARNED == 0
        .byte A_MESSAGE, 7     ; say msg 7 "IT IS GETTING DARK"

; always
rule_445A:
        .byte ANY, ANY, ANY, rule_4465-rule_445A, 1, 1
        .byte C_TURNS_GT, 35     ; if turn > 35
        .byte A_SET_SWITCH, SW_DARK_WARNED, 1     ; SW_DARK_WARNED = 1

; room 1 (IN THE FRONT YARD OF A LARGE ABANDONE...)
rule_4465:
        .byte 1, ANY, ANY, turn_rules_end-rule_4465, 2, 2
        .byte C_OBJ_IN_ROOM, 32, 254     ; if object 32 (JEWELS) is in inventory
        .byte C_SWITCH_EQ, SW_DAISY_DEAD, 1     ; if SW_DAISY_DEAD == 1
        .byte A_MESSAGE, 164     ; say msg 164 "CONGRATULATIONS YOU HAVE BEATEN ADVENTURE AND ARE DECLARED A GURU WIZARD"
        .byte A_GAME_OVER     ; ask to play again
turn_rules_end:
        .byte $FF
        .incbin "data/adventure_4475.bin"    ; $4475-$44FF leftover memory, not used by the code (see NOTES.md)

; ==== command rules ==================================================================
; Tried in order after each command; the first match runs and ends the search. The generic
; GET/DROP/LOOK/SAVE/... rules at the end catch anything earlier rules don't.
command_rules:

; room 1 (IN THE FRONT YARD OF A LARGE ABANDONE...), GO, STAIRS
rule_4500:
        .byte 1, V_GO, N_STAIRS, rule_4508-rule_4500, 0, 1
        .byte A_GOTO_ROOM, 2     ; go to room 2 (ON THE PORCH)

; room 1 (IN THE FRONT YARD OF A LARGE ABANDONE...), UP, STAIRS
rule_4508:
        .byte 1, V_U, N_STAIRS, rule_4510-rule_4508, 0, 1
        .byte A_GOTO_ROOM, 2     ; go to room 2 (ON THE PORCH)

; room 1 (IN THE FRONT YARD OF A LARGE ABANDONE...), LOOK, FENCE
rule_4510:
        .byte 1, V_LOOK, N_FENCE, rule_4518-rule_4510, 0, 1
        .byte A_MESSAGE, 100     ; say msg 100 "IT IS VERY HIGH"

; room 1 (IN THE FRONT YARD OF A LARGE ABANDONE...), UP, FENCE
rule_4518:
        .byte 1, V_U, N_FENCE, rule_4520-rule_4518, 0, 1
        .byte A_MESSAGE, 1     ; say msg 1 "IT IS TOO HIGH"

; room 1 (IN THE FRONT YARD OF A LARGE ABANDONE...), LOOK, TREE
rule_4520:
        .byte 1, V_LOOK, N_TREE, rule_4528-rule_4520, 0, 1
        .byte A_MESSAGE, 101     ; say msg 101 "THERE IS A FOREST"

; room 1 (IN THE FRONT YARD OF A LARGE ABANDONE...), GO, TREE
rule_4528:
        .byte 1, V_GO, N_TREE, rule_4530-rule_4528, 0, 1
        .byte A_GOTO_ROOM, 5     ; go to room 5 (IN A FOREST)

; room 1 (IN THE FRONT YARD OF A LARGE ABANDONE...), JUMP, FENCE
rule_4530:
        .byte 1, V_JUMP, N_FENCE, rule_4538-rule_4530, 0, 1
        .byte A_MESSAGE, 1     ; say msg 1 "IT IS TOO HIGH"

; room 2 (ON THE PORCH), OPEN, DOOR
rule_4538:
        .byte 2, V_OPEN, N_DOOR, rule_4543-rule_4538, 1, 1
        .byte C_SWITCH_EQ, SW_PORCH_DOOR_OPEN, 1     ; if SW_PORCH_DOOR_OPEN == 1
        .byte A_MESSAGE, 129     ; say msg 129 "IT IS OPEN"

; room 2 (ON THE PORCH), OPEN, DOOR
rule_4543:
        .byte 2, V_OPEN, N_DOOR, rule_454E-rule_4543, 0, 2
        .byte A_SET_BASE_VIEW, 2     ; make picture 2 the room view
        .byte A_SET_SWITCH, SW_PORCH_DOOR_OPEN, 1     ; SW_PORCH_DOOR_OPEN = 1

; room 2 (ON THE PORCH), CLOSE, DOOR
rule_454E:
        .byte 2, V_CLOSE, N_DOOR, rule_455C-rule_454E, 1, 2
        .byte C_SWITCH_EQ, SW_PORCH_DOOR_OPEN, 1     ; if SW_PORCH_DOOR_OPEN == 1
        .byte A_SET_BASE_VIEW, 1     ; make picture 1 the room view
        .byte A_SET_SWITCH, SW_PORCH_DOOR_OPEN, 0     ; SW_PORCH_DOOR_OPEN = 0

; room 2 (ON THE PORCH), CLOSE, DOOR
rule_455C:
        .byte 2, V_CLOSE, N_DOOR, rule_4567-rule_455C, 1, 1
        .byte C_SWITCH_EQ, SW_PORCH_DOOR_OPEN, 0     ; if SW_PORCH_DOOR_OPEN == 0
        .byte A_MESSAGE, 128     ; say msg 128 "THE DOOR IS CLOSED"

; room 2 (ON THE PORCH), GO, DOOR
rule_4567:
        .byte 2, V_GO, N_DOOR, rule_4577-rule_4567, 1, 3
        .byte C_SWITCH_EQ, SW_PORCH_DOOR_OPEN, 1     ; if SW_PORCH_DOOR_OPEN == 1
        .byte A_GOTO_ROOM, 3     ; go to room 3 (IN AN ENTRY HALL)
        .byte A_SET_SWITCH, SW_FRONT_DOOR_LOCKED, 1     ; SW_FRONT_DOOR_LOCKED = 1
        .byte A_MESSAGE, 142     ; say msg 142 "THE DOOR HAS BEEN CLOSED AND LOCKED"

; room 2 (ON THE PORCH), GO, DOOR
rule_4577:
        .byte 2, V_GO, N_DOOR, rule_457F-rule_4577, 0, 1
        .byte A_MESSAGE, 128     ; say msg 128 "THE DOOR IS CLOSED"

; room 2 (ON THE PORCH), GO, STAIRS
rule_457F:
        .byte 2, V_GO, N_STAIRS, rule_4587-rule_457F, 0, 1
        .byte A_GOTO_ROOM, 1     ; go to room 1 (IN THE FRONT YARD OF A LARGE ABANDONE...)

; room 3 (IN AN ENTRY HALL), LOOK, PERSON
rule_4587:
        .byte 3, V_LOOK, N_PERSON, rule_4591-rule_4587, 1, 1
        .byte C_VIEW_IS, 53     ; if current picture == 53
        .byte A_MESSAGE, 163     ; say msg 163 "THE PEOPLE WERE EXPLAINED AT THE BEGINNING OF THE GAME."

; room 3 (IN AN ENTRY HALL), GO, DOOR
rule_4591:
        .byte 3, V_GO, N_DOOR, rule_4599-rule_4591, 0, 1
        .byte A_MESSAGE, 48     ; say msg 48 "WHICH DIRECTION?"

; room 3 (IN AN ENTRY HALL), GO, STAIRS
rule_4599:
        .byte 3, V_GO, N_STAIRS, rule_45A5-rule_4599, 1, 2
        .byte C_VIEW_IS, 53     ; if current picture == 53
        .byte A_SET_BASE_VIEW, 4     ; make picture 4 the room view
        .byte A_GOTO_ROOM, 24     ; go to room 24 (AT THE JUNCTION OF AN EAST/WEST HALLW...)

; room 3 (IN AN ENTRY HALL), GO, STAIRS
rule_45A5:
        .byte 3, V_GO, N_STAIRS, rule_45AD-rule_45A5, 0, 1
        .byte A_GOTO_ROOM, 24     ; go to room 24 (AT THE JUNCTION OF AN EAST/WEST HALLW...)

; room 3 (IN AN ENTRY HALL), OPEN, DOOR
rule_45AD:
        .byte 3, V_OPEN, N_DOOR, rule_45B8-rule_45AD, 1, 1
        .byte C_SWITCH_EQ, SW_FRONT_DOOR_LOCKED, 1     ; if SW_FRONT_DOOR_LOCKED == 1
        .byte A_MESSAGE, 82     ; say msg 82 "IT IS LOCKED"

; room 3 (IN AN ENTRY HALL), OPEN, DOOR
rule_45B8:
        .byte 3, V_OPEN, N_DOOR, rule_45C3-rule_45B8, 1, 1
        .byte C_SWITCH_EQ, SW_FRONT_DOOR_LOCKED, 0     ; if SW_FRONT_DOOR_LOCKED == 0
        .byte A_SET_BASE_VIEW, 5     ; make picture 5 the room view

; room 3 (IN AN ENTRY HALL), UNLOCK, DOOR
rule_45C3:
        .byte 3, V_UNLOCK, N_DOOR, rule_45D1-rule_45C3, 1, 2
        .byte C_OBJ_IN_ROOM, 30, 254     ; if object 30 (KEY) is in inventory
        .byte A_SET_SWITCH, SW_FRONT_DOOR_LOCKED, 0     ; SW_FRONT_DOOR_LOCKED = 0
        .byte A_MESSAGE, 2     ; say msg 2 "OK"

; room 3 (IN AN ENTRY HALL), UNLOCK, DOOR
rule_45D1:
        .byte 3, V_UNLOCK, N_DOOR, rule_45D9-rule_45D1, 0, 1
        .byte A_MESSAGE, 83     ; say msg 83 "YOU HAVE NOTHING TO UNLOCK IT WITH"

; room 3 (IN AN ENTRY HALL), BREAK, DOOR
rule_45D9:
        .byte 3, V_BREAK, N_DOOR, rule_45E1-rule_45D9, 0, 1
        .byte A_MESSAGE, 4     ; say msg 4 "IT IS TOO HEAVY"

; room 3 (IN AN ENTRY HALL), NORTH, 
rule_45E1:
        .byte 3, V_N, N_NONE, rule_45EB-rule_45E1, 1, 1
        .byte C_VIEW_IS, 53     ; if current picture == 53
        .byte A_MESSAGE, 128     ; say msg 128 "THE DOOR IS CLOSED"

; room 3 (IN AN ENTRY HALL), NORTH, 
rule_45EB:
        .byte 3, V_N, N_NONE, rule_45F7-rule_45EB, 1, 2
        .byte C_VIEW_IS, 5     ; if current picture == 5
        .byte A_SET_BASE_VIEW, 4     ; make picture 4 the room view
        .byte A_GOTO_ROOM, 2     ; go to room 2 (ON THE PORCH)

; room 3 (IN AN ENTRY HALL), NORTH, 
rule_45F7:
        .byte 3, V_N, N_NONE, rule_4601-rule_45F7, 1, 1
        .byte C_VIEW_IS, 4     ; if current picture == 4
        .byte A_MESSAGE, 128     ; say msg 128 "THE DOOR IS CLOSED"

; room 3 (IN AN ENTRY HALL), EAST, 
rule_4601:
        .byte 3, V_E, N_NONE, rule_460D-rule_4601, 1, 2
        .byte C_VIEW_IS, 53     ; if current picture == 53
        .byte A_SET_BASE_VIEW, 4     ; make picture 4 the room view
        .byte A_GOTO_ROOM, 14     ; go to room 14 (IN THE OLD, DUSTY LIBRARY)

; room 3 (IN AN ENTRY HALL), EAST, 
rule_460D:
        .byte 3, V_E, N_NONE, rule_4615-rule_460D, 0, 1
        .byte A_GOTO_ROOM, 14     ; go to room 14 (IN THE OLD, DUSTY LIBRARY)

; room 3 (IN AN ENTRY HALL), WEST, 
rule_4615:
        .byte 3, V_W, N_NONE, rule_4621-rule_4615, 1, 2
        .byte C_VIEW_IS, 53     ; if current picture == 53
        .byte A_SET_BASE_VIEW, 4     ; make picture 4 the room view
        .byte A_GOTO_ROOM, 4     ; go to room 4 (IN THE KITCHEN)

; room 3 (IN AN ENTRY HALL), WEST, 
rule_4621:
        .byte 3, V_W, N_NONE, rule_4629-rule_4621, 0, 1
        .byte A_GOTO_ROOM, 4     ; go to room 4 (IN THE KITCHEN)

; room 3 (IN AN ENTRY HALL), SOUTH, 
rule_4629:
        .byte 3, V_S, N_NONE, rule_4635-rule_4629, 1, 2
        .byte C_VIEW_IS, 53     ; if current picture == 53
        .byte A_SET_BASE_VIEW, 4     ; make picture 4 the room view
        .byte A_GOTO_ROOM, 16     ; go to room 16 (IN THE DINING ROOM)

; room 3 (IN AN ENTRY HALL), SOUTH, 
rule_4635:
        .byte 3, V_S, N_NONE, rule_463D-rule_4635, 0, 1
        .byte A_GOTO_ROOM, 16     ; go to room 16 (IN THE DINING ROOM)

; room 3 (IN AN ENTRY HALL), UP, STAIRS
rule_463D:
        .byte 3, V_U, N_STAIRS, rule_4645-rule_463D, 0, 1
        .byte A_GOTO_ROOM, 24     ; go to room 24 (AT THE JUNCTION OF AN EAST/WEST HALLW...)

; room 3 (IN AN ENTRY HALL), UP, 
rule_4645:
        .byte 3, V_U, N_NONE, rule_464F-rule_4645, 0, 2
        .byte A_SET_BASE_VIEW, 4     ; make picture 4 the room view
        .byte A_GOTO_ROOM, 24     ; go to room 24 (AT THE JUNCTION OF AN EAST/WEST HALLW...)

; room 4 (IN THE KITCHEN), GET, CABINET
rule_464F:
        .byte 4, V_GET, N_CABINET, rule_4657-rule_464F, 0, 1
        .byte A_MESSAGE, 138     ; say msg 138 "IT'S TOO HEAVY TO LIFT"

; room 4 (IN THE KITCHEN), MOVE, CABINET
rule_4657:
        .byte 4, V_MOVE, N_CABINET, rule_4662-rule_4657, 1, 1
        .byte C_SWITCH_EQ, SW_CABINET_MOVED, 1     ; if SW_CABINET_MOVED == 1
        .byte A_MESSAGE, 139     ; say msg 139 "IT WON'T MOVE ANY FARTHER"

; room 4 (IN THE KITCHEN), MOVE, CABINET
rule_4662:
        .byte 4, V_MOVE, N_CABINET, rule_4675-rule_4662, 0, 4
        .byte A_PLACE_OBJ, 10, 4, 65, 20     ; put object 10 (CABINET) in room 4 (IN THE KITCHEN) at (65,20)
        .byte A_PUT_OBJ, 11, 4     ; put object 11 (BRICKS) in room 4 (IN THE KITCHEN)
        .byte A_SET_SWITCH, SW_CABINET_MOVED, 1     ; SW_CABINET_MOVED = 1
        .byte A_MESSAGE, 10     ; say msg 10 "THE WALL IS BRICKED UP BEHIND IT"

; room 4 (IN THE KITCHEN), OPEN, CABINET
rule_4675:
        .byte 4, V_OPEN, N_CABINET, rule_467E-rule_4675, 0, 1
        .byte A_SET_OBJ_PIC, 97, 10     ; draw object 10 (CABINET) as picture 97

; room 4 (IN THE KITCHEN), CLOSE, CABINET
rule_467E:
        .byte 4, V_CLOSE, N_CABINET, rule_4688-rule_467E, 0, 2
        .byte A_SET_OBJ_PIC, 55, 10     ; draw object 10 (CABINET) as picture 55
        .byte A_RESET_VIEW     ; show the room view

; room 4 (IN THE KITCHEN), LOOK, CABINET
rule_4688:
        .byte 4, V_LOOK, N_CABINET, rule_4693-rule_4688, 1, 1
        .byte C_OBJ_PIC_IS, 10, 55     ; if object 10 (CABINET) picture == 55
        .byte A_MESSAGE, 133     ; say msg 133 "IT IS NOT OPEN"

; room 4 (IN THE KITCHEN), LOOK, CABINET
rule_4693:
        .byte 4, V_LOOK, N_CABINET, rule_469B-rule_4693, 0, 1
        .byte A_SET_VIEW, 12     ; show picture 12

; room 4 (IN THE KITCHEN), BREAK, WALL
rule_469B:
        .byte 4, V_BREAK, N_WALL, rule_46AE-rule_469B, 1, 3
        .byte C_OBJ_IN_ROOM, 42, 254     ; if object 42 (SLEDGEHA) is in inventory
        .byte A_PUT_OBJ, 11, 253     ; put object 11 (BRICKS) in nowhere
        .byte A_PLACE_OBJ, 12, 4, 7, 83     ; put object 12 (HOLE) in room 4 (IN THE KITCHEN) at (7,83)
        .byte A_MESSAGE, 11     ; say msg 11 "THE BRICKS BREAK APART LEAVING A LARGE HOLE"

; room 4 (IN THE KITCHEN), BREAK, BRICKS
rule_46AE:
        .byte 4, V_BREAK, N_BRICKS, rule_46C1-rule_46AE, 1, 3
        .byte C_OBJ_IN_ROOM, 42, 254     ; if object 42 (SLEDGEHA) is in inventory
        .byte A_PUT_OBJ, 11, 253     ; put object 11 (BRICKS) in nowhere
        .byte A_PLACE_OBJ, 12, 4, 7, 83     ; put object 12 (HOLE) in room 4 (IN THE KITCHEN) at (7,83)
        .byte A_MESSAGE, 11     ; say msg 11 "THE BRICKS BREAK APART LEAVING A LARGE HOLE"

; room 4 (IN THE KITCHEN), BREAK, WALL
rule_46C1:
        .byte 4, V_BREAK, N_WALL, rule_46C9-rule_46C1, 0, 1
        .byte A_MESSAGE, 12     ; say msg 12 "YOU HAVE NOTHING STRONG ENOUGH"

; room 4 (IN THE KITCHEN), OPEN, REFRIGER
rule_46C9:
        .byte 4, V_OPEN, N_REFRIGER, rule_46D8-rule_46C9, 1, 2
        .byte C_OBJ_IN_ROOM, 51, 4     ; if object 51 (REFRIGER) is in room 4 (IN THE KITCHEN)
        .byte A_PUT_OBJ, 51, 253     ; put object 51 (REFRIGER) in nowhere
        .byte A_PUT_OBJ, 52, 4     ; put object 52 (REFRIGER) in room 4 (IN THE KITCHEN)

; room 4 (IN THE KITCHEN), OPEN, REFRIGER
rule_46D8:
        .byte 4, V_OPEN, N_REFRIGER, rule_46E3-rule_46D8, 1, 1
        .byte C_OBJ_IN_ROOM, 52, 4     ; if object 52 (REFRIGER) is in room 4 (IN THE KITCHEN)
        .byte A_MESSAGE, 129     ; say msg 129 "IT IS OPEN"

; room 4 (IN THE KITCHEN), CLOSE, REFRIGER
rule_46E3:
        .byte 4, V_CLOSE, N_REFRIGER, rule_46F3-rule_46E3, 1, 3
        .byte C_OBJ_IN_ROOM, 52, 4     ; if object 52 (REFRIGER) is in room 4 (IN THE KITCHEN)
        .byte A_PUT_OBJ, 52, 253     ; put object 52 (REFRIGER) in nowhere
        .byte A_PUT_OBJ, 51, 4     ; put object 51 (REFRIGER) in room 4 (IN THE KITCHEN)
        .byte A_RESET_VIEW     ; show the room view

; room 4 (IN THE KITCHEN), CLOSE, REFRIGER
rule_46F3:
        .byte 4, V_CLOSE, N_REFRIGER, rule_46FF-rule_46F3, 1, 2
        .byte C_OBJ_IN_ROOM, 51, 4     ; if object 51 (REFRIGER) is in room 4 (IN THE KITCHEN)
        .byte A_MESSAGE, 133     ; say msg 133 "IT IS NOT OPEN"
        .byte A_RESET_VIEW     ; show the room view

; room 4 (IN THE KITCHEN), LOOK, REFRIGER
rule_46FF:
        .byte 4, V_LOOK, N_REFRIGER, rule_470A-rule_46FF, 1, 1
        .byte C_OBJ_IN_ROOM, 52, 4     ; if object 52 (REFRIGER) is in room 4 (IN THE KITCHEN)
        .byte A_SET_VIEW, 11     ; show picture 11

; room 4 (IN THE KITCHEN), LOOK, REFRIGER
rule_470A:
        .byte 4, V_LOOK, N_REFRIGER, rule_4715-rule_470A, 1, 1
        .byte C_OBJ_IN_ROOM, 51, 4     ; if object 51 (REFRIGER) is in room 4 (IN THE KITCHEN)
        .byte A_MESSAGE, 128     ; say msg 128 "THE DOOR IS CLOSED"

; room 4 (IN THE KITCHEN), FAUCET, ON
rule_4715:
        .byte 4, V_FAUCET, N_ON, rule_4720-rule_4715, 0, 2
        .byte A_MESSAGE, 13     ; say msg 13 "WATER IS RUNNING INTO THE SINK"
        .byte A_SET_SWITCH, SW_KITCHEN_WATER, 1     ; SW_KITCHEN_WATER = 1

; room 4 (IN THE KITCHEN), GET, WATER
rule_4720:
        .byte 4, V_GET, N_WATER, rule_4734-rule_4720, 2, 3
        .byte C_SWITCH_EQ, SW_KITCHEN_WATER, 1     ; if SW_KITCHEN_WATER == 1
        .byte C_OBJ_IN_ROOM, 14, 254     ; if object 14 (PITCHER) is in inventory
        .byte A_MESSAGE, 92     ; say msg 92 "YOUR PITCHER IS FULL"
        .byte A_PUT_OBJ, 14, 253     ; put object 14 (PITCHER) in nowhere
        .byte A_PUT_OBJ, 15, 254     ; put object 15 (PITCHER) in inventory

; room 4 (IN THE KITCHEN), GET, WATER
rule_4734:
        .byte 4, V_GET, N_WATER, rule_473F-rule_4734, 1, 1
        .byte C_SWITCH_EQ, SW_KITCHEN_WATER, 1     ; if SW_KITCHEN_WATER == 1
        .byte A_MESSAGE, 14     ; say msg 14 "YOU HAVE NO CONTAINER"

; room 4 (IN THE KITCHEN), GET, WATER
rule_473F:
        .byte 4, V_GET, N_WATER, rule_4747-rule_473F, 0, 1
        .byte A_MESSAGE, 131     ; say msg 131 "I SEE NO WATER"

; room 4 (IN THE KITCHEN), LIGHT, STOVE
rule_4747:
        .byte 4, V_LIGHT, N_STOVE, rule_4750-rule_4747, 0, 2
        .byte A_MESSAGE, 16     ; say msg 16 "THE STOVE EXPLODES, YOU ARE DEAD"
        .byte A_GAME_OVER     ; ask to play again

; room 4 (IN THE KITCHEN), OPEN, DOOR
rule_4750:
        .byte 4, V_OPEN, N_DOOR, rule_475D-rule_4750, 1, 2
        .byte C_VIEW_IS, 13     ; if current picture == 13
        .byte A_SET_BASE_VIEW, 14     ; make picture 14 the room view
        .byte A_SET_SWITCH, SW_KITCHEN_DOOR_OPEN, 1     ; SW_KITCHEN_DOOR_OPEN = 1

; room 4 (IN THE KITCHEN), OPEN, DOOR
rule_475D:
        .byte 4, V_OPEN, N_DOOR, rule_4767-rule_475D, 1, 1
        .byte C_VIEW_IS, 14     ; if current picture == 14
        .byte A_MESSAGE, 129     ; say msg 129 "IT IS OPEN"

; room 4 (IN THE KITCHEN), CLOSE, DOOR
rule_4767:
        .byte 4, V_CLOSE, N_DOOR, rule_4774-rule_4767, 1, 2
        .byte C_VIEW_IS, 14     ; if current picture == 14
        .byte A_SET_BASE_VIEW, 13     ; make picture 13 the room view
        .byte A_SET_SWITCH, SW_KITCHEN_DOOR_OPEN, 0     ; SW_KITCHEN_DOOR_OPEN = 0

; room 4 (IN THE KITCHEN), CLOSE, DOOR
rule_4774:
        .byte 4, V_CLOSE, N_DOOR, rule_477E-rule_4774, 1, 1
        .byte C_VIEW_IS, 13     ; if current picture == 13
        .byte A_MESSAGE, 128     ; say msg 128 "THE DOOR IS CLOSED"

; room 4 (IN THE KITCHEN), LOOK, SINK
rule_477E:
        .byte 4, V_LOOK, N_SINK, rule_478B-rule_477E, 1, 2
        .byte C_OBJ_IN_ROOM, 16, 4     ; if object 16 (BUTTERKN) is in room 4 (IN THE KITCHEN)
        .byte A_MESSAGE, 143     ; say msg 143 "THERE IS A BUTTERKNIFE HERE"
        .byte A_SET_VIEW, 10     ; show picture 10

; room 4 (IN THE KITCHEN), LOOK, SINK
rule_478B:
        .byte 4, V_LOOK, N_SINK, rule_4793-rule_478B, 0, 1
        .byte A_SET_VIEW, 10     ; show picture 10

; room 4 (IN THE KITCHEN), GO, HOLE
rule_4793:
        .byte 4, V_GO, N_HOLE, rule_479E-rule_4793, 1, 1
        .byte C_OBJ_IN_ROOM, 12, 4     ; if object 12 (HOLE) is in room 4 (IN THE KITCHEN)
        .byte A_GOTO_ROOM, 19     ; go to room 19 (IN A SMALL PANTRY)

; room 4 (IN THE KITCHEN), FAUCET, OFF
rule_479E:
        .byte 4, V_FAUCET, N_OFF, rule_47A9-rule_479E, 0, 2
        .byte A_SET_SWITCH, SW_KITCHEN_WATER, 0     ; SW_KITCHEN_WATER = 0
        .byte A_MESSAGE, 2     ; say msg 2 "OK"

; room 4 (IN THE KITCHEN), GO, DOOR
rule_47A9:
        .byte 4, V_GO, N_DOOR, rule_47B1-rule_47A9, 0, 1
        .byte A_MESSAGE, 48     ; say msg 48 "WHICH DIRECTION?"

; room 4 (IN THE KITCHEN), WEST, 
rule_47B1:
        .byte 4, V_W, N_NONE, rule_47BB-rule_47B1, 1, 1
        .byte C_VIEW_IS, 14     ; if current picture == 14
        .byte A_GOTO_ROOM, 5     ; go to room 5 (IN A FOREST)

; room 4 (IN THE KITCHEN), WEST, 
rule_47BB:
        .byte 4, V_W, N_NONE, rule_47C3-rule_47BB, 0, 1
        .byte A_MESSAGE, 128     ; say msg 128 "THE DOOR IS CLOSED"

; room 5 (IN A FOREST), UP, 
rule_47C3:
        .byte 5, V_U, N_NONE, rule_47CE-rule_47C3, 1, 1
        .byte C_SWITCH_EQ, SW_KITCHEN_DOOR_OPEN, 0     ; if SW_KITCHEN_DOOR_OPEN == 0
        .byte A_MESSAGE, 144     ; say msg 144 "THE KITCHEN DOOR IS CLOSED"

; room 5 (IN A FOREST), UP, 
rule_47CE:
        .byte 5, V_U, N_NONE, rule_47D6-rule_47CE, 0, 1
        .byte A_GOTO_ROOM, 4     ; go to room 4 (IN THE KITCHEN)

; room 13 (THERE IS A VERY TALL PINE TREE IN FRO...), LOOK, TREE
rule_47D6:
        .byte 13, V_LOOK, N_TREE, rule_47DE-rule_47D6, 0, 1
        .byte A_MESSAGE, 15     ; say msg 15 "THERE IS NOTHING SPECIAL"

; room 5 (IN A FOREST), OPEN, DOOR
rule_47DE:
        .byte 5, V_OPEN, N_DOOR, rule_47EC-rule_47DE, 0, 3
        .byte A_MESSAGE, 162     ; say msg 162 "THE KITCHEN DOOR IS OPEN"
        .byte A_SET_ROOM_VIEW, 4, 14     ; set room 4 (IN THE KITCHEN) view to picture 14
        .byte A_SET_SWITCH, SW_KITCHEN_DOOR_OPEN, 1     ; SW_KITCHEN_DOOR_OPEN = 1

; room 13 (THERE IS A VERY TALL PINE TREE IN FRO...), UP, TREE
rule_47EC:
        .byte 13, V_U, N_TREE, rule_47F4-rule_47EC, 0, 1
        .byte A_GOTO_ROOM, 23     ; go to room 23 (AT THE TOP OF A VERY TALL PINE TREE)

; room 14 (IN THE OLD, DUSTY LIBRARY), OPEN, DOOR
rule_47F4:
        .byte 14, V_OPEN, N_DOOR, rule_4801-rule_47F4, 1, 2
        .byte C_VIEW_IS, 6     ; if current picture == 6
        .byte A_SET_BASE_VIEW, 7     ; make picture 7 the room view
        .byte A_SET_ROOM_VIEW, 15, 8     ; set room 15 (IN THE SIDE YARD) view to picture 8

; room 14 (IN THE OLD, DUSTY LIBRARY), OPEN, DOOR
rule_4801:
        .byte 14, V_OPEN, N_DOOR, rule_480B-rule_4801, 1, 1
        .byte C_VIEW_IS, 7     ; if current picture == 7
        .byte A_MESSAGE, 129     ; say msg 129 "IT IS OPEN"

; room 14 (IN THE OLD, DUSTY LIBRARY), CLOSE, DOOR
rule_480B:
        .byte 14, V_CLOSE, N_DOOR, rule_4818-rule_480B, 1, 2
        .byte C_VIEW_IS, 7     ; if current picture == 7
        .byte A_SET_BASE_VIEW, 6     ; make picture 6 the room view
        .byte A_SET_ROOM_VIEW, 15, 9     ; set room 15 (IN THE SIDE YARD) view to picture 9

; room 14 (IN THE OLD, DUSTY LIBRARY), CLOSE, DOOR
rule_4818:
        .byte 14, V_CLOSE, N_DOOR, rule_4822-rule_4818, 1, 1
        .byte C_VIEW_IS, 6     ; if current picture == 6
        .byte A_MESSAGE, 128     ; say msg 128 "THE DOOR IS CLOSED"

; room 14 (IN THE OLD, DUSTY LIBRARY), GO, DOOR
rule_4822:
        .byte 14, V_GO, N_DOOR, rule_482A-rule_4822, 0, 1
        .byte A_MESSAGE, 48     ; say msg 48 "WHICH DIRECTION?"

; room 14 (IN THE OLD, DUSTY LIBRARY), EAST, 
rule_482A:
        .byte 14, V_E, N_NONE, rule_4834-rule_482A, 1, 1
        .byte C_VIEW_IS, 7     ; if current picture == 7
        .byte A_GOTO_ROOM, 15     ; go to room 15 (IN THE SIDE YARD)

; room 14 (IN THE OLD, DUSTY LIBRARY), EAST, 
rule_4834:
        .byte 14, V_E, N_NONE, rule_483E-rule_4834, 1, 1
        .byte C_VIEW_IS, 6     ; if current picture == 6
        .byte A_MESSAGE, 128     ; say msg 128 "THE DOOR IS CLOSED"

; room 14 (IN THE OLD, DUSTY LIBRARY), WEST, 
rule_483E:
        .byte 14, V_W, N_NONE, rule_4846-rule_483E, 0, 1
        .byte A_GOTO_ROOM, 3     ; go to room 3 (IN AN ENTRY HALL)

; room 14 (IN THE OLD, DUSTY LIBRARY), LOOK, SHELVES
rule_4846:
        .byte 14, V_LOOK, N_SHELVES, rule_484E-rule_4846, 0, 1
        .byte A_MESSAGE, 105     ; say msg 105 "THERE ARE NOT MANY BOOKS LEFT"

; room 14 (IN THE OLD, DUSTY LIBRARY), GET, BOOKS
rule_484E:
        .byte 14, V_GET, N_BOOKS, rule_4856-rule_484E, 0, 1
        .byte A_MESSAGE, 27     ; say msg 27 "IT DOES NOT REMOVE"

; room 14 (IN THE OLD, DUSTY LIBRARY), GET, COUCH
rule_4856:
        .byte 14, V_GET, N_COUCH, rule_485E-rule_4856, 0, 1
        .byte A_MESSAGE, 4     ; say msg 4 "IT IS TOO HEAVY"

; room 14 (IN THE OLD, DUSTY LIBRARY), GET, TABLE
rule_485E:
        .byte 14, V_GET, N_TABLE, rule_4866-rule_485E, 0, 1
        .byte A_MESSAGE, 4     ; say msg 4 "IT IS TOO HEAVY"

; room 14 (IN THE OLD, DUSTY LIBRARY), GET, CHAIR
rule_4866:
        .byte 14, V_GET, N_CHAIR, rule_486E-rule_4866, 0, 1
        .byte A_MESSAGE, 4     ; say msg 4 "IT IS TOO HEAVY"

; room 15 (IN THE SIDE YARD), OPEN, DOOR
rule_486E:
        .byte 15, V_OPEN, N_DOOR, rule_487B-rule_486E, 1, 2
        .byte C_VIEW_IS, 9     ; if current picture == 9
        .byte A_SET_BASE_VIEW, 8     ; make picture 8 the room view
        .byte A_SET_ROOM_VIEW, 14, 7     ; set room 14 (IN THE OLD, DUSTY LIBRARY) view to picture 7

; room 15 (IN THE SIDE YARD), OPEN, DOOR
rule_487B:
        .byte 15, V_OPEN, N_DOOR, rule_4885-rule_487B, 1, 1
        .byte C_VIEW_IS, 8     ; if current picture == 8
        .byte A_MESSAGE, 129     ; say msg 129 "IT IS OPEN"

; room 15 (IN THE SIDE YARD), CLOSE, DOOR
rule_4885:
        .byte 15, V_CLOSE, N_DOOR, rule_4892-rule_4885, 1, 2
        .byte C_VIEW_IS, 8     ; if current picture == 8
        .byte A_SET_BASE_VIEW, 9     ; make picture 9 the room view
        .byte A_SET_ROOM_VIEW, 14, 6     ; set room 14 (IN THE OLD, DUSTY LIBRARY) view to picture 6

; room 15 (IN THE SIDE YARD), CLOSE, DOOR
rule_4892:
        .byte 15, V_CLOSE, N_DOOR, rule_489C-rule_4892, 1, 1
        .byte C_VIEW_IS, 9     ; if current picture == 9
        .byte A_MESSAGE, 128     ; say msg 128 "THE DOOR IS CLOSED"

; room 15 (IN THE SIDE YARD), GO, DOOR
rule_489C:
        .byte 15, V_GO, N_DOOR, rule_48A6-rule_489C, 1, 1
        .byte C_VIEW_IS, 8     ; if current picture == 8
        .byte A_GOTO_ROOM, 14     ; go to room 14 (IN THE OLD, DUSTY LIBRARY)

; room 15 (IN THE SIDE YARD), GO, DOOR
rule_48A6:
        .byte 15, V_GO, N_DOOR, rule_48B0-rule_48A6, 1, 1
        .byte C_VIEW_IS, 9     ; if current picture == 9
        .byte A_MESSAGE, 128     ; say msg 128 "THE DOOR IS CLOSED"

; room 15 (IN THE SIDE YARD), UP, FENCE
rule_48B0:
        .byte 15, V_U, N_FENCE, rule_48B8-rule_48B0, 0, 1
        .byte A_MESSAGE, 1     ; say msg 1 "IT IS TOO HIGH"

; room 15 (IN THE SIDE YARD), JUMP, FENCE
rule_48B8:
        .byte 15, V_JUMP, N_FENCE, rule_48C0-rule_48B8, 0, 1
        .byte A_MESSAGE, 1     ; say msg 1 "IT IS TOO HIGH"

; room 16 (IN THE DINING ROOM)
rule_48C0:
        .byte 16, ANY, ANY, rule_48D6-rule_48C0, 2, 3
        .byte C_OBJ_IN_ROOM, 18, 254     ; if object 18 (CANDLE) is in inventory
        .byte C_SWITCH_EQ, SW_RUG_FIRE, 0     ; if SW_RUG_FIRE == 0
        .byte A_SET_SWITCH, SW_RUG_FIRE, 1     ; SW_RUG_FIRE = 1
        .byte A_MESSAGE, 44     ; say msg 44 "YOU TRIP OVER RUG AND FALL.  OH,OH, YOU STARTED A FIRE WITH YOUR CANDLE!"
        .byte A_PLACE_OBJ, 20, 16, 81, 92     ; put object 20 (FIRE) in room 16 (IN THE DINING ROOM) at (81,92)

; room 16 (IN THE DINING ROOM), POUR, WATER
rule_48D6:
        .byte 16, V_POUR, N_WATER, rule_48F4-rule_48D6, 2, 6
        .byte C_OBJ_IN_ROOM, 15, 254     ; if object 15 (PITCHER) is in inventory
        .byte C_OBJ_IN_ROOM, 20, 16     ; if object 20 (FIRE) is in room 16 (IN THE DINING ROOM)
        .byte A_PUT_OBJ, 20, 253     ; put object 20 (FIRE) in nowhere
        .byte A_PLACE_OBJ, 21, 16, 79, 115     ; put object 21 (HOLE) in room 16 (IN THE DINING ROOM) at (79,115)
        .byte A_MESSAGE, 45     ; say msg 45 "THE FIRE IS OUT"
        .byte A_MESSAGE, 17     ; say msg 17 "THE PITCHER IS EMPTY"
        .byte A_PUT_OBJ, 15, 253     ; put object 15 (PITCHER) in nowhere
        .byte A_PUT_OBJ, 14, 254     ; put object 14 (PITCHER) in inventory

; room 16 (IN THE DINING ROOM)
rule_48F4:
        .byte 16, ANY, ANY, rule_4900-rule_48F4, 1, 2
        .byte C_OBJ_IN_ROOM, 20, 16     ; if object 20 (FIRE) is in room 16 (IN THE DINING ROOM)
        .byte A_MESSAGE, 46     ; say msg 46 "THE FIRE IS OUT OF CONTROL.  YOU ARE DEAD"
        .byte A_GAME_OVER     ; ask to play again

; room 16 (IN THE DINING ROOM), OPEN, DOOR
rule_4900:
        .byte 16, V_OPEN, N_DOOR, rule_490D-rule_4900, 1, 2
        .byte C_VIEW_IS, 28     ; if current picture == 28
        .byte A_SET_BASE_VIEW, 29     ; make picture 29 the room view
        .byte A_SET_ROOM_VIEW, 17, 16     ; set room 17 (IN THE FENCED BACK YARD) view to picture 16

; room 16 (IN THE DINING ROOM), OPEN, DOOR
rule_490D:
        .byte 16, V_OPEN, N_DOOR, rule_4917-rule_490D, 1, 1
        .byte C_VIEW_IS, 29     ; if current picture == 29
        .byte A_MESSAGE, 129     ; say msg 129 "IT IS OPEN"

; room 16 (IN THE DINING ROOM), CLOSE, DOOR
rule_4917:
        .byte 16, V_CLOSE, N_DOOR, rule_4924-rule_4917, 1, 2
        .byte C_VIEW_IS, 29     ; if current picture == 29
        .byte A_SET_BASE_VIEW, 28     ; make picture 28 the room view
        .byte A_SET_ROOM_VIEW, 17, 15     ; set room 17 (IN THE FENCED BACK YARD) view to picture 15

; room 16 (IN THE DINING ROOM), CLOSE, DOOR
rule_4924:
        .byte 16, V_CLOSE, N_DOOR, rule_492E-rule_4924, 1, 1
        .byte C_VIEW_IS, 28     ; if current picture == 28
        .byte A_MESSAGE, 128     ; say msg 128 "THE DOOR IS CLOSED"

; room 16 (IN THE DINING ROOM), GO, DOOR
rule_492E:
        .byte 16, V_GO, N_DOOR, rule_4936-rule_492E, 0, 1
        .byte A_MESSAGE, 48     ; say msg 48 "WHICH DIRECTION?"

; room 16 (IN THE DINING ROOM), NORTH, 
rule_4936:
        .byte 16, V_N, N_NONE, rule_493E-rule_4936, 0, 1
        .byte A_GOTO_ROOM, 3     ; go to room 3 (IN AN ENTRY HALL)

; room 16 (IN THE DINING ROOM), SOUTH, 
rule_493E:
        .byte 16, V_S, N_NONE, rule_4948-rule_493E, 1, 1
        .byte C_VIEW_IS, 29     ; if current picture == 29
        .byte A_GOTO_ROOM, 17     ; go to room 17 (IN THE FENCED BACK YARD)

; room 16 (IN THE DINING ROOM), SOUTH, 
rule_4948:
        .byte 16, V_S, N_NONE, rule_4952-rule_4948, 1, 1
        .byte C_VIEW_IS, 28     ; if current picture == 28
        .byte A_MESSAGE, 128     ; say msg 128 "THE DOOR IS CLOSED"

; room 16 (IN THE DINING ROOM), GET, RUG
rule_4952:
        .byte 16, V_GET, N_RUG, rule_495A-rule_4952, 0, 1
        .byte A_MESSAGE, 4     ; say msg 4 "IT IS TOO HEAVY"

; room 16 (IN THE DINING ROOM), GET, TABLE
rule_495A:
        .byte 16, V_GET, N_TABLE, rule_4962-rule_495A, 0, 1
        .byte A_MESSAGE, 4     ; say msg 4 "IT IS TOO HEAVY"

; room 16 (IN THE DINING ROOM), LIGHT, LAMP
rule_4962:
        .byte 16, V_LIGHT, N_LAMP, rule_496A-rule_4962, 0, 1
        .byte A_MESSAGE, 47     ; say msg 47 "THERE IS NO WICK"

; room 16 (IN THE DINING ROOM), GET, LAMP
rule_496A:
        .byte 16, V_GET, N_LAMP, rule_4972-rule_496A, 0, 1
        .byte A_MESSAGE, 24     ; say msg 24 "IT IS FASTENED DOWN"

; room 16 (IN THE DINING ROOM), LOOK, HOLE
rule_4972:
        .byte 16, V_LOOK, N_HOLE, rule_497A-rule_4972, 0, 1
        .byte A_SET_VIEW, 49     ; show picture 49

; room 17 (IN THE FENCED BACK YARD), OPEN, GATE
rule_497A:
        .byte 17, V_OPEN, N_GATE, rule_4984-rule_497A, 1, 1
        .byte C_VIEW_IS, 16     ; if current picture == 16
        .byte A_SET_BASE_VIEW, 17     ; make picture 17 the room view

; room 17 (IN THE FENCED BACK YARD), OPEN, GATE
rule_4984:
        .byte 17, V_OPEN, N_GATE, rule_498C-rule_4984, 0, 1
        .byte A_SET_BASE_VIEW, 18     ; make picture 18 the room view

; room 17 (IN THE FENCED BACK YARD), OPEN, DOOR
rule_498C:
        .byte 17, V_OPEN, N_DOOR, rule_4999-rule_498C, 1, 2
        .byte C_VIEW_IS, 18     ; if current picture == 18
        .byte A_SET_BASE_VIEW, 17     ; make picture 17 the room view
        .byte A_SET_ROOM_VIEW, 16, 29     ; set room 16 (IN THE DINING ROOM) view to picture 29

; room 17 (IN THE FENCED BACK YARD), OPEN, DOOR
rule_4999:
        .byte 17, V_OPEN, N_DOOR, rule_49A4-rule_4999, 0, 2
        .byte A_SET_BASE_VIEW, 16     ; make picture 16 the room view
        .byte A_SET_ROOM_VIEW, 16, 29     ; set room 16 (IN THE DINING ROOM) view to picture 29

; room 17 (IN THE FENCED BACK YARD), CLOSE, GATE
rule_49A4:
        .byte 17, V_CLOSE, N_GATE, rule_49AE-rule_49A4, 1, 1
        .byte C_VIEW_IS, 17     ; if current picture == 17
        .byte A_SET_BASE_VIEW, 16     ; make picture 16 the room view

; room 17 (IN THE FENCED BACK YARD), CLOSE, GATE
rule_49AE:
        .byte 17, V_CLOSE, N_GATE, rule_49B6-rule_49AE, 0, 1
        .byte A_SET_BASE_VIEW, 15     ; make picture 15 the room view

; room 17 (IN THE FENCED BACK YARD), CLOSE, DOOR
rule_49B6:
        .byte 17, V_CLOSE, N_DOOR, rule_49C3-rule_49B6, 1, 2
        .byte C_VIEW_IS, 17     ; if current picture == 17
        .byte A_SET_BASE_VIEW, 18     ; make picture 18 the room view
        .byte A_SET_ROOM_VIEW, 16, 28     ; set room 16 (IN THE DINING ROOM) view to picture 28

; room 17 (IN THE FENCED BACK YARD), CLOSE, DOOR
rule_49C3:
        .byte 17, V_CLOSE, N_DOOR, rule_49CE-rule_49C3, 0, 2
        .byte A_SET_BASE_VIEW, 15     ; make picture 15 the room view
        .byte A_SET_ROOM_VIEW, 16, 28     ; set room 16 (IN THE DINING ROOM) view to picture 28

; room 17 (IN THE FENCED BACK YARD), GO, DOOR
rule_49CE:
        .byte 17, V_GO, N_DOOR, rule_49D8-rule_49CE, 1, 1
        .byte C_VIEW_IS, 16     ; if current picture == 16
        .byte A_GOTO_ROOM, 16     ; go to room 16 (IN THE DINING ROOM)

; room 17 (IN THE FENCED BACK YARD), GO, DOOR
rule_49D8:
        .byte 17, V_GO, N_DOOR, rule_49E2-rule_49D8, 1, 1
        .byte C_VIEW_IS, 17     ; if current picture == 17
        .byte A_GOTO_ROOM, 16     ; go to room 16 (IN THE DINING ROOM)

; room 17 (IN THE FENCED BACK YARD), GO, DOOR
rule_49E2:
        .byte 17, V_GO, N_DOOR, rule_49EC-rule_49E2, 1, 1
        .byte C_VIEW_IS, 15     ; if current picture == 15
        .byte A_MESSAGE, 128     ; say msg 128 "THE DOOR IS CLOSED"

; room 17 (IN THE FENCED BACK YARD), GO, DOOR
rule_49EC:
        .byte 17, V_GO, N_DOOR, rule_49F6-rule_49EC, 1, 1
        .byte C_VIEW_IS, 18     ; if current picture == 18
        .byte A_MESSAGE, 128     ; say msg 128 "THE DOOR IS CLOSED"

; room 17 (IN THE FENCED BACK YARD), GO, GATE
rule_49F6:
        .byte 17, V_GO, N_GATE, rule_4A00-rule_49F6, 1, 1
        .byte C_VIEW_IS, 18     ; if current picture == 18
        .byte A_GOTO_ROOM, 18     ; go to room 18 (IN A SMALL FENCED CEMETARY)

; room 17 (IN THE FENCED BACK YARD), GO, GATE
rule_4A00:
        .byte 17, V_GO, N_GATE, rule_4A0A-rule_4A00, 1, 1
        .byte C_VIEW_IS, 17     ; if current picture == 17
        .byte A_GOTO_ROOM, 18     ; go to room 18 (IN A SMALL FENCED CEMETARY)

; room 17 (IN THE FENCED BACK YARD), GO, GATE
rule_4A0A:
        .byte 17, V_GO, N_GATE, rule_4A14-rule_4A0A, 1, 1
        .byte C_VIEW_IS, 15     ; if current picture == 15
        .byte A_MESSAGE, 133     ; say msg 133 "IT IS NOT OPEN"

; room 17 (IN THE FENCED BACK YARD), GO, GATE
rule_4A14:
        .byte 17, V_GO, N_GATE, rule_4A1E-rule_4A14, 1, 1
        .byte C_VIEW_IS, 16     ; if current picture == 16
        .byte A_MESSAGE, 133     ; say msg 133 "IT IS NOT OPEN"

; room 17 (IN THE FENCED BACK YARD), UP, FENCE
rule_4A1E:
        .byte 17, V_U, N_FENCE, rule_4A26-rule_4A1E, 0, 1
        .byte A_MESSAGE, 1     ; say msg 1 "IT IS TOO HIGH"

; room 17 (IN THE FENCED BACK YARD), JUMP, FENCE
rule_4A26:
        .byte 17, V_JUMP, N_FENCE, rule_4A2E-rule_4A26, 0, 1
        .byte A_MESSAGE, 1     ; say msg 1 "IT IS TOO HIGH"

; room 17 (IN THE FENCED BACK YARD), LOOK, BODY
rule_4A2E:
        .byte 17, V_LOOK, N_BODY, rule_4A36-rule_4A2E, 0, 1
        .byte A_MESSAGE, 3     ; say msg 3 "IT IS SAM, THE MECHANIC.  HE HAS BEEN HIT IN THE HEAD BY A BLUNT OBJECT"

; room 17 (IN THE FENCED BACK YARD), GET, BODY
rule_4A36:
        .byte 17, V_GET, N_BODY, rule_4A3E-rule_4A36, 0, 1
        .byte A_MESSAGE, 4     ; say msg 4 "IT IS TOO HEAVY"

; room 18 (IN A SMALL FENCED CEMETARY), OPEN, GATE
rule_4A3E:
        .byte 18, V_OPEN, N_GATE, rule_4A48-rule_4A3E, 1, 1
        .byte C_VIEW_IS, 26     ; if current picture == 26
        .byte A_SET_BASE_VIEW, 27     ; make picture 27 the room view

; room 18 (IN A SMALL FENCED CEMETARY), OPEN, GATE
rule_4A48:
        .byte 18, V_OPEN, N_GATE, rule_4A50-rule_4A48, 0, 1
        .byte A_MESSAGE, 129     ; say msg 129 "IT IS OPEN"

; room 18 (IN A SMALL FENCED CEMETARY), CLOSE, GATE
rule_4A50:
        .byte 18, V_CLOSE, N_GATE, rule_4A5A-rule_4A50, 1, 1
        .byte C_VIEW_IS, 27     ; if current picture == 27
        .byte A_SET_BASE_VIEW, 26     ; make picture 26 the room view

; room 18 (IN A SMALL FENCED CEMETARY), CLOSE, GATE
rule_4A5A:
        .byte 18, V_CLOSE, N_GATE, rule_4A62-rule_4A5A, 0, 1
        .byte A_MESSAGE, 128     ; say msg 128 "THE DOOR IS CLOSED"

; room 18 (IN A SMALL FENCED CEMETARY), GO, GATE
rule_4A62:
        .byte 18, V_GO, N_GATE, rule_4A6C-rule_4A62, 1, 1
        .byte C_VIEW_IS, 27     ; if current picture == 27
        .byte A_GOTO_ROOM, 17     ; go to room 17 (IN THE FENCED BACK YARD)

; room 18 (IN A SMALL FENCED CEMETARY), GO, GATE
rule_4A6C:
        .byte 18, V_GO, N_GATE, rule_4A74-rule_4A6C, 0, 1
        .byte A_MESSAGE, 128     ; say msg 128 "THE DOOR IS CLOSED"

; room 18 (IN A SMALL FENCED CEMETARY), UP, FENCE
rule_4A74:
        .byte 18, V_U, N_FENCE, rule_4A7C-rule_4A74, 0, 1
        .byte A_MESSAGE, 1     ; say msg 1 "IT IS TOO HIGH"

; room 18 (IN A SMALL FENCED CEMETARY), JUMP, FENCE
rule_4A7C:
        .byte 18, V_JUMP, N_FENCE, rule_4A84-rule_4A7C, 0, 1
        .byte A_MESSAGE, 1     ; say msg 1 "IT IS TOO HIGH"

; room 18 (IN A SMALL FENCED CEMETARY), GET, GRAVESTO
rule_4A84:
        .byte 18, V_GET, N_GRAVESTO, rule_4A8C-rule_4A84, 0, 1
        .byte A_MESSAGE, 4     ; say msg 4 "IT IS TOO HEAVY"

; room 18 (IN A SMALL FENCED CEMETARY), LOOK, GRAVESTO
rule_4A8C:
        .byte 18, V_LOOK, N_GRAVESTO, rule_4A94-rule_4A8C, 0, 1
        .byte A_MESSAGE, 31     ; say msg 31 "THE WRITING IS WORN DOWN"

; room 18 (IN A SMALL FENCED CEMETARY), READ, GRAVESTO
rule_4A94:
        .byte 18, V_READ, N_GRAVESTO, rule_4A9C-rule_4A94, 0, 1
        .byte A_MESSAGE, 31     ; say msg 31 "THE WRITING IS WORN DOWN"

; room 18 (IN A SMALL FENCED CEMETARY), LOOK, PERSON
rule_4A9C:
        .byte 18, V_LOOK, N_PERSON, rule_4AA4-rule_4A9C, 0, 1
        .byte A_MESSAGE, 32     ; say msg 32 "IT IS JOE, THE GRAVEDIGGER.  HE HAS JUST FINISHED DIGGING THE SIX GRAVES"

; room 18 (IN A SMALL FENCED CEMETARY), LOOK, JOE
rule_4AA4:
        .byte 18, V_LOOK, N_JOE, rule_4AAC-rule_4AA4, 0, 1
        .byte A_MESSAGE, 32     ; say msg 32 "IT IS JOE, THE GRAVEDIGGER.  HE HAS JUST FINISHED DIGGING THE SIX GRAVES"

; room 18 (IN A SMALL FENCED CEMETARY), TALK, JOE
rule_4AAC:
        .byte 18, V_TALK, N_JOE, rule_4AB4-rule_4AAC, 0, 1
        .byte A_MESSAGE, 33     ; say msg 33 "HE DOESN'T TALK MUCH"

; room 18 (IN A SMALL FENCED CEMETARY), TALK, PERSON
rule_4AB4:
        .byte 18, V_TALK, N_PERSON, rule_4ABC-rule_4AB4, 0, 1
        .byte A_MESSAGE, 33     ; say msg 33 "HE DOESN'T TALK MUCH"

; room 18 (IN A SMALL FENCED CEMETARY), KILL, PERSON
rule_4ABC:
        .byte 18, V_KILL, N_PERSON, rule_4AC4-rule_4ABC, 0, 1
        .byte A_MESSAGE, 34     ; say msg 34 "WITH WHAT?"

; room 18 (IN A SMALL FENCED CEMETARY), KILL, JOE
rule_4AC4:
        .byte 18, V_KILL, N_JOE, rule_4ACC-rule_4AC4, 0, 1
        .byte A_MESSAGE, 34     ; say msg 34 "WITH WHAT?"

; room 18 (IN A SMALL FENCED CEMETARY), WITH, DAGGER
rule_4ACC:
        .byte 18, V_WITH, N_DAGGER, rule_4ADD-rule_4ACC, 1, 3
        .byte C_OBJ_IN_ROOM, 53, 254     ; if object 53 (DAGGER) is in inventory
        .byte A_MESSAGE, 30     ; say msg 30 "THERE IS A DEAD BODY HERE"
        .byte A_PUT_OBJ, 27, 18     ; put object 27 (X'S) in room 18 (IN A SMALL FENCED CEMETARY)
        .byte A_SET_SWITCH, SW_JOE_DEAD, 1     ; SW_JOE_DEAD = 1

; room 18 (IN A SMALL FENCED CEMETARY), WITH, DAGGER
rule_4ADD:
.ifdef BUGFIX
        .byte 18, V_WITH, N_DAGGER, rule_4AE8-rule_4ADD, 0, 1
        .byte A_MESSAGE, 132     ; say msg 132 "YOU ARE NOT CARRYING IT"
.else
        .byte 18, V_WITH, N_DAGGER, rule_4AE8-rule_4ADD, 0, 2
        .byte A_MESSAGE, 132     ; say msg 132 "YOU ARE NOT CARRYING IT"
        .byte A_PUT_OBJ, 26, 253     ; put object 26 (DOTS) in nowhere (bug: Joe loses his eyes)
.endif

; room 18 (IN A SMALL FENCED CEMETARY), WITH, GUN
rule_4AE8:
        .byte 18, V_WITH, N_GUN, rule_4B01-rule_4AE8, 2, 5
        .byte C_OBJ_IN_ROOM, 45, 254     ; if object 45 (GUN) is in inventory
        .byte C_SWITCH_EQ, SW_GUN_FIRED, 0     ; if SW_GUN_FIRED == 0
        .byte A_MESSAGE, 30     ; say msg 30 "THERE IS A DEAD BODY HERE"
        .byte A_MESSAGE, 35     ; say msg 35 "YOUR GUN IS EMPTY"
        .byte A_PUT_OBJ, 27, 18     ; put object 27 (X'S) in room 18 (IN A SMALL FENCED CEMETARY)
        .byte A_SET_SWITCH, SW_GUN_FIRED, 1     ; SW_GUN_FIRED = 1
        .byte A_SET_SWITCH, SW_JOE_DEAD, 1     ; SW_JOE_DEAD = 1

; room 18 (IN A SMALL FENCED CEMETARY), LOOK, BODY
rule_4B01:
        .byte 18, V_LOOK, N_BODY, rule_4B09-rule_4B01, 0, 1
        .byte A_MESSAGE, 36     ; say msg 36 "IT IS JOE, THE GRAVEDIGGER"

; room 18 (IN A SMALL FENCED CEMETARY), GET, BODY
rule_4B09:
        .byte 18, V_GET, N_BODY, rule_4B11-rule_4B09, 0, 1
        .byte A_MESSAGE, 4     ; say msg 4 "IT IS TOO HEAVY"

; room 18 (IN A SMALL FENCED CEMETARY), GET, PERSON
rule_4B11:
        .byte 18, V_GET, N_PERSON, rule_4B19-rule_4B11, 0, 1
        .byte A_MESSAGE, 37     ; say msg 37 "I DONT UNDERSTAND WHAT YOU MEAN"

; room 18 (IN A SMALL FENCED CEMETARY), GET, JOE
rule_4B19:
        .byte 18, V_GET, N_JOE, rule_4B21-rule_4B19, 0, 1
        .byte A_MESSAGE, 37     ; say msg 37 "I DONT UNDERSTAND WHAT YOU MEAN"

; room 18 (IN A SMALL FENCED CEMETARY), GO, GRAVES
rule_4B21:
        .byte 18, V_GO, N_GRAVES, rule_4B30-rule_4B21, 1, 3
        .byte C_SWITCH_EQ, SW_JOE_DEAD, 0     ; if SW_JOE_DEAD == 0
        .byte A_MESSAGE, 38     ; say msg 38 "YOU FALL IN ONE AND JOE BURIES YOU.  YOU ARE DEAD"
        .byte A_PUT_OBJ, 24, 18     ; put object 24 (GRAVES) in room 18 (IN A SMALL FENCED CEMETARY)
        .byte A_GAME_OVER     ; ask to play again

; room 18 (IN A SMALL FENCED CEMETARY), GO, GRAVES
rule_4B30:
        .byte 18, V_GO, N_GRAVES, rule_4B38-rule_4B30, 0, 1
        .byte A_MESSAGE, 39     ; say msg 39 "YOU FALL IN ONE AND CLIMB OUT AGAIN"

; room 18 (IN A SMALL FENCED CEMETARY), GET, SHOVEL
rule_4B38:
        .byte 18, V_GET, N_SHOVEL, rule_4B43-rule_4B38, 1, 1
        .byte C_SWITCH_EQ, SW_JOE_DEAD, 0     ; if SW_JOE_DEAD == 0
        .byte A_MESSAGE, 40     ; say msg 40 "JOE WON'T LET YOU"

; room 18 (IN A SMALL FENCED CEMETARY), GET, SHOVEL
rule_4B43:
        .byte 18, V_GET, N_SHOVEL, rule_4B4C-rule_4B43, 0, 1
        .byte A_PUT_OBJ, 28, 254     ; put object 28 (SHOVEL) in inventory

; room 19 (IN A SMALL PANTRY), UP, STAIRS
rule_4B4C:
        .byte 19, V_U, N_STAIRS, rule_4B54-rule_4B4C, 0, 1
        .byte A_GOTO_ROOM, 20     ; go to room 20 (AT THE NORTH END OF A NARROW NORTH/SO...)

; room 19 (IN A SMALL PANTRY), GO, STAIRS
rule_4B54:
        .byte 19, V_GO, N_STAIRS, rule_4B5C-rule_4B54, 0, 1
        .byte A_GOTO_ROOM, 20     ; go to room 20 (AT THE NORTH END OF A NARROW NORTH/SO...)

; room 19 (IN A SMALL PANTRY), GO, HOLE
rule_4B5C:
        .byte 19, V_GO, N_HOLE, rule_4B67-rule_4B5C, 1, 1
        .byte C_OBJ_IN_ROOM, 12, 4     ; if object 12 (HOLE) is in room 4 (IN THE KITCHEN)
        .byte A_GOTO_ROOM, 4     ; go to room 4 (IN THE KITCHEN)

; room 19 (IN A SMALL PANTRY), GO, HOLE
rule_4B67:
        .byte 19, V_GO, N_HOLE, rule_4B6F-rule_4B67, 0, 1
        .byte A_MESSAGE, 156     ; say msg 156 "YOU GO IN THE HOLE BUT CANNOT CONTINUE AND HAVE TO RETURN."

; room 19 (IN A SMALL PANTRY), GET, FOOD
rule_4B6F:
        .byte 19, V_GET, N_FOOD, rule_4B77-rule_4B6F, 0, 1
        .byte A_MESSAGE, 27     ; say msg 27 "IT DOES NOT REMOVE"

; room 19 (IN A SMALL PANTRY), GET, JARS
rule_4B77:
        .byte 19, V_GET, N_JARS, rule_4B7F-rule_4B77, 0, 1
        .byte A_MESSAGE, 27     ; say msg 27 "IT DOES NOT REMOVE"

; room 19 (IN A SMALL PANTRY), GET, BOXES
rule_4B7F:
        .byte 19, V_GET, N_BOXES, rule_4B87-rule_4B7F, 0, 1
        .byte A_MESSAGE, 27     ; say msg 27 "IT DOES NOT REMOVE"

; room 20 (AT THE NORTH END OF A NARROW NORTH/SO...), UP, STAIRS
rule_4B87:
        .byte 20, V_U, N_STAIRS, rule_4B8F-rule_4B87, 0, 1
        .byte A_GOTO_ROOM, 19     ; go to room 19 (IN A SMALL PANTRY)

; room 20 (AT THE NORTH END OF A NARROW NORTH/SO...), GO, STAIRS
rule_4B8F:
        .byte 20, V_GO, N_STAIRS, rule_4B97-rule_4B8F, 0, 1
        .byte A_GOTO_ROOM, 19     ; go to room 19 (IN A SMALL PANTRY)

; room 21 (IN A MOIST BASEMENT), GO, HOLE
rule_4B97:
        .byte 21, V_GO, N_HOLE, rule_4B9F-rule_4B97, 0, 1
        .byte A_GOTO_ROOM, 22     ; go to room 22 (AT THE SOUTH END OF A NORTH/SOUTH TUNNEL)

; room 21 (IN A MOIST BASEMENT), UP, STAIRS
rule_4B9F:
        .byte 21, V_U, N_STAIRS, rule_4BA7-rule_4B9F, 0, 1
        .byte A_GOTO_ROOM, 37     ; go to room 37 (ON A STAIRWAY)

; room 21 (IN A MOIST BASEMENT), GO, STAIRS
rule_4BA7:
        .byte 21, V_GO, N_STAIRS, rule_4BAF-rule_4BA7, 0, 1
        .byte A_GOTO_ROOM, 37     ; go to room 37 (ON A STAIRWAY)

; room 21 (IN A MOIST BASEMENT), GO, DOOR
rule_4BAF:
        .byte 21, V_GO, N_DOOR, rule_4BB7-rule_4BAF, 0, 1
        .byte A_GOTO_ROOM, 20     ; go to room 20 (AT THE NORTH END OF A NARROW NORTH/SO...)

; room 21 (IN A MOIST BASEMENT), BREAK, WALL
rule_4BB7:
        .byte 21, V_BREAK, N_WALL, rule_4BBF-rule_4BB7, 0, 1
        .byte A_MESSAGE, 50     ; say msg 50 "IT IS TOO HARD"

; room 21 (IN A MOIST BASEMENT), GET, TABLE
rule_4BBF:
        .byte 21, V_GET, N_TABLE, rule_4BC7-rule_4BBF, 0, 1
        .byte A_MESSAGE, 4     ; say msg 4 "IT IS TOO HEAVY"

; room 21 (IN A MOIST BASEMENT), GET, ALGAE
rule_4BC7:
        .byte 21, V_GET, N_ALGAE, rule_4BCF-rule_4BC7, 0, 1
        .byte A_MESSAGE, 37     ; say msg 37 "I DONT UNDERSTAND WHAT YOU MEAN"

; room 21 (IN A MOIST BASEMENT), WIPE, ALGAE
rule_4BCF:
        .byte 21, V_WIPE, N_ALGAE, rule_4BE0-rule_4BCF, 2, 2
        .byte C_OBJ_IN_ROOM, 39, 254     ; if object 39 (TOWEL) is in inventory
        .byte C_OBJ_IN_ROOM, 31, 253     ; if object 31 (BRICKS) is in nowhere
        .byte A_MESSAGE, 52     ; say msg 52 "THE WALL IS EXPOSED.  THERE IS A LOOSE BRICK"
        .byte A_PUT_OBJ, 31, 21     ; put object 31 (BRICKS) in room 21 (IN A MOIST BASEMENT)

; room 21 (IN A MOIST BASEMENT), WIPE, ALGAE
rule_4BE0:
        .byte 21, V_WIPE, N_ALGAE, rule_4BEB-rule_4BE0, 1, 1
        .byte C_OBJ_IN_ROOM, 39, 254     ; if object 39 (TOWEL) is in inventory
        .byte A_MESSAGE, 2     ; say msg 2 "OK"

; room 21 (IN A MOIST BASEMENT), WIPE, ALGAE
rule_4BEB:
        .byte 21, V_WIPE, N_ALGAE, rule_4BF3-rule_4BEB, 0, 1
        .byte A_MESSAGE, 51     ; say msg 51 "YOU HAVE NOTHING TO WIPE IT WITH"

; room 21 (IN A MOIST BASEMENT), GET, BRICKS
rule_4BF3:
        .byte 21, V_GET, N_BRICKS, rule_4C02-rule_4BF3, 1, 3
        .byte C_OBJ_IN_ROOM, 31, 21     ; if object 31 (BRICKS) is in room 21 (IN A MOIST BASEMENT)
        .byte A_MESSAGE, 53     ; say msg 53 "YOU HAVE FOUND THE JEWELS!"
        .byte A_GET     ; take the named object
        .byte A_PUT_OBJ, 32, 21     ; put object 32 (JEWELS) in room 21 (IN A MOIST BASEMENT)

; room 21 (IN A MOIST BASEMENT), LOOK, BODY
rule_4C02:
        .byte 21, V_LOOK, N_BODY, rule_4C0A-rule_4C02, 0, 1
        .byte A_MESSAGE, 54     ; say msg 54 "IT IS TOM, THE PLUMBER.  HE SEEMS TO HAVE BEEN STABBED.  THERE IS A DAISY IN HIS HAND"

; room 21 (IN A MOIST BASEMENT), GET, BODY
rule_4C0A:
        .byte 21, V_GET, N_BODY, rule_4C12-rule_4C0A, 0, 1
        .byte A_MESSAGE, 4     ; say msg 4 "IT IS TOO HEAVY"

; room 21 (IN A MOIST BASEMENT), GET, DAISY
rule_4C12:
        .byte 21, V_GET, N_DAISY, rule_4C1A-rule_4C12, 0, 1
        .byte A_MESSAGE, 37     ; say msg 37 "I DONT UNDERSTAND WHAT YOU MEAN"

; room 21 (IN A MOIST BASEMENT), LOOK, TABLE
rule_4C1A:
        .byte 21, V_LOOK, N_TABLE, rule_4C22-rule_4C1A, 0, 1
        .byte A_MESSAGE, 55     ; say msg 55 "THERE IS A SKELETON KEY HERE"

; room 21 (IN A MOIST BASEMENT), LOOK, BRICKS
rule_4C22:
        .byte 21, V_LOOK, N_BRICKS, rule_4C2A-rule_4C22, 0, 1
        .byte A_MESSAGE, 56     ; say msg 56 "IT IS LOOSE"

; room 21 (IN A MOIST BASEMENT), LOOK, JEWELS
rule_4C2A:
        .byte 21, V_LOOK, N_JEWELS, rule_4C32-rule_4C2A, 0, 1
        .byte A_MESSAGE, 57     ; say msg 57 "THEY ARE JEWELS, ALL RIGHT!"

; room 22 (AT THE SOUTH END OF A NORTH/SOUTH TUNNEL), GO, HOLE
rule_4C32:
        .byte 22, V_GO, N_HOLE, rule_4C3A-rule_4C32, 0, 1
        .byte A_GOTO_ROOM, 21     ; go to room 21 (IN A MOIST BASEMENT)

; room 22 (AT THE SOUTH END OF A NORTH/SOUTH TUNNEL), LOOK, TUNNEL
rule_4C3A:
        .byte 22, V_LOOK, N_TUNNEL, rule_4C42-rule_4C3A, 0, 1
        .byte A_MESSAGE, 59     ; say msg 59 "IT IS VERY LONG"

; room 23 (AT THE TOP OF A VERY TALL PINE TREE), UP, TREE
rule_4C42:
        .byte 23, V_U, N_TREE, rule_4C4A-rule_4C42, 0, 1
        .byte A_GOTO_ROOM, 13     ; go to room 13 (THERE IS A VERY TALL PINE TREE IN FRO...)

; room 23 (AT THE TOP OF A VERY TALL PINE TREE), LOOK, TELESCOP
rule_4C4A:
        .byte 23, V_LOOK, N_TELESCOP, rule_4C57-rule_4C4A, 0, 3
        .byte A_SET_VIEW, 22     ; show picture 22
        .byte A_MESSAGE, 22     ; say msg 22 "YOU ARE LOOKING THROUGH THE ATTIC WINDOW.  YOU SEE A TRAPDOOR IN THE ATTIC CEILING"
        .byte A_PUT_OBJ, 40, 39     ; put object 40 (TRAPDOOR) in room 39 (IN THE ATTIC)

; room 23 (AT THE TOP OF A VERY TALL PINE TREE), GO, HOUSE
rule_4C57:
        .byte 23, V_GO, N_HOUSE, rule_4C5F-rule_4C57, 0, 1
        .byte A_MESSAGE, 23     ; say msg 23 "YOU HAD BETTER CLIMB DOWN FIRST"

; room 23 (AT THE TOP OF A VERY TALL PINE TREE), GET, TELESCOP
rule_4C5F:
        .byte 23, V_GET, N_TELESCOP, rule_4C67-rule_4C5F, 0, 1
        .byte A_MESSAGE, 24     ; say msg 24 "IT IS FASTENED DOWN"

; room 24 (AT THE JUNCTION OF AN EAST/WEST HALLW...), GO, STAIRS
rule_4C67:
        .byte 24, V_GO, N_STAIRS, rule_4C6F-rule_4C67, 0, 1
        .byte A_GOTO_ROOM, 3     ; go to room 3 (IN AN ENTRY HALL)

; room 24 (AT THE JUNCTION OF AN EAST/WEST HALLW...), GO, HALL
rule_4C6F:
        .byte 24, V_GO, N_HALL, rule_4C77-rule_4C6F, 0, 1
        .byte A_MESSAGE, 48     ; say msg 48 "WHICH DIRECTION?"

; room 24 (AT THE JUNCTION OF AN EAST/WEST HALLW...), GO, DOOR
rule_4C77:
        .byte 24, V_GO, N_DOOR, rule_4C7F-rule_4C77, 0, 1
        .byte A_MESSAGE, 61     ; say msg 61 "WHERE?"

; room 24 (AT THE JUNCTION OF AN EAST/WEST HALLW...), LOOK, DOOR
rule_4C7F:
        .byte 24, V_LOOK, N_DOOR, rule_4C87-rule_4C7F, 0, 1
        .byte A_MESSAGE, 61     ; say msg 61 "WHERE?"

; room 24 (AT THE JUNCTION OF AN EAST/WEST HALLW...), LOOK, HALL
rule_4C87:
        .byte 24, V_LOOK, N_HALL, rule_4C8F-rule_4C87, 0, 1
        .byte A_MESSAGE, 48     ; say msg 48 "WHICH DIRECTION?"

; room 25 (THERE IS A DOORWAY HERE), GO, DOOR
rule_4C8F:
        .byte 25, V_GO, N_DOOR, rule_4C9C-rule_4C8F, 1, 2
        .byte C_OBJ_IN_ROOM, 54, 26     ; if object 54 (LINE) is in room 26 (IN A LARGE BEDROOM)
        .byte A_MESSAGE, 69     ; say msg 69 "A DAGGER IS THROWN AT YOU FROM OUTSIDE THE ROOM.  IT MISSES!"
        .byte A_GOTO_ROOM, 26     ; go to room 26 (IN A LARGE BEDROOM)

; room 25 (THERE IS A DOORWAY HERE), GO, DOOR
rule_4C9C:
        .byte 25, V_GO, N_DOOR, rule_4CA4-rule_4C9C, 0, 1
        .byte A_GOTO_ROOM, 26     ; go to room 26 (IN A LARGE BEDROOM)

; room 26 (IN A LARGE BEDROOM), GO, DOOR
rule_4CA4:
        .byte 26, V_GO, N_DOOR, rule_4CAF-rule_4CA4, 0, 2
        .byte A_GOTO_ROOM, 25     ; go to room 25 (THERE IS A DOORWAY HERE)
        .byte A_PUT_OBJ, 54, 253     ; put object 54 (LINE) in nowhere

; room 26 (IN A LARGE BEDROOM), GET, DAGGER
rule_4CAF:
        .byte 26, V_GET, N_DAGGER, rule_4CB9-rule_4CAF, 0, 2
        .byte A_PUT_OBJ, 54, 253     ; put object 54 (LINE) in nowhere
        .byte A_GET     ; take the named object

; room 26 (IN A LARGE BEDROOM), GET, BED
rule_4CB9:
        .byte 26, V_GET, N_BED, rule_4CC1-rule_4CB9, 0, 1
        .byte A_MESSAGE, 4     ; say msg 4 "IT IS TOO HEAVY"

; room 26 (IN A LARGE BEDROOM), GET, TRUNK
rule_4CC1:
        .byte 26, V_GET, N_TRUNK, rule_4CC9-rule_4CC1, 0, 1
        .byte A_MESSAGE, 4     ; say msg 4 "IT IS TOO HEAVY"

; room 27 (THERE IS A DOORWAY HERE), GO, DOOR
rule_4CC9:
        .byte 27, V_GO, N_DOOR, rule_4CD1-rule_4CC9, 0, 1
        .byte A_GOTO_ROOM, 28     ; go to room 28 (IN A SMALL BEDROOM)

; room 28 (IN A SMALL BEDROOM), GO, DOOR
rule_4CD1:
        .byte 28, V_GO, N_DOOR, rule_4CD9-rule_4CD1, 0, 1
        .byte A_GOTO_ROOM, 27     ; go to room 27 (THERE IS A DOORWAY HERE)

; room 28 (IN A SMALL BEDROOM), LOOK, BODY
rule_4CD9:
        .byte 28, V_LOOK, N_BODY, rule_4CE1-rule_4CD9, 0, 1
        .byte A_MESSAGE, 71     ; say msg 71 "IT IS SALLY, THE SEAMSTRESS.  SHE HAS A LARGE LUMP ON HER HEAD.  THERE IS A BLOND HAIR ON HER DRESS"

; room 28 (IN A SMALL BEDROOM), GET, BODY
rule_4CE1:
        .byte 28, V_GET, N_BODY, rule_4CE9-rule_4CE1, 0, 1
        .byte A_MESSAGE, 4     ; say msg 4 "IT IS TOO HEAVY"

; room 28 (IN A SMALL BEDROOM), GET, BED
rule_4CE9:
        .byte 28, V_GET, N_BED, rule_4CF1-rule_4CE9, 0, 1
        .byte A_MESSAGE, 4     ; say msg 4 "IT IS TOO HEAVY"

; room 29 (THERE IS A DOORWAY HERE), GO, DOOR
rule_4CF1:
        .byte 29, V_GO, N_DOOR, rule_4CF9-rule_4CF1, 0, 1
        .byte A_GOTO_ROOM, 30     ; go to room 30 (IN AN OLD NURSERY)

; room 30 (IN AN OLD NURSERY), GO, DOOR
rule_4CF9:
        .byte 30, V_GO, N_DOOR, rule_4D01-rule_4CF9, 0, 1
        .byte A_GOTO_ROOM, 29     ; go to room 29 (THERE IS A DOORWAY HERE)

; room 30 (IN AN OLD NURSERY), LOOK, BODY
rule_4D01:
        .byte 30, V_LOOK, N_BODY, rule_4D09-rule_4D01, 0, 1
        .byte A_MESSAGE, 67     ; say msg 67 "IT IS DR. GREEN.  IT APPEARS HE HAS BEEN STABBED"

; room 30 (IN AN OLD NURSERY), GET, BODY
rule_4D09:
        .byte 30, V_GET, N_BODY, rule_4D11-rule_4D09, 0, 1
        .byte A_MESSAGE, 4     ; say msg 4 "IT IS TOO HEAVY"

; room 30 (IN AN OLD NURSERY), GET, CHAIR
rule_4D11:
        .byte 30, V_GET, N_CHAIR, rule_4D19-rule_4D11, 0, 1
        .byte A_MESSAGE, 4     ; say msg 4 "IT IS TOO HEAVY"

; room 30 (IN AN OLD NURSERY), GET, TRUNK
rule_4D19:
        .byte 30, V_GET, N_TRUNK, rule_4D21-rule_4D19, 0, 1
        .byte A_MESSAGE, 4     ; say msg 4 "IT IS TOO HEAVY"

; room 30 (IN AN OLD NURSERY), GET, CRADLE
rule_4D21:
        .byte 30, V_GET, N_CRADLE, rule_4D29-rule_4D21, 0, 1
        .byte A_MESSAGE, 4     ; say msg 4 "IT IS TOO HEAVY"

; room 31 (THERE IS A DOORWAY HERE), GO, DOOR
rule_4D29:
        .byte 31, V_GO, N_DOOR, rule_4D31-rule_4D29, 0, 1
        .byte A_GOTO_ROOM, 32     ; go to room 32 (IN A BOYS BEDROOM)

; room 32 (IN A BOYS BEDROOM), GO, DOOR
rule_4D31:
        .byte 32, V_GO, N_DOOR, rule_4D39-rule_4D31, 0, 1
        .byte A_GOTO_ROOM, 31     ; go to room 31 (THERE IS A DOORWAY HERE)

; room 32 (IN A BOYS BEDROOM), GET, BED
rule_4D39:
        .byte 32, V_GET, N_BED, rule_4D41-rule_4D39, 0, 1
        .byte A_MESSAGE, 4     ; say msg 4 "IT IS TOO HEAVY"

; room 32 (IN A BOYS BEDROOM), GET, TRUNK
rule_4D41:
        .byte 32, V_GET, N_TRUNK, rule_4D49-rule_4D41, 0, 1
        .byte A_MESSAGE, 4     ; say msg 4 "IT IS TOO HEAVY"

; room 33 (AT A STAIRWAY), UP, STAIRS
rule_4D49:
        .byte 33, V_U, N_STAIRS, rule_4D51-rule_4D49, 0, 1
        .byte A_GOTO_ROOM, 39     ; go to room 39 (IN THE ATTIC)

; room 33 (AT A STAIRWAY), GO, STAIRS
rule_4D51:
        .byte 33, V_GO, N_STAIRS, rule_4D59-rule_4D51, 0, 1
        .byte A_GOTO_ROOM, 39     ; go to room 39 (IN THE ATTIC)

; room 34 (THERE IS A DOORWAY HERE), GO, DOOR
rule_4D59:
        .byte 34, V_GO, N_DOOR, rule_4D61-rule_4D59, 0, 1
        .byte A_GOTO_ROOM, 35     ; go to room 35 (IN THE STUDY)

; room 35 (IN THE STUDY), GO, DOOR
rule_4D61:
        .byte 35, V_GO, N_DOOR, rule_4D69-rule_4D61, 0, 1
        .byte A_MESSAGE, 48     ; say msg 48 "WHICH DIRECTION?"

; room 35 (IN THE STUDY), LOOK, PICTURE
rule_4D69:
        .byte 35, V_LOOK, N_PICTURE, rule_4D71-rule_4D69, 0, 1
        .byte A_MESSAGE, 73     ; say msg 73 "ITS NICE BUT NOT EXACTLY MY CUP OF TEA. THANX FOR THE LOOK THOUGH."

; room 35 (IN THE STUDY), GET, TABLE
rule_4D71:
        .byte 35, V_GET, N_TABLE, rule_4D79-rule_4D71, 0, 1
        .byte A_MESSAGE, 4     ; say msg 4 "IT IS TOO HEAVY"

; room 35 (IN THE STUDY), GET, CHAIR
rule_4D79:
        .byte 35, V_GET, N_CHAIR, rule_4D81-rule_4D79, 0, 1
        .byte A_MESSAGE, 4     ; say msg 4 "IT IS TOO HEAVY"

; room 35 (IN THE STUDY), UNSCREW, BOLTS
rule_4D81:
        .byte 35, V_UNSCREW, N_BOLTS, rule_4D89-rule_4D81, 0, 1
        .byte A_MESSAGE, 34     ; say msg 34 "WITH WHAT?"

; room 35 (IN THE STUDY), GET, PICTURE
rule_4D89:
        .byte 35, V_GET, N_PICTURE, rule_4D98-rule_4D89, 1, 3
        .byte C_SWITCH_EQ, SW_PICTURE_LOOSE, 1     ; if SW_PICTURE_LOOSE == 1
        .byte A_GET     ; take the named object
        .byte A_PUT_OBJ, 37, 35     ; put object 37 (BUTTON) in room 35 (IN THE STUDY)
        .byte A_MESSAGE, 76     ; say msg 76 "THERE IS A BUTTON ON THE WALL"

; room 35 (IN THE STUDY), GET, PICTURE
rule_4D98:
        .byte 35, V_GET, N_PICTURE, rule_4DA0-rule_4D98, 0, 1
        .byte A_MESSAGE, 74     ; say msg 74 "IT IS FASTENED TO THE WALL WITH FOUR BOLTS"

; room 35 (IN THE STUDY), WITH, BUTTERKN
rule_4DA0:
        .byte 35, V_WITH, N_BUTTERKN, rule_4DAE-rule_4DA0, 1, 2
        .byte C_OBJ_IN_ROOM, 16, 254     ; if object 16 (BUTTERKN) is in inventory
        .byte A_MESSAGE, 75     ; say msg 75 "THE PICTURE IS LOOSE"
        .byte A_SET_SWITCH, SW_PICTURE_LOOSE, 1     ; SW_PICTURE_LOOSE = 1

; room 35 (IN THE STUDY), WITH, BUTTERKN
rule_4DAE:
        .byte 35, V_WITH, N_BUTTERKN, rule_4DB6-rule_4DAE, 0, 1
        .byte A_MESSAGE, 132     ; say msg 132 "YOU ARE NOT CARRYING IT"

; room 35 (IN THE STUDY), PRESS, BUTTON
rule_4DB6:
        .byte 35, V_PRESS, N_BUTTON, rule_4DC0-rule_4DB6, 1, 1
        .byte C_VIEW_IS, 41     ; if current picture == 41
        .byte A_SET_BASE_VIEW, 40     ; make picture 40 the room view

; room 35 (IN THE STUDY), PRESS, BUTTON
rule_4DC0:
        .byte 35, V_PRESS, N_BUTTON, rule_4DCA-rule_4DC0, 0, 2
        .byte A_SET_BASE_VIEW, 41     ; make picture 41 the room view
        .byte A_MESSAGE, 77     ; say msg 77 "PART OF THE WALL OPENS"

; room 35 (IN THE STUDY), CLOSE, WALL
rule_4DCA:
        .byte 35, V_CLOSE, N_WALL, rule_4DD2-rule_4DCA, 0, 1
        .byte A_SET_BASE_VIEW, 40     ; make picture 40 the room view

; room 35 (IN THE STUDY), GO, WALL
rule_4DD2:
        .byte 35, V_GO, N_WALL, rule_4DE1-rule_4DD2, 1, 3
        .byte C_VIEW_IS, 41     ; if current picture == 41
        .byte A_GOTO_ROOM, 36     ; go to room 36 (IN A MUSTY CRAWLSPACE)
        .byte A_MESSAGE, 95     ; say msg 95 "THE WALL CLOSES BEHIND YOU WITH A BANG"
        .byte A_SET_ROOM_VIEW, 35, 40     ; set room 35 (IN THE STUDY) view to picture 40

; room 36 (IN A MUSTY CRAWLSPACE), GO, STAIRS
rule_4DE1:
        .byte 36, V_GO, N_STAIRS, rule_4DE9-rule_4DE1, 0, 1
        .byte A_GOTO_ROOM, 37     ; go to room 37 (ON A STAIRWAY)

; room 36 (IN A MUSTY CRAWLSPACE), OPEN, WALL
rule_4DE9:
        .byte 36, V_OPEN, N_WALL, rule_4DF1-rule_4DE9, 0, 1
        .byte A_MESSAGE, 96     ; say msg 96 "IT WON'T OPEN"

; room 36 (IN A MUSTY CRAWLSPACE), BREAK, WALL
rule_4DF1:
        .byte 36, V_BREAK, N_WALL, rule_4DF9-rule_4DF1, 0, 1
        .byte A_MESSAGE, 50     ; say msg 50 "IT IS TOO HARD"

; room 37 (ON A STAIRWAY), GO, STAIRS
rule_4DF9:
        .byte 37, V_GO, N_STAIRS, rule_4E01-rule_4DF9, 0, 1
        .byte A_MESSAGE, 48     ; say msg 48 "WHICH DIRECTION?"

; room 38 (IN THE BATHROOM), GO, DOOR
rule_4E01:
        .byte 38, V_GO, N_DOOR, rule_4E09-rule_4E01, 0, 1
        .byte A_GOTO_ROOM, 35     ; go to room 35 (IN THE STUDY)

; room 38 (IN THE BATHROOM), FAUCET, ON
rule_4E09:
        .byte 38, V_FAUCET, N_ON, rule_4E14-rule_4E09, 0, 2
        .byte A_MESSAGE, 13     ; say msg 13 "WATER IS RUNNING INTO THE SINK"
        .byte A_SET_SWITCH, SW_BATHROOM_WATER, 1     ; SW_BATHROOM_WATER = 1

; room 38 (IN THE BATHROOM), GET, WATER
rule_4E14:
        .byte 38, V_GET, N_WATER, rule_4E28-rule_4E14, 2, 3
        .byte C_SWITCH_EQ, SW_BATHROOM_WATER, 1     ; if SW_BATHROOM_WATER == 1
        .byte C_OBJ_IN_ROOM, 14, 254     ; if object 14 (PITCHER) is in inventory
        .byte A_MESSAGE, 92     ; say msg 92 "YOUR PITCHER IS FULL"
        .byte A_PUT_OBJ, 14, 253     ; put object 14 (PITCHER) in nowhere
        .byte A_PUT_OBJ, 15, 254     ; put object 15 (PITCHER) in inventory

; room 38 (IN THE BATHROOM), GET, WATER
rule_4E28:
        .byte 38, V_GET, N_WATER, rule_4E33-rule_4E28, 1, 1
        .byte C_SWITCH_EQ, SW_BATHROOM_WATER, 1     ; if SW_BATHROOM_WATER == 1
        .byte A_MESSAGE, 14     ; say msg 14 "YOU HAVE NO CONTAINER"

; room 38 (IN THE BATHROOM), GET, WATER
rule_4E33:
        .byte 38, V_GET, N_WATER, rule_4E3B-rule_4E33, 0, 1
        .byte A_MESSAGE, 131     ; say msg 131 "I SEE NO WATER"

; room 38 (IN THE BATHROOM), FAUCET, OFF
rule_4E3B:
        .byte 38, V_FAUCET, N_OFF, rule_4E46-rule_4E3B, 0, 2
        .byte A_SET_SWITCH, SW_BATHROOM_WATER, 0     ; SW_BATHROOM_WATER = 0
        .byte A_MESSAGE, 2     ; say msg 2 "OK"

; room 38 (IN THE BATHROOM), FLUSH, TOILET
rule_4E46:
        .byte 38, V_FLUSH, N_TOILET, rule_4E4E-rule_4E46, 0, 1
        .byte A_MESSAGE, 2     ; say msg 2 "OK"

; room 38 (IN THE BATHROOM), LOOK, BODY
rule_4E4E:
        .byte 38, V_LOOK, N_BODY, rule_4E56-rule_4E4E, 0, 1
        .byte A_MESSAGE, 93     ; say msg 93 "IT IS BILL, THE BUTCHER. HE HAS BEEN STRANGLED WITH A PAIR OF PANTYHOSE"

; room 38 (IN THE BATHROOM), GET, BODY
rule_4E56:
        .byte 38, V_GET, N_BODY, rule_4E5E-rule_4E56, 0, 1
        .byte A_MESSAGE, 4     ; say msg 4 "IT IS TOO HEAVY"

; room 38 (IN THE BATHROOM), GET, SHOWER
rule_4E5E:
        .byte 38, V_GET, N_SHOWER, rule_4E66-rule_4E5E, 0, 1
        .byte A_MESSAGE, 158     ; say msg 158 "THANK YOU. I LOVE TO FEEL CLEAN. THATS MUCH BETTER."

; room 38 (IN THE BATHROOM), GO, TOILET
rule_4E66:
        .byte 38, V_GO, N_TOILET, rule_4E6E-rule_4E66, 0, 1
        .byte A_MESSAGE, 157     ; say msg 157 "THANX. THAT FEELS EVER SO MUCH BETTER"

; room 39 (IN THE ATTIC), HELP
rule_4E6E:
        .byte 39, V_HELP, ANY, rule_4E79-rule_4E6E, 1, 1
        .byte C_OBJ_IN_ROOM, 42, 39     ; if object 42 (SLEDGEHA) is in room 39 (IN THE ATTIC)
        .byte A_MESSAGE, 153     ; say msg 153 "I THINK I SEE A SLEDGEHAMMER HERE."

; room 39 (IN THE ATTIC), GO, STAIRS
rule_4E79:
        .byte 39, V_GO, N_STAIRS, rule_4E81-rule_4E79, 0, 1
        .byte A_GOTO_ROOM, 33     ; go to room 33 (AT A STAIRWAY)

; room 39 (IN THE ATTIC), OPEN, TRAPDOOR
rule_4E81:
        .byte 39, V_OPEN, N_TRAPDOOR, rule_4E90-rule_4E81, 1, 2
        .byte C_OBJ_IN_ROOM, 40, 39     ; if object 40 (TRAPDOOR) is in room 39 (IN THE ATTIC)
        .byte A_PUT_OBJ, 40, 253     ; put object 40 (TRAPDOOR) in nowhere
        .byte A_PUT_OBJ, 41, 39     ; put object 41 (TRAPDOOR) in room 39 (IN THE ATTIC)

; room 39 (IN THE ATTIC), OPEN, TRAPDOOR
rule_4E90:
        .byte 39, V_OPEN, N_TRAPDOOR, rule_4E9B-rule_4E90, 1, 1
        .byte C_OBJ_IN_ROOM, 41, 39     ; if object 41 (TRAPDOOR) is in room 39 (IN THE ATTIC)
        .byte A_MESSAGE, 129     ; say msg 129 "IT IS OPEN"

; room 39 (IN THE ATTIC), OPEN, TRAPDOOR
rule_4E9B:
        .byte 39, V_OPEN, N_TRAPDOOR, rule_4EA3-rule_4E9B, 0, 1
        .byte A_MESSAGE, 80     ; say msg 80 "WHAT TRAPDOOR?"

; room 39 (IN THE ATTIC), CLOSE, TRAPDOOR
rule_4EA3:
        .byte 39, V_CLOSE, N_TRAPDOOR, rule_4EB2-rule_4EA3, 1, 2
        .byte C_OBJ_IN_ROOM, 41, 39     ; if object 41 (TRAPDOOR) is in room 39 (IN THE ATTIC)
        .byte A_PUT_OBJ, 41, 253     ; put object 41 (TRAPDOOR) in nowhere
        .byte A_PUT_OBJ, 40, 39     ; put object 40 (TRAPDOOR) in room 39 (IN THE ATTIC)

; room 39 (IN THE ATTIC), CLOSE, TRAPDOOR
rule_4EB2:
        .byte 39, V_CLOSE, N_TRAPDOOR, rule_4EBD-rule_4EB2, 1, 1
        .byte C_OBJ_IN_ROOM, 40, 39     ; if object 40 (TRAPDOOR) is in room 39 (IN THE ATTIC)
        .byte A_MESSAGE, 128     ; say msg 128 "THE DOOR IS CLOSED"

; room 39 (IN THE ATTIC), CLOSE, TRAPDOOR
rule_4EBD:
        .byte 39, V_CLOSE, N_TRAPDOOR, rule_4EC5-rule_4EBD, 0, 1
        .byte A_MESSAGE, 80     ; say msg 80 "WHAT TRAPDOOR?"

; room 39 (IN THE ATTIC), GO, TRAPDOOR
rule_4EC5:
        .byte 39, V_GO, N_TRAPDOOR, rule_4ED0-rule_4EC5, 1, 1
        .byte C_OBJ_IN_ROOM, 41, 39     ; if object 41 (TRAPDOOR) is in room 39 (IN THE ATTIC)
        .byte A_GOTO_ROOM, 41     ; go to room 41 (IN THE TOWER)

; room 39 (IN THE ATTIC), GO, TRAPDOOR
rule_4ED0:
        .byte 39, V_GO, N_TRAPDOOR, rule_4EDB-rule_4ED0, 1, 1
        .byte C_OBJ_IN_ROOM, 40, 39     ; if object 40 (TRAPDOOR) is in room 39 (IN THE ATTIC)
        .byte A_MESSAGE, 133     ; say msg 133 "IT IS NOT OPEN"

; room 39 (IN THE ATTIC), GO, TRAPDOOR
rule_4EDB:
        .byte 39, V_GO, N_TRAPDOOR, rule_4EE3-rule_4EDB, 0, 1
        .byte A_MESSAGE, 80     ; say msg 80 "WHAT TRAPDOOR?"

; room 39 (IN THE ATTIC), UP, LADDER
rule_4EE3:
        .byte 39, V_U, N_LADDER, rule_4EEE-rule_4EE3, 1, 1
        .byte C_OBJ_IN_ROOM, 41, 39     ; if object 41 (TRAPDOOR) is in room 39 (IN THE ATTIC)
        .byte A_GOTO_ROOM, 41     ; go to room 41 (IN THE TOWER)

; room 39 (IN THE ATTIC), UP, LADDER
rule_4EEE:
        .byte 39, V_U, N_LADDER, rule_4EF6-rule_4EEE, 0, 1
        .byte A_MESSAGE, 150     ; say msg 150 "YOU CLIMB UP BUMP YOUR HEAD ON THE CEILING AND FALL, DAZED BUT ALIVE."

; room 39 (IN THE ATTIC), GO, DOOR
rule_4EF6:
        .byte 39, V_GO, N_DOOR, rule_4EFE-rule_4EF6, 0, 1
        .byte A_GOTO_ROOM, 40     ; go to room 40 (IN A STORAGE ROOM)

; room 39 (IN THE ATTIC), LOOK, WINDOW
rule_4EFE:
        .byte 39, V_LOOK, N_WINDOW, rule_4F06-rule_4EFE, 0, 1
        .byte A_MESSAGE, 79     ; say msg 79 "YOU SEE A FOREST"

; room 39 (IN THE ATTIC), GET, LADDER
rule_4F06:
        .byte 39, V_GET, N_LADDER, rule_4F0E-rule_4F06, 0, 1
        .byte A_MESSAGE, 27     ; say msg 27 "IT DOES NOT REMOVE"

; room 39 (IN THE ATTIC), BREAK, WINDOW
rule_4F0E:
        .byte 39, V_BREAK, N_WINDOW, rule_4F16-rule_4F0E, 0, 1
        .byte A_MESSAGE, 2     ; say msg 2 "OK"

; room 39 (IN THE ATTIC), GO, WINDOW
rule_4F16:
        .byte 39, V_GO, N_WINDOW, rule_4F21-rule_4F16, 0, 3
        .byte A_MESSAGE, 147     ; say msg 147 "YOU FALL TO EARTH. LUCKILY YOU HAVE ONLY MINOR INJURIES."
        .byte A_MESSAGE, 148     ; say msg 148 "UNFORTUNATELY THE AMBULANCE DRIVER SMASHS INTO A VOLKWAGEN. NO SURVIVORS. YOU ARE DEAD."
        .byte A_GAME_OVER     ; ask to play again

; room 40 (IN A STORAGE ROOM), GO, DOOR
rule_4F21:
        .byte 40, V_GO, N_DOOR, rule_4F29-rule_4F21, 0, 1
        .byte A_GOTO_ROOM, 39     ; go to room 39 (IN THE ATTIC)

; room 40 (IN A STORAGE ROOM), GET, BOXES
rule_4F29:
        .byte 40, V_GET, N_BOXES, rule_4F31-rule_4F29, 0, 1
        .byte A_MESSAGE, 27     ; say msg 27 "IT DOES NOT REMOVE"

; room 40 (IN A STORAGE ROOM), GET, TRUNK
rule_4F31:
        .byte 40, V_GET, N_TRUNK, rule_4F39-rule_4F31, 0, 1
        .byte A_MESSAGE, 4     ; say msg 4 "IT IS TOO HEAVY"

; room 40 (IN A STORAGE ROOM), OPEN, TRUNK
rule_4F39:
        .byte 40, V_OPEN, N_TRUNK, rule_4F4B-rule_4F39, 2, 2
        .byte C_SWITCH_EQ, SW_TRUNK_UNLOCKED, 1     ; if SW_TRUNK_UNLOCKED == 1
        .byte C_OBJ_IN_ROOM, 43, 40     ; if object 43 (TRUNK) is in room 40 (IN A STORAGE ROOM)
        .byte A_PUT_OBJ, 43, 253     ; put object 43 (TRUNK) in nowhere
        .byte A_PUT_OBJ, 44, 40     ; put object 44 (TRUNK) in room 40 (IN A STORAGE ROOM)

; room 40 (IN A STORAGE ROOM), OPEN, TRUNK
rule_4F4B:
        .byte 40, V_OPEN, N_TRUNK, rule_4F56-rule_4F4B, 1, 1
        .byte C_SWITCH_EQ, SW_TRUNK_UNLOCKED, 1     ; if SW_TRUNK_UNLOCKED == 1
.ifdef BUGFIX
        .byte A_MESSAGE, 129    ; say msg 129 "IT IS OPEN" (bug fix: the trunk is open here)
.else
        .byte A_MESSAGE, 82     ; say msg 82 "IT IS LOCKED" (bug: only the open trunk gets here)
.endif

; room 40 (IN A STORAGE ROOM), OPEN, TRUNK
rule_4F56:
        .byte 40, V_OPEN, N_TRUNK, rule_4F61-rule_4F56, 1, 1
        .byte C_OBJ_IN_ROOM, 44, 40     ; if object 44 (TRUNK) is in room 40 (IN A STORAGE ROOM)
        .byte A_MESSAGE, 129     ; say msg 129 "IT IS OPEN"

; room 40 (IN A STORAGE ROOM), OPEN, TRUNK
rule_4F61:
        .byte 40, V_OPEN, N_TRUNK, rule_4F69-rule_4F61, 0, 1
        .byte A_MESSAGE, 82     ; say msg 82 "IT IS LOCKED"

; room 40 (IN A STORAGE ROOM), CLOSE, TRUNK
rule_4F69:
        .byte 40, V_CLOSE, N_TRUNK, rule_4F78-rule_4F69, 1, 2
        .byte C_OBJ_IN_ROOM, 44, 40     ; if object 44 (TRUNK) is in room 40 (IN A STORAGE ROOM)
        .byte A_PUT_OBJ, 44, 253     ; put object 44 (TRUNK) in nowhere
        .byte A_PUT_OBJ, 43, 40     ; put object 43 (TRUNK) in room 40 (IN A STORAGE ROOM)

; room 40 (IN A STORAGE ROOM), CLOSE, TRUNK
rule_4F78:
        .byte 40, V_CLOSE, N_TRUNK, rule_4F83-rule_4F78, 1, 1
        .byte C_OBJ_IN_ROOM, 43, 40     ; if object 43 (TRUNK) is in room 40 (IN A STORAGE ROOM)
        .byte A_MESSAGE, 133     ; say msg 133 "IT IS NOT OPEN"

; room 40 (IN A STORAGE ROOM), LOOK, TRUNK
rule_4F83:
        .byte 40, V_LOOK, N_TRUNK, rule_4F8E-rule_4F83, 1, 1
        .byte C_OBJ_IN_ROOM, 44, 40     ; if object 44 (TRUNK) is in room 40 (IN A STORAGE ROOM)
        .byte A_SET_VIEW, 50     ; show picture 50

; room 40 (IN A STORAGE ROOM), LOOK, TRUNK
rule_4F8E:
        .byte 40, V_LOOK, N_TRUNK, rule_4F9C-rule_4F8E, 2, 1
        .byte C_OBJ_IN_ROOM, 43, 40     ; if object 43 (TRUNK) is in room 40 (IN A STORAGE ROOM)
        .byte C_SWITCH_EQ, SW_TRUNK_UNLOCKED, 0     ; if SW_TRUNK_UNLOCKED == 0
        .byte A_MESSAGE, 82     ; say msg 82 "IT IS LOCKED"

; room 40 (IN A STORAGE ROOM), LOOK, TRUNK
rule_4F9C:
        .byte 40, V_LOOK, N_TRUNK, rule_4FAA-rule_4F9C, 2, 1
        .byte C_OBJ_IN_ROOM, 43, 40     ; if object 43 (TRUNK) is in room 40 (IN A STORAGE ROOM)
        .byte C_SWITCH_EQ, SW_TRUNK_UNLOCKED, 1     ; if SW_TRUNK_UNLOCKED == 1
        .byte A_MESSAGE, 133     ; say msg 133 "IT IS NOT OPEN"

; room 40 (IN A STORAGE ROOM), UNLOCK, TRUNK
rule_4FAA:
        .byte 40, V_UNLOCK, N_TRUNK, rule_4FBE-rule_4FAA, 3, 2
        .byte C_OBJ_IN_ROOM, 43, 40     ; if object 43 (TRUNK) is in room 40 (IN A STORAGE ROOM)
        .byte C_OBJ_IN_ROOM, 22, 254     ; if object 22 (KEY) is in inventory
        .byte C_SWITCH_EQ, SW_TRUNK_UNLOCKED, 0     ; if SW_TRUNK_UNLOCKED == 0
        .byte A_MESSAGE, 2     ; say msg 2 "OK"
        .byte A_SET_SWITCH, SW_TRUNK_UNLOCKED, 1     ; SW_TRUNK_UNLOCKED = 1

; room 40 (IN A STORAGE ROOM), UNLOCK, TRUNK
rule_4FBE:
        .byte 40, V_UNLOCK, N_TRUNK, rule_4FCF-rule_4FBE, 3, 1
        .byte C_OBJ_IN_ROOM, 43, 40     ; if object 43 (TRUNK) is in room 40 (IN A STORAGE ROOM)
        .byte C_OBJ_IN_ROOM, 22, 254     ; if object 22 (KEY) is in inventory
        .byte C_SWITCH_EQ, SW_TRUNK_UNLOCKED, 1     ; if SW_TRUNK_UNLOCKED == 1
        .byte A_MESSAGE, 136     ; say msg 136 "IT IS UNLOCKED"

; room 40 (IN A STORAGE ROOM), UNLOCK, TRUNK
rule_4FCF:
        .byte 40, V_UNLOCK, N_TRUNK, rule_4FDD-rule_4FCF, 2, 1
        .byte C_OBJ_IN_ROOM, 43, 40     ; if object 43 (TRUNK) is in room 40 (IN A STORAGE ROOM)
        .byte C_SWITCH_EQ, SW_TRUNK_UNLOCKED, 0     ; if SW_TRUNK_UNLOCKED == 0
        .byte A_MESSAGE, 83     ; say msg 83 "YOU HAVE NOTHING TO UNLOCK IT WITH"

; room 40 (IN A STORAGE ROOM), UNLOCK, TRUNK
rule_4FDD:
        .byte 40, V_UNLOCK, N_TRUNK, rule_4FEB-rule_4FDD, 2, 1
        .byte C_OBJ_IN_ROOM, 43, 40     ; if object 43 (TRUNK) is in room 40 (IN A STORAGE ROOM)
        .byte C_SWITCH_EQ, SW_TRUNK_UNLOCKED, 1     ; if SW_TRUNK_UNLOCKED == 1
        .byte A_MESSAGE, 136     ; say msg 136 "IT IS UNLOCKED"

; room 40 (IN A STORAGE ROOM), GO, WINDOW
rule_4FEB:
.ifdef BUGFIX
        .byte 40, V_GO, N_WINDOW, rule_4FF5-rule_4FEB, 0, 3
.else
        .byte 40, V_GO, N_WINDOW, rule_4FF5-rule_4FEB, 0, 2   ; bug: the game goes on after
.endif
        .byte A_MESSAGE, 147     ; say msg 147 "YOU FALL TO EARTH. LUCKILY YOU HAVE ONLY MINOR INJURIES."
        .byte A_MESSAGE, 148     ; say msg 148 "UNFORTUNATELY THE AMBULANCE DRIVER SMASHS INTO A VOLKWAGEN. NO SURVIVORS. YOU ARE DEAD."
.ifdef BUGFIX
        .byte A_GAME_OVER     ; ask to play again (bug fix: as the attic window does)
.endif

; room 41 (IN THE TOWER), GO, TRAPDOOR
rule_4FF5:
        .byte 41, V_GO, N_TRAPDOOR, rule_4FFD-rule_4FF5, 0, 1
        .byte A_GOTO_ROOM, 39     ; go to room 39 (IN THE ATTIC)

; room 41 (IN THE TOWER), LOOK, PERSON
rule_4FFD:
        .byte 41, V_LOOK, N_PERSON, rule_5008-rule_4FFD, 1, 1
        .byte C_SWITCH_EQ, SW_DAISY_DEAD, 0     ; if SW_DAISY_DEAD == 0
        .byte A_MESSAGE, 87     ; say msg 87 "SHE IS GOING TO KILL YOU"

; room 41 (IN THE TOWER), LOOK, DAISY
rule_5008:
        .byte 41, V_LOOK, N_DAISY, rule_5013-rule_5008, 1, 1
        .byte C_SWITCH_EQ, SW_DAISY_DEAD, 0     ; if SW_DAISY_DEAD == 0
        .byte A_MESSAGE, 87     ; say msg 87 "SHE IS GOING TO KILL YOU"

; room 41 (IN THE TOWER), LOOK, DAISY
rule_5013:
        .byte 41, V_LOOK, N_DAISY, rule_501B-rule_5013, 0, 1
        .byte A_MESSAGE, 88     ; say msg 88 "SHE IS DEAD"

; room 41 (IN THE TOWER), KILL, DAISY
rule_501B:
        .byte 41, V_KILL, N_DAISY, rule_5023-rule_501B, 0, 1
        .byte A_MESSAGE, 34     ; say msg 34 "WITH WHAT?"

; room 41 (IN THE TOWER), WITH, DAGGER
rule_5023:
        .byte 41, V_WITH, N_DAGGER, rule_502E-rule_5023, 1, 1
        .byte C_SWITCH_EQ, SW_DAISY_DEAD, 1     ; if SW_DAISY_DEAD == 1
        .byte A_MESSAGE, 166     ; say msg 166 "DAISY IS ALREADY DEAD"

; room 41 (IN THE TOWER), WITH, DAGGER
rule_502E:
        .byte 41, V_WITH, N_DAGGER, rule_503A-rule_502E, 1, 2
        .byte C_OBJ_IN_ROOM, 53, 254     ; if object 53 (DAGGER) is in inventory
        .byte A_MESSAGE, 90     ; say msg 90 "DAISY STABBED YOU.  YOU ARE DEAD"
        .byte A_GAME_OVER     ; ask to play again

; room 41 (IN THE TOWER), WITH, DAGGER
rule_503A:
        .byte 41, V_WITH, N_DAGGER, rule_5045-rule_503A, 0, 3
        .byte A_MESSAGE, 132     ; say msg 132 "YOU ARE NOT CARRYING IT"
        .byte A_MESSAGE, 90     ; say msg 90 "DAISY STABBED YOU.  YOU ARE DEAD"
        .byte A_GAME_OVER     ; ask to play again

; room 41 (IN THE TOWER), WITH, GUN
rule_5045:
        .byte 41, V_WITH, N_GUN, rule_5061-rule_5045, 2, 6
        .byte C_SWITCH_EQ, SW_GUN_FIRED, 0     ; if SW_GUN_FIRED == 0
        .byte C_OBJ_IN_ROOM, 45, 254     ; if object 45 (GUN) is in inventory
        .byte A_PUT_OBJ, 47, 253     ; put object 47 (DOTS) in nowhere
        .byte A_PUT_OBJ, 48, 41     ; put object 48 (X'S) in room 41 (IN THE TOWER)
        .byte A_SET_SWITCH, SW_GUN_FIRED, 1     ; SW_GUN_FIRED = 1
        .byte A_MESSAGE, 35     ; say msg 35 "YOUR GUN IS EMPTY"
        .byte A_SET_SWITCH, SW_DAISY_DEAD, 1     ; SW_DAISY_DEAD = 1
        .byte A_MESSAGE, 161     ; say msg 161 "DAISY IS NOW DEAD"

; room 41 (IN THE TOWER), WITH, GUN
rule_5061:
        .byte 41, V_WITH, N_GUN, rule_506C-rule_5061, 1, 1
        .byte C_SWITCH_EQ, SW_DAISY_DEAD, 1     ; if SW_DAISY_DEAD == 1
        .byte A_MESSAGE, 166     ; say msg 166 "DAISY IS ALREADY DEAD"

; room 41 (IN THE TOWER), WITH, GUN
rule_506C:
        .byte 41, V_WITH, N_GUN, rule_507D-rule_506C, 2, 3
        .byte C_SWITCH_EQ, SW_GUN_FIRED, 1     ; if SW_GUN_FIRED == 1
        .byte C_OBJ_IN_ROOM, 45, 254     ; if object 45 (GUN) is in inventory
        .byte A_MESSAGE, 35     ; say msg 35 "YOUR GUN IS EMPTY"
        .byte A_MESSAGE, 90     ; say msg 90 "DAISY STABBED YOU.  YOU ARE DEAD"
        .byte A_GAME_OVER     ; ask to play again

; room 41 (IN THE TOWER), WITH, GUN
rule_507D:
        .byte 41, V_WITH, N_GUN, rule_5088-rule_507D, 0, 3
        .byte A_MESSAGE, 132     ; say msg 132 "YOU ARE NOT CARRYING IT"
        .byte A_MESSAGE, 90     ; say msg 90 "DAISY STABBED YOU.  YOU ARE DEAD"
        .byte A_GAME_OVER     ; ask to play again

; room 41 (IN THE TOWER), GET, BODY
rule_5088:
        .byte 41, V_GET, N_BODY, rule_5090-rule_5088, 0, 1
        .byte A_MESSAGE, 4     ; say msg 4 "IT IS TOO HEAVY"

; room 41 (IN THE TOWER), WITH, BUTTERKN
rule_5090:
        .byte 41, V_WITH, N_BUTTERKN, rule_509C-rule_5090, 1, 2
        .byte C_OBJ_IN_ROOM, 16, 254     ; if object 16 (BUTTERKN) is in inventory
        .byte A_MESSAGE, 90     ; say msg 90 "DAISY STABBED YOU.  YOU ARE DEAD"
        .byte A_GAME_OVER     ; ask to play again

; room 41 (IN THE TOWER), WITH, BUTTERKN
rule_509C:
        .byte 41, V_WITH, N_BUTTERKN, rule_50A7-rule_509C, 0, 3
        .byte A_MESSAGE, 132     ; say msg 132 "YOU ARE NOT CARRYING IT"
        .byte A_MESSAGE, 90     ; say msg 90 "DAISY STABBED YOU.  YOU ARE DEAD"
        .byte A_GAME_OVER     ; ask to play again

; room 41 (IN THE TOWER), WITH, SLEDGEHA
rule_50A7:
        .byte 41, V_WITH, N_SLEDGEHA, rule_50B3-rule_50A7, 1, 2
        .byte C_OBJ_IN_ROOM, 42, 254     ; if object 42 (SLEDGEHA) is in inventory
        .byte A_MESSAGE, 90     ; say msg 90 "DAISY STABBED YOU.  YOU ARE DEAD"
        .byte A_GAME_OVER     ; ask to play again

; room 41 (IN THE TOWER), WITH, SLEDGEHA
rule_50B3:
        .byte 41, V_WITH, N_SLEDGEHA, rule_50BE-rule_50B3, 0, 3
        .byte A_MESSAGE, 132     ; say msg 132 "YOU ARE NOT CARRYING IT"
        .byte A_MESSAGE, 90     ; say msg 90 "DAISY STABBED YOU.  YOU ARE DEAD"
        .byte A_GAME_OVER     ; ask to play again

; room 41 (IN THE TOWER), GET, NOTE
rule_50BE:
        .byte 41, V_GET, N_NOTE, rule_50C9-rule_50BE, 1, 1
        .byte C_SWITCH_EQ, SW_DAISY_DEAD, 0     ; if SW_DAISY_DEAD == 0
        .byte A_MESSAGE, 86     ; say msg 86 "DAISY WON'T LET YOU"

; room 41 (IN THE TOWER), GET, NOTE
rule_50C9:
        .byte 41, V_GET, N_NOTE, rule_50D2-rule_50C9, 0, 2
        .byte A_MESSAGE, 2     ; say msg 2 "OK"
        .byte A_GET     ; take the named object

; room 41 (IN THE TOWER), GET, KNIFE
rule_50D2:
        .byte 41, V_GET, N_KNIFE, rule_50DA-rule_50D2, 0, 1
        .byte A_MESSAGE, 37     ; say msg 37 "I DONT UNDERSTAND WHAT YOU MEAN"

; room 41 (IN THE TOWER), LOOK, BODY
rule_50DA:
        .byte 41, V_LOOK, N_BODY, rule_50E2-rule_50DA, 0, 1
        .byte A_MESSAGE, 88     ; say msg 88 "SHE IS DEAD"

; room 41 (IN THE TOWER), CLOSE, TRAPDOOR
rule_50E2:
        .byte 41, V_CLOSE, N_TRAPDOOR, rule_50EA-rule_50E2, 0, 1
        .byte A_MESSAGE, 134     ; say msg 134 "IT WONT CLOSE HERE"

; LOOK, WINDOW
rule_50EA:
        .byte ANY, V_LOOK, N_WINDOW, rule_50F2-rule_50EA, 0, 1
        .byte A_MESSAGE, 5     ; say msg 5 "WINDOWS ARE BOARDED UP EXCEPT THE ATTIC WINDOW"

; LOOK, NOTE
rule_50F2:
        .byte ANY, V_LOOK, N_NOTE, rule_50FD-rule_50F2, 1, 1
        .byte C_OBJ_IN_ROOM, 9, 254     ; if object 9 (NOTE) is in inventory
        .byte A_MESSAGE, 65     ; say msg 65 "THERE IS WRITING ON IT"

; READ, NOTE
rule_50FD:
        .byte ANY, V_READ, N_NOTE, rule_5108-rule_50FD, 1, 1
        .byte C_OBJ_IN_ROOM, 9, 254     ; if object 9 (NOTE) is in inventory
        .byte A_SET_VIEW, 48     ; show picture 48

; LOOK, ROOM
rule_5108:
        .byte ANY, V_LOOK, N_ROOM, rule_510F-rule_5108, 0, 1
        .byte A_RESET_VIEW     ; show the room view

; LIGHT, MATCHES
rule_510F:
        .byte ANY, V_LIGHT, N_MATCHES, rule_511E-rule_510F, 1, 3
        .byte C_OBJ_IN_ROOM, 13, 254     ; if object 13 (MATCHES) is in inventory
        .byte A_SET_SWITCH, SW_MATCH_BURNING, 4     ; SW_MATCH_BURNING = 4
        .byte A_LAMP_ON     ; light on
        .byte A_MESSAGE, 2     ; say msg 2 "OK"

; LIGHT, MATCHES
rule_511E:
        .byte ANY, V_LIGHT, N_MATCHES, rule_5126-rule_511E, 0, 1
        .byte A_MESSAGE, 132     ; say msg 132 "YOU ARE NOT CARRYING IT"

; POUR, WATER
rule_5126:
        .byte ANY, V_POUR, N_WATER, rule_5137-rule_5126, 1, 3
        .byte C_OBJ_IN_ROOM, 15, 254     ; if object 15 (PITCHER) is in inventory
        .byte A_PUT_OBJ, 15, 253     ; put object 15 (PITCHER) in nowhere
        .byte A_PUT_OBJ, 14, 254     ; put object 14 (PITCHER) in inventory
        .byte A_MESSAGE, 17     ; say msg 17 "THE PITCHER IS EMPTY"

; POUR, WATER
rule_5137:
        .byte ANY, V_POUR, N_WATER, rule_513F-rule_5137, 0, 1
        .byte A_MESSAGE, 131     ; say msg 131 "I SEE NO WATER"

; LOOK, TREE
rule_513F:
        .byte ANY, V_LOOK, N_TREE, rule_5149-rule_513F, 1, 1
        .byte C_VIEW_IS, 20     ; if current picture == 20
        .byte A_MESSAGE, 15     ; say msg 15 "THERE IS NOTHING SPECIAL"

; UP, TREE
rule_5149:
        .byte ANY, V_U, N_TREE, rule_5153-rule_5149, 1, 1
        .byte C_VIEW_IS, 20     ; if current picture == 20
        .byte A_MESSAGE, 15     ; say msg 15 "THERE IS NOTHING SPECIAL"

; LIGHT, CANDLE
rule_5153:
        .byte ANY, V_LIGHT, N_CANDLE, rule_5168-rule_5153, 2, 4
        .byte C_OBJ_IN_ROOM, 19, 254     ; if object 19 (CANDLE) is in inventory
        .byte C_OBJ_IN_ROOM, 13, 254     ; if object 13 (MATCHES) is in inventory
        .byte A_PUT_OBJ, 19, 253     ; put object 19 (CANDLE) in nowhere
        .byte A_PUT_OBJ, 18, 254     ; put object 18 (CANDLE) in inventory
        .byte A_LAMP_ON     ; light on
        .byte A_MESSAGE, 2     ; say msg 2 "OK"

; UNLIGHT, CANDLE
rule_5168:
        .byte ANY, V_UNLIGHT, N_CANDLE, rule_5177-rule_5168, 1, 2
        .byte C_OBJ_IN_ROOM, 18, 254     ; if object 18 (CANDLE) is in inventory
        .byte A_PUT_OBJ, 18, 253     ; put object 18 (CANDLE) in nowhere
        .byte A_PUT_OBJ, 19, 254     ; put object 19 (CANDLE) in inventory

; BREAK, WINDOW
rule_5177:
        .byte ANY, V_BREAK, N_WINDOW, rule_517F-rule_5177, 0, 1
        .byte A_MESSAGE, 5     ; say msg 5 "WINDOWS ARE BOARDED UP EXCEPT THE ATTIC WINDOW"

; GO, WINDOW
rule_517F:
        .byte ANY, V_GO, N_WINDOW, rule_5187-rule_517F, 0, 1
        .byte A_MESSAGE, 5     ; say msg 5 "WINDOWS ARE BOARDED UP EXCEPT THE ATTIC WINDOW"

; WITH, GUN
rule_5187:
        .byte ANY, V_WITH, N_GUN, rule_5198-rule_5187, 2, 2
        .byte C_OBJ_IN_ROOM, 45, 254     ; if object 45 (GUN) is in inventory
        .byte C_SWITCH_EQ, SW_GUN_FIRED, 0     ; if SW_GUN_FIRED == 0
        .byte A_SET_SWITCH, SW_GUN_FIRED, 1     ; SW_GUN_FIRED = 1
        .byte A_MESSAGE, 160     ; say msg 160 "YOUR GUN IS NOW EMPTY"

; WITH, GUN
rule_5198:
        .byte ANY, V_WITH, N_GUN, rule_51A6-rule_5198, 1, 2
        .byte C_OBJ_IN_ROOM, 45, 254     ; if object 45 (GUN) is in inventory
        .byte A_SET_SWITCH, SW_GUN_FIRED, 1     ; SW_GUN_FIRED = 1
        .byte A_MESSAGE, 35     ; say msg 35 "YOUR GUN IS EMPTY"

; LOOK, GUN
rule_51A6:
        .byte ANY, V_LOOK, N_GUN, rule_51AE-rule_51A6, 0, 1
        .byte A_MESSAGE, 84     ; say msg 84 "THERE IS ONE BULLET IN THE GUN"

; READ, NOTE
rule_51AE:
        .byte ANY, V_READ, N_NOTE, rule_51B9-rule_51AE, 1, 1
        .byte C_OBJ_IN_ROOM, 17, 254     ; if object 17 (NOTE) is in inventory
        .byte A_SET_VIEW, 24     ; show picture 24

; READ, NOTE
rule_51B9:
        .byte ANY, V_READ, N_NOTE, rule_51C4-rule_51B9, 1, 1
        .byte C_OBJ_IN_ROOM, 35, 254     ; if object 35 (NOTE) is in inventory
        .byte A_SET_VIEW, 36     ; show picture 36

; READ, NOTE
rule_51C4:
        .byte ANY, V_READ, N_NOTE, rule_51CF-rule_51C4, 1, 1
        .byte C_OBJ_IN_ROOM, 49, 254     ; if object 49 (NOTE) is in inventory
        .byte A_SET_VIEW, 51     ; show picture 51

; NORTH, 
rule_51CF:
        .byte ANY, V_N, N_NONE, rule_51D6-rule_51CF, 0, 1
        .byte A_GO_N     ; go north

; SOUTH, 
rule_51D6:
        .byte ANY, V_S, N_NONE, rule_51DD-rule_51D6, 0, 1
        .byte A_GO_S     ; go south

; EAST, 
rule_51DD:
        .byte ANY, V_E, N_NONE, rule_51E4-rule_51DD, 0, 1
        .byte A_GO_E     ; go east

; WEST, 
rule_51E4:
        .byte ANY, V_W, N_NONE, rule_51EB-rule_51E4, 0, 1
        .byte A_GO_W     ; go west

; UP, 
rule_51EB:
        .byte ANY, V_U, N_NONE, rule_51F2-rule_51EB, 0, 1
        .byte A_GO_U     ; go up

; DOWN, 
rule_51F2:
        .byte ANY, V_D, N_NONE, rule_51F9-rule_51F2, 0, 1
        .byte A_GO_D     ; go down

; GET
rule_51F9:
        .byte ANY, V_GET, ANY, rule_5200-rule_51F9, 0, 1
        .byte A_GET     ; take the named object

; DROP
rule_5200:
        .byte ANY, V_DROP, ANY, rule_5207-rule_5200, 0, 1
        .byte A_DROP     ; drop the named object

; LOOK, NOTE
rule_5207:
        .byte ANY, V_LOOK, N_NOTE, rule_5212-rule_5207, 1, 1
        .byte C_OBJ_IN_ROOM, 17, 254     ; if object 17 (NOTE) is in inventory
        .byte A_MESSAGE, 65     ; say msg 65 "THERE IS WRITING ON IT"

; LOOK, NOTE
rule_5212:
        .byte ANY, V_LOOK, N_NOTE, rule_521D-rule_5212, 1, 1
        .byte C_OBJ_IN_ROOM, 35, 254     ; if object 35 (NOTE) is in inventory
        .byte A_MESSAGE, 65     ; say msg 65 "THERE IS WRITING ON IT"

; LOOK, NOTE
rule_521D:
        .byte ANY, V_LOOK, N_NOTE, rule_5228-rule_521D, 1, 1
        .byte C_OBJ_IN_ROOM, 49, 254     ; if object 49 (NOTE) is in inventory
        .byte A_MESSAGE, 65     ; say msg 65 "THERE IS WRITING ON IT"

; LOOK, NOTE
rule_5228:
        .byte ANY, V_LOOK, N_NOTE, rule_5230-rule_5228, 0, 1
        .byte A_MESSAGE, 127     ; say msg 127 "IM NOT CARRYING THAT"

; READ, NOTE
rule_5230:
        .byte ANY, V_READ, N_NOTE, rule_5238-rule_5230, 0, 1
        .byte A_MESSAGE, 127     ; say msg 127 "IM NOT CARRYING THAT"

; SAVE, GAME
rule_5238:
        .byte ANY, V_SAVE, N_GAME, rule_523F-rule_5238, 0, 1
        .byte A_SAVE_GAME     ; save game

; DRINK, WATER
rule_523F:
        .byte ANY, V_DRINK, N_WATER, rule_5250-rule_523F, 1, 3
        .byte C_OBJ_IN_ROOM, 15, 254     ; if object 15 (PITCHER) is in inventory
        .byte A_MESSAGE, 2     ; say msg 2 "OK"
        .byte A_PUT_OBJ, 15, 253     ; put object 15 (PITCHER) in nowhere
        .byte A_PUT_OBJ, 14, 254     ; put object 14 (PITCHER) in inventory

; RESTORE, GAME
rule_5250:
        .byte ANY, V_RESTORE, N_GAME, rule_5257-rule_5250, 0, 1
        .byte A_RESTORE_GAME     ; restore game

; QUIT, 
rule_5257:
        .byte ANY, V_QUIT, N_NONE, rule_525E-rule_5257, 0, 1
        .byte A_GAME_OVER     ; ask to play again

; HELP
rule_525E:
        .byte ANY, V_HELP, ANY, rule_5268-rule_525E, 1, 1
        .byte C_VIEW_IS, 20     ; if current picture == 20
        .byte A_MESSAGE, 165     ; say msg 165 "IF ONLY I COULD TELL IF I'D BEEN HERE BEFORE..."

; HELP
rule_5268:
        .byte ANY, V_HELP, ANY, rule_5270-rule_5268, 0, 1
        .byte A_MESSAGE, 141     ; say msg 141 "TRY GOING IN SOME DIRECTION EX:NORTH,SOUTH,EAST,WEST,UP,DOWN"

; LOOK
rule_5270:
        .byte ANY, V_LOOK, ANY, rule_5278-rule_5270, 0, 1
        .byte A_MESSAGE, 15     ; say msg 15 "THERE IS NOTHING SPECIAL"

; INVENTOR, 
rule_5278:
        .byte ANY, V_INVENTOR, N_NONE, rule_527F-rule_5278, 0, 1
        .byte A_INVENTORY     ; list objects carried

; FUCK
rule_527F:
        .byte ANY, V_PROFANITY, ANY, rule_5288-rule_527F, 0, 2
        .byte A_MESSAGE, 149     ; say msg 149 "IF YOU FEEL THAT WAY I REFUSE TO PLAY WITH YOU..."
        .byte A_QUIT     ; say msg 140 "THANK YOU FOR PLAYING HI-RES ADVENTURE ... GOOD-BYE"; exit to DOS

; LIGHT, CANDLE
rule_5288:
        .byte ANY, V_LIGHT, N_CANDLE, rule_5293-rule_5288, 1, 1
        .byte C_OBJ_IN_ROOM, 13, 254     ; if object 13 (MATCHES) is in inventory
        .byte A_MESSAGE, 154     ; say msg 154 "YOU DON'T HAVE IT"

; LIGHT, CANDLE
rule_5293:
        .byte ANY, V_LIGHT, N_CANDLE, rule_529B-rule_5293, 0, 1
        .byte A_MESSAGE, 155     ; say msg 155 "YOU HAVE NOTHING TO LIGHT IT WITH"

; SLEEP
rule_529B:
        .byte ANY, V_SLEEP, ANY, command_rules_end-rule_529B, 0, 1
        .byte A_MESSAGE, 159     ; say msg 159 "I FEEL MUCH MORE RESTED NOW"
command_rules_end:
        .byte $FF
; leftover memory, not used: lines here can be deleted to make room
        .byte $A0,$A0,$C3,$C1,$D2,$D2,$D9,$C9,$CE,$C7,$BF,$A0,$A0,$A0,$A0,$A0
        .byte $A0,$A0,$C4,$CF,$CE,$C5,$A0,$A0,$A0,$A0,$FF,$FF,$00,$00,$FF,$FF
        .byte $00,$00,$FF,$FF,$00,$00,$FF,$FF,$00,$00,$FF,$FF,$00,$00,$FF,$FF
        .byte $00,$00,$FF,$FF,$00,$00,$FF,$FF,$00,$00,$FF,$FF,$00,$00,$FF,$FF
        .byte $00,$00,$FF,$FF,$00,$00,$FF,$FF,$00,$00,$FF,$FF,$00,$00,$FF,$FF
        .byte $00,$00,$FF,$FF,$00,$00,$FF,$FF,$00,$00,$FF,$FF

; ==== picture directory ==============================================================
; Picture n is at offset in file BLOCKblock; load_picture reads entry n at PICDIR + 3n. The
; table and the BLOCK files are built from src/pictures/ (tools/picfile.py).
        .include "pictures.inc"    ; generated from src/pictures/ by tools/picfile.py
        .incbin "data/adventure_5426.bin"    ; leftover memory, not used (see NOTES.md)

; ==== message index ==================================================================
; Byte offset of each message in the MESSAGES text file (also saved as MESSAGE OBJECT). The
; table and MESSAGES are built from src/messages.txt (tools/msgfile.py).
        .include "messages.inc"    ; generated from src/messages.txt by tools/msgfile.py
        .byte $08

; ---- dead code from an older build -------------------------------------------------------
; Nothing reaches these routines. They call the macro library at $4A00, its address in that build
; (those bytes are now command rules), and use that build's variable layout.
old_var_085E             = $085E
old_var_085F             = $085F
old_hex_in               = $5A01    ; old build variables, where run_rules is now
old_hex_out              = $5A02    ; 4 ASCII hex digits
old_hex_hi               = $5A06
old_hex_lo               = $5A07
old_msg_offset           = $5A0A    ; word

; unreachable older copy of the end of init_game (shape table at $6D00; also sets the DOS language
; flag)
dead_init_tail:
        LDA #$00
        STA old_var_085F
        STA old_var_085E
        LDA #$7F
        STA var_hcolor
        LDA #$00
        STA hgr_shape_table
        LDA #$6D
        STA hgr_shape_table+1
        LDX #$08
        JSR old_rt_copy
        .word dead_blank_word
        .word mul_dest
        LDX #$08
        JSR old_rt_copy
        .word dead_done_word
        .word blank_word
        LDA #$80
        STA applesoft_errflg
        LDA #$00
        STA prompt_char
        STA picture_ptr+1
        LDA #$40
        STA dos_language_flag
        LDX #$02
        JSR old_rt_copy
        .word dead_disk_error_ptr
        .word dos_error_vector
        JSR old_rt_print
        hiasc "\x04OPEN MESSAGES\r\x04\r"
        .byte $00
        RTS
dead_blank_word:
        hiasc "        "
dead_done_word:
        hiasc "DONE    "
dead_init_tables:
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00
dead_disk_error_ptr:
        .word dead_disk_error

; the older disk-error handler: unlike the shipped one (disk_error_handler), its RTS follows
; the text directly; the shipped build put the OPEN-once flag in between
dead_disk_error:
        JSR old_rt_print
        hiasc "\rA DISK ERROR HAS OCCURED"
        .byte $00
        RTS
        .incbin "data/adventure_56EC.bin"    ; fill

; ==== shape table ====================================================================
; Applesoft shape table for the small objects (notes, matches, welcome mat, a door).
shape_table:
        .byte 6, 0
        .word shape_1-shape_table
        .word shape_2-shape_table
        .word shape_3-shape_table
        .word shape_4-shape_table
        .word shape_5-shape_table
        .word shape_6-shape_table
        .word shape_7-shape_table
; leftover memory, not used: lines here can be deleted to make room
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00
shape_1:
        .byte $3E,$24,$2D,$36,$04,$00
shape_2:
        .byte $36,$36,$0D,$18,$15,$24,$24,$4D,$39,$37,$36,$2E,$25,$38,$4C,$09
        .byte $18,$36,$36,$2D,$0D,$08,$18,$08,$58,$39,$37,$36,$2E,$6D,$24,$24
        .byte $2D,$36,$36,$77,$09,$20,$24,$AC,$0D,$18,$36,$36,$4D,$39,$27,$24
        .byte $2C,$B5,$27,$00
shape_3:
        .byte $36,$36,$2D,$20,$E4,$4D,$36,$36,$2D,$24,$24,$6F,$31,$36,$2E,$25
        .byte $24,$3C,$4D,$36,$36,$0D,$18,$08,$18,$28,$36,$77,$6E,$08,$18,$08
        .byte $18,$36,$36,$0D,$18,$15,$24,$24,$0D,$36,$36,$0D,$18,$08,$18,$28
        .byte $36,$36,$0F,$18,$68,$09,$18,$30,$2E,$25,$B4,$9A,$0A,$18,$24,$00
shape_4:
        .byte $36,$36,$36,$36,$36,$36,$36,$2D,$2D,$2D,$2D,$2D,$2D,$2D,$2D,$2D
        .byte $2D,$2D,$25,$24,$24,$24,$24,$24,$24,$3C,$3F,$3F,$3F,$3F,$3F,$3F
        .byte $3F,$3F,$3F,$3F,$B7,$31,$36,$36,$36,$36,$0D,$18,$08,$18,$08,$18
        .byte $08,$18,$A8,$36,$AE,$0D,$18,$0C,$18,$08,$18,$30,$36,$B6,$36,$6E
        .byte $24,$24,$24,$24,$2C,$2D,$36,$36,$36,$36,$3E,$6F,$09,$08,$18,$08
        .byte $18,$08,$18,$08,$18,$28,$2D,$F5,$33,$36,$36,$36,$6E,$09,$24,$24
        .byte $24,$24,$2C,$B5,$12,$B7,$92,$25,$00
shape_5:
        .byte $2D,$2D,$2D,$2D,$2D,$2D,$2D,$2D,$2D,$2D,$2D,$2D,$2D,$35,$36,$36
        .byte $36,$36,$36,$36,$3E,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F
        .byte $3F,$3F,$24,$24,$24,$24,$24,$24,$AC,$92,$92,$92,$2D,$2D,$2D,$2D
        .byte $2D,$2D,$2D,$2D,$2D,$2D,$2D,$2D,$E5,$DB,$DB,$DB,$DB,$DB,$DB,$DB
        .byte $1B,$20,$24,$24,$AC,$2A,$EC,$B0,$32,$36,$0D,$24,$24,$24,$2D,$36
        .byte $36,$36,$0F,$18,$08,$18,$4D,$08,$18,$28,$F5,$36,$36,$6E,$21,$24
        .byte $24,$2C,$B5,$92,$3A,$4C,$11,$24,$24,$24,$0D,$36,$36,$36,$0F,$18
        .byte $08,$18,$4D,$08,$18,$48,$3B,$36,$36,$36,$6D,$08,$18,$08,$18,$08
        .byte $58,$9B,$D2,$0D,$08,$18,$08,$37,$36,$35,$36,$27,$00
shape_6:
        .byte $2D,$2D,$2D,$2D,$2D,$2D,$2D,$2D,$2D,$2D,$2D,$2D,$2D,$35,$36,$36
        .byte $36,$36,$36,$36,$36,$18,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F,$3F
        .byte $3F,$3F,$3F,$24,$24,$24,$24,$24,$24,$B4,$0A,$58,$2D,$2D,$2D,$2D
        .byte $2D,$2D,$2D,$2D,$2D,$2D,$2D,$2D,$F5,$DB,$DB,$DB,$DB,$DB,$DB,$DB
        .byte $9B,$32,$36,$26,$08,$58,$0D,$18,$36,$36,$0D,$24,$24,$2D,$36,$36
        .byte $0C,$D8,$4D,$08,$18,$2D,$17,$36,$6E,$21,$24,$2C,$B5,$12,$6F,$21
        .byte $24,$B4,$29,$08,$18,$36,$36,$0D,$24,$24,$B5,$16,$0D,$25,$3C,$24
        .byte $25,$00
shape_7:
        .byte $15,$4C,$12,$59,$00,$09

; Unreachable older version of MESSLSTR's file path.
dead_read_message:
        LDA #$00
        STA floor_slot
        ASL lru_turn+1
        ROL floor_slot
        JSR old_BUMP16
        .word lru_turn+1
        .word $14
        LDY #$00
        LDA ($14),Y
        STA old_msg_offset
        INY
        LDA ($14),Y
        STA old_msg_offset+1
        JSR dead_offset_to_hex
        LDX #$04
        JSR old_rt_copy
        .word old_hex_out
        .word old_read_digits
        JSR dead_read_message_cmd
        LDA #$00
        STA $14
        LDA #$02
        STA $15
        LDY #$00
dead_read_message__print_loop:
        LDA ($14),Y
        JSR COUT
        LDA ($14),Y
        INY
        CMP #$8D
        BNE dead_read_message__print_loop
        RTS

dead_read_message_cmd:
        JSR old_rt_print
        hiasc "\x04READ MESSAGES,B$"
old_read_digits:
        .byte $00,$00,$00,$00     ; patched with the offset in hex
        hiasc "\r"
        .byte $00
        JSR GETLN1
        LDA input_buffer
        STA lru_turn+1
        LDA input_buffer+1
        STA floor_slot
        JSR old_rt_print
        hiasc "\x04\r"
        .byte $00
        LDA lru_turn+1
        STA input_buffer
        LDA floor_slot
        STA input_buffer+1
        RTS

dead_offset_to_hex:
        LDA old_msg_offset+1
        STA old_hex_in
        JSR dead_split_nibbles
        LDA old_hex_hi
        STA old_hex_out
        LDA old_hex_lo
        STA old_hex_out+1
        LDA old_msg_offset
        STA old_hex_in
        JSR dead_split_nibbles
        LDA old_hex_hi
        STA old_hex_out+2
        LDA old_hex_lo
        STA old_hex_out+3
        JSR dead_nibbles_to_ascii
        RTS

dead_split_nibbles:
        LDA old_hex_in
        STA old_hex_hi
        STA old_hex_lo
        LSR old_hex_hi
        LSR old_hex_hi
        LSR old_hex_hi
        LSR old_hex_hi
        LDA #$0F
        AND old_hex_lo
        STA old_hex_lo
        RTS

dead_nibbles_to_ascii:
        LDY #$00
dead_nibbles_to_ascii__loop:
        LDA old_hex_out,Y
        TAX
        LDA dead_hex_digits,X
        STA old_hex_out,Y
        INY
        CPY #$04
        BNE dead_nibbles_to_ascii__loop
        RTS
dead_hex_digits:
        .byte $B0,$B1,$B2,$B3,$B4,$B5,$B6,$B7,$B8,$B9,$C1,$C2,$C3,$C4,$C5

; ==== the engine =====================================================================

; Run the game logic for the command just parsed: the command rules first, then the turn
; rules.
run_rules:
        JSR run_command_rules
        JSR run_turn_rules
        RTS

; Try each command rule in order. The first one whose header and conditions match runs its
; actions and ends the search (test_rule leaves cmp_result = 1). If the table ends with no
; match, say "I DONT UNDERSTAND WHAT YOU MEAN".
run_command_rules:
        LDA command_rules_addr
        STA WORK
        STA rule_ptr
        LDA command_rules_addr+1
        STA WORK+1
        STA rule_ptr+1
        JMP run_command_rules__loop
command_rules_addr:
        .word command_rules
run_command_rules__loop:
        JSR test_rule
        LDA cmp_result
        CMP #$01
        BEQ run_command_rules__done
        JSR next_rule
        LDA cmp_result
        CMP #HV
        BNE run_command_rules__loop
        LDX #MSG_DONT_UNDERSTAND
        JSR MESSLSTR
run_command_rules__done:
        RTS

; Run every matching turn rule (match timers, darkness, the winning check), whatever happened
; to the command.
run_turn_rules:
        LDA turn_rules_addr
        STA WORK
        STA rule_ptr
        LDA turn_rules_addr+1
        STA WORK+1
        STA rule_ptr+1
        JMP run_turn_rules__loop
turn_rules_addr:
        .word turn_rules
run_turn_rules__loop:
        JSR test_rule
        JSR next_rule
        LDA cmp_result
        CMP #HV
        BNE run_turn_rules__loop
        RTS

; Test the rule at rule_ptr: room, verb and noun must match (ANY matches everything). If they
; do, WORK steps through the conditions; each condition handler continues at cond_pass or
; cond_fail, and when all have passed rule_done runs the actions.
; cmp_result: 0 = header did not match, 1 = header matched (and conditions passed unless a
; condition reset it to 0).
test_rule:
        LDA #$00
        STA cmp_result
        LDY #RULE_ROOM
        LDA (rule_ptr),Y
        CMP #ANY
        BEQ test_rule__check_verb
        CMP CURONO
        BEQ test_rule__check_verb
        JMP rule_done
test_rule__check_verb:
        LDY #RULE_VERB
        LDA (rule_ptr),Y
        CMP #ANY
        BEQ test_rule__check_noun
        CMP verb
        BEQ test_rule__check_noun
        JMP rule_done
test_rule__check_noun:
        LDY #RULE_NOUN
        LDA (rule_ptr),Y
        CMP #ANY
        BEQ test_rule__matched
        CMP noun
        BEQ test_rule__matched
        JMP rule_done
test_rule__matched:
        LDY #RULE_NCOND
        LDA (rule_ptr),Y
        STA counter
        LDA #$01
        STA cmp_result
        LDX #6
        JSR BUMPIT
        .word WORK

; Dispatch the condition at WORK through tbl_conditions, or run the actions when counter
; (conditions left) reaches 0. Condition handlers read their operands at (WORK),Y.
next_condition:
        LDA counter
        BNE next_condition__dispatch
        JMP rule_done
next_condition__dispatch:
        LDY #$00
        LDA (WORK),Y
        ASL A
        TAY
        LDA tbl_conditions,Y
        STA rt_ptr1
        INY
        LDA tbl_conditions,Y
        STA rt_ptr1+1
        JMP (rt_ptr1)
tbl_conditions:
        .word 0
        .word 0
        .word 0
        .word cond_obj_in_room
        .word 0
        .word cond_turns_gt
        .word cond_switch_eq
        .word 0
        .word 0
        .word cond_view_is
        .word cond_obj_pic_is

; Condition 3: object ARG_X is in room ARG_Y.
cond_obj_in_room:
        LDY #ARG_X
        LDA (WORK),Y
        TAX
        JSR find_object
        LDY #OROOM
        LDA (found_obj),Y
        STA cond_actual
        LDY #ARG_Y
        LDA (WORK),Y
        LDX #2
        CMP cond_actual
        BEQ cond_pass
        JMP cond_fail

; Condition 5: turns > ARG_X. Fails whenever the turn counter's high byte is set, so from turn
; 256 on it is never true.
cond_turns_gt:
        LDA turns+1
        LDX #1
        CMP #$00
.ifdef BUGFIX
        BNE cond_pass             ; bug fix: from turn 256 the count is above any N
.else
        BNE cond_fail             ; bug: from turn 256 "turn > N" is never true again
.endif
        LDY #ARG_X
        LDA (WORK),Y
        CMP turns
        BCS cond_fail
        JMP cond_pass

; Condition 6: SWITCH[ARG_X] == ARG_Y.
cond_switch_eq:
        LDX #2
        LDY #ARG_X
        LDA (WORK),Y
        TAY
        LDA SWITCH,Y
        STA cond_actual
        LDY #ARG_Y
        LDA (WORK),Y
        CMP cond_actual
        BEQ cond_pass
        JMP cond_fail

; Condition 9: the picture on screen is ARG_X (close-up views).
cond_view_is:
        LDX #1
        LDY #ARG_X
        LDA (WORK),Y
        CMP shown_picture
        BEQ cond_pass
        JMP cond_fail

; Condition 10: object ARG_X is drawn as picture ARG_Y.
cond_obj_pic_is:
        LDY #ARG_X
        LDA (WORK),Y
        TAX
        JSR find_object
        LDY #OPIC
        LDA (found_obj),Y
        STA cond_actual
        LDY #ARG_Y
        LDA (WORK),Y
        LDX #2
        CMP cond_actual
        BEQ cond_pass
        JMP cond_fail

; Condition true: step WORK past it (opcode + X operand bytes) and test the next one.
cond_pass:
        INX
        JSR BUMPIT
        .word WORK
        LDY counter
        DEY
        STY counter
        JMP next_condition

; Condition false: the rule does not run.
cond_fail:
        LDA #$00
        STA cmp_result
        JMP rule_done

; All conditions passed (cmp_result still 1): run the rule's actions.
rule_done:
        LDA #$01
        CMP cmp_result
        BEQ rule_done__run
        RTS
rule_done__run:
        JSR run_actions
        RTS

; Advance rule_ptr (and WORK) by RULE_LEN. cmp_result = HV at the end of the table, else 0.
next_rule:
        LDY #RULE_LEN
        LDA (rule_ptr),Y
        TAX
        JSR BUMPIT
        .word rule_ptr
        LDA rule_ptr
        STA WORK
        LDA rule_ptr+1
        STA WORK+1
        LDY #$00
        LDA (WORK),Y
        CMP #HV
        BEQ next_rule__at_end
        LDA #$00
        STA cmp_result
        RTS
next_rule__at_end:
        LDA #$FF
        STA cmp_result
        RTS

; found_obj = the record of object X. Walks OBJBASE by ONEXT; hitting HV is a BRK (the
; source comments it ";UH-OH, KABOOM!").
find_object:
        STX find_objectno
        LDA objbase_addr
        STA found_obj
        LDA objbase_addr+1
        STA found_obj+1
        JMP find_object__loop
objbase_addr:
        .word OBJBASE
find_object__loop:
        LDY #OBJECTNO
        LDA (found_obj),Y
        CMP find_objectno
        BEQ find_object__found
        CMP #HV
        BNE find_object__next
        BRK
find_object__next:
        LDY #ONEXT
        LDA (found_obj),Y
        TAX
        JSR BUMPIT
        .word found_obj
        JMP find_object__loop
find_object__found:
        RTS
        .incbin "data/adventure_5BB9.bin"    ; $5BB9-$5DFF fill

; The game loop. Draw first, then read and act: a change made by an action shows on the next
; turn's redraw.
main:
        JSR init_game
main__turn:
        JSR draw_room
        JSR read_command
        JSR run_rules
        JSR nothing
        LDX #1
        JSR BUMPIT
        .word turns
        JMP main__turn
        .incbin "data/adventure_5E19.bin"    ; $5E19-$60FF leftover memory, not used by the code (see NOTES.md)

; Start (or restart) a game: room 1, turn 1, switches and picture cache cleared, CUROOM at
; room 1, HPLOT colour white, the custom DOS error handler installed, MESSAGES opened (once),
; hi-res page 1 with four lines of text.
init_game:
        LDA #$01
        STA turns
        LDA #$00
        STA turns+1
        LDA #$01
        STA CURONO
        LDX #NSWITCH
        JSR rt_copy
        .word init_switches
        .word SWITCH
        LDX #NSWITCH
        JSR rt_copy
        .word init_pic_cache
        .word pic_cache
        LDA #<ROOMBASE
        STA CUROOM
        LDA #>ROOMBASE
        STA CUROOM+1
        LDX #10
        JSR BUMPIT
        .word CUROOM
        LDA #<applesoft_vars
        STA fake_vartab
        LDA #>applesoft_vars
        STA fake_vartab+1
        LDA #$00
        STA var_x
        STA var_x+1
        STA var_y
        STA var_y+1
        STA var_hcolor
        STA var_hcolor+1
        STA var_rot
        STA var_rot+1
        STA var_shape
        STA var_shape+1
        LDA #$01
        STA input_len
        LDA #$00
        STA parse_pos
        LDA #$00
        STA draw_dx
        STA draw_dy
        LDA #$7F
        STA var_hcolor
        LDA #<shape_table
        STA hgr_shape_table
        LDA #>shape_table
        STA hgr_shape_table+1
        LDX #WORDLEN
        JSR rt_copy
        .word init_blank_word
        .word blank_word
        LDX #WORDLEN
        JSR rt_copy
        .word init_done_word
        .word done_word
        LDA #$80
        STA applesoft_errflg
        LDA #$00
        STA prompt_char
        STA picture_ptr+1
        LDA #$FF
        STA applesoft_d9
        LDX #$02
        JSR rt_copy
        .word disk_error_handler_ptr
        .word dos_error_vector
        LDA messages_open
        CMP #$FF
        BEQ init_game__opened
        LDA #$FF
        STA messages_open          ; OPEN MESSAGES only on the first game
        JSR rt_print
        hiasc "\x04OPEN MESSAGES\r\x04\r"
        .byte $00
init_game__opened:
        LDA #$00
        STA LAMPSTAT
        LDA TXTCLR
        LDA MIXSET
        LDA HIRES
        JSR rt_print
        hiasc "\r\r\r\r\r"
        .byte $00
        RTS
init_blank_word:
        .byte $A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0
init_done_word:
        .byte $C4,$CF,$CE,$C5,$A0,$A0,$A0,$A0
init_pic_cache:
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00
init_switches:
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00
disk_error_handler_ptr:
        .word disk_error_handler

; Installed in dos_error_vector by init_game. Prints the message, then falls into
; messages_open (see there).
disk_error_handler:
        JSR rt_print
        hiasc "\rA DISK ERROR HAS OCCURED"
        .byte $00
; The flag byte sits between the text's terminator and the RTS, so rt_print "returns" into it:
; it executes $00 (BRK) before init_game has run and $FF (an undocumented 3-byte opcode that
; swallows the RTS) afterwards. A disk error therefore never returns cleanly. The older handler
; (dead_disk_error) had the RTS straight after the text.
messages_open:
        .byte $00                 ; $FF once MESSAGES has been OPENed (init_game)
        RTS
        .incbin "data/adventure_6234.bin"    ; $6234-$62FF leftover memory: the assembler's symbol table (see NOTES.md)

; Prompt, read a line and parse it into verb and noun numbers. The first word must be a verb
; and the second a noun; an unknown word prints "I DONT KNOW HOW TO <word> SOMETHING" (or
; "... <verb> A <noun>") by copying the words into the message text, and asks again.
; A blank second word looks up as N_NONE (eight spaces is in the noun table).
read_command:
        LDA #$00
        STA cmd_unused
        JSR print_prompt
        JSR get_line
        JSR next_word
        JSR lookup_word
        .word verb_table
        LDA word_id
        CMP #NOT_FOUND
        BEQ read_command__unknown_verb
        STA verb
        LDX #WORDLEN
        JSR rt_copy
        .word word_buf
        .word verb_word
        JSR next_word
        JSR lookup_word
        .word noun_table
        LDA word_id
        CMP #NOT_FOUND
        BEQ read_command__unknown_noun
        STA noun
        LDX #WORDLEN
        JSR rt_copy
        .word word_buf
        .word noun_word
        RTS
        .byte $60
read_command__unknown_verb:
        LDX #WORDLEN
        JSR rt_copy
        .word word_buf
        .word unknown_verb_text
        JSR rt_print
        hiasc "I DONT KNOW HOW TO "
unknown_verb_text:
        hiasc "        "
        hiasc " SOMETHING\r"
        .byte $00
        JMP read_command
read_command__unknown_noun:
        LDX #WORDLEN
        JSR rt_copy
        .word verb_word
        .word unknown_noun_verb
        LDX #WORDLEN
        JSR rt_copy
        .word word_buf
        .word unknown_noun_text
        JSR rt_print
        hiasc "I DONT KNOW HOW TO "
unknown_noun_verb:
        hiasc "        "
        hiasc " A "
unknown_noun_text:
        hiasc "        \r"
        .byte $00
        JMP read_command

; Print the separator and ENTER COMMAND.
print_prompt:
        JSR rt_print
        hiasc "--------------- ENTER COMMAND"
        .byte $00
        RTS

; Read a line into input_buffer. GETLN prints the prompt in $33, set here to '?', so the
; question mark follows ENTER COMMAND on the same line. RETURN on an empty line toggles
; between the picture (mixed mode) and a full text page, so earlier messages can be reread.
get_line:
        LDA #$BF
        STA prompt_char
        JSR GETLN
        LDA input_buffer
        CMP #HI_CR
        BEQ get_line__empty
        STX input_len
        LDA #$00
        STA parse_pos
        RTS
get_line__empty:
        LDA text_mode
        CMP #$FF
        BEQ get_line__show_picture
        LDA #$FF
        STA text_mode
        LDA TXTSET
        JMP get_line
get_line__show_picture:
        LDA #$00
        STA text_mode
        LDA TXTCLR
        LDA MIXSET
        LDA LOWSCR
        LDA HIRES
        JMP get_line

; Copy the next word of input_buffer, from parse_pos, into word_buf (blank-padded, first
; WORDLEN characters kept; the rest of a longer word is skipped). The end of the line is
; marked with INPUT_END first.
next_word:
        LDX #WORDLEN
        JSR rt_copy
        .word blank_word
        .word word_buf
        LDY input_len
        LDA #INPUT_END
        STA input_buffer,Y
        LDY parse_pos
next_word__skip_blanks:
        LDA input_buffer,Y
        CMP #INPUT_END
        BEQ next_word__done
        CMP #HI_SPACE
        BNE next_word__start_word
        INY
        JMP next_word__skip_blanks
next_word__start_word:
        LDX #$00
next_word__store_char:
        STA word_buf,X
next_word__next_char:
        INY
        INX
        LDA input_buffer,Y
        CMP #INPUT_END
        BEQ next_word__done
        CMP #HI_SPACE
        BEQ next_word__done
        CPX #WORDLEN
        BCS next_word__next_char
        JMP next_word__store_char
next_word__done:
        STY parse_pos
        RTS

; Called as  JSR lookup_word / .word table. Looks word_buf up in a word table:
;   word[WORDLEN]  count  synonym[WORDLEN] * count     count 0 = none; HV ends the table
; word_id = the group's number (1 = first group), or NOT_FOUND. Uses the inline-operand
; convention itself: rt_args fetches the table address, rt_return skips it.
lookup_word:
        JSR rt_args
        LDA #$00
        STA word_id
        LDY #$00
        LDA (rt_operands),Y
        STA WORK
        INY
        LDA (rt_operands),Y
        STA WORK+1
lookup_word__next_group:
        INC word_id
        LDX #WORDLEN
        JSR rt_compare
        .word word_buf
        LDA cmp_result
        CMP #$00
        BEQ lookup_word__done
        LDX #8
        JSR BUMPIT
        .word WORK
        LDY #$00
        LDA (WORK),Y
        CMP #HV
        BNE lookup_word__check_synonyms
        LDA #NOT_FOUND
        STA word_id
        JMP lookup_word__done
lookup_word__check_synonyms:
        CMP #$00
        BNE lookup_word__synonyms
        JSR rt_inc16
        .word WORK
        JMP lookup_word__next_group
lookup_word__synonyms:
        LDA (WORK),Y
        STA counter
        JSR rt_inc16
        .word WORK
lookup_word__next_synonym:
        LDA counter
        BEQ lookup_word__next_group
        LDX #WORDLEN
        JSR rt_compare
        .word word_buf
        LDA cmp_result
        CMP #$00
        BEQ lookup_word__done
        LDX #8
        JSR BUMPIT
        .word WORK
        DEC counter
        JMP lookup_word__next_synonym
lookup_word__done:
        LDX #2
        JSR rt_return

; $FF while get_line shows the full text page instead of the picture.
text_mode:
        .byte $00
; leftover memory, not used: lines here can be deleted to make room
        .byte $FF,$FF,$00,$00,$FF,$FF,$00,$00,$FF,$FF,$00,$00,$FF,$FF,$00,$00
        .byte $FF,$FF,$00,$00,$FF,$FF,$00,$00,$FF,$FF,$00,$00,$FF,$FF,$00,$00
        .byte $FF,$FF,$00,$00,$FF,$FF,$00,$00,$FF,$FF,$00,$00,$FF,$FF,$00,$00
        .byte $FF,$FF,$00,$00

; Run the rule's actions: AWORK = WORK (just past the conditions), actions_left =
; RULE_NACT. Each action handler (ACnn00) leaves through AC9000, which steps AWORK past it
; and dispatches the next one through tbl_actions.
run_actions:
        LDA WORK
        STA AWORK
        LDA WORK+1
        STA AWORK+1
        LDY #RULE_NACT
        LDA (rule_ptr),Y
        STA actions_left

; Dispatch the action at AWORK, or return when none are left.
next_action:
        LDA actions_left
        BEQ stop_actions
        LDA AWORK
        STA ZWORK
        LDA AWORK+1
        STA ZWORK+1
        LDY #$00
        LDA (ZWORK),Y
        ASL A
        TAY
        LDA tbl_actions,Y
        STA ZAWORK
        INY
        LDA tbl_actions,Y
        STA ZAWORK+1
        JMP (ZAWORK)

; Ends the action list early: the movement actions (ACNEWROM) and the game-ending ones leave
; through here.
stop_actions:
        RTS
tbl_actions:
        .word 0
        .word AC1100
        .word AC1200
        .word AC1300
        .word AC1400
        .word AC1500
        .word AC1600
        .word AC1700
        .word AC1800
        .word AC1900
        .word AC2000
        .word AC2100
        .word AC2200
        .word AC2300
        .word AC2400
        .word AC2500
        .word AC2600
        .word AC2700
        .word AC2800
        .word AC2900
        .word AC3000
        .word AC3100
        .word AC3200
        .word AC3300
        .word AC3400
        .word AC3500
        .word AC3600
        .word AC3700
        .word AC3800
        .word AC3900

; action 1: SWITCH[Y] += X
AC1100:
        LDY #ARG_X
        LDA (ZWORK),Y
        TAX
        LDY #ARG_Y
        LDA (ZWORK),Y
        TAY
        LDA SWITCH,Y
        CLC
        STX AWORK1
        ADC AWORK1
        STA SWITCH,Y
        LDX #2
        JMP AC9000

; action 2: SWITCH[Y] -= X
AC1200:
        LDY #ARG_X
        LDA (ZWORK),Y
        STA AWORK1
        LDY #ARG_Y
        LDA (ZWORK),Y
        TAY
        LDA SWITCH,Y
        SEC
        SBC AWORK1
        STA SWITCH,Y
        LDX #2
        JMP AC9000

; action 3: SWITCH[X] = Y
AC1300:
        LDY #ARG_X
        LDA (ZWORK),Y
        TAX
        LDY #ARG_Y
        LDA (ZWORK),Y
        STA SWITCH,X
        LDX #2
        JMP AC9000

; action 4: list objects carried
AC1400:
        LDA #<OBJBASE
        STA ZAWORK
        LDA #>OBJBASE
        STA ZAWORK+1
AC1400__loop:
        LDY #OBJECTNO
        LDA (ZAWORK),Y
        CMP #HV
        BEQ AC1400__done
        LDY #OROOM
        LDA (ZAWORK),Y
        CMP #CARRYING
        BEQ AC1400__list_it
AC1400__next:
        LDY #ONEXT
        LDA (ZAWORK),Y
        TAX
        JSR BUMPIT
        .word ZAWORK
        JMP AC1400__loop
AC1400__list_it:
        LDY #OMSG
        LDA (ZAWORK),Y
        TAX
        JSR MESSLSTR
        JMP AC1400__next
AC1400__done:
        LDX #0
        JMP AC9000

; action 5: put object X in room Y
AC1500:
        LDA #<OBJBASE
        STA ZAWORK
        LDA #>OBJBASE
        STA ZAWORK+1
        LDY #ARG_X
        LDA (ZWORK),Y
        STA AWORK1
        LDY #ARG_Y
        LDA (ZWORK),Y
        STA AWORK2
AC1500__loop:
        LDY #OBJECTNO
        LDA (ZAWORK),Y
        CMP #HV
        BNE AC1500__check_id
        BRK
AC1500__check_id:
        CMP AWORK1
        BEQ AC1500__found
        LDY #ONEXT
        LDA (ZAWORK),Y
        TAX
        JSR BUMPIT
        .word ZAWORK
        JMP AC1500__loop
AC1500__found:
        LDY #OROOM
        LDA AWORK2
        STA (ZAWORK),Y
        LDX #2
        JMP AC9000

; action 6: move to room X (current view of the room left reverts to its base view)
AC1600:
        LDY #RBASEPIC
        LDA (CUROOM),Y
        LDY #RCURPIC
        STA (CUROOM),Y
        LDA #<ROOMBASE
        STA AWORK2
        LDA #>ROOMBASE
        STA AWORK2+1
        LDY #ARG_X
        LDA (ZWORK),Y
        STA AWORK3
        STA CURONO
        LDA #$00
        STA AWORK3+1
        LDX #RTBLSIZ
        JSR MULTIPLY
        .word AWORK3
        JSR BUMP16
        .word AWORK3
        .word AWORK2
        LDA AWORK2
        STA CUROOM
        LDA AWORK2+1
        STA CUROOM+1
        LDX #1
        JMP AC9000

; action 7: show picture X in this room
AC1700:
        LDY #ARG_X
        LDA (ZWORK),Y
        LDY #RCURPIC
        STA (CUROOM),Y
        LDX #1
        JMP AC9000

; action 8: make picture X this room's permanent view
AC1800:
        LDY #ARG_X
        LDA (ZWORK),Y
        LDY #RBASEPIC
        STA (CUROOM),Y
        LDY #RCURPIC
        STA (CUROOM),Y
        LDX #1
        JMP AC9000

; action 9: print message X
AC1900:
        LDY #ARG_X
        LDA (ZWORK),Y
        TAX
        JSR MESSLSTR
        LDX #1
        JMP AC9000

; action 10: light on
AC2000:
        LDY #ON
        STY LAMPSTAT
        LDX #0
        JMP AC9000

; action 11: light off
AC2100:
        LDY #OFF
        STY LAMPSTAT
        LDX #0
        JMP AC9000

; action 12: unused (BRK)
AC2200:
        BRK

; action 13: quit
AC2300:
        LDX #MSG_GOODBYE
        JSR MESSLSTR
        JMP dos_warm_start

; action 14: unused (BRK)
AC2400:
        BRK

; action 15: save game (BSAVE SAVED GAME,A$830,L$8CF)
AC2500:
        JSR rt_print
        hiasc "\x04BSAVE SAVED GAME,A$830,L$8CF\r"
        .byte $00
        LDX #0
        JMP AC9000

; Action 16: restore game. BLOADs the save file over $0830-$10FE (variables, objects, rooms),
; empties the picture cache so blocks are reloaded, then puts back the action pointer saved
; before the load. Bug: both bytes are stored into AWORK's low byte; the high byte keeps
; the value from the save file.
AC2600:
        LDA AWORK
        STA ZAWORK
        LDA AWORK+1
        STA ZAWORK+1
        JSR rt_print
        hiasc "\x04BLOAD SAVED GAME,A$830\r"
        .byte $00
        LDX #$14
        LDA #$00
AC2600__clear_cache:
        STA pic_cache,X
        DEX
        BNE AC2600__clear_cache
        STA pic_cache
        LDA ZAWORK
        STA AWORK
        LDA ZAWORK+1
.ifdef BUGFIX
        STA AWORK+1           ; bug fix: the high byte goes to the high byte
.else
        STA AWORK             ; bug: both bytes go to the low byte
.endif
        LDX #0
        JMP AC9000

; Action 17: game over. "WOULD YOU LIKE TO PLAY AGAIN": N quits (AC2300), anything else BLOADs
; STARTUP (the initial objects and rooms), clears the screen and restarts at main.
AC2700:
        JSR rt_print
        hiasc "WOULD YOU LIKE TO PLAY AGAIN"
        .byte $00
        JSR GETLN1
        LDA input_buffer
        CMP #'N'|$80
        BEQ AC2700__quit
        LDA AWORK
        STA ZAWORK
        LDA AWORK+1
        STA ZAWORK+1
        JSR rt_print
        hiasc "\x04BLOAD STARTUP\r"
        .byte $00
        JSR hgr
        JSR rt_print
        hiasc "PRESS RETURN TO BEGIN PLAY"
        .byte $00
        JMP main
AC2700__quit:
        JMP AC2300

; action 18: put object X in room Y at (x, y)
AC2800:
        LDY #ARG_X
        LDA (ZWORK),Y
        STA AX
        LDY #ARG_Y
        LDA (ZWORK),Y
        STA AY
        LDY #ARG_3
        LDA (ZWORK),Y
        STA AX1
        LDY #ARG_4
        LDA (ZWORK),Y
        STA AY1
        LDA #<OBJBASE
        STA ZAWORK
        LDA #>OBJBASE
        STA ZAWORK+1
AC2800__loop:
        LDY #OBJECTNO
        LDA (ZAWORK),Y
        CMP AX
        BEQ AC2800__found
        LDY #ONEXT
        LDA (ZAWORK),Y
        TAX
        JSR BUMPIT
        .word ZAWORK
        JMP AC2800__loop
AC2800__found:
        LDY #OROOM
        LDA AY
        STA (ZAWORK),Y
        LDY #OXCOORD
        LDA AX1
        STA (ZAWORK),Y
        LDY #OYCOORD
        LDA AY1
        STA (ZAWORK),Y
        LDX #4
        JMP AC9000

; action 19: object Y's picture = X (OPIC only)
AC2900:
        LDY #ARG_X
        LDA (ZWORK),Y
        STA AX
        LDY #ARG_Y
        LDA (ZWORK),Y
        STA AY
        LDA #<OBJBASE
        STA ZAWORK
        LDA #>OBJBASE
        STA ZAWORK+1
AC2900__loop:
        LDY #OBJECTNO
        LDA (ZAWORK),Y
        CMP #HV
        BNE AC2900__check_id
        BRK
AC2900__check_id:
        CMP AY
        BEQ AC2900__found
        LDY #ONEXT
        LDA (ZAWORK),Y
        TAX
        JSR BUMPIT
        .word ZAWORK
        JMP AC2900__loop
AC2900__found:
        LDY #OPIC
        LDA AX
        STA (ZAWORK),Y
        LDX #2
        JMP AC9000

; action 20: switch to the permanent view for this room
AC3000:
        LDY #RBASEPIC
        LDA (CUROOM),Y
        LDY #RCURPIC
        STA (CUROOM),Y
        LDX #0
        JMP AC9000

; action 21: go north
AC3100:
        LDY #RN
        LDA (CUROOM),Y
        STA AX
        JMP ACNEWROM

; action 22: go south
AC3200:
        LDY #RS
        LDA (CUROOM),Y
        STA AX
        JMP ACNEWROM

; action 23: go east
AC3300:
        LDY #RE
        LDA (CUROOM),Y
        STA AX
        JMP ACNEWROM

; action 24: go west
AC3400:
        LDY #RW
        LDA (CUROOM),Y
        STA AX
        JMP ACNEWROM

; action 25: go up
AC3500:
        LDY #RU
        LDA (CUROOM),Y
        STA AX
        JMP ACNEWROM

; action 26: go down
AC3600:
        LDY #RD
        LDA (CUROOM),Y
        STA AX
        JMP ACNEWROM

; Move through exit AX of the current room (0 = "I CANT GO IN THAT DIRECTION"). The room
; left reverts to its permanent view. Bug: AWORK2's low byte is never set to the new room
; number before the multiply, so CUROOM is wrong until draw_room rebuilds it from CURONO at
; the start of the next turn; nothing reads it in between. Ends the action list.
ACNEWROM:
        LDA AX
        CMP #$00
        BNE ACNEWROM__move
        LDX #MSG_CANT_GO
        JSR MESSLSTR
        JMP ACNEWROM__done
ACNEWROM__move:
        LDA #$00
        STA AWORK2+1
        LDA AX
        STA CURONO
        LDX #RTBLSIZ
        LDY #RBASEPIC
        LDA (CUROOM),Y
        LDY #RCURPIC
        STA (CUROOM),Y
        JSR MULTIPLY
        .word AWORK2
        LDA #<ROOMBASE
        STA AWORK3
        LDA #>ROOMBASE
        STA AWORK3+1
        JSR BUMP16
        .word AWORK2
        .word AWORK3
        LDA AWORK3
        STA CUROOM
        LDA AWORK3+1
        STA CUROOM+1
ACNEWROM__done:
        LDX #0
        JMP stop_actions

; Action 27: take the object named by the command's noun. Only an object in this room counts.
; OFIXED -> "IT DOESNT MOVE". OMOVED objects can always be taken; an OMOVABLE one only when
; the picture on screen is one it appears in (ORPICSTA). Otherwise "I DONT SEE IT HERE".
AC3700:
        LDY noun
        STY AX
        LDA #<OBJBASE
        STA ZAWORK
        LDA #>OBJBASE
        STA ZAWORK+1
AC3700__loop:
        LDY #OBJECTNO
        LDA (ZAWORK),Y
        CMP #HV
        BEQ AC3700__not_here
        LDY #ONOUN
        LDA (ZAWORK),Y
        CMP AX
        BNE AC3700__next
        LDY #OROOM
        LDA (ZAWORK),Y
        CMP CURONO
        BNE AC3700__next
        LDY #OSTATUS
        LDA (ZAWORK),Y
        CMP #OFIXED
        BNE AC3700__not_fixed
        LDX #MSG_DOESNT_MOVE
        JSR MESSLSTR
        JMP AC3700__done
AC3700__next:
        LDY #ONEXT
        LDA (ZAWORK),Y
        TAX
        JSR BUMPIT
        .word ZAWORK
        JMP AC3700__loop
AC3700__not_fixed:
        LDY #OSTATUS
        LDA (ZAWORK),Y
        CMP #OMOVED
        BEQ AC3700__take
        LDY #RCURPIC
        LDA (CUROOM),Y
        STA AWORK2
        LDY #ORPICKT
        LDA (ZAWORK),Y
        STA AWORK3
        LDY #$0B
AC3700__check_pic:
        LDX AWORK3
        BEQ AC3700__next
        LDA (ZAWORK),Y
        CMP AWORK2
        BEQ AC3700__take
        INY
        LDX AWORK3
        DEX
        STX AWORK3
        JMP AC3700__check_pic
AC3700__take:
        LDA #CARRYING
        LDY #OROOM
        STA (ZAWORK),Y
        LDA #OMOVED
        LDY #OSTATUS
        STA (ZAWORK),Y
        JMP AC3700__done
AC3700__not_here:
        LDX #MSG_DONT_SEE_IT
        JSR MESSLSTR
AC3700__done:
        LDX #0
        JMP AC9000

; Action 28: drop the object named by the command's noun into this room, as OMOVED (drawn in
; the next floor slot). Not carried -> "I DONT UNDERSTAND WHAT YOU MEAN".
AC3800:
        LDA #<OBJBASE
        STA ZAWORK
        LDA #>OBJBASE
        STA ZAWORK+1
AC3800__loop:
        LDY #OBJECTNO
        LDA (ZAWORK),Y
        CMP #HV
        BEQ AC3800__not_carried
        LDY #ONOUN
        LDA (ZAWORK),Y
        CMP noun
        BNE AC3800__next
        LDY #OROOM
        LDA (ZAWORK),Y
        CMP #CARRYING
        BNE AC3800__next
        LDY #OROOM
        LDA CURONO
        STA (ZAWORK),Y
        LDA #OMOVED
        LDY #OSTATUS
        STA (ZAWORK),Y
        JMP AC3800__done
AC3800__next:
        LDY #ONEXT
        LDA (ZAWORK),Y
        TAX
        JSR BUMPIT
        .word ZAWORK
        JMP AC3800__loop
AC3800__not_carried:
        LDX #MSG_DONT_UNDERSTAND
        JSR MESSLSTR
AC3800__done:
        LDX #0
        JMP AC9000

; action 29: set room X's views to picture Y
AC3900:
        LDA #<ROOMBASE
        STA ZAWORK
        LDA #>ROOMBASE
        STA ZAWORK+1
        LDY #ARG_X
        LDA (ZWORK),Y
        STA AWORK2
        LDY #ARG_Y
        LDA (ZWORK),Y
        STA AWORK3
        LDA #$00
        STA AWORK2+1
        LDX #RTBLSIZ
        JSR MULTIPLY
        .word AWORK2
        JSR BUMP16
        .word AWORK2
        .word ZAWORK
        LDA AWORK3
        LDY #RBASEPIC
        STA (ZAWORK),Y
        LDY #RCURPIC
        STA (ZAWORK),Y
        LDX #2
        JMP AC9000

; Common exit of every action handler: AWORK += 1 + X (the opcode and X operand bytes),
; one fewer action left, next one.
AC9000:
        INX
        JSR BUMPIT
        .word AWORK
        LDX actions_left
        DEX
        STX actions_left
        JMP next_action
stale_basic:
        .byte $4F,$52,$3F,$22,$00,$F3,$17,$10,$27,$83,$20,$38,$31,$2C,$22,$59
        .byte $4F,$55,$20,$41,$52,$45,$20,$49,$4E,$20,$41,$20,$53,$54,$4F,$52
        .byte $41,$47,$45,$20,$52,$4F,$4F,$4D,$22,$00,$0B,$18,$1A,$27,$83,$20
        .byte $38,$32,$2C,$22,$49,$00

; ---- relocated Applesoft hi-res routines ($6A00-$6DB8) ---------------------------------

; ---- relocated Applesoft hi-res routines ($6A00-$6DB8) ---------------------------------------
; A copy of the Applesoft ROM's hi-res graphics code (HGR, HPOSN, HPLOT, HGLIN, DRAW and their
; helpers), moved into the game and changed in three ways: Applesoft's HGR.* zero-page variables
; ($E0-$EA) live at $0320-$032A instead; the HPLOT/DRAW arguments are read from the engine's own
; Applesoft-style variables at applesoft_vars (VAR_* offsets in game.inc) instead of from
; BASIC; and DRAW's scale is fixed at 1. Names follow the Applesoft routines (HPOSN,
; MOVE.UP.OR.DOWN, ...). Routines marked "not called by the game" came along with the copy.
;
; The hi-res screen: 280 x 192 pixels, 7 pixels per byte (bit 0 leftmost, bit 7 selects the
; colour group), 40 bytes per row. Rows are interleaved in memory: row y is at
;   $2000 + $400 * (y & 7) + $80 * ((y >> 3) & 7) + $28 * (y >> 6)
; so moving up or down a row means adjusting HBASL/HBASH (hbasl) rather than adding 40.
;
; HGR: show hi-res page 1 in mixed mode (four text lines at the bottom) and clear it.
hgr:
        LDA #$20
        STA hgr_page
        LDA HIRES
        LDA MIXSET
        LDA TXTCLR

; HCLR: clear the page to black (hgr_bits = 0), via BKGND.
hclr:
        LDA #$00
bkgnd:                                 ; Applesoft BKGND: fill the page with the colour in A
        STA hgr_bits
        LDA hgr_page
        STA hgr_shape_ptr+1
        LDY #$00
        STY hgr_shape_ptr
hclr__loop:
        LDA hgr_bits
        STA (hgr_shape_ptr),Y
        JSR color_shift
        INY
        BNE hclr__loop
        INC hgr_shape_ptr+1
        LDA hgr_shape_ptr+1
        AND #$1F
        BNE hclr__loop
        RTS

; Applesoft HPOSN: put the pen at (X + 256 * Y-register, A): hbasl = the row's address,
; hgr_horiz = the byte column (x / 7) and hmask = the pixel's bit (x mod 7), and hgr_bits = the
; colour pattern for that column.
hposn:
        STA hgr_y
        STX hgr_x
        STY hgr_x+1
        PHA
        AND #$C0
        STA hbasl
        LSR A
        LSR A
        ORA hbasl
        STA hbasl
        PLA
        STA hbasl+1
        ASL A
        ASL A
        ASL A
        ROL hbasl+1
        ASL A
        ROL hbasl+1
        ASL A
        ROR hbasl
        LDA hbasl+1
        AND #$1F
        ORA hgr_page
        STA hbasl+1
        TXA
        CPY #$00
        BEQ hposn__div7
        LDY #$23
        ADC #$04
hposn__div7_count:
        INY
hposn__div7:
        SBC #$07
        BCS hposn__div7_count
        STY hgr_horiz
        TAX
        LDA hgr_msktbl-$F9,X        ; X = $F9..$FF here, so this reads hgr_msktbl
        STA hmask
        TYA
        LSR A
        LDA hgr_color

; Set hgr_bits from the colour in A, shifted for an odd byte column.
hgr_set_bits:
        STA hgr_bits
        BCS color_shift
        RTS

; Applesoft HPLOT0: HPOSN then plot the point.
hplot0:                                ; (not called by the game)
        JSR hposn
hplot_here:
        LDA hgr_bits
        EOR (hbasl),Y
        AND hmask
        EOR (hbasl),Y
        STA (hbasl),Y
        RTS

; Applesoft MOVE.LEFT.OR.RIGHT: move the pen one pixel; N set = right, clear = left. Shifts
; hmask and steps hgr_horiz to the next byte (wrapping from column 0 to 39 and back).
move_left_or_right:
        BPL move_left_or_right__right
        LDA hmask
        LSR A
        BCS move_left_or_right__left_byte
        EOR #$C0
move_left_or_right__store_mask:
        STA hmask
        RTS
move_left_or_right__left_byte:
        DEY
        BPL move_left_or_right__left_edge
        LDY #$27
move_left_or_right__left_edge:
        LDA #$C0
move_left_or_right__new_byte:
        STA hmask
        STY hgr_horiz
        LDA hgr_bits

; Applesoft COLOR.SHIFT: on odd byte columns the green/violet bit patterns swap, so flip
; hgr_bits for colours that need it.
color_shift:
        ASL A
        CMP #$C0
        BPL color_shift__done
        LDA hgr_bits
        EOR #$7F
        STA hgr_bits
color_shift__done:
        RTS
move_left_or_right__right:
        LDA hmask
        ASL A
        EOR #$80
        BMI move_left_or_right__store_mask
        LDA #$81
        INY
        CPY #$28
        BCC move_left_or_right__new_byte
        LDY #$00
        BCS move_left_or_right__new_byte

; XDRAW0's plot-and-move step (the XOR version of draw_move_ud_plot). Not called by the game.
xdraw_move_ud_plot:
        CLC
        LDA hgr_dx+1
        AND #$04
        BEQ draw_move_ud__move
        LDA #$7F
        AND hmask
        AND (hbasl),Y
        BNE draw_move_ud__plot
        INC hgr_collisions
        LDA #$7F
        AND hmask
        BPL draw_move_ud__plot

; DRAW0's step: plot the point if the vector's plot bit (bit 2) is set, then move. Counts a
; collision in hgr_collisions when the pixel was already on.
draw_move_ud_plot:
        CLC

; As draw_move_ud_plot, entered for the second axis of a step.
draw_move_ud:
        LDA hgr_dx+1
        AND #$04
        BEQ draw_move_ud__move
        LDA (hbasl),Y
        EOR hgr_bits
        AND hmask
        BNE draw_move_ud__plot
        INC hgr_collisions
draw_move_ud__plot:
        EOR (hbasl),Y
        STA (hbasl),Y
draw_move_ud__move:
        LDA hgr_dx+1
        ADC hgr_quadrant
        AND #$03
        CMP #$02
        ROR A
        BCS move_left_or_right

; Applesoft MOVE.UP.OR.DOWN: move the pen one row; N clear = up, N set = down (move_down).
; Within a block of 8 rows a row is $400 bytes from the next; crossing a block or a third of
; the screen changes HBASL as well (the row layout is described at hgr).
move_up_or_down:
        BMI move_down
        CLC
        LDA hbasl+1
        BIT hgr_con_1c
        BNE move_up_or_down__up_line
        ASL hbasl
        BCS move_up_or_down__up_third
        BIT draw_move_ud__move+5                ; BIT on the constant $03 in the AND above (an Applesoft trick)
        BEQ move_up_or_down__up_block
        ADC #$1F
        SEC
        BCS move_up_or_down__up_ror
move_up_or_down__up_block:
        ADC #$23
        PHA
        LDA hbasl
        ADC #$B0
        BCS move_up_or_down__up_lo
        ADC #$F0
move_up_or_down__up_lo:
        STA hbasl
        PLA
        BCS move_up_or_down__up_ror
move_up_or_down__up_third:
        ADC #$1F
move_up_or_down__up_ror:
        ROR hbasl
move_up_or_down__up_line:
        ADC #$FC
move_up_or_down__store_hbash:
        STA hbasl+1
        RTS
        .byte $18

; Move the pen down one row.
move_down:
        LDA hbasl+1
        ADC #$04
        BIT hgr_con_1c
        BNE move_up_or_down__store_hbash
        ASL hbasl
        BCC move_down__next_third
        ADC #$E0
        CLC
        BIT move_down+3                ; BIT on the constant $04 in the ADC above (an Applesoft trick)
        BEQ move_down__ror
        LDA hbasl
        ADC #$50
        EOR #$F0
        BEQ move_down__store_lo
        EOR #$F0
move_down__store_lo:
        STA hbasl
        LDA hgr_page
        BCC move_down__ror
move_down__next_third:
        ADC #$E0
move_down__ror:
        ROR hbasl
        BCC move_up_or_down__store_hbash

; Applesoft HLINRL: a line relative to (0,0): clear the start point and fall into HGLIN.
; Not called by the game.
hlinrl:
        PHA
        LDA #$00
        STA hgr_x
        STA hgr_x+1
        STA hgr_y
        PLA

; Applesoft HGLIN: draw a line from the current point (HGR.X, HGR.Y) to (A + 256 * X, Y): a
; Bresenham-style walk of |dx| + |dy| steps, each moving one pixel horizontally or vertically
; and plotting it. Leaves the pen at the end point.
hglin:
        PHA
        SEC
        SBC hgr_x
        PHA
        TXA
        SBC hgr_x+1
        STA hgr_quadrant
        BCS hglin__dx_positive
        PLA
        EOR #$FF
        ADC #$01
        PHA
        LDA #$00
        SBC hgr_quadrant
hglin__dx_positive:
        STA hgr_dx+1
        STA hgr_err+1
        PLA
        STA hgr_dx
        STA hgr_err
        PLA
        STA hgr_x
        STX hgr_x+1
        TYA
        CLC
        SBC hgr_y
        BCC hglin__dy_set
        EOR #$FF
        ADC #$FE
hglin__dy_set:
        STA hgr_dy
        STY hgr_y
        ROR hgr_quadrant
        SEC
        SBC hgr_dx
        TAX
        LDA #$FF
        SBC hgr_dx+1
        STA hgr_count_hi
        LDY hgr_horiz
        BCS hglin__step
hglin__step_x:
        ASL A
        JSR move_left_or_right
        SEC
hglin__step:
        LDA hgr_err
        ADC hgr_dy
        STA hgr_err
        LDA hgr_err+1
        SBC #$00
hglin__plot:
        STA hgr_err+1
        LDA (hbasl),Y
        EOR hgr_bits
        AND hmask
        EOR (hbasl),Y
        STA (hbasl),Y
        INX
        BNE hglin__next
        INC hgr_count_hi
        BEQ hglin__done
hglin__next:
        LDA hgr_quadrant
        BCS hglin__step_x
        JSR move_up_or_down
        CLC
        LDA hgr_err
        ADC hgr_dx
        STA hgr_err
        LDA hgr_err+1
        ADC hgr_dx+1
hglin__always:
        BVC hglin__plot             ; always taken: V is clear here

; Applesoft MSKTBL: the bit for each of the 7 pixels in a hi-res byte (bit 7 is the colour bit)
hgr_msktbl:
        .byte $81,$82,$84,$88,$90,$A0,$C0
; a $1C constant that MOVE.UP.OR.DOWN tests with BIT (bits 2-4: the row within a block of 8)
hgr_con_1c:
        .byte $1C
; Applesoft COS table: step sizes for each rotation, indexed by DRAW0
hgr_cos_table:
        .byte $FF,$FE,$FA,$F4,$EC,$E1,$D4,$C5,$B4,$A1,$8D,$78,$61,$49,$31,$18
        .byte $FF

; Applesoft HFIND: work out HGR.X / HGR.Y from the screen position (HBASL, HMASK, HGR.HORIZ).
; Not called by the game.
hfind:
        LDA hbasl
        ASL A
        LDA hbasl+1
        AND #$03
        ROL A
        ORA hbasl
        ASL A
        ASL A
        ASL A
        STA hgr_y
        LDA hbasl+1
        LSR A
        LSR A
        AND #$07
        ORA hgr_y
        STA hgr_y
        LDA hgr_horiz
        ASL A
        ADC hgr_horiz
        ASL A
        TAX
        DEX
        LDA hmask
        AND #$7F
hfind__count_bits:
        INX
        LSR A
        BNE hfind__count_bits
        STA hgr_x+1
        TXA
        CLC
        ADC hgr_horiz
        BCC hfind__no_carry
        INC hgr_x+1
hfind__no_carry:
        STA hgr_x
hglin__done:                            ; HGLIN's exit, shared with HFIND
        RTS

; Applesoft DRAW0: draw the shape at (X, Y-register) at the pen with rotation and scale from A
; (here always 0 and 1). Each shape byte holds up to three vectors: 2 bits of direction (up,
; right, down, left) and a plot bit; a 00 byte ends the shape.
draw0:
        STX hgr_shape_ptr
        STY hgr_shape_ptr+1
        TAX
        LSR A
        LSR A
        LSR A
        LSR A
        STA hgr_quadrant
        TXA
        AND #$0F
        TAX
        LDY hgr_cos_table,X
        STY hgr_dx
        EOR #$0F
        TAX
        LDY hgr_cos_table+1,X
        INY
        STY hgr_dy
        LDY hgr_horiz
        LDX #$00
        STX hgr_collisions
        LDA (hgr_shape_ptr,X)
draw0__vector:
        STA hgr_dx+1
        LDX #$80
        STX hgr_err
        STX hgr_err+1
        LDX hgr_scale
draw0__scale_loop:
        LDA hgr_err
        SEC
        ADC hgr_dx
        STA hgr_err
        BCC draw0__step_y
        JSR draw_move_ud_plot
        CLC
draw0__step_y:
        LDA hgr_err+1
        ADC hgr_dy
        STA hgr_err+1
        BCC draw0__next_step
        JSR draw_move_ud
draw0__next_step:
        DEX
        BNE draw0__scale_loop
        LDA hgr_dx+1
        LSR A
        LSR A
        LSR A
        BNE draw0__vector
        INC hgr_shape_ptr
        BNE draw0__next_byte
        INC hgr_shape_ptr+1
draw0__next_byte:
        LDA (hgr_shape_ptr,X)
        BNE draw0__vector
        RTS

; Applesoft XDRAW0: DRAW0 with each point XORed onto the screen. Not called by the game.
xdraw0:
        STX hgr_shape_ptr
        STY hgr_shape_ptr+1
        TAX
        LSR A
        LSR A
        LSR A
        LSR A
        STA hgr_quadrant
        TXA
        AND #$0F
        TAX
        LDY hgr_cos_table,X
        STY hgr_dx
        EOR #$0F
        TAX
        LDY hgr_cos_table+1,X
        INY
        STY hgr_dy
        LDY hgr_horiz
        LDX #$00
        STX hgr_collisions
        LDA (hgr_shape_ptr,X)
xdraw0__vector:
        STA hgr_dx+1
        LDX #$80
        STX hgr_err
        STX hgr_err+1
        LDX hgr_scale
xdraw0__scale_loop:
        LDA hgr_err
        SEC
        ADC hgr_dx
        STA hgr_err
        BCC xdraw0__step_y
        JSR xdraw_move_ud_plot
        CLC
xdraw0__step_y:
        LDA hgr_err+1
        ADC hgr_dy
        STA hgr_err+1
        BCC xdraw0__next_step
        JSR draw_move_ud
xdraw0__next_step:
        DEX
        BNE xdraw0__scale_loop
        LDA hgr_dx+1
        LSR A
        LSR A
        LSR A
        BNE xdraw0__vector
        INC hgr_shape_ptr
        BNE xdraw0__next_byte
        INC hgr_shape_ptr+1
xdraw0__next_byte:
        LDA (hgr_shape_ptr,X)
        BNE xdraw0__vector
        RTS

; HFNS: read var_hcolor, var_y and var_x and position the pen there (HPOSN).
hfns:
        JSR get_hcolor
        STA hgr_color
        JSR get_var_y
        PHA
        JSR get_var_x
        PLA
        JSR hposn
        LDX hgr_saved_x
        RTS

; HPLOT var_x,var_y: position the pen and plot a point.
hplot_xy:
        JSR hfns
        JMP hplot_here

; HPLOT TO var_x,var_y: a line from the pen to the point (HGLIN).
hplot_to_xy:
        LDA hgr_horiz
        LSR A
        JSR get_hcolor
        JSR hgr_set_bits
        JSR get_var_x
        TXA
        PHA
        TYA
        TAX
        JSR get_var_y
        TAY
        PLA
        JSR hglin
        LDX hgr_saved_x
        RTS

; HCOLOR then BKGND: fill the screen with the colour. Not called by the game.
hcolor_bkgnd:
        JSR get_hcolor
        JMP bkgnd

; DRAW var_shape AT var_x,var_y.
draw_shape:
        JSR hfns
        JSR find_shape
        JSR draw0
        LDX hgr_saved_x
        RTS

; XDRAW var_shape AT var_x,var_y. Not called by the game.
xdraw_shape:
        JSR hfns
        JSR find_shape
        JSR xdraw0
        LDX hgr_saved_x
        RTS

; Point hgr_shape_ptr at shape var_shape (1..count) in the shape table. The Applesoft code read
; SCALE= here; this copy loads 1 instead (LDA #$01 / NOP).
find_shape:
        STX hgr_saved_x
        LDY #$32                   ; SCALE's offset, left over: the JSR get_var that used it
        LDA #$01                   ; became LDA #$01 / NOP, so the scale is always 1
        NOP
        STA hgr_scale
        LDY #VAR_ROT
        JSR get_var
        PHA
        LDA hgr_shape_table
        STA hgr_shape_ptr
        LDA hgr_shape_table+1
        STA hgr_shape_ptr+1
        LDY #VAR_SHAPE
        JSR get_var
        BEQ quantity_error
        LDX #0
        CMP (hgr_shape_ptr,X)
        BEQ find_shape__in_range
        BCS quantity_error
find_shape__in_range:
        ASL A
        BCC find_shape__no_carry
        INC hgr_shape_ptr+1
        CLC
find_shape__no_carry:
        TAY
        LDA (hgr_shape_ptr),Y
        ADC hgr_shape_ptr
        TAX
        INY
        LDA (hgr_shape_ptr),Y
        ADC hgr_shape_ptr+1
        NOP
        TAY
        PLA
        RTS

; A = var_hcolor (an error unless < 256).
get_hcolor:
        LDY #VAR_HCOLOR

; A = the low byte of the variable whose high byte is at applesoft_vars + Y; a non-zero high
; byte is an error.
get_var:
        LDA (fake_vartab),Y
        BNE quantity_error
        DEY
        LDA (fake_vartab),Y
get_var__done:
        RTS

; X (low) and Y-register (high) = var_x; an error unless < 280.
get_var_x:
        STX hgr_saved_x
        LDY #VAR_X
        LDA (fake_vartab),Y
        TAX
        INY
        LDA (fake_vartab),Y
        TAY
        CPX #$18
        SBC #$01
        BCC get_var__done

; Bad argument: Applesoft's ILLEGAL QUANTITY error in ROM.
quantity_error:
        JMP applesoft_error

; A = var_y; an error unless < 192.
get_var_y:
        LDY #VAR_Y_HI
        JSR get_var
        CMP #$C0
        BCS quantity_error
        RTS
; leftover memory, not used: lines here can be deleted to make room
        .byte $FF,$00,$00,$FF,$FF,$00,$00,$FF,$FF,$00,$00,$FF,$FF,$00,$00,$FF
        .byte $FF,$00,$00,$FF,$FF,$00,$00,$FF,$FF,$00,$00,$FF,$FF,$00,$00,$FF
        .byte $FF,$00,$00,$FF,$FF,$00,$00,$FF,$FF,$00,$00,$FF,$FF,$00,$00,$FF
        .byte $FF,$00,$00,$FF,$FF,$00,$00,$FF,$FF,$00,$00,$FF,$FF,$00,$00,$FF
        .byte $FF,$00,$00,$FF,$FF,$00,$00

; Called every turn from main; does nothing.
nothing:
        RTS
        .incbin "data/adventure_6E01.bin"    ; $6E01-$6FFF fill

; Draw the objects in the current room. An OMOVED object (taken and dropped) goes in the next
; floor slot, and only in the room's permanent view. Any other object is drawn at its own
; position when the picture on screen is in its ORPICSTA list. OFIXED objects (the people)
; are drawn that way too.
draw_objects:
        LDA #$00
        STA floor_slot
        LDA #<OBJBASE
        STA ZWORK
        LDA #>OBJBASE
        STA ZWORK+1
draw_objects__loop:
        LDY #OBJECTNO
        LDA (ZWORK),Y
        CMP #HV
        BNE draw_objects__check_room
        JMP draw_objects__done
draw_objects__check_room:
        LDY #OROOM
        LDA (ZWORK),Y
        CMP CURONO
        BEQ draw_objects__in_room
draw_objects__next:
        LDY #ONEXT
        LDA (ZWORK),Y
        TAX
        JSR BUMPIT
        .word ZWORK
        JMP draw_objects__loop
draw_objects__in_room:
        LDY #OSTATUS
        LDA (ZWORK),Y
        CMP #OMOVED
        BEQ draw_objects__moved
        LDY #ORPICKT
        LDA (ZWORK),Y
        STA counter
draw_objects__check_pic:
        LDA counter
        BEQ draw_objects__next
        LDY #$0B
        CLC
        DEY
        TYA
        ADC counter
        TAY
        LDA (ZWORK),Y
        CMP shown_picture
        BEQ draw_objects__visible
        LDY counter
        DEY
        STY counter
        JMP draw_objects__check_pic
draw_objects__visible:
        JSR draw_object_in_place
        JMP draw_objects__next
draw_objects__moved:
        LDY #RBASEPIC
        LDA (CUROOM),Y
        LDY #RCURPIC
        CMP (CUROOM),Y
        BNE draw_objects__next
        JSR draw_object_on_floor
        JMP draw_objects__next

; Draw the object at ZWORK at its OXCOORD/OYCOORD.
draw_object_in_place:
        LDY #OXCOORD
        LDA (ZWORK),Y
        STA draw_dx
        LDY #OYCOORD
        LDA (ZWORK),Y
        STA draw_dy
        LDY #OPIC
        LDA (ZWORK),Y
        TAX
        JSR draw_object
        LDA #$00
        STA draw_dx
        STA draw_dy
        RTS

; dropped object: next floor_slots position
draw_object_on_floor:
        LDA floor_slot
        ASL A
        TAY
        LDA floor_slots,Y
        STA draw_dx
        INY
        LDA floor_slots,Y
        STA draw_dy
        LDY #OPIC
        LDA (ZWORK),Y
        TAX
        JSR draw_object
        LDA #$00
        STA draw_dx
        STA draw_dy
        LDX floor_slot
        INX
        STX floor_slot
        RTS

; Draw picture or shape X offset by draw_dx/draw_dy: a shape (OSHAPE = 1) with the relocated
; DRAW, otherwise the vector picture through draw_picture. shown_picture is saved and restored
; around it, because draw_picture draws shown_picture.
draw_object:
        LDY shown_picture
        STY saved_picture
        STX shown_picture
        LDY #OSHAPE
        LDA (ZWORK),Y
        CMP #$01
        BEQ draw_object__shape
        LDA ZWORK
        STA saved_object_ptr
        LDA ZWORK+1
        STA saved_object_ptr+1
        JSR draw_picture
        LDA saved_object_ptr
        STA ZWORK
        LDA saved_object_ptr+1
        STA ZWORK+1
        LDX saved_picture
        STX shown_picture
        RTS
draw_object__shape:
        STX var_shape
        LDA draw_dx
        STA var_x
        LDA draw_dy
        STA var_y
        JSR draw_shape
        LDX saved_picture
        STX shown_picture
        RTS
draw_objects__done:
        RTS
floor_slots:
        .byte $60,$70,$40,$70,$80,$70,$20,$70,$A0,$70,$00,$70,$C0,$70,$00,$50
        .byte $20,$50,$40,$50,$60,$50,$80,$50,$A0,$50,$C0,$50,$00,$30,$20,$30
        .byte $40,$30,$60,$30,$80,$30,$A0,$30,$C0,$30
saved_picture:
        .byte $00
        .incbin "data/adventure_712A.bin"    ; $712A-$71FF fill

; picture_ptr = the start of picture X: look up its (block, offset) in picture_directory
; (PICDIR + 3 * X) and make sure the block is in the cache.
load_picture:
        LDA #$00
        STA picdir_index+1
        LDA #$03
        STA picdir_index
        LDA #<picture_directory
        STA ZWORK
        LDA #>picture_directory
        STA ZWORK+1
        JSR MULTIPLY
        .word picdir_index
        JSR BUMP16
        .word picdir_index
        .word ZWORK
        LDY #$00
        LDA (ZWORK),Y
        STA pic_block
        LDY #$01
        LDA (ZWORK),Y
        STA pic_offset
        INY
        LDA (ZWORK),Y
        STA pic_offset+1
        JSR find_cached_block
        JSR BUMP16
        .word pic_offset
        .word ZWORK
        RTS

; Cache lookup, then picture_ptr = slot buffer + pic_offset.
find_cached_block:
        JSR cache_lookup
        JSR BUMP16
        .word pic_offset
        .word ZWORK
        LDA ZWORK
        STA picture_ptr
        LDA ZWORK+1
        STA picture_ptr+1
        RTS

; Find pic_block in the five cache slots. A hit records the current turn in the slot; a miss
; evicts the least recently used slot and loads the block into it.
cache_lookup:
        LDA #$00
        STA counter
        LDA #<pic_cache
        STA ZWORK
        LDA #>pic_cache
        STA ZWORK+1
cache_lookup__loop:
        LDA counter
        CMP #CACHE_SLOTS
        BEQ cache_lookup__miss
        LDY #$02
        LDA (ZWORK),Y
        CMP pic_block
        BEQ cache_lookup__hit
        LDX #4
        JSR BUMPIT
        .word ZWORK
        LDY counter
        INY
        STY counter
        JMP cache_lookup__loop
cache_lookup__hit:
        LDY #$00
        LDA turns
        STA (ZWORK),Y
        LDA turns+1
        INY
        STA (ZWORK),Y
        LDA counter
        ASL A
        TAY
        LDA cache_slots,Y
        STA ZWORK
        INY
        LDA cache_slots,Y
        STA ZWORK+1
        JMP cache_lookup__done
cache_lookup__miss:
        JSR cache_choose_victim
        JSR cache_load_block
        JMP cache_lookup__done
cache_lookup__done:
        RTS

; Pick the slot with the oldest turn (cache_victim, ZWORK = its buffer).
cache_choose_victim:
        LDA #$FF
        STA lru_turn
        STA lru_turn+1
        LDY #$00
        LDA #$00
        STA counter
cache_choose_victim__loop:
        LDA pic_cache+1,Y
        CMP lru_turn+1
        BCC cache_choose_victim__older
        BEQ cache_choose_victim__check_lo
        JMP cache_choose_victim__next
cache_choose_victim__check_lo:
        LDA pic_cache,Y
        CMP lru_turn
        BCC cache_choose_victim__older
        JMP cache_choose_victim__next
cache_choose_victim__older:
        LDA pic_cache,Y
        STA lru_turn
        LDA pic_cache+1,Y
        STA lru_turn+1
        STY rt_temp
        TYA
        CLC
        ROR A
        TAY
        LDA cache_slots,Y
        STA ZWORK
        INY
        LDA cache_slots,Y
        STA ZWORK+1
        LDY rt_temp
        LDA counter
        STA cache_victim
        JMP cache_choose_victim__next
cache_choose_victim__next:
        INY
        INY
        INY
        INY
        LDX counter
        INX
        STX counter
        TXA
        CMP #CACHE_SLOTS
        BNE cache_choose_victim__loop
        RTS

; Load BLOCKn into the victim slot by patching the digits of the DOS command below and
; printing it, then record the block and the turn in the slot.
cache_load_block:
        LDA pic_block
        ASL A
        TAY
        LDA block_num_text,Y
        STA bload_block_digits     ; patch the BLOAD command below
        INY
        LDA block_num_text,Y
        STA bload_block_digits+1   ; patch the BLOAD command below
        LDA cache_victim
        ASL A
        ASL A
        TAY
        LDA cache_addr_text,Y
        STA bload_addr_digits      ; patch the BLOAD command below
        INY
        LDA cache_addr_text,Y
        STA bload_addr_digits+1    ; patch the BLOAD command below
        INY
        LDA cache_addr_text,Y
        STA bload_addr_digits+2    ; patch the BLOAD command below
        INY
        LDA cache_addr_text,Y
        STA bload_addr_digits+3    ; patch the BLOAD command below
cache_load_block__bload:
        JSR rt_print
        hiasc "\x04BLOAD BLOCK"
bload_block_digits:
        .byte $00,$00             ; patched: block number
        hiasc ",A$"
bload_addr_digits:
        .byte $00,$00,$00,$00     ; patched: cache slot address
        hiasc "\r"
        .byte $00
        LDA cache_victim
        ASL A
        ASL A
        TAY
        LDA turns
        STA pic_cache,Y
        INY
        LDA turns+1
        STA pic_cache,Y
        INY
        LDA pic_block
        STA pic_cache,Y
        RTS
cache_addr_text:
        .byte $B7,$C4,$B0,$B0,$B8,$B2,$B0,$B0,$B8,$B7,$B0,$B0,$B8,$C3,$B0,$B0
        .byte $B9,$B1,$B0,$B0
block_num_text:
        .byte $B0,$A0,$B1,$A0,$B2,$A0,$B3,$A0,$B4,$A0,$B5,$A0,$B6,$A0,$B7,$A0
        .byte $B8,$A0,$B9,$A0,$B1,$B0,$B1,$B1,$B1,$B2,$B1,$B3,$B1,$B4,$B1,$B5
        .byte $B1,$B6,$B1,$B7,$B1,$B8,$B1,$B9,$B2,$B0
cache_slots:
        .byte $00,$7D,$00,$82,$00,$87,$00,$8C,$00,$91
cache_victim:
        .byte $00
; leftover memory, not used: lines here can be deleted to make room
        .byte $00,$01,$00,$0A,$00,$0E,$00,$0D,$00,$09,$00,$0F,$00,$0B,$00,$0F
        .byte $00,$11,$00,$04,$00,$00,$FF,$FF,$00,$00,$FF,$FF,$00,$00,$FF,$FF
        .byte $00,$00,$FF,$FF,$00,$00,$FF,$FF,$00,$00,$FF,$FF,$00,$00,$FF,$FF
        .byte $00,$00,$FF,$FF,$00,$00,$FF,$FF,$00,$00,$FF,$FF,$00,$00,$FF,$FF
        .byte $00,$00,$FF,$FF,$00,$00,$FF,$FF,$00,$00,$FF,$FF,$00,$00,$FF,$FF
        .byte $00,$00

; Print message X. Four short ones are built in; the rest are read from the MESSAGES file:
; message_index gives the byte offset, read_message_line READs that line into input_buffer,
; word_wrap breaks it at 39 columns. Afterwards a short pause unless msg_no_delay is $FF
; (room descriptions).
MESSLSTR:
        STX scratch_word
        CPX #MSG_CANT_GO
        BNE MESSLSTR__try_not_carrying
        JSR rt_print
        hiasc "I CANT GO IN THAT DIRECTION\r"
        .byte $00
        JMP MESSLSTR__done
MESSLSTR__try_not_carrying:
        CPX #MSG_NOT_CARRYING
        BNE MESSLSTR__try_dont_understand
        JSR rt_print
        hiasc "IM NOT CARRYING THAT\r"
        .byte $00
        JMP MESSLSTR__done
MESSLSTR__try_dont_understand:
        CPX #MSG_DONT_UNDERSTAND
        BNE MESSLSTR__try_getting_dark
        JSR rt_print
        hiasc "I DONT UNDERSTAND WHAT YOU MEAN\r"
        .byte $00
        JMP MESSLSTR__done
MESSLSTR__try_getting_dark:
        CPX #MSG_GETTING_DARK
        BNE MESSLSTR__from_file
        JSR rt_print
        hiasc "IT IS GETTING DARK\r"
        .byte $00
        JMP MESSLSTR__done
MESSLSTR__from_file:
        LDA message_index_addr
        STA ZWORK
        LDA message_index_addr+1
        STA ZWORK+1
        JMP MESSLSTR__index
message_index_addr:
        .word message_index
MESSLSTR__index:
        LDA #$00
        STA scratch_word+1
        ASL scratch_word
        ROL scratch_word+1
        JSR BUMP16
        .word scratch_word
        .word ZWORK
        LDY #$00
        LDA (ZWORK),Y
        STA msg_offset
        INY
        LDA (ZWORK),Y
        STA msg_offset+1
        JSR offset_to_hex
        LDX #$04
        JSR rt_copy
        .word hex_out
        .word read_offset_digits
        JSR read_message_line
        LDA #<input_buffer
        STA ZWORK
        LDA #>input_buffer
        STA ZWORK+1
        JSR word_wrap
        LDY #$00
MESSLSTR__print_loop:
        LDA (ZWORK),Y
        CMP #$00
        BNE MESSLSTR__put_char
        LDA #HI_CR
MESSLSTR__put_char:
        JSR COUT
        LDA (ZWORK),Y
        INY
        CMP #$00
        BNE MESSLSTR__print_loop
        LDA msg_no_delay
        CMP #$FF
        BEQ MESSLSTR__done
        LDY #$0E
MESSLSTR__pause:
        DEY
        BEQ MESSLSTR__done
        LDA #$FF
        JSR WAIT
        JMP MESSLSTR__pause
MESSLSTR__done:
        RTS

; READ MESSAGES,B$xxxx (offset patched in by MESSLSTR) and let DOS read one line into
; input_buffer via GETLN1. The first two bytes of the line are saved around the CTRL-D that
; ends the READ, because printing it disturbs them.
read_message_line:
        JSR rt_print
        hiasc "\x04READ MESSAGES,B$"
read_offset_digits:
        .byte $00,$00,$00,$00     ; patched: byte offset of the message in hex
        hiasc "\r"
        .byte $00
        JSR GETLN1
        LDA input_buffer
        STA scratch_word
        LDA input_buffer+1
        STA scratch_word+1
        JSR rt_print
        hiasc "\x04\r"
        .byte $00
        LDA scratch_word
        STA input_buffer
        LDA scratch_word+1
        STA input_buffer+1
        RTS

; msg_offset -> four ASCII hex digits in hex_out.
offset_to_hex:
        LDA msg_offset+1
        STA hex_in
        JSR split_nibbles
        LDA hex_hi
        STA hex_out
        LDA hex_lo
        STA hex_out+1
        LDA msg_offset
        STA hex_in
        JSR split_nibbles
        LDA hex_hi
        STA hex_out+2
        LDA hex_lo
        STA hex_out+3
        JSR nibbles_to_ascii
        RTS

; hex_in -> hex_hi (high nibble), hex_lo (low nibble).
split_nibbles:
        LDA hex_in
        STA hex_hi
        STA hex_lo
        LSR hex_hi
        LSR hex_hi
        LSR hex_hi
        LSR hex_hi
        LDA #$0F
        AND hex_lo
        STA hex_lo
        RTS

; Map the four nibbles in hex_out to ASCII digits.
nibbles_to_ascii:
        LDY #$00
nibbles_to_ascii__loop:
        LDA hex_out,Y
        TAX
        LDA hex_digits,X
        STA hex_out,Y
        INY
        CPY #$04
        BNE nibbles_to_ascii__loop
        RTS

; Break the $8D-terminated line at ZWORK into lines of at most 39 columns at spaces, and
; replace the final $8D with $00.
word_wrap:
        LDY #$00
        LDA #39
        STA scratch_word
word_wrap__scan:
        LDA (ZWORK),Y
        CMP #HI_CR
        BEQ word_wrap__done
        CPY scratch_word
        BEQ word_wrap__at_margin
word_wrap__next_char:
        INY
        JMP word_wrap__scan
word_wrap__at_margin:
        LDA (ZWORK),Y
        CMP #HI_SPACE
        BEQ word_wrap__break_line
word_wrap__back_to_space:
        DEY
        LDA (ZWORK),Y
        CMP #HI_SPACE
        BNE word_wrap__back_to_space
word_wrap__break_line:
        LDA #HI_CR
        STA (ZWORK),Y
        SEC
        TYA
        ADC scratch_word
        STA scratch_word
        JMP word_wrap__next_char
word_wrap__done:
        LDA #$00
        STA (ZWORK),Y
        RTS
hex_digits:
        .byte $B0,$B1,$B2,$B3,$B4,$B5,$B6,$B7,$B8,$B9,$C1,$C2,$C3,$C4,$C5,$C6
hex_in:
        .byte $00
hex_out:
        .byte $00,$00,$00,$00
hex_hi:
        .byte $00
hex_lo:
        .byte $00
        .byte $00,$00
msg_offset:
        .byte $1A,$B4
; leftover memory, not used: lines here can be deleted to make room
        .byte $FF,$FF,$00,$00,$FF,$FF,$00,$00,$FF,$FF,$00,$00,$FF,$FF,$00,$00

; ---- the macro library ---------------------------------------------------------------------
; A jump table; each entry takes its operands inline after the JSR (see NOTES.md).
rt_copy:
        JMP rt_copy_body

; word at .word addr += X
BUMPIT:
        JMP BUMPIT_body

; word at .word dst += word at .word src
BUMP16:
        JMP BUMP16_body

; compare X bytes at (WORK) with .word addr; cmp_result = 0 if equal
rt_compare:
        JMP rt_compare_body

; rt_operands = the caller's inline operands
rt_args:
        JMP rt_args_body

; return to the caller's caller skipping X inline operand bytes
rt_return:
        JMP rt_return_body

; word at .word addr += 1
rt_inc16:
        JMP rt_inc16_body

; print the inline $00-terminated text
rt_print:
        JMP rt_print_body

; mul_result = word at .word addr * X
MULTIPLY:
        JMP MULTIPLY_body
; leftover memory, not used: lines here can be deleted to make room
        .byte $C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$A0,$A0,$A0,$A0,$A0,$A0,$A0,$A0
        .byte $A0

; rt_args: the routine that called it was itself called with inline operands; point
; rt_operands at them (its caller's return address + 1).
rt_args_body:
        PLA
        STA rt_ptr1
        PLA
        STA rt_ptr1+1
        PLA
        STA rt_operands
        PLA
        STA rt_operands+1
        PHA
        LDA rt_operands
        PHA
        LDA rt_ptr1+1
        PHA
        LDA rt_ptr1
        PHA
        LDA rt_operands
        CLC
        ADC #$01
        STA rt_operands
        LDA rt_operands+1
        ADC #$00
        STA rt_operands+1
        RTS

; rt_return: return from the routine that called it to that routine's caller, skipping X
; inline operand bytes. Never returns to its own caller.
rt_return_body:
        PLA
        PLA
        PLA
        CLC
        STX rt_ptr1
        ADC rt_ptr1
        STA rt_ptr1
        PLA
        ADC #$00
        STA rt_ptr1+1
        LDA rt_ptr1+1
        PHA
        LDA rt_ptr1
        PHA
        RTS

; rt_print: print the inline text up to $00 with COUT, then skip it.
rt_print_body:
        JSR rt_args
        LDY #$00
rt_print_body__loop:
        LDA (rt_operands),Y
        INY
        CMP #$00
        BEQ rt_print_body__done
        JSR COUT
        JMP rt_print_body__loop
rt_print_body__done:
        TYA
        TAX
        JSR rt_return

; rt_copy: copy X bytes from src to dst (copies from the end down).
rt_copy_body:
        JSR rt_args
        LDY #$00
        LDA (rt_operands),Y
        STA rt_ptr1
        INY
        LDA (rt_operands),Y
        STA rt_ptr1+1
        INY
        LDA (rt_operands),Y
        STA rt_ptr2
        INY
        LDA (rt_operands),Y
        STA rt_ptr2+1
        TXA
        TAY
        DEY
rt_copy_body__loop:
        LDA (rt_ptr1),Y
        STA (rt_ptr2),Y
        DEY
        BNE rt_copy_body__loop
        LDA (rt_ptr1),Y
        STA (rt_ptr2),Y
        LDX #4
        JSR rt_return

; BUMPIT: add X to the word at addr.
BUMPIT_body:
        STX rt_temp
        JSR rt_args
        LDY #$00
        LDA (rt_operands),Y
        STA rt_ptr2
        INY
        LDA (rt_operands),Y
        STA rt_ptr2+1
        LDY #$00
        LDA (rt_ptr2),Y
        CLC
        ADC rt_temp
        STA (rt_ptr2),Y
        INY
        LDA (rt_ptr2),Y
        ADC #$00
        STA (rt_ptr2),Y
        LDX #2
        JSR rt_return

; rt_inc16: add 1 to the word at addr.
rt_inc16_body:
        JSR rt_args
        LDY #$00
        LDA (rt_operands),Y
        STA rt_ptr2
        INY
        LDA (rt_operands),Y
        STA rt_ptr2+1
        LDY #$00
        LDA (rt_ptr2),Y
        CLC
        ADC #$01
        STA (rt_ptr2),Y
        INY
        LDA (rt_ptr2),Y
        ADC #$00
        STA (rt_ptr2),Y
        LDX #2
        JSR rt_return

; rt_compare: compare X bytes at (WORK) with addr; cmp_result = 0 if equal, 1 if not.
rt_compare_body:
        STX rt_temp
        JSR rt_args
        LDY #$00
        LDA (rt_operands),Y
        STA rt_ptr2
        INY
        LDA (rt_operands),Y
        STA rt_ptr2+1
        LDA WORK
        STA rt_ptr1
        LDA WORK+1
        STA rt_ptr1+1
        LDY #$00
rt_compare_body__loop:
        LDA (rt_ptr1),Y
        CMP (rt_ptr2),Y
        BNE rt_compare_body__differ
        INY
        DEX
        TXA
        BEQ rt_compare_body__equal
        JMP rt_compare_body__loop
rt_compare_body__differ:
        LDA #$01
        STA cmp_result
        JMP rt_compare_body__done
rt_compare_body__equal:
        LDA #$00
        STA cmp_result
rt_compare_body__done:
        LDX #2
        JSR rt_return

; BUMP16: word at dst += word at src.
BUMP16_body:
        JSR rt_args
        LDY #$00
        LDA (rt_operands),Y
        STA rt_ptr1
        INY
        LDA (rt_operands),Y
        STA rt_ptr1+1
        INY
        LDA (rt_operands),Y
        STA rt_ptr2
        INY
        LDA (rt_operands),Y
        STA rt_ptr2+1
        CLC
        LDY #$00
        LDA (rt_ptr1),Y
        ADC (rt_ptr2),Y
        STA (rt_ptr2),Y
        INY
        LDA (rt_ptr1),Y
        ADC (rt_ptr2),Y
        STA (rt_ptr2),Y
        LDX #4
        JSR rt_return

; MULTIPLY: the word at addr *= X (8-step shift and add through mul_result).
MULTIPLY_body:
        STX mul_count
        JSR rt_args
        LDY #$00
        LDA (rt_operands),Y
        STA rt_ptr1
        STA mul_dest
        INY
        LDA (rt_operands),Y
        STA rt_ptr1+1
        STA mul_dest+1
        LDY #$00
        LDA (rt_ptr1),Y
        STA mul_multiplicand
        INY
        LDA (rt_ptr1),Y
        STA mul_multiplicand+1
        LDY #$00
        LDA #$00
        STA mul_carry
        LDX #$08
        STX scratch_word
        LDA #$00
        STA mul_result
        STA mul_result+1
MULTIPLY_body__loop:
        LDA scratch_word
        BEQ MULTIPLY_body__done
        LSR mul_count
        BCC MULTIPLY_body__no_add
        JSR BUMP16
        .word mul_multiplicand
        .word mul_result
MULTIPLY_body__no_add:
        ASL mul_multiplicand
        ROL mul_multiplicand+1
        LDY scratch_word
        DEY
        STY scratch_word
        JMP MULTIPLY_body__loop
MULTIPLY_body__done:
        LDA mul_dest
        STA rt_ptr1
        LDA mul_dest+1
        STA rt_ptr1+1
        LDA mul_result
        LDY #$00
        STA (rt_ptr1),Y
        INY
        LDA mul_result+1
        STA (rt_ptr1),Y
        LDX #2
        JSR rt_return
        .incbin "data/adventure_77CC.bin"    ; $77CC-$78FF fill

; Redraw the room: CUROOM from CURONO, clear the screen, and if the room is lit (LAMPSTAT =
; ON) draw its current picture and the objects. Then print the description without the usual
; pause.
draw_room:
        JSR set_curoom
        LDY #RCURPIC
        LDA (CUROOM),Y
        STA shown_picture
        JSR hgr
        LDA LAMPSTAT
        CMP #$00
        BNE draw_room__describe
        JSR draw_picture
        JSR draw_objects
draw_room__describe:
        LDY #RMSG
        LDA (CUROOM),Y
        TAX
        LDA #$FF
        STA msg_no_delay
        JSR MESSLSTR
        LDA #$00
        STA msg_no_delay
        RTS

; CUROOM = ROOMBASE + CURONO * RTBLSIZ.
set_curoom:
        LDA #$00
        STA room_offset+1
        LDA CURONO
        STA room_offset
        JMP set_curoom__compute
roombase_addr:
        .word ROOMBASE
set_curoom__compute:
        LDX #RTBLSIZ
        JSR MULTIPLY
        .word room_offset
        LDA roombase_addr
        STA CUROOM
        LDA roombase_addr+1
        STA CUROOM+1
        JSR BUMP16
        .word room_offset
        .word CUROOM
        RTS
stale_hglin_copy:
        .incbin "data/stale_hglin_copy.bin"    ; $7956-$79FF 

; Draw shown_picture: a stream of (x, y) pairs, each a line from the previous point, except
; that 00 00 makes the next point start a new line and FF FF ends the picture. Points are
; offset by draw_dx/draw_dy and clamped to MAX_X / MAX_Y.
draw_picture:
        LDX shown_picture
        JSR load_picture
draw_picture__next_point:
        LDY #$00
        LDA (picture_ptr),Y
        CMP #PIC_END
        BNE draw_picture__check_newline
        INY
        LDA (picture_ptr),Y
        CMP #PIC_END
        BEQ draw_picture__done
        DEY
        LDA (picture_ptr),Y
draw_picture__check_newline:
        CMP #PIC_NEWLINE
        BNE draw_picture__point
        INY
        LDA (picture_ptr),Y
        CMP #PIC_NEWLINE
        BNE draw_picture__reload_x
        LDA #$01
        STA pen_up
        LDX #2
        JSR BUMPIT
        .word picture_ptr
        JMP draw_picture__next_point
draw_picture__reload_x:
        DEY
        LDA (picture_ptr),Y
draw_picture__point:
        CLC
        ADC draw_dx
        CMP #MAX_X
        BCC draw_picture__x_ok
        LDA #MAX_X
draw_picture__x_ok:
        STA var_x
        INY
        LDA (picture_ptr),Y
        CLC
        ADC draw_dy
        CMP #MAX_Y
        BCC draw_picture__y_ok
        LDA #MAX_Y
draw_picture__y_ok:
        STA var_y
        LDA pen_up
        CMP #0
        BEQ draw_picture__line_to
        JSR hplot_xy
        LDA #$00
        STA pen_up
        JMP draw_picture__advance
draw_picture__line_to:
        JSR hplot_to_xy
draw_picture__advance:
        LDX #2
        JSR BUMPIT
        .word picture_ptr
        JMP draw_picture__next_point
draw_picture__done:
        RTS

; ---- end of ADVENTURE ------------------------------------------------------------------------
; Everything after the hi-res page is free to move: the fill below shrinks as the code and data
; above grow, and the file always ends at $7CFF, below the picture cache.
        .assert * <= CACHE_START, error, "ADVENTURE has grown into the picture cache at $7D00: delete leftover memory or dead code"
fill_to_cache:                         ; up to the picture cache (shrinks as anything after $2000 grows)
        incbin_upto "data/adventure_7A72.bin", 654, CACHE_START    ; fill

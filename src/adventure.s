; ADVENTURE - Hi-Res Adventure #1: Mystery House (On-Line Systems, 1980)
;
; The game engine and its database. DOS BRUNs this file at $0800. Assemble with
; tools/asm6502.py; build.sh checks the result against the original byte for byte.
;
; Memory map (all inside this file unless noted)
;   $0800  start, then the engine's variables (applesoft_vars, room_no, SWITCH, ...)
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
AWORK                    = $0077    ; rule/parser cursor (word table walk; current condition)
rule_ptr                 = $0079    ; start of the rule being tested
counter                  = $007B    ; loop counter (conditions left / table slot)
temp_7c                  = $007C
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
old_rt_add8              = $4A03
old_rt_add16             = $4A06
old_rt_print             = $4A15
unknown_verb_text        = $6362    ; patched into "I DONT KNOW HOW TO ________ SOMETHING"
unknown_noun_verb        = $63A1    ; patched into "I DONT KNOW HOW TO ________ A ________"
unknown_noun_text        = $63AC
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
cmd_state:
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
cond_value:
        .byte $26
        .byte $0D
find_id:
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
room_no:
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
msg_scratch:
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
room_index:
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
action_ptr:
        .byte $14,$44
act_temp:
        .byte $01
        .byte $4B
act_word1:
        .byte $1E,$0D
act_word2:
        .byte $1E,$00
actions_left:
        .byte $00
act_arg1:
        .byte $20
act_arg2:
        .byte $31
act_arg3:
        .byte $53
act_arg4:
        .byte $54
LAMPSTAT:
        .byte $00
saved_zwork:
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
        .org $0900
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
        .incbin "data/adventure_0B9D.bin"    ; $0B9D-$0CFF leftover memory, not used by the code (see NOTES.md)

; ==== rooms ==========================================================================
; RTBLSIZ bytes per room, indexed by room number (room 0 unused): RROOMNO, RMSG, the six
; exits RN RS RE RW RU RD (0 = none), RBASEPIC, RCURPIC.
        .org $0D00
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
        .incbin "data/adventure_0EA4.bin"    ; $0EA4-$16FF leftover memory, not used by the code (see NOTES.md)

; ==== nouns ==========================================================================
; Word groups: head word, synonym count, synonyms; all WORDLEN characters, high-bit ASCII.
; The group number is the noun's id (N_* in game.inc). Ends with HV.
        .org $1700
noun_table:
        .hiasc "DAISY   "            ; N_DAISY = 1
        .byte 1
        .hiasc "FLOWER  "
        .hiasc "BILL    "            ; N_BILL = 2
        .byte 0
        .hiasc "JOE     "            ; N_JOE = 3
        .byte 0
        .hiasc "SALLY   "            ; N_SALLY = 4
        .byte 0
        .hiasc "SAM     "            ; N_SAM = 5
        .byte 0
        .hiasc "TOM     "            ; N_TOM = 6
        .byte 0
        .hiasc "DOCTOR  "            ; N_DOCTOR = 7
        .byte 3
        .hiasc "GREEN   "
        .hiasc "DR.     "
        .hiasc "DR.GREEN"
        .hiasc "DAGGER  "            ; N_DAGGER = 8
        .byte 0
        .hiasc "GUN     "            ; N_GUN = 9
        .byte 1
        .hiasc "PISTOL  "
        .hiasc "NOTE    "            ; N_NOTE = 10
        .byte 3
        .hiasc "MEMO    "
        .hiasc "LETTER  "
        .hiasc "PAPER   "
        .hiasc "BLA     "            ; N_BLA = 11
        .byte 1
        .hiasc "DOG     "
        .hiasc "DOG     "            ; N_DOG = 12
        .byte 0
        .hiasc "FOOD    "            ; N_FOOD = 13
        .byte 1
        .hiasc "BREAD   "
        .hiasc "LAST    "            ; N_LAST = 14
        .byte 0
        .hiasc "BODY    "            ; N_BODY = 15
        .byte 2
        .hiasc "CORPSE  "
        .hiasc "CADAVER "
        .hiasc "TRAPDOOR"            ; N_TRAPDOOR = 16
        .byte 0
        .hiasc "KNIFE   "            ; N_KNIFE = 17
        .byte 0
        .hiasc "BOLTS   "            ; N_BOLTS = 18
        .byte 1
        .hiasc "SCREWS  "
        .hiasc "BUTTERKN"            ; N_BUTTERKN = 19
        .byte 0
        .hiasc "PICTURE "            ; N_PICTURE = 20
        .byte 1
        .hiasc "PORTRAIT"
        .hiasc "BUTTON  "            ; N_BUTTON = 21
        .byte 1
        .hiasc "KNOB    "
        .hiasc "CRAWLSPA"            ; N_CRAWLSPA = 22
        .byte 0
        .hiasc "STAIRS  "            ; N_STAIRS = 23
        .byte 2
        .hiasc "STAIRWAY"
        .hiasc "STEPS   "
        .hiasc "WALL    "            ; N_WALL = 24
        .byte 1
        .hiasc "WALLS   "
        .hiasc "DOOR    "            ; N_DOOR = 25
        .byte 2
        .hiasc "DOORS   "
        .hiasc "DOORWAY "
        .hiasc "TABLE   "            ; N_TABLE = 26
        .byte 1
        .hiasc "DESK    "
        .hiasc "DRAWERS "            ; N_DRAWERS = 27
        .byte 0
        .hiasc "RUG     "            ; N_RUG = 28
        .byte 1
        .hiasc "CARPET  "
        .hiasc "WATER   "            ; N_WATER = 29
        .byte 1
        .hiasc "LIQUID  "
        .hiasc "TOILET  "            ; N_TOILET = 30
        .byte 2
        .hiasc "POTTY   "
        .hiasc "JOHN    "
        .hiasc "TOWEL   "            ; N_TOWEL = 31
        .byte 1
        .hiasc "CLOTH   "
        .hiasc "SHOWER  "            ; N_SHOWER = 32
        .byte 0
        .hiasc "SLEDGEHA"            ; N_SLEDGEHA = 33
        .byte 1
        .hiasc "HAMMER  "
        .hiasc "WINDOW  "            ; N_WINDOW = 34
        .byte 0
        .hiasc "BOXES   "            ; N_BOXES = 35
        .byte 1
        .hiasc "BOX     "
        .hiasc "TRUNK   "            ; N_TRUNK = 36
        .byte 1
        .hiasc "CHEST   "
        .hiasc "FENCE   "            ; N_FENCE = 37
        .byte 0
        .hiasc "CANDLE  "            ; N_CANDLE = 38
        .byte 0
        .hiasc "LAMP    "            ; N_LAMP = 39
        .byte 0
        .hiasc "HOLE    "            ; N_HOLE = 40
        .byte 0
        .hiasc "KEY     "            ; N_KEY = 41
        .byte 0
        .hiasc "SHELVES "            ; N_SHELVES = 42
        .byte 1
        .hiasc "BOOKSHEL"
        .hiasc "FIREPLAC"            ; N_FIREPLAC = 43
        .byte 1
        .hiasc "CHIMNEY "
        .hiasc "COUCH   "            ; N_COUCH = 44
        .byte 3
        .hiasc "SOFA    "
        .hiasc "DAVENPOR"
        .hiasc "DIVAN   "
        .hiasc "BED     "            ; N_BED = 45
        .byte 1
        .hiasc "MATTRESS"
        .hiasc "FLOOR   "            ; N_FLOOR = 46
        .byte 0
        .hiasc "ALGAE   "            ; N_ALGAE = 47
        .byte 0
        .hiasc "BRICKS  "            ; N_BRICKS = 48
        .byte 1
        .hiasc "BRICK   "
        .hiasc "JEWELS  "            ; N_JEWELS = 49
        .byte 3
        .hiasc "GEMS    "
        .hiasc "TREASURE"
        .hiasc "DIAMONDS"
        .hiasc "JARS    "            ; N_JARS = 50
        .byte 3
        .hiasc "JAR     "
        .hiasc "BOTTLE  "
        .hiasc "BOTTLES "
        .hiasc "GATE    "            ; N_GATE = 51
        .byte 0
        .hiasc "TREE    "            ; N_TREE = 52
        .byte 1
        .hiasc "TREES   "
        .hiasc "TELESCOP"            ; N_TELESCOP = 53
        .byte 0
        .hiasc "PERSON  "            ; N_PERSON = 54
        .byte 3
        .hiasc "MAN     "
        .hiasc "WOMAN   "
        .hiasc "PEOPLE  "
        .hiasc "GRAVESTO"            ; N_GRAVESTO = 55
        .byte 1
        .hiasc "TOMBSTON"
        .hiasc "CABINET "            ; N_CABINET = 56
        .byte 1
        .hiasc "CUPBOARD"
        .hiasc "MATCHES "            ; N_MATCHES = 57
        .byte 1
        .hiasc "MATCH   "
        .hiasc "REFRIGER"            ; N_REFRIGER = 58
        .byte 3
        .hiasc "FRIDGE  "
        .hiasc "ICEBOX  "
        .hiasc "REFRIDGE"
        .hiasc "PITCHER "            ; N_PITCHER = 59
        .byte 0
        .hiasc "STOVE   "            ; N_STOVE = 60
        .byte 1
        .hiasc "RANGE   "
        .hiasc "PORCH   "            ; N_PORCH = 61
        .byte 0
        .hiasc "GRAVES  "            ; N_GRAVES = 62
        .byte 1
        .hiasc "GRAVE   "
        .hiasc "FAUCET  "            ; N_FAUCET = 63
        .byte 1
        .hiasc "TAP     "
        .hiasc "ON      "            ; N_ON = 64
        .byte 0
        .hiasc "OFF     "            ; N_OFF = 65
        .byte 0
        .hiasc "SINK    "            ; N_SINK = 66
        .byte 1
        .hiasc "TUB     "
        .hiasc "CRADLE  "            ; N_CRADLE = 67
        .byte 1
        .hiasc "CRIB    "
        .hiasc "CHAIR   "            ; N_CHAIR = 68
        .byte 1
        .hiasc "ROCKER  "
        .hiasc "SHOVEL  "            ; N_SHOVEL = 69
        .byte 1
        .hiasc "SPADE   "
        .hiasc "        "            ; N_NONE = 70
        .byte 0
        .hiasc "ROOM    "            ; N_ROOM = 71
        .byte 1
        .hiasc "AROUND  "
        .hiasc "TUNNEL  "            ; N_TUNNEL = 72
        .byte 0
        .hiasc "HOUSE   "            ; N_HOUSE = 73
        .byte 2
        .hiasc "BUILDING"
        .hiasc "HOME    "
        .hiasc "HALL    "            ; N_HALL = 74
        .byte 2
        .hiasc "HALLWAY "
        .hiasc "CORRIDOR"
        .hiasc "LADDER  "            ; N_LADDER = 75
        .byte 0
        .hiasc "FIRE    "            ; N_FIRE = 76
        .byte 0
        .hiasc "DOTS    "            ; N_DOTS = 77
        .byte 0
        .hiasc "X'S     "            ; N_X_S = 78
        .byte 0
        .hiasc "WELCOME "            ; N_WELCOME = 79
        .byte 0
        .hiasc "LINE    "            ; N_LINE = 80
        .byte 0
        .hiasc "N       "            ; N_N = 81
        .byte 1
        .hiasc "NORTH   "
        .hiasc "S       "            ; N_S = 82
        .byte 1
        .hiasc "SOUTH   "
        .hiasc "E       "            ; N_E = 83
        .byte 1
        .hiasc "EAST    "
        .hiasc "W       "            ; N_W = 84
        .byte 1
        .hiasc "WEST    "
        .hiasc "U       "            ; N_U = 85
        .byte 1
        .hiasc "UP      "
        .hiasc "D       "            ; N_D = 86
        .byte 1
        .hiasc "DOWN    "
        .hiasc "BOOKS   "            ; N_BOOKS = 87
        .byte 1
        .hiasc "BOOK    "
        .hiasc "GAME    "            ; N_GAME = 88
        .byte 1
        .hiasc "ADVENTUR"
        .hiasc "DONE    "            ; N_DONE = 89
        .byte $FF
        .incbin "data/adventure_1C61.bin"    ; $1C61-$1FFF leftover memory, not used by the code (see NOTES.md)
        .org $2000
title_1980:
        .incbin "data/title_1980.bin"    ; $2000-$3FFF 

; ==== verbs ==========================================================================
; Same layout as the nouns; ids are V_* in game.inc.
        .org $4000
verb_table:
        .hiasc "GO      "            ; V_GO = 1
        .byte 5
        .hiasc "ENTER   "
        .hiasc "RUN     "
        .hiasc "EXIT    "
        .hiasc "LEAVE   "
        .hiasc "WALK    "
        .hiasc "U       "            ; V_U = 2
        .byte 3
        .hiasc "UP      "
        .hiasc "CLIMB   "
        .hiasc "ASCEND  "
        .hiasc "D       "            ; V_D = 3
        .byte 2
        .hiasc "DOWN    "
        .hiasc "DESCEND "
        .hiasc "OPEN    "            ; V_OPEN = 4
        .byte 0
        .hiasc "CLOSE   "            ; V_CLOSE = 5
        .byte 1
        .hiasc "SHUT    "
        .hiasc "UNLOCK  "            ; V_UNLOCK = 6
        .byte 1
        .hiasc "UNLATCH "
        .hiasc "N       "            ; V_N = 7
        .byte 1
        .hiasc "NORTH   "
        .hiasc "S       "            ; V_S = 8
        .byte 1
        .hiasc "SOUTH   "
        .hiasc "E       "            ; V_E = 9
        .byte 1
        .hiasc "EAST    "
        .hiasc "W       "            ; V_W = 10
        .byte 1
        .hiasc "WEST    "
        .hiasc "BREAK   "            ; V_BREAK = 11
        .byte 2
        .hiasc "TEAR    "
        .hiasc "BUST    "
        .hiasc "MOVE    "            ; V_MOVE = 12
        .byte 2
        .hiasc "SLIDE   "
        .hiasc "PUSH    "
        .hiasc "LOOK    "            ; V_LOOK = 13
        .byte 1
        .hiasc "EXAMINE "
        .hiasc "GET     "            ; V_GET = 14
        .byte 2
        .hiasc "TAKE    "
        .hiasc "LIFT    "
        .hiasc "LIGHT   "            ; V_LIGHT = 15
        .byte 1
        .hiasc "STRIKE  "
        .hiasc "POUR    "            ; V_POUR = 16
        .byte 1
        .hiasc "DUMP    "
        .hiasc "DROP    "            ; V_DROP = 17
        .byte 2
        .hiasc "SET     "
        .hiasc "LEAVE   "
        .hiasc "JUMP    "            ; V_JUMP = 18
        .byte 1
        .hiasc "LEAP    "
        .hiasc "READ    "            ; V_READ = 19
        .byte 0
        .hiasc "TALK    "            ; V_TALK = 20
        .byte 1
        .hiasc "SPEAK   "
        .hiasc "KILL    "            ; V_KILL = 21
        .byte 1
        .hiasc "SLAY    "
        .hiasc "EAT     "            ; V_EAT = 22
        .byte 1
        .hiasc "CONSUME "
        .hiasc "WIPE    "            ; V_WIPE = 23
        .byte 2
        .hiasc "RUB     "
        .hiasc "REMOVE  "
        .hiasc "FLUSH   "            ; V_FLUSH = 24
        .byte 0
        .hiasc "UNSCREW "            ; V_UNSCREW = 25
        .byte 2
        .hiasc "UNBOLT  "
        .hiasc "LOOSEN  "
        .hiasc "WITH    "            ; V_WITH = 26
        .byte 3
        .hiasc "USE     "
        .hiasc "SHOOT   "
        .hiasc "FIRE    "
        .hiasc "PRESS   "            ; V_PRESS = 27
        .byte 1
        .hiasc "PUSH    "
        .hiasc "TURN    "            ; V_TURN = 28
        .byte 0
        .hiasc "FAUCET  "            ; V_FAUCET = 29
        .byte 2
        .hiasc "TAP     "
        .hiasc "WATER   "
        .hiasc "WATER   "            ; V_WATER = 30
        .byte 0
        .hiasc "ON      "            ; V_ON = 31
        .byte 0
        .hiasc "OFF     "            ; V_OFF = 32
        .byte 0
        .hiasc "UNLIGHT "            ; V_UNLIGHT = 33
        .byte 1
        .hiasc "OFF     "
        .hiasc "SAVE    "            ; V_SAVE = 34
        .byte 1
        .hiasc "STORE   "
        .hiasc "RESTORE "            ; V_RESTORE = 35
        .byte 0
        .hiasc "QUIT    "            ; V_QUIT = 36
        .byte 2
        .hiasc "BYE     "
        .hiasc "STOP    "
        .hiasc "HELP    "            ; V_HELP = 37
        .byte 0
        .hiasc "INVENTOR"            ; V_INVENTOR = 38
        .byte 3
        .hiasc "INVEN   "
        .hiasc "CARRYING"
        .hiasc "?       "
        .hiasc "FUCK    "            ; V_PROFANITY = 39
        .byte 3
        .hiasc "SUCK    "
        .hiasc "SHIT    "
        .hiasc "CUNT    "
        .hiasc "SCORE   "            ; V_SCORE = 40
        .byte 0
        .hiasc "SLEEP   "            ; V_SLEEP = 41
        .byte 3
        .hiasc "REST    "
        .hiasc "RETIRE  "
        .hiasc "LIE     "
        .hiasc "DRINK   "            ; V_DRINK = 42
        .byte 2
        .hiasc "SIP     "
        .hiasc "TASTE   "
        .hiasc "DONE    "            ; V_DONE = 43
        .byte $FF
        .incbin "data/adventure_4343.bin"    ; $4343-$43FF leftover memory, not used by the code (see NOTES.md)

; ==== turn rules =====================================================================
; Every matching rule runs after each command. Rule layout: room, verb, noun (ANY matches
; all), length, number of conditions, number of actions, conditions (C_*), actions (A_*).
        .org $4400
turn_rules:

; always
rule_4400:
        .byte ANY, ANY, ANY, rule_440B-rule_4400, 1, 1
        .byte C_SWITCH_EQ, 3, 1     ; if switch[3] == 1
        .byte A_MESSAGE, 130     ; say msg 130 "THE MATCH WENT OUT"

; always
rule_440B:
        .byte ANY, ANY, ANY, rule_4417-rule_440B, 1, 1
        .byte C_SWITCH_EQ, 3, 0     ; if switch[3] == 0
        .byte A_SET_SWITCH, 3, 1     ; switch[3] = 1

; always
rule_4417:
        .byte ANY, ANY, ANY, rule_4420-rule_4417, 0, 1
        .byte A_SUB_SWITCH, 1, 3     ; switch[3] -= 1

; always
rule_4420:
        .byte ANY, ANY, ANY, rule_442C-rule_4420, 2, 1
        .byte C_TURNS_GT, 36     ; if turn > 36
        .byte C_SWITCH_EQ, 3, 0     ; if switch[3] == 0
        .byte A_LAMP_OFF     ; light off

; always
rule_442C:
        .byte ANY, ANY, ANY, rule_443C-rule_442C, 3, 1
        .byte C_OBJ_IN_ROOM, 18, 253     ; if object 18 (CANDLE) is in nowhere
        .byte C_SWITCH_EQ, 3, 0     ; if switch[3] == 0
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
        .byte C_SWITCH_EQ, 16, 0     ; if switch[16] == 0
        .byte A_MESSAGE, 7     ; say msg 7 "IT IS GETTING DARK"

; always
rule_445A:
        .byte ANY, ANY, ANY, rule_4465-rule_445A, 1, 1
        .byte C_TURNS_GT, 35     ; if turn > 35
        .byte A_SET_SWITCH, 16, 1     ; switch[16] = 1

; room 1 (IN THE FRONT YARD OF A LARGE ABANDONE...)
rule_4465:
        .byte 1, ANY, ANY, turn_rules_end-rule_4465, 2, 2
        .byte C_OBJ_IN_ROOM, 32, 254     ; if object 32 (JEWELS) is in inventory
        .byte C_SWITCH_EQ, 11, 1     ; if switch[11] == 1
        .byte A_MESSAGE, 164     ; say msg 164 "CONGRATULATIONS YOU HAVE BEATEN ADVENTURE AND ARE DECLARED A GURU WIZARD"
        .byte A_GAME_OVER     ; ask to play again
turn_rules_end:
        .byte $FF
        .incbin "data/adventure_4475.bin"    ; $4475-$44FF leftover memory, not used by the code (see NOTES.md)

; ==== command rules ==================================================================
; Tried in order after each command; the first match runs and ends the search. The generic
; GET/DROP/LOOK/SAVE/... rules at the end catch anything earlier rules don't.
        .org $4500
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
        .byte C_SWITCH_EQ, 12, 1     ; if switch[12] == 1
        .byte A_MESSAGE, 129     ; say msg 129 "IT IS OPEN"

; room 2 (ON THE PORCH), OPEN, DOOR
rule_4543:
        .byte 2, V_OPEN, N_DOOR, rule_454E-rule_4543, 0, 2
        .byte A_SET_BASE_VIEW, 2     ; make picture 2 the room view
        .byte A_SET_SWITCH, 12, 1     ; switch[12] = 1

; room 2 (ON THE PORCH), CLOSE, DOOR
rule_454E:
        .byte 2, V_CLOSE, N_DOOR, rule_455C-rule_454E, 1, 2
        .byte C_SWITCH_EQ, 12, 1     ; if switch[12] == 1
        .byte A_SET_BASE_VIEW, 1     ; make picture 1 the room view
        .byte A_SET_SWITCH, 12, 0     ; switch[12] = 0

; room 2 (ON THE PORCH), CLOSE, DOOR
rule_455C:
        .byte 2, V_CLOSE, N_DOOR, rule_4567-rule_455C, 1, 1
        .byte C_SWITCH_EQ, 12, 0     ; if switch[12] == 0
        .byte A_MESSAGE, 128     ; say msg 128 "THE DOOR IS CLOSED"

; room 2 (ON THE PORCH), GO, DOOR
rule_4567:
        .byte 2, V_GO, N_DOOR, rule_4577-rule_4567, 1, 3
        .byte C_SWITCH_EQ, 12, 1     ; if switch[12] == 1
        .byte A_GOTO_ROOM, 3     ; go to room 3 (IN AN ENTRY HALL)
        .byte A_SET_SWITCH, 1, 1     ; switch[1] = 1
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
        .byte C_SWITCH_EQ, 1, 1     ; if switch[1] == 1
        .byte A_MESSAGE, 82     ; say msg 82 "IT IS LOCKED"

; room 3 (IN AN ENTRY HALL), OPEN, DOOR
rule_45B8:
        .byte 3, V_OPEN, N_DOOR, rule_45C3-rule_45B8, 1, 1
        .byte C_SWITCH_EQ, 1, 0     ; if switch[1] == 0
        .byte A_SET_BASE_VIEW, 5     ; make picture 5 the room view

; room 3 (IN AN ENTRY HALL), UNLOCK, DOOR
rule_45C3:
        .byte 3, V_UNLOCK, N_DOOR, rule_45D1-rule_45C3, 1, 2
        .byte C_OBJ_IN_ROOM, 30, 254     ; if object 30 (KEY) is in inventory
        .byte A_SET_SWITCH, 1, 0     ; switch[1] = 0
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
        .byte C_SWITCH_EQ, 13, 1     ; if switch[13] == 1
        .byte A_MESSAGE, 139     ; say msg 139 "IT WON'T MOVE ANY FARTHER"

; room 4 (IN THE KITCHEN), MOVE, CABINET
rule_4662:
        .byte 4, V_MOVE, N_CABINET, rule_4675-rule_4662, 0, 4
        .byte A_PLACE_OBJ, 10, 4, 65, 20     ; put object 10 (CABINET) in room 4 (IN THE KITCHEN) at (65,20)
        .byte A_PUT_OBJ, 11, 4     ; put object 11 (BRICKS) in room 4 (IN THE KITCHEN)
        .byte A_SET_SWITCH, 13, 1     ; switch[13] = 1
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
        .byte A_SET_SWITCH, 4, 1     ; switch[4] = 1

; room 4 (IN THE KITCHEN), GET, WATER
rule_4720:
        .byte 4, V_GET, N_WATER, rule_4734-rule_4720, 2, 3
        .byte C_SWITCH_EQ, 4, 1     ; if switch[4] == 1
        .byte C_OBJ_IN_ROOM, 14, 254     ; if object 14 (PITCHER) is in inventory
        .byte A_MESSAGE, 92     ; say msg 92 "YOUR PITCHER IS FULL"
        .byte A_PUT_OBJ, 14, 253     ; put object 14 (PITCHER) in nowhere
        .byte A_PUT_OBJ, 15, 254     ; put object 15 (PITCHER) in inventory

; room 4 (IN THE KITCHEN), GET, WATER
rule_4734:
        .byte 4, V_GET, N_WATER, rule_473F-rule_4734, 1, 1
        .byte C_SWITCH_EQ, 4, 1     ; if switch[4] == 1
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
        .byte A_SET_SWITCH, 14, 1     ; switch[14] = 1

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
        .byte A_SET_SWITCH, 14, 0     ; switch[14] = 0

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
        .byte A_SET_SWITCH, 4, 0     ; switch[4] = 0
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
        .byte C_SWITCH_EQ, 14, 0     ; if switch[14] == 0
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
        .byte A_SET_SWITCH, 14, 1     ; switch[14] = 1

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
        .byte C_SWITCH_EQ, 5, 0     ; if switch[5] == 0
        .byte A_SET_SWITCH, 5, 1     ; switch[5] = 1
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
        .byte A_SET_SWITCH, 7, 1     ; switch[7] = 1

; room 18 (IN A SMALL FENCED CEMETARY), WITH, DAGGER
rule_4ADD:
        .byte 18, V_WITH, N_DAGGER, rule_4AE8-rule_4ADD, 0, 2
        .byte A_MESSAGE, 132     ; say msg 132 "YOU ARE NOT CARRYING IT"
        .byte A_PUT_OBJ, 26, 253     ; put object 26 (DOTS) in nowhere

; room 18 (IN A SMALL FENCED CEMETARY), WITH, GUN
rule_4AE8:
        .byte 18, V_WITH, N_GUN, rule_4B01-rule_4AE8, 2, 5
        .byte C_OBJ_IN_ROOM, 45, 254     ; if object 45 (GUN) is in inventory
        .byte C_SWITCH_EQ, 6, 0     ; if switch[6] == 0
        .byte A_MESSAGE, 30     ; say msg 30 "THERE IS A DEAD BODY HERE"
        .byte A_MESSAGE, 35     ; say msg 35 "YOUR GUN IS EMPTY"
        .byte A_PUT_OBJ, 27, 18     ; put object 27 (X'S) in room 18 (IN A SMALL FENCED CEMETARY)
        .byte A_SET_SWITCH, 6, 1     ; switch[6] = 1
        .byte A_SET_SWITCH, 7, 1     ; switch[7] = 1

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
        .byte C_SWITCH_EQ, 7, 0     ; if switch[7] == 0
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
        .byte C_SWITCH_EQ, 7, 0     ; if switch[7] == 0
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
        .byte C_SWITCH_EQ, 8, 1     ; if switch[8] == 1
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
        .byte A_SET_SWITCH, 8, 1     ; switch[8] = 1

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
        .byte A_SET_SWITCH, 9, 1     ; switch[9] = 1

; room 38 (IN THE BATHROOM), GET, WATER
rule_4E14:
        .byte 38, V_GET, N_WATER, rule_4E28-rule_4E14, 2, 3
        .byte C_SWITCH_EQ, 9, 1     ; if switch[9] == 1
        .byte C_OBJ_IN_ROOM, 14, 254     ; if object 14 (PITCHER) is in inventory
        .byte A_MESSAGE, 92     ; say msg 92 "YOUR PITCHER IS FULL"
        .byte A_PUT_OBJ, 14, 253     ; put object 14 (PITCHER) in nowhere
        .byte A_PUT_OBJ, 15, 254     ; put object 15 (PITCHER) in inventory

; room 38 (IN THE BATHROOM), GET, WATER
rule_4E28:
        .byte 38, V_GET, N_WATER, rule_4E33-rule_4E28, 1, 1
        .byte C_SWITCH_EQ, 9, 1     ; if switch[9] == 1
        .byte A_MESSAGE, 14     ; say msg 14 "YOU HAVE NO CONTAINER"

; room 38 (IN THE BATHROOM), GET, WATER
rule_4E33:
        .byte 38, V_GET, N_WATER, rule_4E3B-rule_4E33, 0, 1
        .byte A_MESSAGE, 131     ; say msg 131 "I SEE NO WATER"

; room 38 (IN THE BATHROOM), FAUCET, OFF
rule_4E3B:
        .byte 38, V_FAUCET, N_OFF, rule_4E46-rule_4E3B, 0, 2
        .byte A_SET_SWITCH, 9, 0     ; switch[9] = 0
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
        .byte C_SWITCH_EQ, 10, 1     ; if switch[10] == 1
        .byte C_OBJ_IN_ROOM, 43, 40     ; if object 43 (TRUNK) is in room 40 (IN A STORAGE ROOM)
        .byte A_PUT_OBJ, 43, 253     ; put object 43 (TRUNK) in nowhere
        .byte A_PUT_OBJ, 44, 40     ; put object 44 (TRUNK) in room 40 (IN A STORAGE ROOM)

; room 40 (IN A STORAGE ROOM), OPEN, TRUNK
rule_4F4B:
        .byte 40, V_OPEN, N_TRUNK, rule_4F56-rule_4F4B, 1, 1
        .byte C_SWITCH_EQ, 10, 1     ; if switch[10] == 1
        .byte A_MESSAGE, 82     ; say msg 82 "IT IS LOCKED"

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
        .byte C_SWITCH_EQ, 10, 0     ; if switch[10] == 0
        .byte A_MESSAGE, 82     ; say msg 82 "IT IS LOCKED"

; room 40 (IN A STORAGE ROOM), LOOK, TRUNK
rule_4F9C:
        .byte 40, V_LOOK, N_TRUNK, rule_4FAA-rule_4F9C, 2, 1
        .byte C_OBJ_IN_ROOM, 43, 40     ; if object 43 (TRUNK) is in room 40 (IN A STORAGE ROOM)
        .byte C_SWITCH_EQ, 10, 1     ; if switch[10] == 1
        .byte A_MESSAGE, 133     ; say msg 133 "IT IS NOT OPEN"

; room 40 (IN A STORAGE ROOM), UNLOCK, TRUNK
rule_4FAA:
        .byte 40, V_UNLOCK, N_TRUNK, rule_4FBE-rule_4FAA, 3, 2
        .byte C_OBJ_IN_ROOM, 43, 40     ; if object 43 (TRUNK) is in room 40 (IN A STORAGE ROOM)
        .byte C_OBJ_IN_ROOM, 22, 254     ; if object 22 (KEY) is in inventory
        .byte C_SWITCH_EQ, 10, 0     ; if switch[10] == 0
        .byte A_MESSAGE, 2     ; say msg 2 "OK"
        .byte A_SET_SWITCH, 10, 1     ; switch[10] = 1

; room 40 (IN A STORAGE ROOM), UNLOCK, TRUNK
rule_4FBE:
        .byte 40, V_UNLOCK, N_TRUNK, rule_4FCF-rule_4FBE, 3, 1
        .byte C_OBJ_IN_ROOM, 43, 40     ; if object 43 (TRUNK) is in room 40 (IN A STORAGE ROOM)
        .byte C_OBJ_IN_ROOM, 22, 254     ; if object 22 (KEY) is in inventory
        .byte C_SWITCH_EQ, 10, 1     ; if switch[10] == 1
        .byte A_MESSAGE, 136     ; say msg 136 "IT IS UNLOCKED"

; room 40 (IN A STORAGE ROOM), UNLOCK, TRUNK
rule_4FCF:
        .byte 40, V_UNLOCK, N_TRUNK, rule_4FDD-rule_4FCF, 2, 1
        .byte C_OBJ_IN_ROOM, 43, 40     ; if object 43 (TRUNK) is in room 40 (IN A STORAGE ROOM)
        .byte C_SWITCH_EQ, 10, 0     ; if switch[10] == 0
        .byte A_MESSAGE, 83     ; say msg 83 "YOU HAVE NOTHING TO UNLOCK IT WITH"

; room 40 (IN A STORAGE ROOM), UNLOCK, TRUNK
rule_4FDD:
        .byte 40, V_UNLOCK, N_TRUNK, rule_4FEB-rule_4FDD, 2, 1
        .byte C_OBJ_IN_ROOM, 43, 40     ; if object 43 (TRUNK) is in room 40 (IN A STORAGE ROOM)
        .byte C_SWITCH_EQ, 10, 1     ; if switch[10] == 1
        .byte A_MESSAGE, 136     ; say msg 136 "IT IS UNLOCKED"

; room 40 (IN A STORAGE ROOM), GO, WINDOW
rule_4FEB:
        .byte 40, V_GO, N_WINDOW, rule_4FF5-rule_4FEB, 0, 2
        .byte A_MESSAGE, 147     ; say msg 147 "YOU FALL TO EARTH. LUCKILY YOU HAVE ONLY MINOR INJURIES."
        .byte A_MESSAGE, 148     ; say msg 148 "UNFORTUNATELY THE AMBULANCE DRIVER SMASHS INTO A VOLKWAGEN. NO SURVIVORS. YOU ARE DEAD."

; room 41 (IN THE TOWER), GO, TRAPDOOR
rule_4FF5:
        .byte 41, V_GO, N_TRAPDOOR, rule_4FFD-rule_4FF5, 0, 1
        .byte A_GOTO_ROOM, 39     ; go to room 39 (IN THE ATTIC)

; room 41 (IN THE TOWER), LOOK, PERSON
rule_4FFD:
        .byte 41, V_LOOK, N_PERSON, rule_5008-rule_4FFD, 1, 1
        .byte C_SWITCH_EQ, 11, 0     ; if switch[11] == 0
        .byte A_MESSAGE, 87     ; say msg 87 "SHE IS GOING TO KILL YOU"

; room 41 (IN THE TOWER), LOOK, DAISY
rule_5008:
        .byte 41, V_LOOK, N_DAISY, rule_5013-rule_5008, 1, 1
        .byte C_SWITCH_EQ, 11, 0     ; if switch[11] == 0
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
        .byte C_SWITCH_EQ, 11, 1     ; if switch[11] == 1
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
        .byte C_SWITCH_EQ, 6, 0     ; if switch[6] == 0
        .byte C_OBJ_IN_ROOM, 45, 254     ; if object 45 (GUN) is in inventory
        .byte A_PUT_OBJ, 47, 253     ; put object 47 (DOTS) in nowhere
        .byte A_PUT_OBJ, 48, 41     ; put object 48 (X'S) in room 41 (IN THE TOWER)
        .byte A_SET_SWITCH, 6, 1     ; switch[6] = 1
        .byte A_MESSAGE, 35     ; say msg 35 "YOUR GUN IS EMPTY"
        .byte A_SET_SWITCH, 11, 1     ; switch[11] = 1
        .byte A_MESSAGE, 161     ; say msg 161 "DAISY IS NOW DEAD"

; room 41 (IN THE TOWER), WITH, GUN
rule_5061:
        .byte 41, V_WITH, N_GUN, rule_506C-rule_5061, 1, 1
        .byte C_SWITCH_EQ, 11, 1     ; if switch[11] == 1
        .byte A_MESSAGE, 166     ; say msg 166 "DAISY IS ALREADY DEAD"

; room 41 (IN THE TOWER), WITH, GUN
rule_506C:
        .byte 41, V_WITH, N_GUN, rule_507D-rule_506C, 2, 3
        .byte C_SWITCH_EQ, 6, 1     ; if switch[6] == 1
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
        .byte C_SWITCH_EQ, 11, 0     ; if switch[11] == 0
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
        .byte A_SET_SWITCH, 3, 4     ; switch[3] = 4
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
        .byte C_SWITCH_EQ, 6, 0     ; if switch[6] == 0
        .byte A_SET_SWITCH, 6, 1     ; switch[6] = 1
        .byte A_MESSAGE, 160     ; say msg 160 "YOUR GUN IS NOW EMPTY"

; WITH, GUN
rule_5198:
        .byte ANY, V_WITH, N_GUN, rule_51A6-rule_5198, 1, 2
        .byte C_OBJ_IN_ROOM, 45, 254     ; if object 45 (GUN) is in inventory
        .byte A_SET_SWITCH, 6, 1     ; switch[6] = 1
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
; Picture n is at offset in file BLOCKblock; load_picture reads entry n at PICDIR + 3n.
        .org $5300
picture_directory:
; block, offset within the block (entry 0 is unused)
        .byte $C7, <$A0CF, >$A0CF   ; picture 0
        .byte $01, <$0000, >$0000   ; picture 1
        .byte $01, <$004E, >$004E   ; picture 2
        .byte $01, <$00A6, >$00A6   ; picture 3
        .byte $01, <$02BC, >$02BC   ; picture 4
        .byte $02, <$0000, >$0000   ; picture 5
        .byte $02, <$00BA, >$00BA   ; picture 6
        .byte $02, <$02BC, >$02BC   ; picture 7
        .byte $03, <$0000, >$0000   ; picture 8
        .byte $03, <$008C, >$008C   ; picture 9
        .byte $03, <$012C, >$012C   ; picture 10
        .byte $03, <$01B4, >$01B4   ; picture 11
        .byte $03, <$020A, >$020A   ; picture 12
        .byte $03, <$0274, >$0274   ; picture 13
        .byte $04, <$0000, >$0000   ; picture 14
        .byte $04, <$0104, >$0104   ; picture 15
        .byte $04, <$019C, >$019C   ; picture 16
        .byte $04, <$024E, >$024E   ; picture 17
        .byte $05, <$0000, >$0000   ; picture 18
        .byte $05, <$00A4, >$00A4   ; picture 19
        .byte $05, <$00E4, >$00E4   ; picture 20
        .byte $05, <$01E0, >$01E0   ; picture 21
        .byte $06, <$0000, >$0000   ; picture 22
        .byte $06, <$0064, >$0064   ; picture 23
        .byte $06, <$00F2, >$00F2   ; picture 24
        .byte $06, <$020E, >$020E   ; picture 25
        .byte $07, <$0000, >$0000   ; picture 26
        .byte $07, <$015A, >$015A   ; picture 27
        .byte $07, <$02AE, >$02AE   ; picture 28
        .byte $08, <$0000, >$0000   ; picture 29
        .byte $08, <$0176, >$0176   ; picture 30
        .byte $08, <$0272, >$0272   ; picture 31
        .byte $09, <$0000, >$0000   ; picture 32
        .byte $09, <$0166, >$0166   ; picture 33
        .byte $09, <$01A8, >$01A8   ; picture 34
        .byte $09, <$0250, >$0250   ; picture 35
        .byte $0A, <$0000, >$0000   ; picture 36
        .byte $0A, <$01AC, >$01AC   ; picture 37
        .byte $0A, <$02DE, >$02DE   ; picture 38
        .byte $0B, <$0000, >$0000   ; picture 39
        .byte $0B, <$00A0, >$00A0   ; picture 40
        .byte $0B, <$0192, >$0192   ; picture 41
        .byte $0B, <$0288, >$0288   ; picture 42
        .byte $0C, <$0000, >$0000   ; picture 43
        .byte $0C, <$0088, >$0088   ; picture 44
        .byte $0C, <$00F0, >$00F0   ; picture 45
        .byte $0C, <$0232, >$0232   ; picture 46
        .byte $0C, <$02BA, >$02BA   ; picture 47
        .byte $0D, <$0000, >$0000   ; picture 48
        .byte $0D, <$02D6, >$02D6   ; picture 49
        .byte $0E, <$0000, >$0000   ; picture 50
        .byte $0E, <$0032, >$0032   ; picture 51
        .byte $0E, <$0136, >$0136   ; picture 52
        .byte $0E, <$01E8, >$01E8   ; picture 53
        .byte $0E, <$0298, >$0298   ; picture 54
        .byte $0F, <$0000, >$0000   ; picture 55
        .byte $0F, <$004E, >$004E   ; picture 56
        .byte $0F, <$0068, >$0068   ; picture 57
        .byte $0F, <$007C, >$007C   ; picture 58
        .byte $0F, <$00B4, >$00B4   ; picture 59
        .byte $0F, <$00EC, >$00EC   ; picture 60
        .byte $0F, <$010A, >$010A   ; picture 61
        .byte $0F, <$0140, >$0140   ; picture 62
        .byte $0F, <$017C, >$017C   ; picture 63
        .byte $0F, <$01AE, >$01AE   ; picture 64
        .byte $0F, <$01C8, >$01C8   ; picture 65
        .byte $0F, <$020C, >$020C   ; picture 66
        .byte $0F, <$02E2, >$02E2   ; picture 67
        .byte $10, <$0000, >$0000   ; picture 68
        .byte $10, <$008A, >$008A   ; picture 69
        .byte $10, <$0094, >$0094   ; picture 70
        .byte $10, <$00AE, >$00AE   ; picture 71
        .byte $10, <$00E2, >$00E2   ; picture 72
        .byte $10, <$01A2, >$01A2   ; picture 73
        .byte $10, <$01D8, >$01D8   ; picture 74
        .byte $10, <$01E6, >$01E6   ; picture 75
        .byte $10, <$020C, >$020C   ; picture 76
        .byte $11, <$0000, >$0000   ; picture 77
        .byte $11, <$00C8, >$00C8   ; picture 78
        .byte $11, <$00D0, >$00D0   ; picture 79
        .byte $11, <$0132, >$0132   ; picture 80
        .byte $11, <$0142, >$0142   ; picture 81
        .byte $11, <$0216, >$0216   ; picture 82
        .byte $11, <$0224, >$0224   ; picture 83
        .byte $11, <$023E, >$023E   ; picture 84
        .byte $11, <$0256, >$0256   ; picture 85
        .byte $11, <$027C, >$027C   ; picture 86
        .byte $11, <$02D8, >$02D8   ; picture 87
        .byte $12, <$0000, >$0000   ; picture 88
        .byte $12, <$0058, >$0058   ; picture 89
        .byte $12, <$012E, >$012E   ; picture 90
        .byte $12, <$0138, >$0138   ; picture 91
        .byte $12, <$0152, >$0152   ; picture 92
        .byte $13, <$0000, >$0000   ; picture 93
        .byte $13, <$0026, >$0026   ; picture 94
        .byte $13, <$006A, >$006A   ; picture 95
        .byte $13, <$00AA, >$00AA   ; picture 96
        .byte $13, <$00C4, >$00C4   ; picture 97
        .incbin "data/adventure_5426.bin"    ; $5426-$54FF leftover memory, not used by the code (see NOTES.md)

; ==== message index ==================================================================
; Byte offset of each message in the MESSAGES text file (also saved as MESSAGE OBJECT).
        .org $5500
message_index:
        .word $0006   ; 0 (unused)
        .word $0000   ; 1 IT IS TOO HIGH
        .word $000F   ; 2 OK
        .word $0012   ; 3 IT IS SAM, THE MECHANIC.  HE HAS BEEN HIT IN THE HEAD BY A B
        .word $005A   ; 4 IT IS TOO HEAVY
        .word $006A   ; 5 WINDOWS ARE BOARDED UP EXCEPT THE ATTIC WINDOW
        .word $0099   ; 6 YOU ARE IN THE FENCED BACK YARD.  THE FENCE FOLLOWS THE SIDE
        .word $010C   ; 7 IT IS GETTING DARK
        .word $011F   ; 8 YOU ARE IN THE SIDE YARD.  YOU CAN FOLLOW THE FENCE TO THE S
        .word $0160   ; 9 YOU ARE IN THE KITCHEN.  THERE IS A REFRIGERATOR, STOVE AND 
        .word $01A4   ; 10 THE WALL IS BRICKED UP BEHIND IT
        .word $01C5   ; 11 THE BRICKS BREAK APART LEAVING A LARGE HOLE
        .word $01F1   ; 12 YOU HAVE NOTHING STRONG ENOUGH
        .word $0210   ; 13 WATER IS RUNNING INTO THE SINK
        .word $022F   ; 14 YOU HAVE NO CONTAINER
        .word $0245   ; 15 THERE IS NOTHING SPECIAL
        .word $025E   ; 16 THE STOVE EXPLODES, YOU ARE DEAD
        .word $027F   ; 17 THE PITCHER IS EMPTY
        .word $0294   ; 18 YOU CAN'T CLIMB THESE TREES
        .word $02B0   ; 19 YOU ARE IN A FOREST
        .word $02C4   ; 20 THERE IS A VERY TALL PINE TREE IN FRONT OF YOU
        .word $02F3   ; 21 YOU ARE AT THE TOP OF A VERY TALL PINE TREE
        .word $031F   ; 22 YOU ARE LOOKING THROUGH THE ATTIC WINDOW.  YOU SEE A TRAPDOO
        .word $0372   ; 23 YOU HAD BETTER CLIMB DOWN FIRST
        .word $0392   ; 24 IT IS FASTENED DOWN
        .word $03A6   ; 25 YOU ARE AT THE NORTH END OF A NARROW NORTH/SOUTH PASSAGEWAY
        .word $03E2   ; 26 YOU ARE IN A SMALL PANTRY
        .word $03FC   ; 27 IT DOES NOT REMOVE
        .word $040F   ; 28 YOU ARE IN A SMALL FENCED CEMETARY.  THERE ARE SIX NEWLY DUG
        .word $0453   ; 29 THERE IS A MAN HERE
        .word $0467   ; 30 THERE IS A DEAD BODY HERE
        .word $0481   ; 31 THE WRITING IS WORN DOWN
        .word $049A   ; 32 IT IS JOE, THE GRAVEDIGGER.  HE HAS JUST FINISHED DIGGING TH
        .word $04E3   ; 33 HE DOESN'T TALK MUCH
        .word $04F8   ; 34 WITH WHAT?
        .word $0503   ; 35 YOUR GUN IS EMPTY
        .word $0515   ; 36 IT IS JOE, THE GRAVEDIGGER
        .word $0530   ; 37 I DONT UNDERSTAND WHAT YOU MEAN
        .word $0547   ; 38 YOU FALL IN ONE AND JOE BURIES YOU.  YOU ARE DEAD
        .word $0579   ; 39 YOU FALL IN ONE AND CLIMB OUT AGAIN
        .word $059D   ; 40 JOE WON'T LET YOU
        .word $05AF   ; 41 YOU ARE IN THE DINING ROOM
        .word $05CA   ; 42 IT IS DARK, YOU CAN'T SEE
        .word $05E4   ; 43 WOULD YOU LIKE TO PLAY AGAIN?
        .word $0602   ; 44 YOU TRIP OVER RUG AND FALL.  OH,OH, YOU STARTED A FIRE WITH 
        .word $064B   ; 45 THE FIRE IS OUT
        .word $065B   ; 46 THE FIRE IS OUT OF CONTROL.  YOU ARE DEAD
        .word $0685   ; 47 THERE IS NO WICK
        .word $0696   ; 48 WHICH DIRECTION?
        .word $06A7   ; 49 YOU ARE IN A MOIST BASEMENT. ALGAE COVERS THE WALLS. THERE I
        .word $06F7   ; 50 IT IS TOO HARD
        .word $0706   ; 51 YOU HAVE NOTHING TO WIPE IT WITH
        .word $0727   ; 52 THE WALL IS EXPOSED.  THERE IS A LOOSE BRICK
        .word $0754   ; 53 YOU HAVE FOUND THE JEWELS!
        .word $076F   ; 54 IT IS TOM, THE PLUMBER.  HE SEEMS TO HAVE BEEN STABBED.  THE
        .word $07C5   ; 55 THERE IS A SKELETON KEY HERE
        .word $07E2   ; 56 IT IS LOOSE
        .word $07EE   ; 57 THEY ARE JEWELS, ALL RIGHT!
        .word $080A   ; 58 YOU ARE AT THE SOUTH END OF A NORTH/SOUTH TUNNEL
        .word $083B   ; 59 IT IS VERY LONG
        .word $084B   ; 60 YOU ARE AT THE JUNCTION OF AN EAST/WEST HALLWAY AND A NORTH/
        .word $0895   ; 61 WHERE?
        .word $089C   ; 62 THERE IS A DOORWAY HERE
        .word $08B4   ; 63 YOU ARE AT A STAIRWAY
        .word $08CA   ; 64 YOU ARE IN A BOYS BEDROOM
        .word $08E4   ; 65 THERE IS WRITING ON IT
        .word $08FB   ; 66 YOU ARE IN AN OLD NURSERY. THERE IS A DEAD BODY HERE.
        .word $0931   ; 67 IT IS DR. GREEN.  IT APPEARS HE HAS BEEN STABBED
        .word $0962   ; 68 YOU ARE IN A LARGE BEDROOM
        .word $097D   ; 69 A DAGGER IS THROWN AT YOU FROM OUTSIDE THE ROOM.  IT MISSES!
        .word $09BA   ; 70 YOU ARE IN A SMALL BEDROOM. THERE IS A DEAD BODY HERE.
        .word $09F1   ; 71 IT IS SALLY, THE SEAMSTRESS.  SHE HAS A LARGE LUMP ON HER HE
        .word $0A55   ; 72 YOU ARE IN THE STUDY
        .word $0A6A   ; 73 ITS NICE BUT NOT EXACTLY MY CUP OF TEA. THANX FOR THE LOOK T
        .word $0AAD   ; 74 IT IS FASTENED TO THE WALL WITH FOUR BOLTS
        .word $0AD8   ; 75 THE PICTURE IS LOOSE
        .word $0AED   ; 76 THERE IS A BUTTON ON THE WALL
        .word $0B0B   ; 77 PART OF THE WALL OPENS
        .word $0B22   ; 78 YOU ARE IN THE ATTIC
        .word $0B37   ; 79 YOU SEE A FOREST
        .word $0B48   ; 80 WHAT TRAPDOOR?
        .word $0B57   ; 81 YOU ARE IN A STORAGE ROOM
        .word $0B71   ; 82 IT IS LOCKED
        .word $0B7E   ; 83 YOU HAVE NOTHING TO UNLOCK IT WITH
        .word $0BA1   ; 84 THERE IS ONE BULLET IN THE GUN
        .word $0BC0   ; 85 YOU ARE IN THE TOWER
        .word $0BD5   ; 86 DAISY WON'T LET YOU
        .word $0BE9   ; 87 SHE IS GOING TO KILL YOU
        .word $0C02   ; 88 SHE IS DEAD
        .word $0C0E   ; 89 YOU KILLED DAISY
        .word $0C1F   ; 90 DAISY STABBED YOU.  YOU ARE DEAD
        .word $0C40   ; 91 YOU ARE IN THE BATHROOM. THERE IS A DEAD BODY HERE.
        .word $0C74   ; 92 YOUR PITCHER IS FULL
        .word $0C89   ; 93 IT IS BILL, THE BUTCHER. HE HAS BEEN STRANGLED WITH A PAIR O
        .word $0CD1   ; 94 YOU ARE IN A MUSTY CRAWLSPACE
        .word $0CEF   ; 95 THE WALL CLOSES BEHIND YOU WITH A BANG
        .word $0D16   ; 96 IT WON'T OPEN
        .word $0D24   ; 97 YOU ARE ON A STAIRWAY
        .word $0D3A   ; 98 YOU ARE ON THE PORCH.  STONE STEPS LEAD DOWN TO THE FRONT YA
        .word $0D79   ; 99 YOU ARE IN THE FRONT YARD OF A LARGE ABANDONED VICTORIAN HOU
        .word $0DDE   ; 100 IT IS VERY HIGH
        .word $0DEE   ; 101 THERE IS A FOREST
        .word $0E00   ; 102 YOU ARE IN AN ENTRY HALL.  DOORWAYS GO EAST, WEST AND SOUTH.
        .word $0E51   ; 103 THE FRONT DOOR TO THE NORTH HAS BEEN CLOSED AND LOCKED
        .word $0E88   ; 104 YOU ARE IN THE OLD, DUSTY LIBRARY
        .word $0EAA   ; 105 THERE ARE NOT MANY BOOKS LEFT
        .word $0EC8   ; 106 IT IS TOO FAR DOWN
        .word $0EDB   ; 107 THERE ARE MATCHES HERE
        .word $0EF2   ; 108 A BUTTERKNIFE
        .word $0F00   ; 109 MATCHES
        .word $0F08   ; 110 A NOTE
        .word $0F0F   ; 111 A SKELETON KEY
        .word $0F1E   ; 112 A SMALL KEY
        .word $0F2A   ; 113 A SHOVEL
        .word $0F33   ; 114 A SLEDGEHAMMER
        .word $0F42   ; 115 A LIT CANDLE
        .word $0F4F   ; 116 AN UNLIT CANDLE
        .word $0F5F   ; 117 A DAGGER
        .word $0F68   ; 118 A GUN
        .word $0F6E   ; 119 A KNIFE
        .word $0F76   ; 120 A PICTURE
        .word $0F80   ; 121 A TOWEL
        .word $0F88   ; 122 A BRICK
        .word $0F90   ; 123 JEWELS
        .word $0F97   ; 124 A CABINET
        .word $0FA1   ; 125 AN EMPTY PITCHER
        .word $0FB2   ; 126 A PITCHER FULL OF WATER
        .word $0FCA   ; 127 IM NOT CARRYING THAT
        .word $0FDB   ; 128 THE DOOR IS CLOSED
        .word $0FEE   ; 129 IT IS OPEN
        .word $0FF9   ; 130 THE MATCH WENT OUT
        .word $100C   ; 131 I SEE NO WATER
        .word $101B   ; 132 YOU ARE NOT CARRYING IT
        .word $1033   ; 133 IT IS NOT OPEN
        .word $1042   ; 134 IT WONT CLOSE HERE
        .word $1055   ; 135 AN OPEN CABINET
        .word $1065   ; 136 IT IS UNLOCKED
        .word $1074   ; 137 I CANT GO IN THAT DIRECTION
        .word $1092   ; 138 IT'S TOO HEAVY TO LIFT
        .word $10A9   ; 139 IT WON'T MOVE ANY FARTHER
        .word $10C3   ; 140 THANK YOU FOR PLAYING HI-RES ADVENTURE ... GOOD-BYE
        .word $10F7   ; 141 TRY GOING IN SOME DIRECTION EX:NORTH,SOUTH,EAST,WEST,UP,DOWN
        .word $1134   ; 142 THE DOOR HAS BEEN CLOSED AND LOCKED
        .word $1158   ; 143 THERE IS A BUTTERKNIFE HERE
        .word $1174   ; 144 THE KITCHEN DOOR IS CLOSED
        .word $118F   ; 145 I DONT KNOW WHAT YOU MEAN
        .word $11A9   ; 146 I DONT SEE IT HERE
        .word $11BC   ; 147 YOU FALL TO EARTH. LUCKILY YOU HAVE ONLY MINOR INJURIES.
        .word $11F5   ; 148 UNFORTUNATELY THE AMBULANCE DRIVER SMASHS INTO A VOLKWAGEN. 
        .word $124D   ; 149 IF YOU FEEL THAT WAY I REFUSE TO PLAY WITH YOU...
        .word $127F   ; 150 YOU CLIMB UP BUMP YOUR HEAD ON THE CEILING AND FALL, DAZED B
        .word $12C5   ; 151 IT DOESNT MOVE
        .word $12D4   ; 152 I DONT SEE IT HERE
        .word $12E7   ; 153 I THINK I SEE A SLEDGEHAMMER HERE.
        .word $130A   ; 154 YOU DON'T HAVE IT
        .word $131C   ; 155 YOU HAVE NOTHING TO LIGHT IT WITH
        .word $133E   ; 156 YOU GO IN THE HOLE BUT CANNOT CONTINUE AND HAVE TO RETURN.
        .word $1379   ; 157 THANX. THAT FEELS EVER SO MUCH BETTER
        .word $139F   ; 158 THANK YOU. I LOVE TO FEEL CLEAN. THATS MUCH BETTER.
        .word $13D3   ; 159 I FEEL MUCH MORE RESTED NOW
        .word $13EF   ; 160 YOUR GUN IS NOW EMPTY
        .word $1405   ; 161 DAISY IS NOW DEAD
        .word $1417   ; 162 THE KITCHEN DOOR IS OPEN
        .word $1430   ; 163 THE PEOPLE WERE EXPLAINED AT THE BEGINNING OF THE GAME.
        .word $1468   ; 164 CONGRATULATIONS YOU HAVE BEATEN ADVENTURE AND ARE DECLARED A
        .word $14B1   ; 165 IF ONLY I COULD TELL IF I'D BEEN HERE BEFORE...
        .word $14E1   ; 166 DAISY IS ALREADY DEAD
        .word $14F7   ; 167  
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
        .hiasc "\x04OPEN MESSAGES\r\x04\r"
        .byte $00
        RTS
dead_blank_word:
        .hiasc "        "
dead_done_word:
        .hiasc "DONE    "
dead_init_tables:
        .byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
        .byte $00,$00,$00,$00
dead_disk_error_ptr:
        .word dead_disk_error

; the older disk-error handler: unlike the shipped one (disk_error_handler), its RTS follows
; the text directly; the shipped build put the OPEN-once flag in between
dead_disk_error:
        JSR old_rt_print
        .hiasc "\rA DISK ERROR HAS OCCURED"
        .byte $00
        RTS
; leftover memory, not used: lines here can be deleted to make room
        .byte $00,$00,$FF,$FF,$00,$00,$FF,$FF,$00,$00,$FF,$FF
        .byte $00,$00,$FF,$FF,$00,$00,$FF,$FF

; ==== shape table ====================================================================
; Applesoft shape table for the small objects (notes, matches, welcome mat, a door).
        .org $5700
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

; Unreachable older version of print_message's file path.
dead_read_message:
        LDA #$00
        STA floor_slot
        ASL lru_turn+1
        ROL floor_slot
        JSR old_rt_add16
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
dead_read_message.print_loop:
        LDA ($14),Y
        JSR COUT
        LDA ($14),Y
        INY
        CMP #$8D
        BNE dead_read_message.print_loop
        RTS

dead_read_message_cmd:
        JSR old_rt_print
        .hiasc "\x04READ MESSAGES,B$"
old_read_digits:
        .byte $00,$00,$00,$00     ; patched with the offset in hex
        .hiasc "\r"
        .byte $00
        JSR GETLN1
        LDA input_buffer
        STA lru_turn+1
        LDA input_buffer+1
        STA floor_slot
        JSR old_rt_print
        .hiasc "\x04\r"
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
dead_nibbles_to_ascii.loop:
        LDA old_hex_out,Y
        TAX
        LDA dead_hex_digits,X
        STA old_hex_out,Y
        INY
        CPY #$04
        BNE dead_nibbles_to_ascii.loop
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
        STA AWORK
        STA rule_ptr
        LDA command_rules_addr+1
        STA AWORK+1
        STA rule_ptr+1
        JMP run_command_rules.loop
command_rules_addr:
        .byte $00,$45
run_command_rules.loop:
        JSR test_rule
        LDA cmp_result
        CMP #$01
        BEQ run_command_rules.done
        JSR next_rule
        LDA cmp_result
        CMP #HV
        BNE run_command_rules.loop
        LDX #MSG_DONT_UNDERSTAND
        JSR print_message
run_command_rules.done:
        RTS

; Run every matching turn rule (match timers, darkness, the winning check), whatever happened
; to the command.
run_turn_rules:
        LDA turn_rules_addr
        STA AWORK
        STA rule_ptr
        LDA turn_rules_addr+1
        STA AWORK+1
        STA rule_ptr+1
        JMP run_turn_rules.loop
turn_rules_addr:
        .byte $00,$44
run_turn_rules.loop:
        JSR test_rule
        JSR next_rule
        LDA cmp_result
        CMP #HV
        BNE run_turn_rules.loop
        RTS

; Test the rule at rule_ptr: room, verb and noun must match (ANY matches everything). If they
; do, AWORK steps through the conditions; each condition handler continues at cond_pass or
; cond_fail, and when all have passed rule_done runs the actions.
; cmp_result: 0 = header did not match, 1 = header matched (and conditions passed unless a
; condition reset it to 0).
test_rule:
        LDA #$00
        STA cmp_result
        LDY #RULE_ROOM
        LDA (rule_ptr),Y
        CMP #ANY
        BEQ test_rule.check_verb
        CMP room_no
        BEQ test_rule.check_verb
        JMP rule_done
test_rule.check_verb:
        LDY #RULE_VERB
        LDA (rule_ptr),Y
        CMP #ANY
        BEQ test_rule.check_noun
        CMP verb
        BEQ test_rule.check_noun
        JMP rule_done
test_rule.check_noun:
        LDY #RULE_NOUN
        LDA (rule_ptr),Y
        CMP #ANY
        BEQ test_rule.matched
        CMP noun
        BEQ test_rule.matched
        JMP rule_done
test_rule.matched:
        LDY #RULE_NCOND
        LDA (rule_ptr),Y
        STA counter
        LDA #$01
        STA cmp_result
        LDX #6
        JSR rt_add8
        .word AWORK

; Dispatch the condition at AWORK through tbl_conditions, or run the actions when counter
; (conditions left) reaches 0. Condition handlers read their operands at (AWORK),Y.
next_condition:
        LDA counter
        BNE next_condition.dispatch
        JMP rule_done
next_condition.dispatch:
        LDY #$00
        LDA (AWORK),Y
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
        LDA (AWORK),Y
        TAX
        JSR find_object
        LDY #OROOM
        LDA (found_obj),Y
        STA cond_value
        LDY #ARG_Y
        LDA (AWORK),Y
        LDX #2
        CMP cond_value
        BEQ cond_pass
        JMP cond_fail

; Condition 5: turns > ARG_X. Fails whenever the turn counter's high byte is set, so from turn
; 256 on it is never true.
cond_turns_gt:
        LDA turns+1
        LDX #1
        CMP #$00
        BNE cond_fail
        LDY #ARG_X
        LDA (AWORK),Y
        CMP turns
        BCS cond_fail
        JMP cond_pass

; Condition 6: SWITCH[ARG_X] == ARG_Y.
cond_switch_eq:
        LDX #2
        LDY #ARG_X
        LDA (AWORK),Y
        TAY
        LDA SWITCH,Y
        STA cond_value
        LDY #ARG_Y
        LDA (AWORK),Y
        CMP cond_value
        BEQ cond_pass
        JMP cond_fail

; Condition 9: the picture on screen is ARG_X (close-up views).
cond_view_is:
        LDX #1
        LDY #ARG_X
        LDA (AWORK),Y
        CMP shown_picture
        BEQ cond_pass
        JMP cond_fail

; Condition 10: object ARG_X is drawn as picture ARG_Y.
cond_obj_pic_is:
        LDY #ARG_X
        LDA (AWORK),Y
        TAX
        JSR find_object
        LDY #OPIC
        LDA (found_obj),Y
        STA cond_value
        LDY #ARG_Y
        LDA (AWORK),Y
        LDX #2
        CMP cond_value
        BEQ cond_pass
        JMP cond_fail

; Condition true: step AWORK past it (opcode + X operand bytes) and test the next one.
cond_pass:
        INX
        JSR rt_add8
        .word AWORK
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
        BEQ rule_done.run
        RTS
rule_done.run:
        JSR run_actions
        RTS

; Advance rule_ptr (and AWORK) by RULE_LEN. cmp_result = HV at the end of the table, else 0.
next_rule:
        LDY #RULE_LEN
        LDA (rule_ptr),Y
        TAX
        JSR rt_add8
        .word rule_ptr
        LDA rule_ptr
        STA AWORK
        LDA rule_ptr+1
        STA AWORK+1
        LDY #$00
        LDA (AWORK),Y
        CMP #HV
        BEQ next_rule.at_end
        LDA #$00
        STA cmp_result
        RTS
next_rule.at_end:
        LDA #$FF
        STA cmp_result
        RTS

; found_obj = the record of object X. Walks OBJBASE by ONEXT; hitting HV is a BRK (the
; source comments it ";UH-OH, KABOOM!").
find_object:
        STX find_id
        LDA objbase_addr
        STA found_obj
        LDA objbase_addr+1
        STA found_obj+1
        JMP find_object.loop
objbase_addr:
        .byte $00,$09
find_object.loop:
        LDY #OBJECTNO
        LDA (found_obj),Y
        CMP find_id
        BEQ find_object.found
        CMP #HV
        BNE find_object.next
        BRK
find_object.next:
        LDY #ONEXT
        LDA (found_obj),Y
        TAX
        JSR rt_add8
        .word found_obj
        JMP find_object.loop
find_object.found:
        RTS
        .incbin "data/adventure_5BB9.bin"    ; $5BB9-$5DFF fill
        .org $5E00

; The game loop. Draw first, then read and act: a change made by an action shows on the next
; turn's redraw.
main:
        JSR init_game
main.turn:
        JSR draw_room
        JSR read_command
        JSR run_rules
        JSR nothing
        LDX #1
        JSR rt_add8
        .word turns
        JMP main.turn
        .incbin "data/adventure_5E19.bin"    ; $5E19-$60FF leftover memory, not used by the code (see NOTES.md)
        .org $6100

; Start (or restart) a game: room 1, turn 1, switches and picture cache cleared, CUROOM at
; room 1, HPLOT colour white, the custom DOS error handler installed, MESSAGES opened (once),
; hi-res page 1 with four lines of text.
init_game:
        LDA #$01
        STA turns
        LDA #$00
        STA turns+1
        LDA #$01
        STA room_no
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
        JSR rt_add8
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
        BEQ init_game.opened
        LDA #$FF
        STA messages_open          ; OPEN MESSAGES only on the first game
        JSR rt_print
        .hiasc "\x04OPEN MESSAGES\r\x04\r"
        .byte $00
init_game.opened:
        LDA #$00
        STA LAMPSTAT
        LDA TXTCLR
        LDA MIXSET
        LDA HIRES
        JSR rt_print
        .hiasc "\r\r\r\r\r"
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
        .byte $15,$62

; Installed in dos_error_vector by init_game. Prints the message, then falls into
; messages_open (see there).
disk_error_handler:
        JSR rt_print
        .hiasc "\rA DISK ERROR HAS OCCURED"
        .byte $00
; The flag byte sits between the text's terminator and the RTS, so rt_print "returns" into it:
; it executes $00 (BRK) before init_game has run and $FF (an undocumented 3-byte opcode that
; swallows the RTS) afterwards. A disk error therefore never returns cleanly. The older handler
; (dead_disk_error) had the RTS straight after the text.
messages_open:
        .byte $00                 ; $FF once MESSAGES has been OPENed (init_game)
        RTS
        .incbin "data/adventure_6234.bin"    ; $6234-$62FF leftover memory: the assembler's symbol table (see NOTES.md)
        .org $6300

; Prompt, read a line and parse it into verb and noun numbers. The first word must be a verb
; and the second a noun; an unknown word prints "I DONT KNOW HOW TO <word> SOMETHING" (or
; "... <verb> A <noun>") by copying the words into the message text, and asks again.
; A blank second word looks up as N_NONE (eight spaces is in the noun table).
read_command:
        LDA #$00
        STA cmd_state
        JSR print_prompt
        JSR get_line
        JSR next_word
        JSR lookup_word
        .word verb_table
        LDA word_id
        CMP #NOT_FOUND
        BEQ read_command.unknown_verb
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
        BEQ read_command.unknown_noun
        STA noun
        LDX #WORDLEN
        JSR rt_copy
        .word word_buf
        .word noun_word
        RTS
        .byte $60
read_command.unknown_verb:
        LDX #WORDLEN
        JSR rt_copy
        .word word_buf
        .word unknown_verb_text
        JSR rt_print
        .hiasc "I DONT KNOW HOW TO          SOMETHING\r"
        .byte $00
        JMP read_command
read_command.unknown_noun:
        LDX #WORDLEN
        JSR rt_copy
        .word verb_word
        .word unknown_noun_verb
        LDX #WORDLEN
        JSR rt_copy
        .word word_buf
        .word unknown_noun_text
        JSR rt_print
        .hiasc "I DONT KNOW HOW TO          A         \r"
        .byte $00
        JMP read_command

; Print the separator and ENTER COMMAND.
print_prompt:
        JSR rt_print
        .hiasc "--------------- ENTER COMMAND"
        .byte $00
        RTS

; Read a line into input_buffer with the Monitor's GETLN (no prompt character). RETURN on its
; own toggles between the picture (mixed mode) and a full text page, so earlier messages can be
; reread.
get_line:
        LDA #$BF
        STA prompt_char
        JSR GETLN
        LDA input_buffer
        CMP #HI_CR
        BEQ get_line.empty
        STX input_len
        LDA #$00
        STA parse_pos
        RTS
get_line.empty:
        LDA text_mode
        CMP #$FF
        BEQ get_line.show_picture
        LDA #$FF
        STA text_mode
        LDA TXTSET
        JMP get_line
get_line.show_picture:
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
next_word.skip_blanks:
        LDA input_buffer,Y
        CMP #INPUT_END
        BEQ next_word.done
        CMP #HI_SPACE
        BNE next_word.start_word
        INY
        JMP next_word.skip_blanks
next_word.start_word:
        LDX #$00
next_word.store_char:
        STA word_buf,X
next_word.next_char:
        INY
        INX
        LDA input_buffer,Y
        CMP #INPUT_END
        BEQ next_word.done
        CMP #HI_SPACE
        BEQ next_word.done
        CPX #WORDLEN
        BCS next_word.next_char
        JMP next_word.store_char
next_word.done:
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
        STA AWORK
        INY
        LDA (rt_operands),Y
        STA AWORK+1
lookup_word.next_group:
        INC word_id
        LDX #WORDLEN
        JSR rt_compare
        .word word_buf
        LDA cmp_result
        CMP #$00
        BEQ lookup_word.done
        LDX #8
        JSR rt_add8
        .word AWORK
        LDY #$00
        LDA (AWORK),Y
        CMP #HV
        BNE lookup_word.check_synonyms
        LDA #NOT_FOUND
        STA word_id
        JMP lookup_word.done
lookup_word.check_synonyms:
        CMP #$00
        BNE lookup_word.synonyms
        JSR rt_inc16
        .word AWORK
        JMP lookup_word.next_group
lookup_word.synonyms:
        LDA (AWORK),Y
        STA counter
        JSR rt_inc16
        .word AWORK
lookup_word.next_synonym:
        LDA counter
        BEQ lookup_word.next_group
        LDX #WORDLEN
        JSR rt_compare
        .word word_buf
        LDA cmp_result
        CMP #$00
        BEQ lookup_word.done
        LDX #8
        JSR rt_add8
        .word AWORK
        DEC counter
        JMP lookup_word.next_synonym
lookup_word.done:
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

; Run the rule's actions: action_ptr = AWORK (just past the conditions), actions_left =
; RULE_NACT. Each action handler (ACnn00) leaves through AC9000, which steps action_ptr past it
; and dispatches the next one through tbl_actions.
run_actions:
        LDA AWORK
        STA action_ptr
        LDA AWORK+1
        STA action_ptr+1
        LDY #RULE_NACT
        LDA (rule_ptr),Y
        STA actions_left

; Dispatch the action at action_ptr, or return when none are left.
next_action:
        LDA actions_left
        BEQ stop_actions
        LDA action_ptr
        STA ZWORK
        LDA action_ptr+1
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
        STX act_temp
        ADC act_temp
        STA SWITCH,Y
        LDX #2
        JMP AC9000

; action 2: SWITCH[Y] -= X
AC1200:
        LDY #ARG_X
        LDA (ZWORK),Y
        STA act_temp
        LDY #ARG_Y
        LDA (ZWORK),Y
        TAY
        LDA SWITCH,Y
        SEC
        SBC act_temp
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
AC1400.loop:
        LDY #OBJECTNO
        LDA (ZAWORK),Y
        CMP #HV
        BEQ AC1400.done
        LDY #OROOM
        LDA (ZAWORK),Y
        CMP #CARRYING
        BEQ AC1400.list_it
AC1400.next:
        LDY #ONEXT
        LDA (ZAWORK),Y
        TAX
        JSR rt_add8
        .word ZAWORK
        JMP AC1400.loop
AC1400.list_it:
        LDY #OMSG
        LDA (ZAWORK),Y
        TAX
        JSR print_message
        JMP AC1400.next
AC1400.done:
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
        STA act_temp
        LDY #ARG_Y
        LDA (ZWORK),Y
        STA act_word1
AC1500.loop:
        LDY #OBJECTNO
        LDA (ZAWORK),Y
        CMP #HV
        BNE AC1500.check_id
        BRK
AC1500.check_id:
        CMP act_temp
        BEQ AC1500.found
        LDY #ONEXT
        LDA (ZAWORK),Y
        TAX
        JSR rt_add8
        .word ZAWORK
        JMP AC1500.loop
AC1500.found:
        LDY #OROOM
        LDA act_word1
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
        STA act_word1
        LDA #>ROOMBASE
        STA act_word1+1
        LDY #ARG_X
        LDA (ZWORK),Y
        STA act_word2
        STA room_no
        LDA #$00
        STA act_word2+1
        LDX #RTBLSIZ
        JSR rt_mul8
        .word act_word2
        JSR rt_add16
        .word act_word2
        .word act_word1
        LDA act_word1
        STA CUROOM
        LDA act_word1+1
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
        JSR print_message
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
        JSR print_message
        JMP dos_warm_start

; action 14: unused (BRK)
AC2400:
        BRK

; action 15: save game (BSAVE SAVED GAME,A$830,L$8CF)
AC2500:
        JSR rt_print
        .hiasc "\x04BSAVE SAVED GAME,A$830,L$8CF\r"
        .byte $00
        LDX #0
        JMP AC9000

; Action 16: restore game. BLOADs the save file over $0830-$10FE (variables, objects, rooms),
; empties the picture cache so blocks are reloaded, then puts back the action pointer saved
; before the load. Bug: both bytes are stored into action_ptr's low byte; the high byte keeps
; the value from the save file.
AC2600:
        LDA action_ptr
        STA ZAWORK
        LDA action_ptr+1
        STA ZAWORK+1
        JSR rt_print
        .hiasc "\x04BLOAD SAVED GAME,A$830\r"
        .byte $00
        LDX #$14
        LDA #$00
AC2600.clear_cache:
        STA pic_cache,X
        DEX
        BNE AC2600.clear_cache
        STA pic_cache
        LDA ZAWORK
        STA action_ptr             ; bug: both bytes go to the low byte
        LDA ZAWORK+1
        STA action_ptr             ; bug: both bytes go to the low byte
        LDX #0
        JMP AC9000

; Action 17: game over. "WOULD YOU LIKE TO PLAY AGAIN": N quits (AC2300), anything else BLOADs
; STARTUP (the initial objects and rooms), clears the screen and restarts at main.
AC2700:
        JSR rt_print
        .hiasc "WOULD YOU LIKE TO PLAY AGAIN"
        .byte $00
        JSR GETLN1
        LDA input_buffer
        CMP #'N'|$80
        BEQ AC2700.quit
        LDA action_ptr
        STA ZAWORK
        LDA action_ptr+1
        STA ZAWORK+1
        JSR rt_print
        .hiasc "\x04BLOAD STARTUP\r"
        .byte $00
        JSR hgr
        JSR rt_print
        .hiasc "PRESS RETURN TO BEGIN PLAY"
        .byte $00
        JMP main
AC2700.quit:
        JMP AC2300

; action 18: put object X in room Y at (x, y)
AC2800:
        LDY #ARG_X
        LDA (ZWORK),Y
        STA act_arg1
        LDY #ARG_Y
        LDA (ZWORK),Y
        STA act_arg2
        LDY #ARG_3
        LDA (ZWORK),Y
        STA act_arg3
        LDY #ARG_4
        LDA (ZWORK),Y
        STA act_arg4
        LDA #<OBJBASE
        STA ZAWORK
        LDA #>OBJBASE
        STA ZAWORK+1
AC2800.loop:
        LDY #OBJECTNO
        LDA (ZAWORK),Y
        CMP act_arg1
        BEQ AC2800.found
        LDY #ONEXT
        LDA (ZAWORK),Y
        TAX
        JSR rt_add8
        .word ZAWORK
        JMP AC2800.loop
AC2800.found:
        LDY #OROOM
        LDA act_arg2
        STA (ZAWORK),Y
        LDY #OXCOORD
        LDA act_arg3
        STA (ZAWORK),Y
        LDY #OYCOORD
        LDA act_arg4
        STA (ZAWORK),Y
        LDX #4
        JMP AC9000

; action 19: make picture X the shape for object Y
AC2900:
        LDY #ARG_X
        LDA (ZWORK),Y
        STA act_arg1
        LDY #ARG_Y
        LDA (ZWORK),Y
        STA act_arg2
        LDA #<OBJBASE
        STA ZAWORK
        LDA #>OBJBASE
        STA ZAWORK+1
AC2900.loop:
        LDY #OBJECTNO
        LDA (ZAWORK),Y
        CMP #HV
        BNE AC2900.check_id
        BRK
AC2900.check_id:
        CMP act_arg2
        BEQ AC2900.found
        LDY #ONEXT
        LDA (ZAWORK),Y
        TAX
        JSR rt_add8
        .word ZAWORK
        JMP AC2900.loop
AC2900.found:
        LDY #OPIC
        LDA act_arg1
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
        STA act_arg1
        JMP ACNEWROM

; action 22: go south
AC3200:
        LDY #RS
        LDA (CUROOM),Y
        STA act_arg1
        JMP ACNEWROM

; action 23: go east
AC3300:
        LDY #RE
        LDA (CUROOM),Y
        STA act_arg1
        JMP ACNEWROM

; action 24: go west
AC3400:
        LDY #RW
        LDA (CUROOM),Y
        STA act_arg1
        JMP ACNEWROM

; action 25: go up
AC3500:
        LDY #RU
        LDA (CUROOM),Y
        STA act_arg1
        JMP ACNEWROM

; action 26: go down
AC3600:
        LDY #RD
        LDA (CUROOM),Y
        STA act_arg1
        JMP ACNEWROM

; Move through exit act_arg1 of the current room (0 = "I CANT GO IN THAT DIRECTION"). The room
; left reverts to its permanent view. Bug: act_word1's low byte is never set to the new room
; number before the multiply, so CUROOM is wrong until draw_room rebuilds it from room_no at
; the start of the next turn; nothing reads it in between. Ends the action list.
ACNEWROM:
        LDA act_arg1
        CMP #$00
        BNE ACNEWROM.move
        LDX #MSG_CANT_GO
        JSR print_message
        JMP ACNEWROM.done
ACNEWROM.move:
        LDA #$00
        STA act_word1+1
        LDA act_arg1
        STA room_no
        LDX #RTBLSIZ
        LDY #RBASEPIC
        LDA (CUROOM),Y
        LDY #RCURPIC
        STA (CUROOM),Y
        JSR rt_mul8
        .word act_word1
        LDA #<ROOMBASE
        STA act_word2
        LDA #>ROOMBASE
        STA act_word2+1
        JSR rt_add16
        .word act_word1
        .word act_word2
        LDA act_word2
        STA CUROOM
        LDA act_word2+1
        STA CUROOM+1
ACNEWROM.done:
        LDX #0
        JMP stop_actions

; Action 27: take the object named by the command's noun. Only an object in this room counts.
; OFIXED -> "IT DOESNT MOVE". OMOVED objects can always be taken; an OMOVABLE one only when
; the picture on screen is one it appears in (ORPICSTA). Otherwise "I DONT SEE IT HERE".
AC3700:
        LDY noun
        STY act_arg1
        LDA #<OBJBASE
        STA ZAWORK
        LDA #>OBJBASE
        STA ZAWORK+1
AC3700.loop:
        LDY #OBJECTNO
        LDA (ZAWORK),Y
        CMP #HV
        BEQ AC3700.not_here
        LDY #ONOUN
        LDA (ZAWORK),Y
        CMP act_arg1
        BNE AC3700.next
        LDY #OROOM
        LDA (ZAWORK),Y
        CMP room_no
        BNE AC3700.next
        LDY #OSTATUS
        LDA (ZAWORK),Y
        CMP #OFIXED
        BNE AC3700.not_fixed
        LDX #MSG_DOESNT_MOVE
        JSR print_message
        JMP AC3700.done
AC3700.next:
        LDY #ONEXT
        LDA (ZAWORK),Y
        TAX
        JSR rt_add8
        .word ZAWORK
        JMP AC3700.loop
AC3700.not_fixed:
        LDY #OSTATUS
        LDA (ZAWORK),Y
        CMP #OMOVED
        BEQ AC3700.take
        LDY #RCURPIC
        LDA (CUROOM),Y
        STA act_word1
        LDY #ORPICKT
        LDA (ZAWORK),Y
        STA act_word2
        LDY #$0B
AC3700.check_pic:
        LDX act_word2
        BEQ AC3700.next
        LDA (ZAWORK),Y
        CMP act_word1
        BEQ AC3700.take
        INY
        LDX act_word2
        DEX
        STX act_word2
        JMP AC3700.check_pic
AC3700.take:
        LDA #CARRYING
        LDY #OROOM
        STA (ZAWORK),Y
        LDA #OMOVED
        LDY #OSTATUS
        STA (ZAWORK),Y
        JMP AC3700.done
AC3700.not_here:
        LDX #MSG_DONT_SEE_IT
        JSR print_message
AC3700.done:
        LDX #0
        JMP AC9000

; Action 28: drop the object named by the command's noun into this room, as OMOVED (drawn in
; the next floor slot). Not carried -> "I DONT UNDERSTAND WHAT YOU MEAN".
AC3800:
        LDA #<OBJBASE
        STA ZAWORK
        LDA #>OBJBASE
        STA ZAWORK+1
AC3800.loop:
        LDY #OBJECTNO
        LDA (ZAWORK),Y
        CMP #HV
        BEQ AC3800.not_carried
        LDY #ONOUN
        LDA (ZAWORK),Y
        CMP noun
        BNE AC3800.next
        LDY #OROOM
        LDA (ZAWORK),Y
        CMP #CARRYING
        BNE AC3800.next
        LDY #OROOM
        LDA room_no
        STA (ZAWORK),Y
        LDA #OMOVED
        LDY #OSTATUS
        STA (ZAWORK),Y
        JMP AC3800.done
AC3800.next:
        LDY #ONEXT
        LDA (ZAWORK),Y
        TAX
        JSR rt_add8
        .word ZAWORK
        JMP AC3800.loop
AC3800.not_carried:
        LDX #MSG_DONT_UNDERSTAND
        JSR print_message
AC3800.done:
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
        STA act_word1
        LDY #ARG_Y
        LDA (ZWORK),Y
        STA act_word2
        LDA #$00
        STA act_word1+1
        LDX #RTBLSIZ
        JSR rt_mul8
        .word act_word1
        JSR rt_add16
        .word act_word1
        .word ZAWORK
        LDA act_word2
        LDY #RBASEPIC
        STA (ZAWORK),Y
        LDY #RCURPIC
        STA (ZAWORK),Y
        LDX #2
        JMP AC9000

; Common exit of every action handler: action_ptr += 1 + X (the opcode and X operand bytes),
; one fewer action left, next one.
AC9000:
        INX
        JSR rt_add8
        .word action_ptr
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
; A copy of the Applesoft ROM's HGR/HPOSN/HPLOT/HGLIN/DRAW code, moved here and changed to use
; $0320-$032A for Applesoft's HGR.* variables ($E0-$EA) and the engine's applesoft_vars for
; the HPLOT/DRAW arguments. Labels inside follow the ROM's structure; the Lxxxx ones are left
; unnamed.
;
; HGR: show hi-res page 1 in mixed mode and clear it.
hgr:
        LDA #$20
        STA hgr_page
        LDA HIRES
        LDA MIXSET
        LDA TXTCLR
hclr:
        LDA #$00
        STA hgr_bits
        LDA hgr_page
        STA hgr_shape_ptr+1
        LDY #$00
        STY hgr_shape_ptr
L6A1B:
        LDA hgr_bits
        STA (hgr_shape_ptr),Y
        JSR color_shift
        INY
        BNE L6A1B
        INC hgr_shape_ptr+1
        LDA hgr_shape_ptr+1
        AND #$1F
        BNE L6A1B
        RTS

; Applesoft HPOSN
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
        BEQ L6A63
        LDY #$23
        ADC #$04
L6A62:
        INY
L6A63:
        SBC #$07
        BCS L6A62
        STY hgr_horiz
        TAX
        LDA L6AEA,X
        STA hmask
        TYA
        LSR A
        LDA hgr_color

hgr_set_bits:
        STA hgr_bits
        BCS color_shift
        RTS

; Applesoft HPLOT0
hplot0:
        .byte $20,$2E,$6A
hplot_here:
        LDA hgr_bits
        EOR (hbasl),Y
        AND hmask
        EOR (hbasl),Y
        STA (hbasl),Y
        RTS

; Applesoft MOVE_LEFT_OR_RIGHT
move_left_or_right:
        BPL L6AAE
        LDA hmask
        LSR A
        BCS L6A94
        EOR #$C0
L6A91:
        STA hmask
        RTS
L6A94:
        DEY
        BPL L6A99
        LDY #$27
L6A99:
        LDA #$C0
L6A9B:
        STA hmask
        STY hgr_horiz
        LDA hgr_bits

; Applesoft COLOR.SHIFT
color_shift:
        ASL A
        CMP #$C0
        BPL L6AAD
        LDA hgr_bits
        EOR #$7F
        STA hgr_bits
L6AAD:
        RTS
L6AAE:
        LDA hmask
        ASL A
        EOR #$80
        BMI L6A91
        LDA #$81
        INY
        CPY #$28
        BCC L6A9B
        LDY #$00
        BCS L6A9B
        CLC
        LDA hgr_dx+1
        AND #$04
        BEQ L6AEE
        LDA #$7F
        AND hmask
        AND (hbasl),Y
        BNE L6AEA
        INC hgr_collisions
        LDA #$7F
        AND hmask
        BPL L6AEA

draw_move_ud_plot:
        CLC

draw_move_ud:
        LDA hgr_dx+1
        AND #$04
        BEQ L6AEE
        LDA (hbasl),Y
        EOR hgr_bits
        AND hmask
        BNE L6AEA
        INC hgr_collisions
L6AEA:
        EOR (hbasl),Y
        STA (hbasl),Y
L6AEE:
        LDA hgr_dx+1
        ADC hgr_quadrant
        AND #$03
        CMP #$02
        ROR A
        BCS move_left_or_right

move_down:
        BMI L6B2B
        CLC
        LDA hbasl+1
        BIT hgr_mask_table_m1
        BNE L6B25
        ASL hbasl
        BCS L6B21
        BIT L6AEE+5                ; BIT on the constant $03 in the AND above (an Applesoft trick)
        BEQ L6B11
        ADC #$1F
        SEC
        BCS L6B23
L6B11:
        ADC #$23
        PHA
        LDA hbasl
        ADC #$B0
        BCS L6B1C
        ADC #$F0
L6B1C:
        STA hbasl
        PLA
        BCS L6B23
L6B21:
        ADC #$1F
L6B23:
        ROR hbasl
L6B25:
        ADC #$FC
L6B27:
        STA hbasl+1
        RTS
        .byte $18
L6B2B:
        LDA hbasl+1
        ADC #$04
        BIT hgr_mask_table_m1
        BNE L6B27
        ASL hbasl
        BCC L6B51
        ADC #$E0
        CLC
        BIT L6B2B+3                ; BIT on the constant $04 in the ADC above (an Applesoft trick)
        BEQ L6B53
        LDA hbasl
        ADC #$50
        EOR #$F0
        BEQ L6B4A
        EOR #$F0
L6B4A:
        STA hbasl
        LDA hgr_page
        BCC L6B53
L6B51:
        ADC #$E0
L6B53:
        ROR hbasl
        BCC L6B27
        PHA
        LDA #$00
        STA hgr_x
        STA hgr_x+1
        STA hgr_y
        PLA

; Applesoft HGLIN: line from the current point
hglin:
        PHA
        SEC
        SBC hgr_x
        PHA
        TXA
        SBC hgr_x+1
        STA hgr_quadrant
        BCS L6B7C
        PLA
        EOR #$FF
        ADC #$01
        PHA
        LDA #$00
        SBC hgr_quadrant
L6B7C:
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
        BCC L6B97
        EOR #$FF
        ADC #$FE
L6B97:
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
        BCS L6BB2
L6BAD:
        ASL A
        JSR move_left_or_right
        SEC
L6BB2:
        LDA hgr_err
        ADC hgr_dy
        STA hgr_err
        LDA hgr_err+1
        SBC #$00
L6BBC:
        STA hgr_err+1
        LDA (hbasl),Y
        EOR hgr_bits
        AND hmask
        EOR (hbasl),Y
        STA (hbasl),Y
        INX
        BNE L6BCF
        INC hgr_count_hi
        BEQ L6C3A
L6BCF:
        LDA hgr_quadrant
        BCS L6BAD
        JSR move_down
        CLC
        LDA hgr_err
        ADC hgr_dx
        STA hgr_err
        LDA hgr_err+1
        ADC hgr_dx+1
        BVC L6BBC                  ; always taken: V is clear here
        .byte $81,$82,$84,$88,$90,$A0,$C0
hgr_mask_table_m1:
        .byte $1C
hgr_mask_table:
        .byte $FF,$FE,$FA,$F4,$EC,$E1,$D4,$C5,$B4,$A1,$8D,$78,$61,$49,$31,$18
        .byte $FF,$A5,$26,$0A,$A5,$27,$29,$03,$2A,$05,$26,$0A,$0A,$0A,$8D,$22
        .byte $03,$A5,$27,$4A,$4A,$29,$07,$0D,$22,$03,$8D,$22,$03,$AD,$25,$03
        .byte $0A,$6D,$25,$03,$0A,$AA,$CA,$A5,$30,$29,$7F,$E8,$4A,$D0,$FC,$8D
        .byte $21,$03,$8A,$18,$6D,$25,$03,$90,$03,$EE,$21,$03,$8D,$20,$03
L6C3A:
        RTS

; Applesoft DRAW0
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
        LDY hgr_mask_table,X
        STY hgr_dx
        EOR #$0F
        TAX
        LDY hgr_mask_table+1,X
        INY
        STY hgr_dy
        LDY hgr_horiz
        LDX #$00
        STX hgr_collisions
        LDA (hgr_shape_ptr,X)
L6C62:
        STA hgr_dx+1
        LDX #$80
        STX hgr_err
        STX hgr_err+1
        LDX hgr_scale
L6C6D:
        LDA hgr_err
        SEC
        ADC hgr_dx
        STA hgr_err
        BCC L6C7A
        JSR draw_move_ud_plot
        CLC
L6C7A:
        LDA hgr_err+1
        ADC hgr_dy
        STA hgr_err+1
        BCC L6C85
        JSR draw_move_ud
L6C85:
        DEX
        BNE L6C6D
        LDA hgr_dx+1
        LSR A
        LSR A
        LSR A
        BNE L6C62
        INC hgr_shape_ptr
        BNE L6C95
        INC hgr_shape_ptr+1
L6C95:
        LDA (hgr_shape_ptr,X)
        BNE L6C62
        RTS
; leftover memory, not used: lines here can be deleted to make room
        .byte $86,$1A,$84,$1B,$AA,$4A,$4A,$4A,$4A,$85,$53,$8A,$29,$0F,$AA,$BC
        .byte $EB,$6B,$84,$50,$49,$0F,$AA,$BC,$EC,$6B,$C8,$84,$52,$AC,$25,$03
        .byte $A2,$00,$8E,$2A,$03,$A1,$1A,$85,$51,$A2,$80,$86,$54,$86,$55,$AE
        .byte $27,$03,$A5,$54,$38,$65,$50,$85,$54,$90,$04,$20,$C0,$6A,$18,$A5
        .byte $55,$65,$52,$85,$55,$90,$03,$20,$D9,$6A,$CA,$D0,$E5,$A5,$51,$4A
        .byte $4A,$4A,$D0,$D3,$E6,$1A,$D0,$02,$E6,$1B,$A1,$1A,$D0,$C9,$60

; HFNS: read var_x / var_y and position the pen there (HPOSN).
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

; HPLOT var_x,var_y
hplot_xy:
        JSR hfns
        JMP hplot_here

; HPLOT TO var_x,var_y
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
        .byte $20,$90,$6D,$4C,$10,$6A

; DRAW var_shape AT var_x,var_y
draw_shape:
        JSR hfns
        JSR find_shape
        JSR draw0
        LDX hgr_saved_x
        RTS
        .byte $20,$F9,$6C,$20,$51,$6D,$20,$9A,$6C,$AE,$23,$03,$60

; Look up var_shape in the shape table (1..count) for DRAW0.
find_shape:
        STX hgr_saved_x
        LDY #$32
        LDA #$01
        NOP
        STA hgr_scale
        LDY #$28
        JSR get_var
        PHA
        LDA hgr_shape_table
        STA hgr_shape_ptr
        LDA hgr_shape_table+1
        STA hgr_shape_ptr+1
        LDY #$20
        JSR get_var
        BEQ quantity_error
        LDX #0
        CMP (hgr_shape_ptr,X)
        BEQ L6D7B
        BCS quantity_error
L6D7B:
        ASL A
        BCC L6D81
        INC hgr_shape_ptr+1
        CLC
L6D81:
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

; Read HCOLOR from var_hcolor (must be < 256).
get_hcolor:
        LDY #$16

; Read the variable at applesoft_vars + Y; a high byte other than 0 is an error.
get_var:
        LDA (fake_vartab),Y
        BNE quantity_error
        DEY
        LDA (fake_vartab),Y
L6D99:
        RTS

; X coordinate: must be < 280.
get_var_x:
        STX hgr_saved_x
        LDY #$05
        LDA (fake_vartab),Y
        TAX
        INY
        LDA (fake_vartab),Y
        TAY
        CPX #$18
        SBC #$01
        BCC L6D99

; Bad coordinate: Applesoft's error routine.
quantity_error:
        JMP applesoft_error

; Y coordinate: must be < 192.
get_var_y:
        LDY #$0D
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
        .org $7000

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
draw_objects.loop:
        LDY #OBJECTNO
        LDA (ZWORK),Y
        CMP #HV
        BNE draw_objects.check_room
        JMP draw_objects.done
draw_objects.check_room:
        LDY #OROOM
        LDA (ZWORK),Y
        CMP room_no
        BEQ draw_objects.in_room
draw_objects.next:
        LDY #ONEXT
        LDA (ZWORK),Y
        TAX
        JSR rt_add8
        .word ZWORK
        JMP draw_objects.loop
draw_objects.in_room:
        LDY #OSTATUS
        LDA (ZWORK),Y
        CMP #OMOVED
        BEQ draw_objects.moved
        LDY #ORPICKT
        LDA (ZWORK),Y
        STA counter
draw_objects.check_pic:
        LDA counter
        BEQ draw_objects.next
        LDY #$0B
        CLC
        DEY
        TYA
        ADC counter
        TAY
        LDA (ZWORK),Y
        CMP shown_picture
        BEQ draw_objects.visible
        LDY counter
        DEY
        STY counter
        JMP draw_objects.check_pic
draw_objects.visible:
        JSR draw_object_in_place
        JMP draw_objects.next
draw_objects.moved:
        LDY #RBASEPIC
        LDA (CUROOM),Y
        LDY #RCURPIC
        CMP (CUROOM),Y
        BNE draw_objects.next
        JSR draw_object_on_floor
        JMP draw_objects.next

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
        BEQ draw_object.shape
        LDA ZWORK
        STA saved_zwork
        LDA ZWORK+1
        STA saved_zwork+1
        JSR draw_picture
        LDA saved_zwork
        STA ZWORK
        LDA saved_zwork+1
        STA ZWORK+1
        LDX saved_picture
        STX shown_picture
        RTS
draw_object.shape:
        STX var_shape
        LDA draw_dx
        STA var_x
        LDA draw_dy
        STA var_y
        JSR draw_shape
        LDX saved_picture
        STX shown_picture
        RTS
draw_objects.done:
        RTS
floor_slots:
        .byte $60,$70,$40,$70,$80,$70,$20,$70,$A0,$70,$00,$70,$C0,$70,$00,$50
        .byte $20,$50,$40,$50,$60,$50,$80,$50,$A0,$50,$C0,$50,$00,$30,$20,$30
        .byte $40,$30,$60,$30,$80,$30,$A0,$30,$C0,$30
saved_picture:
        .byte $00
        .incbin "data/adventure_712A.bin"    ; $712A-$71FF fill
        .org $7200

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
        JSR rt_mul8
        .word picdir_index
        JSR rt_add16
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
        JSR rt_add16
        .word pic_offset
        .word ZWORK
        RTS

; Cache lookup, then picture_ptr = slot buffer + pic_offset.
find_cached_block:
        JSR cache_lookup
        JSR rt_add16
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
cache_lookup.loop:
        LDA counter
        CMP #CACHE_SLOTS
        BEQ cache_lookup.miss
        LDY #$02
        LDA (ZWORK),Y
        CMP pic_block
        BEQ cache_lookup.hit
        LDX #4
        JSR rt_add8
        .word ZWORK
        LDY counter
        INY
        STY counter
        JMP cache_lookup.loop
cache_lookup.hit:
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
        JMP cache_lookup.done
cache_lookup.miss:
        JSR cache_choose_victim
        JSR cache_load_block
        JMP cache_lookup.done
cache_lookup.done:
        RTS

; Pick the slot with the oldest turn (cache_victim, ZWORK = its buffer).
cache_choose_victim:
        LDA #$FF
        STA lru_turn
        STA lru_turn+1
        LDY #$00
        LDA #$00
        STA counter
cache_choose_victim.loop:
        LDA pic_cache+1,Y
        CMP lru_turn+1
        BCC cache_choose_victim.older
        BEQ cache_choose_victim.check_lo
        JMP cache_choose_victim.next
cache_choose_victim.check_lo:
        LDA pic_cache,Y
        CMP lru_turn
        BCC cache_choose_victim.older
        JMP cache_choose_victim.next
cache_choose_victim.older:
        LDA pic_cache,Y
        STA lru_turn
        LDA pic_cache+1,Y
        STA lru_turn+1
        STY temp_7c
        TYA
        CLC
        ROR A
        TAY
        LDA cache_slots,Y
        STA ZWORK
        INY
        LDA cache_slots,Y
        STA ZWORK+1
        LDY temp_7c
        LDA counter
        STA cache_victim
        JMP cache_choose_victim.next
cache_choose_victim.next:
        INY
        INY
        INY
        INY
        LDX counter
        INX
        STX counter
        TXA
        CMP #CACHE_SLOTS
        BNE cache_choose_victim.loop
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
        JSR rt_print
        .hiasc "\x04BLOAD BLOCK"
bload_block_digits:
        .byte $00,$00             ; patched: block number
        .hiasc ",A$"
bload_addr_digits:
        .byte $00,$00,$00,$00     ; patched: cache slot address
        .hiasc "\r"
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
print_message:
        STX msg_scratch
        CPX #MSG_CANT_GO
        BNE print_message.try_not_carrying
        JSR rt_print
        .hiasc "I CANT GO IN THAT DIRECTION\r"
        .byte $00
        JMP print_message.done
print_message.try_not_carrying:
        CPX #MSG_NOT_CARRYING
        BNE print_message.try_dont_understand
        JSR rt_print
        .hiasc "IM NOT CARRYING THAT\r"
        .byte $00
        JMP print_message.done
print_message.try_dont_understand:
        CPX #MSG_DONT_UNDERSTAND
        BNE print_message.try_getting_dark
        JSR rt_print
        .hiasc "I DONT UNDERSTAND WHAT YOU MEAN\r"
        .byte $00
        JMP print_message.done
print_message.try_getting_dark:
        CPX #MSG_GETTING_DARK
        BNE print_message.from_file
        JSR rt_print
        .hiasc "IT IS GETTING DARK\r"
        .byte $00
        JMP print_message.done
print_message.from_file:
        LDA message_index_addr
        STA ZWORK
        LDA message_index_addr+1
        STA ZWORK+1
        JMP print_message.index
message_index_addr:
        .byte $00,$55
print_message.index:
        LDA #$00
        STA msg_scratch+1
        ASL msg_scratch
        ROL msg_scratch+1
        JSR rt_add16
        .word msg_scratch
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
print_message.print_loop:
        LDA (ZWORK),Y
        CMP #$00
        BNE print_message.put_char
        LDA #HI_CR
print_message.put_char:
        JSR COUT
        LDA (ZWORK),Y
        INY
        CMP #$00
        BNE print_message.print_loop
        LDA msg_no_delay
        CMP #$FF
        BEQ print_message.done
        LDY #$0E
print_message.pause:
        DEY
        BEQ print_message.done
        LDA #$FF
        JSR WAIT
        JMP print_message.pause
print_message.done:
        RTS

; READ MESSAGES,B$xxxx (offset patched in by print_message) and let DOS read one line into
; input_buffer via GETLN1. The first two bytes of the line are saved around the CTRL-D that
; ends the READ, because printing it disturbs them.
read_message_line:
        JSR rt_print
        .hiasc "\x04READ MESSAGES,B$"
read_offset_digits:
        .byte $00,$00,$00,$00     ; patched: byte offset of the message in hex
        .hiasc "\r"
        .byte $00
        JSR GETLN1
        LDA input_buffer
        STA msg_scratch
        LDA input_buffer+1
        STA msg_scratch+1
        JSR rt_print
        .hiasc "\x04\r"
        .byte $00
        LDA msg_scratch
        STA input_buffer
        LDA msg_scratch+1
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
nibbles_to_ascii.loop:
        LDA hex_out,Y
        TAX
        LDA hex_digits,X
        STA hex_out,Y
        INY
        CPY #$04
        BNE nibbles_to_ascii.loop
        RTS

; Break the $8D-terminated line at ZWORK into lines of at most 39 columns at spaces, and
; replace the final $8D with $00.
word_wrap:
        LDY #$00
        LDA #39
        STA msg_scratch
word_wrap.scan:
        LDA (ZWORK),Y
        CMP #HI_CR
        BEQ word_wrap.done
        CPY msg_scratch
        BEQ word_wrap.at_margin
word_wrap.next_char:
        INY
        JMP word_wrap.scan
word_wrap.at_margin:
        LDA (ZWORK),Y
        CMP #HI_SPACE
        BEQ word_wrap.break_line
word_wrap.back_to_space:
        DEY
        LDA (ZWORK),Y
        CMP #HI_SPACE
        BNE word_wrap.back_to_space
word_wrap.break_line:
        LDA #HI_CR
        STA (ZWORK),Y
        SEC
        TYA
        ADC msg_scratch
        STA msg_scratch
        JMP word_wrap.next_char
word_wrap.done:
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
rt_add8:
        JMP rt_add8_body

; word at .word dst += word at .word src
rt_add16:
        JMP rt_add16_body

; compare X bytes at (AWORK) with .word addr; cmp_result = 0 if equal
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
rt_mul8:
        JMP rt_mul8_body
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
rt_print_body.loop:
        LDA (rt_operands),Y
        INY
        CMP #$00
        BEQ rt_print_body.done
        JSR COUT
        JMP rt_print_body.loop
rt_print_body.done:
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
rt_copy_body.loop:
        LDA (rt_ptr1),Y
        STA (rt_ptr2),Y
        DEY
        BNE rt_copy_body.loop
        LDA (rt_ptr1),Y
        STA (rt_ptr2),Y
        LDX #4
        JSR rt_return

; rt_add8: add X to the word at addr.
rt_add8_body:
        STX temp_7c
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
        ADC temp_7c
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

; rt_compare: compare X bytes at (AWORK) with addr; cmp_result = 0 if equal, 1 if not.
rt_compare_body:
        STX temp_7c
        JSR rt_args
        LDY #$00
        LDA (rt_operands),Y
        STA rt_ptr2
        INY
        LDA (rt_operands),Y
        STA rt_ptr2+1
        LDA AWORK
        STA rt_ptr1
        LDA AWORK+1
        STA rt_ptr1+1
        LDY #$00
rt_compare_body.loop:
        LDA (rt_ptr1),Y
        CMP (rt_ptr2),Y
        BNE rt_compare_body.differ
        INY
        DEX
        TXA
        BEQ rt_compare_body.equal
        JMP rt_compare_body.loop
rt_compare_body.differ:
        LDA #$01
        STA cmp_result
        JMP rt_compare_body.done
rt_compare_body.equal:
        LDA #$00
        STA cmp_result
rt_compare_body.done:
        LDX #2
        JSR rt_return

; rt_add16: word at dst += word at src.
rt_add16_body:
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

; rt_mul8: the word at addr *= X (8-step shift and add through mul_result).
rt_mul8_body:
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
        STX msg_scratch
        LDA #$00
        STA mul_result
        STA mul_result+1
rt_mul8_body.loop:
        LDA msg_scratch
        BEQ rt_mul8_body.done
        LSR mul_count
        BCC rt_mul8_body.no_add
        JSR rt_add16
        .word mul_multiplicand
        .word mul_result
rt_mul8_body.no_add:
        ASL mul_multiplicand
        ROL mul_multiplicand+1
        LDY msg_scratch
        DEY
        STY msg_scratch
        JMP rt_mul8_body.loop
rt_mul8_body.done:
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
        .org $7900

; Redraw the room: CUROOM from room_no, clear the screen, and if the room is lit (LAMPSTAT =
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
        BNE draw_room.describe
        JSR draw_picture
        JSR draw_objects
draw_room.describe:
        LDY #RMSG
        LDA (CUROOM),Y
        TAX
        LDA #$FF
        STA msg_no_delay
        JSR print_message
        LDA #$00
        STA msg_no_delay
        RTS

; CUROOM = ROOMBASE + room_no * RTBLSIZ.
set_curoom:
        LDA #$00
        STA room_index+1
        LDA room_no
        STA room_index
        JMP set_curoom.compute
roombase_addr:
        .byte $00,$0D
set_curoom.compute:
        LDX #RTBLSIZ
        JSR rt_mul8
        .word room_index
        LDA roombase_addr
        STA CUROOM
        LDA roombase_addr+1
        STA CUROOM+1
        JSR rt_add16
        .word room_index
        .word CUROOM
        RTS
stale_hglin_copy:
        .incbin "data/stale_hglin_copy.bin"    ; $7956-$79FF 
        .org $7A00

; Draw shown_picture: a stream of (x, y) pairs, each a line from the previous point, except
; that 00 00 makes the next point start a new line and FF FF ends the picture. Points are
; offset by draw_dx/draw_dy and clamped to MAX_X / MAX_Y.
draw_picture:
        LDX shown_picture
        JSR load_picture
draw_picture.next_point:
        LDY #$00
        LDA (picture_ptr),Y
        CMP #PIC_END
        BNE draw_picture.check_newline
        INY
        LDA (picture_ptr),Y
        CMP #PIC_END
        BEQ draw_picture.done
        DEY
        LDA (picture_ptr),Y
draw_picture.check_newline:
        CMP #PIC_NEWLINE
        BNE draw_picture.point
        INY
        LDA (picture_ptr),Y
        CMP #PIC_NEWLINE
        BNE draw_picture.reload_x
        LDA #$01
        STA pen_up
        LDX #2
        JSR rt_add8
        .word picture_ptr
        JMP draw_picture.next_point
draw_picture.reload_x:
        DEY
        LDA (picture_ptr),Y
draw_picture.point:
        CLC
        ADC draw_dx
        CMP #MAX_X
        BCC draw_picture.x_ok
        LDA #MAX_X
draw_picture.x_ok:
        STA var_x
        INY
        LDA (picture_ptr),Y
        CLC
        ADC draw_dy
        CMP #MAX_Y
        BCC draw_picture.y_ok
        LDA #MAX_Y
draw_picture.y_ok:
        STA var_y
        LDA pen_up
        CMP #0
        BEQ draw_picture.line_to
        JSR hplot_xy
        LDA #$00
        STA pen_up
        JMP draw_picture.advance
draw_picture.line_to:
        JSR hplot_to_xy
draw_picture.advance:
        LDX #2
        JSR rt_add8
        .word picture_ptr
        JMP draw_picture.next_point
draw_picture.done:
        RTS
        .incbin "data/adventure_7A72.bin"    ; $7A72-$7CFF fill

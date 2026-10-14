; AUTO LOAD OBJ - the loader added for the 1987 public-domain release.
; MYSTERY.HELLO BLOADs this file (which also puts the Sierra title picture, title_1987, on hi-res
; page 1) and CALLs start. It offers the instructions, then BRUNs ADVENTURE. It carries its own
; copy of the macro library at $1C00 (the same code as ADVENTURE's at $7600).
; Assemble with tools/asm6502.py; build.sh checks the result against the original.

        .include "apple2.inc"

; ---- addresses outside the image or inside other items ----
rt_operands              = $0071    ; rt_args: pointer to the caller's inline operands
WORK                    = $0077    ; rt_compare operand pointer
rt_temp                  = $007C
rt_ptr1                  = $007D    ; library scratch pointer (also dispatch target)
rt_ptr2                  = $0081    ; library scratch pointer
input_buffer             = $0200    ; monitor GETLN input line
cmp_result               = $0851    ; rt_compare result; also "rule matched" / end-of-table flag
scratch_word              = $087D
mul_multiplicand         = $087F
mul_result               = $0881
mul_count                = $0883
mul_carry                = $0884
mul_dest                 = $0885

        .org $0FFD

; Show the title picture with four lines of text and ask for G (game) or I (instructions).
start:
        LDA MIXSET
        LDX #$FF
        TXS
        LDA TXTCLR
        LDA HIRES
start.menu:
        JSR rt_print
        .hiasc "\r\r\r\r\r\r\r\r\r\r\r\r\r\r\r\r\r\r\rENTER G FOR GAME OR I FOR INSTRUCTIONS"
        .byte $00
        JSR GETLN1
        LDA input_buffer
        CMP #'G'|$80                ; G: play
        BNE start.not_game
        JMP run_adventure
start.not_game:
        CMP #'I'|$80                ; I: instructions
        BEQ show_instructions
        JMP start.menu

; Full-screen text: six pages of instructions ending with the cast of characters, each page
; waiting for RETURN (GETLN1), then on to the game.
show_instructions:
        LDA TXTSET
        JSR HOME
        JSR rt_print
        .hiasc "\rINSTRUCTIONS FOR HI-RES ADVENTURE\r\r\r"
        .byte $00
        JSR rt_print
        .hiasc "ADVENTURE IS ONE OF THE MOST FACINATING\rAND CHALLENGING GAMES AVAILABLE FOR\rYOUR APPLE COMPUTER. WINNING IS QUITE\rA CHALLENGE IN A GAME WHERE IT MAY TAKE\r"
        .byte $00
        JSR rt_print
        .hiasc "HOURS TO MOVE AND WEEKS TO SOLVE A \rPUZZLE. HI-RES ADVENTURE #1 ('MYSTERY\rHOUSE') TAKES PLACE IN AN OLD HOUSE\r"
        .byte $00
        JSR rt_print
        .hiasc "WITH MANY ROOMS. AS YOU ENTER THE\rHOUSE, SEVEN OTHER PERSONS WILL BE\rIN THE LIVING ROOM. EVENTUALLY THEY\rARE DISPERSED THROUGHOUT THE HOUSE AND\r"
        .byte $00
        JSR rt_print
        .hiasc "YOU START FINDING THEM - DEAD! YOU MUST\rFIND THE KILLER BEFORE HE(SHE?) ENDS UP\rKILLING YOU.\r\r"
        .byte $00
        JSR rt_print
        .hiasc "PRESS RETURN TO CONTINUE"
        .byte $00
        JSR GETLN1
        JSR HOME
        JSR rt_print
        .hiasc "\r\rYOU PROGRESS THROUGH THE HOUSE BY\r"
        .byte $00
        JSR rt_print
        .hiasc "PROVIDING TWO WORD COMMANDS WHICH \rUSUALLY CONTAIN A VERB AND THEN A \rNOUN BUT AREN'T ALWAYS IN THAT ORDER.\r"
        .byte $00
        JSR rt_print
        .hiasc "EXAMPLES ARE 'WATER ON' AND 'OPEN\rDOOR'. IF A SET OF WORDS DOESNT SEEM\rTO BE WORKING TRY DIFFERENT TERMINOLOGY\r\r"
        .byte $00
        JSR rt_print
        .hiasc "IF YOU SHOULD FIND A STAIRCASE YOU MAY\rTRY 'UP STAIRS' OR 'GO STAIRS'.\r"
        .byte $00
        JSR rt_print
        .hiasc "SOME OF THE ACTIONS YOU CAN TAKE ARE\rGET, DROP, GO, LOOK, READ, CLIMB\rMOVE, HIT, KILL ETC.\r\r"
        .byte $00
        JSR rt_print
        .hiasc "PRESS RETURN TO CONTINUE"
        .byte $00
        JSR GETLN1
        JSR HOME
        JSR rt_print
        .hiasc "\r\r\r\r\rYOU MAY GO IN THE DIRECTIONS NORTH, \rSOUTH, EAST, WEST, UP AND DOWN. TYPE\rNORTH OR N TO GO NORTH. THE OTHER\r"
        .byte $00
        JSR rt_print
        .hiasc "DIRECTIONS MAY ALSO BE ABBREVIATED AS\rWELL. WHEN YOUR WAY IS BLOCKED AND\rYOU CAN'T USE DIRECTIONS TO MOVE \r"
        .byte $00
        JSR rt_print
        .hiasc "YOU MAY HAVE TO REFER TO THE ACTUAL\rOBJECT IN YOUR WAY. IN THESE CASES\rYOU COULD TYPE 'GO DOOR', 'GO HOLE',\r'GO GATE' ETC.\r\r"
        .byte $00
        JSR rt_print
        .hiasc "PRESS RETURN TO CONTINUE"
        .byte $00
        JSR GETLN1
        JSR HOME
        JSR rt_print
        .hiasc "\r\r\rIN GENERAL THE TOP OF THE SCREEN IS\rNORTH. THE BOTTOM IS SOUTH, THE LEFT\rSIDE IS WEST AND THE RIGHT SIDE IS\r"
        .byte $00
        JSR rt_print
        .hiasc "EAST. BECAUSE OF THE DIFFICULTY OF\rDRAWING DOORWAYS TO THE SOUTH OR THE\rBOTTOM OF THE SCREEN, THERE ARE ONE\r"
        .byte $00
        JSR rt_print
        .hiasc "OR TWO ROOMS WHERE THE DOORWAYS DO NOT\rMATCH UP TO THE NORMAL DIRECTIONS.\r\r"
        .byte $00
        JSR rt_print
        .hiasc "IF YOU WANT A CLOSER LOOK AT SOMETHING\rSAY LOOK (OBJECT). TO RETURN TO THE\rMAIN VIEW SAY LOOK ROOM.\r\r"
        .byte $00
        JSR rt_print
        .hiasc "SAVE GAME AND RESTORE GAME MAY\rALSO BE USED.\r\r\rPRESS RETURN TO CONTINUE"
        .byte $00
        JSR GETLN1
        JSR HOME
        JSR rt_print
        .hiasc "\r\r\rA NOTE OF CAUTION: CARRYING MORE THAN\rONE NOTE MAY BE CONFUSING AS THE"
        .byte $00
        JSR rt_print
        .hiasc "\rCOMPUTER WILL ARBITRARILY DECIDE WHICH\rONE TO READ OR DROP.\r\r"
        .byte $00
        JSR rt_print
        .hiasc "SHOULD YOU WISH TO REVIEW PAST COMMANDS\rYOU MAY PRESS RETURN WITHOUT TYPING TO\r"
        .byte $00
        JSR rt_print
        .hiasc "FLIP/FLOP BETWEEN GRAPHICS AND TEXT.\r\rIF YOUR COPY SHOULD EVER FAIL TO LOAD\r(OR GET MUNCHED BY A HUNGRY DISK DRIVE)\r"
        .byte $00
        JSR rt_print
        .hiasc "SEND IT WITH FIVE DOLLARS TO:\r\r"
        .byte $00
        JSR rt_print
        .hiasc "     ON-LINE SYSTEMS\r     36575 MUDGE RANCH ROAD\r"
        .byte $00
        JSR rt_print
        .hiasc "     COARSEGOLD CA. 93614\r\r"
        .byte $00
        JSR rt_print
        .hiasc "\r\r\rPRESS RETURN TO CONTINUE"
        .byte $00
        JSR GETLN1
        JSR HOME
        JSR rt_print
        .hiasc "\r\r"
        .byte $00
        JSR rt_print
        .hiasc "AT THE START OF THE GAME THERE\r"
        .byte $00
        JSR rt_print
        .hiasc "WILL BE SEVEN OTHER PEOPLE IN\rTHE HOUSE WITH YOU. THEIR NAMES,\rOCCUPATIONS, AND HAIRCOLOR ARE\rAS FOLLOWS:\r\r"
        .byte $00
        JSR rt_print
        .hiasc "TOM      SAM       SALLY\rBLOND    BRUNETTE  REDHEAD\rPLUMBER  MECHANIC  SEAMSTRESS\r\rDR. GREEN  JOE          BILL\r"
        .byte $00
        JSR rt_print
        .hiasc "BRUNETTE   BRUNETTE     BLOND\rSURGEON    GRAVEDIGGER  BUTCHER\r\rDAISY\rBLOND\r"
        .byte $00
        JSR rt_print
        .hiasc "COOK.\r\r\r\r"
        .byte $00
        JSR rt_print
        .hiasc "PRESS RETURN TO BEGIN PLAY"
        .byte $00
        JSR GETLN1

; Print CTRL-D BRUN ADVENTURE: DOS takes it as a command and loads the game over this program,
; so the RTS is only reached if the BRUN fails.
run_adventure:
        JSR rt_print
        .hiasc "\r\x04BRUN ADVENTURE\r"
        .byte $00
        RTS
; leftover memory, not used: lines here can be deleted to make room
        .byte $C9,$A0,$D6,$C1,$CC,$CC,$C5,$D9,$A0,$C3,$C1,$AE,$A0,$B9,$B3,$B0
        .byte $B6,$B5,$8D,$8D,$00,$20,$15,$18,$8D,$8D,$8D,$D0,$D2,$C5,$D3,$D3
        .byte $A0,$D2,$C5,$D4,$D5,$D2,$CE,$A0,$D4,$CF,$A0,$C3,$CF,$CE,$D4,$C9
        .byte $CE,$D5,$C5,$00,$20,$6F,$FD,$20,$15,$18,$8D,$8D,$8D,$8D,$8D,$8D
        .byte $00,$20,$15,$18,$C1,$D4,$A0,$D4,$C8,$C5,$A0,$D3,$D4,$C1,$D2,$D4
        .byte $A0,$CF,$C6,$A0,$D4,$C8,$C5,$A0,$C7,$C1,$CD,$C5,$A0,$D4,$C8,$C5
        .byte $D2,$C5,$8D,$00,$20,$15,$18,$D7,$C9,$CC,$CC,$A0,$C2,$C5,$A0

; ---- the macro library (see src/adventure.s and NOTES.md) ----
; copy X bytes: .word src, dst
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
        LDX #$04
        JSR rt_return
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
        LDX #$02
        JSR rt_return
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
        LDX #$02
        JSR rt_return
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
        LDX #$02
        JSR rt_return
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
        LDX #$04
        JSR rt_return
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
MULTIPLY_body.loop:
        LDA scratch_word
        BEQ MULTIPLY_body.done
        LSR mul_count
        BCC MULTIPLY_body.no_add
        JSR BUMP16
        .word mul_multiplicand
        .word mul_result
MULTIPLY_body.no_add:
        ASL mul_multiplicand
        ROL mul_multiplicand+1
        LDY scratch_word
        DEY
        STY scratch_word
        JMP MULTIPLY_body.loop
MULTIPLY_body.done:
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
        LDX #$02
        JSR rt_return
        .incbin "data/autoload_1DCC.bin"    ; $1DCC-$1FFF leftover memory, not used by the code (see NOTES.md)
        .org $2000
title_1987:
        .incbin "data/title_1987.bin"    ; $2000-$3FFF 

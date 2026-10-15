; Fragments of the original ADVENTURE source, recovered from stale memory saved inside
; the ADVENTURE binary (see tools/source_fragments.py). The text between fragments
; was overwritten. Labels ACnn00 are the action handlers at tbl_actions[nn-10];
; every handler leaves through AC9000 with X = operand bytes consumed.

; ---- fragment at $08AD ----
         STA  AWORK
         LDA  WORK+$1
         STA  AWORK+$1
;
; GET # OF ACTIONS TO DO
;

; ---- fragment at $0BA3 ----
         ADR  AC3200
         ADR  AC3300
         ADR  AC3400
         ADR  AC3500
         ADR  AC3600
         ADR  AC3700
         ADR  AC3800
         ADR  AC3900
;
;
;
AC1100   ;
; ADD X TO SWITCH Y
;
         LDY  #X
         LDA  (ZWORK),Y            ;GET X
         TAX
         LDY  #Y
         LDA  (ZWORK),Y            ;GET Y
         TAY
         LDA  SWITCH,Y             ;GET CONTENTS OF SWITCH Y
         CLC
         STX  AWORK1               ;SAVE X
         ADC  AWORK1               ;SAVE X
         STA  SWITCH,Y             ;UPDATE SWITCH
         LDX  #$2
         JMP  AC9000
;
;
;
AC1200   ;

; ---- fragment at $0EB7 ----
;
AC1410   LDY  #OBJECTNO
         LDA  (ZAWORK),Y
         CMP  #HV
         BEQ  AC1480
         LDY  #OROOM
         LDA  (ZAWORK),Y
         CMP  #CARRYING            ;AM I CARRYING IT
         BEQ  AC1430               ;YEP
;
; BUMP TO NEXT ENTRY
;
AC1420   LDY  #ONEXT
         LDA  (ZAWORK),Y
         TAX
         JSR  BUMPIT
         ADR  ZAWORK
         JMP  AC1410
;
; LIST THE MESSAGE FOR THE OBJECT
;
AC1430   LDY  #OMSG
         LDA  (ZAWORK),Y
         TAX
         JSR  MESSLSTR
         JMP  AC1420               ;GO FIND NEXT OBJECT
;
; EXIT
;
AC1480   LDX  #ZERO
         JMP  AC9000
;
;
;
AC1500   ;
;PUT OBJECT X IN ROOM Y
;
         LDA  #OBJBASE             ;GET OBJTAB BASE ADDRESS
         STA  ZAWORK
         LDA  /OBJBASE
         STA  ZAWORK+$1
         LDY  #X
         LDA  (ZWORK),Y            ;GET X
         STA  AWORK1               ;SAVE IT
         LDY  #Y
         LDA  (ZWORK),Y            ;GET Y
         STA  AWORK2               ;SAVE IT
;
; LOOP THRU OBJECT TABLE
;
AC1510   LDY  #OBJECTNO            ;GET #
         LDA  (ZAWORK),Y           ;GET IT
         CMP  #HV                  ;DONE ?
         BNE  AC1520               ;BETTER NOT BE
         BRK                       ;BAD OBJECT
AC1520   CMP  AWORK1               ;THIS OBJECT
         BEQ  AC1540               ;YEP
         LDY  #ONEXT
         LDA  (ZAWORK),Y           ;POINT TO NEXT
         TAX
         JSR  BUMPIT
         ADR  ZAWORK
         JMP  AC1510               ;GO LOOP
AC1540   ;
; OK-WE'VE FOUND IT
;
         LDY  #OROOM
         LDA  AWORK2               ;GET NEW ROOM NO
         STA  (ZAWORK),Y
         LDX  #$2
         JMP  AC9000
;
;
;
AC1600   ;
; MOVE TO ROOM X
;
;
;SET RCURPIC = BASEPIC IN ROOM LEAVING
;
         LDY  #RBASEPIC
         LDA  (CUROOM),Y           ;GET BASEPIC
         LDY  #RCURPIC
         STA  (CUROOM),Y           ;MAKE IT CURRENT
         LDA  #ROOMBASE            ;GET ROOMTABLE ADDRESS
         STA  AWORK2               ;SAVE IT
         LDA  /ROOMBASE
         STA  AWORK2+$1
         LDY  #X
         LDA  (ZWORK),Y            ;GET ROOM TO MOVE TO
         STA  AWORK3
         STA  CURONO               ;UPDATE ROOM#
         LDA  #ZERO
         STA  AWORK3+$1
;
; MULT NEW ROOM # BY ENT SIZE
;
         LDX  #RTBLSIZ
         JSR  MULTIPLY
         ADR  AWORK3
;
; NOW ADD IT TO THE ROOM BASE
;
         JSR  BUMP16
         ADR  AWORK3
         ADR  AWORK2
;
;WORK2 NOW HAS THE ROOM BASE
;
         LDA  AWORK2
         STA  CUROOM
         LDA  AWORK2+$1
         STA  CUROOM+$1
         LDX  #$1
         JMP  AC9000
;
;
;
AC1700   ;
; CHANGE CURRENT VIEW TO PICTURE X
;
         LDY  #X
         LDA  (ZWORK),Y            ;GET X
         LDY  #RCURPIC
         STA  (CUROOM),Y           ;MAKE IT THE CURRENT PIC
         LDX  #$1
         JMP  AC9000
;
;
;
AC1800   ;
; MAKE THE PERMANENT PIC X
;
         LDY  #X
         LDA  (ZWORK),Y
         LDY  #RBASEPIC            ;SET BASE TO CUR
         STA  (CUROOM),Y
         LDY  #RCURPIC
         STA  (CUROOM),Y
         LDX  #$1
         JMP  AC9000
;
;
;
AC1900   ;
; ISSUE MESSAGE X
;
         LDY  #X                   ;GET X
         LDA  (ZWORK),Y
         TAX
         JSR  MESSLSTR             ;ISSUE MESSAGE
         LDX  #$1
         JMP  AC9000
;
;
;
AC2000   ;
; TURN LIGHT ON
;
         LDY  #ON
         STY  LAMPSTAT
         LDX  #ZERO
         JMP  AC9000
;
;
;
AC2100   ;
; TURN LAMP OFF
;
         LDY  #OFF
         STY  LAMPSTAT

; ---- fragment at $1C65 ----
;
         LDY  #ONEXT
         LDA  (ZAWORK),Y
         TAX
         JSR  BUMPIT
         ADR  ZAWORK
         JMP  AC2810
;
AC2820   ;
; OK-WE'VE GOT THE OBJECT
;
         LDY  #OROOM               ;UPDATE THE ROOM
         LDA  AY
         STA  (ZAWORK),Y
         LDY  #OXCOORD             ;SET XCOORD
         LDA  AX1
         STA  (ZAWORK),Y
         LDY  #OYCOORD             ;SET YCOORD
         LDA  AY1
         STA  (ZAWORK),Y
         LDX  #$4
         JMP  AC9000
;
;
;
AC2900   ;
; MAKE X THE SHAPE FOR OBJECT Y
;
         LDY  #X                   ;GET X
         LDA  (ZWORK),Y
         STA  AX
         LDY  #Y
         LDA  (ZWORK),Y
         STA  AY
;
; POINT TO OBJECT TABLE START
;
         LDA  #OBJBASE
         STA  ZAWORK
         LDA  /OBJBASE
         STA  ZAWORK+$1
;
; FIND THE OBJECT
;
; (damaged) AC2910  ..#OBJECTNO
         LDA  (ZAWORK),Y
         CMP  #HV
         BNE  AC2920
         BRK                       ;UH-OH, KABOOM!
AC2920   CMP  AY                   ;FOUND IT?
         BEQ  AC2930
;
; BUMP TO NEXT ENTRY
;
         LDY  #ONEXT
         LDA  (ZAWORK),Y
         TAX
         JSR  BUMPIT
         ADR  ZAWORK
         JMP  AC2910
;
AC2930   ;
; WOOPEE! WE'VE GOT IT!
;
         LDY  #OPIC
         LDA  AX
         STA  (ZAWORK),Y
         LDX  #$2
         JMP  AC9000
;
;
;
AC3000   ;
; SWITCH TO PERMANENT VIEW FOR THIS ROOM
;
         LDY  #RBASEPIC
         LDA  (CUROOM),Y
         LDY  #RCURPIC
         STA  (CUROOM),Y
         LDX  #ZERO
         JMP  AC9000
;
;
;

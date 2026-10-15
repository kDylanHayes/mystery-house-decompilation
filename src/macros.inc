; Macros that make the source standard ca65 (cc65 2.18+). tools/asm6502.py implements the same
; two macros natively and skips these definitions.

        .feature string_escapes         ; "\r" and "\x04" in strings

; hiasc "text": Apple II text, each character with bit 7 set
.macro hiasc str
        .repeat .strlen(str), i
        .byte .strat(str, i) | $80
        .endrepeat
.endmacro

; incbin_upto "file", length, limit: as much of the file (length bytes) as fits before the
; address limit. Leftover memory in front of a pinned address shrinks to make room this way.
.macro incbin_upto file, length, limit
        .if length <= (limit) - *
        .incbin file
        .elseif (limit) - * > 0
        .incbin file, 0, (limit) - *
        .endif
.endmacro

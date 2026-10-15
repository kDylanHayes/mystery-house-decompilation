#!/usr/bin/env python3
"""Recover the fragments of the original 6502 assembly source left inside ADVENTURE.

usage: source_fragments.py <ADVENTURE.bin> <out dir>

Writes <out dir>/fragments.s (decoded) and <out dir>/raw/fragment_XXXX.bin (the tokenized bytes
exactly as they sit in the binary, XXXX = run-time address).

When ADVENTURE was saved, memory from about $0880 to $2000 still held part of the assembler's
tokenized source buffer: the action handlers AC1100-AC3000 (the bytecode interpreter's actions)
with their comments. Each source line is stored as

    [length] [opcode token] [addressing-mode byte] operand text [$BB comment text] $0D

(length counts the bytes after itself, up to and including the $0D). A comment-only line is
[length] ';' text $0D, and a label is a 10-byte prefix record: $0A, the label padded to 8
characters, ': ', followed by the line's statement.

The format is that of LISA (Lazer's Interactive Symbolic Assembler, Randall Hyde), which
On-Line Systems itself sold from 1980: every opcode token found here ($CD LDA, $CB JSR,
$D8 ADR, ...) has LISA v2's value, and so do the line layout (length byte, token, operand-mode
byte, $BB before the comment, $0D) and the 8-character labels. The tokens were first worked out
by matching the fragments against the assembled handlers, then found to agree with LISA's
table. The separate label record differs from LISA v2's files (label inline); this is a 1980
in-memory buffer, from an earlier version or the editor's own layout. NOTES.md has the detail.
"""
import pathlib
import os
import sys

LOAD = 0x0800
# LISA v2's mnemonic tokens, $80 + index (from the LISA v2 table in CiderPress II's
# FileConv/Code/LisaAsm.cs). '___' marks an unused token.
LISA_MNEMONICS = (
    'BGE BLT BMI BCC BCS BPL BNE BEQ BVS BVC BSB BNM BM1 BNZ BIZ BIM '   # $80
    'BIP BIC BNC BRA BTR BFL BRK BKS CLV CLC CLD CLI DEX DEY INX INY '   # $90
    'NOP PHA PLA PHP PLP RTS RTI RSB RTN SEC SEI SED TAX TAY TSX TXA '   # $A0
    'TXS TYA ADD CPR DCR INR SUB LDD POP PPD STD STP LDR STO SET ___ '   # $B0
    'ADC AND ORA BIT CMP CPX CPY DEC EOR INC JMP JSR ___ LDA LDX LDY '   # $C0
    'STA STX STY XOR LSR ROR ROL ASL ADR EQU ORG OBJ EPZ STR DCM ASC '   # $D0
    'ICL END LST NLS HEX BYT HBY PAU DFS DCI ... PAG INV BLK DBY TTL '   # $E0
    'SBC ___ LET .IF .EL .FI =   PHS DPH .DA GEN NOG USR ___ ___ ___'    # $F0
).split()
TOKENS = {0x80 + i: m for i, m in enumerate(LISA_MNEMONICS) if m != '___'}


def parse(d, p):
    out = []
    while p < len(d):
        n = d[p]
        if n == 0x0A and p + 11 <= len(d) and d[p + 9:p + 11] == b': ' and 0x41 <= d[p + 1] <= 0x5A:
            out.append((p, 'label', d[p + 1:p + 9].decode('ascii').rstrip()))
            p += 11
            continue
        if n < 2 or p + n >= len(d) or d[p + n] != 0x0D or 0x0D in d[p + 1:p + n]:
            break
        out.append((p, 'line', d[p + 1:p + n]))
        p += n + 1
    return out, p


def render(lines):
    text = []
    label = ''
    for p, kind, v in lines:
        if kind == 'label':
            label = v
            continue
        if v[0] == 0x3B:
            body = v.decode('latin-1')
            text.append(('%-8s %s' % (label, body)).rstrip() if label else body)
        elif v[0] in TOKENS:
            rest = v[2:]
            c = rest.find(b'\xbb')
            opnd, cmt = (rest[:c], rest[c + 1:]) if c >= 0 else (rest, b'')
            line = '%-8s %-4s %s' % (label, TOKENS[v[0]], opnd.decode('latin-1').strip())
            if cmt:
                line = '%-34s ;%s' % (line, cmt.decode('latin-1'))
            text.append(line.rstrip())
        else:
            # a line split by the gap in the saved buffer: label run into the statement
            text.append('; (damaged) ' + ''.join(chr(b) if 32 <= b < 127 else '.' for b in v))
        label = ''
    return text


def main():
    d = pathlib.Path(sys.argv[1]).read_bytes()
    frags = []
    p = 0
    while p < len(d):
        lines, e = parse(d, p)
        if len(lines) >= 4 and sum(1 for _, k, v in lines if k == 'line' and v[0] in TOKENS) >= 1:
            frags.append((p, lines))
            p = e
        else:
            p += 1
    out = sys.argv[2]
    os.makedirs(os.path.join(out, 'raw'), exist_ok=True)
    for p, lines in frags:
        last_p, kind, v = lines[-1]
        end = last_p + (11 if kind == 'label' else d[last_p] + 1)
        pathlib.Path(os.path.join(out, 'raw', 'fragment_%04X.bin' % (p + LOAD))).write_bytes(d[p:end])
    with open(os.path.join(out, 'fragments.s'), 'w') as f:
        f.write('; Fragments of the original ADVENTURE source, recovered from stale memory saved inside\n'
                '; the ADVENTURE binary (see tools/source_fragments.py). The text between fragments\n'
                '; was overwritten. Labels ACnn00 are the action handlers at tbl_actions[nn-10];\n'
                '; every handler leaves through AC9000 with X = operand bytes consumed.\n')
        for p, lines in frags:
            f.write('\n; ---- fragment at $%04X ----\n' % (p + LOAD))
            f.write('\n'.join(render(lines)) + '\n')
    print('%d source fragments, %d lines' % (len(frags), sum(len(l) for _, l in frags)))


if __name__ == '__main__':
    main()

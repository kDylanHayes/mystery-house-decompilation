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
characters, ': ', followed by the line's statement. The opcode tokens were identified by
matching each fragment against the assembled handlers in this binary.
"""
import os
import sys

LOAD = 0x0800
TOKENS = {
    0x86: 'BNE', 0x87: 'BEQ', 0x96: 'BRK', 0x99: 'CLC', 0xAC: 'TAX', 0xAD: 'TAY', 0xC0: 'ADC',
    0xC4: 'CMP', 0xCA: 'JMP', 0xCB: 'JSR', 0xCD: 'LDA', 0xCE: 'LDX', 0xCF: 'LDY', 0xD0: 'STA',
    0xD1: 'STX', 0xD2: 'STY', 0xD8: '.DA',
}


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
    d = open(sys.argv[1], 'rb').read()
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
        open(os.path.join(out, 'raw', 'fragment_%04X.bin' % (p + LOAD)), 'wb').write(d[p:end])
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

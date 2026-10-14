#!/usr/bin/env python3
"""A small two-pass 6502 assembler for the sources in src/.

usage: asm6502.py [-I dir]... <source.s> <out.bin> [listing.txt [symbols.csv]]

-I adds a directory to search for .include and .incbin files after the including file's own.

symbols.csv lists every label and every constant defined outside game.inc (name,address,kind,file),
with the comment block written directly above each label; build.sh feeds it to Ghidra.

Syntax (a subset of the common ca65/Merlin conventions):

  label:                 define a label at the current address
  name = expr            define a constant
  .org expr              set the address (the first .org is the load address)
  .byte expr, ...        bytes; "text" emits ASCII
  .hiasc "text", ...     ASCII with bit 7 set, as the Apple II prints it; \\r and \\xNN escapes
  .word expr, ...        little-endian words
  .incbin "file"         raw bytes, path relative to the source file
  .incbin "file", upto expr   as much of the file as fits before address expr: leftover bytes in
                         front of a table that is generated (and may grow) shrink to make room
  .include "file"        another source file, relative to this one
  LDA a:expr             force absolute addressing for a zero-page address
  ; comment

Expressions: numbers ($hex, %binary, decimal, 'c'), labels, + - * / & |, parentheses, and the
prefixes < (low byte) and > (high byte). Zero-page addressing is used when the operand's value is
known in the first pass and below $100; anything defined later is assumed to be absolute.
"""
import os
import re
import sys

OPCODES = {}
for row in """
ADC 69 65 75 -- 6D 7D 79 -- 61 71 -- -- --
AND 29 25 35 -- 2D 3D 39 -- 21 31 -- -- --
ASL -- 06 16 -- 0E 1E -- -- -- -- 0A -- --
BIT -- 24 -- -- 2C -- -- -- -- -- -- -- --
CMP C9 C5 D5 -- CD DD D9 -- C1 D1 -- -- --
CPX E0 E4 -- -- EC -- -- -- -- -- -- -- --
CPY C0 C4 -- -- CC -- -- -- -- -- -- -- --
DEC -- C6 D6 -- CE DE -- -- -- -- -- -- --
EOR 49 45 55 -- 4D 5D 59 -- 41 51 -- -- --
INC -- E6 F6 -- EE FE -- -- -- -- -- -- --
JMP -- -- -- -- 4C -- -- 6C -- -- -- -- --
JSR -- -- -- -- 20 -- -- -- -- -- -- -- --
LDA A9 A5 B5 -- AD BD B9 -- A1 B1 -- -- --
LDX A2 A6 -- B6 AE -- BE -- -- -- -- -- --
LDY A0 A4 B4 -- AC BC -- -- -- -- -- -- --
LSR -- 46 56 -- 4E 5E -- -- -- -- 4A -- --
ORA 09 05 15 -- 0D 1D 19 -- 01 11 -- -- --
ROL -- 26 36 -- 2E 3E -- -- -- -- 2A -- --
ROR -- 66 76 -- 6E 7E -- -- -- -- 6A -- --
SBC E9 E5 F5 -- ED FD F9 -- E1 F1 -- -- --
STA -- 85 95 -- 8D 9D 99 -- 81 91 -- -- --
STX -- 86 -- 96 8E -- -- -- -- -- -- -- --
STY -- 84 94 -- 8C -- -- -- -- -- -- -- --
""".strip().splitlines():
    f = row.split()
    OPCODES[f[0]] = dict((m, int(v, 16)) for m, v in zip(
        ['imm', 'zp', 'zpx', 'zpy', 'abs', 'abx', 'aby', 'ind', 'izx', 'izy', 'acc', 'rel', 'imp'],
        f[1:]) if v != '--')
IMPLIED = {'BRK': 0x00, 'PHP': 0x08, 'CLC': 0x18, 'PLP': 0x28, 'SEC': 0x38, 'RTI': 0x40,
           'PHA': 0x48, 'CLI': 0x58, 'RTS': 0x60, 'PLA': 0x68, 'SEI': 0x78, 'DEY': 0x88,
           'TXA': 0x8A, 'TYA': 0x98, 'TXS': 0x9A, 'TAY': 0xA8, 'TAX': 0xAA, 'CLV': 0xB8,
           'TSX': 0xBA, 'INY': 0xC8, 'DEX': 0xCA, 'CLD': 0xD8, 'INX': 0xE8, 'NOP': 0xEA,
           'SED': 0xF8}
BRANCH = {'BPL': 0x10, 'BMI': 0x30, 'BVC': 0x50, 'BVS': 0x70, 'BCC': 0x90, 'BCS': 0xB0,
          'BNE': 0xD0, 'BEQ': 0xF0}


class AsmError(Exception):
    pass


class Unknown(Exception):
    """A symbol that is not defined yet (only allowed in the first pass)."""


class Assembler:
    def __init__(self):
        self.symbols = {}
        self.final = False
        self.defined = {}     # name -> ('label' | 'const', source file)
        self.include_dirs = []
        self.notes = {}       # label -> comment block above it

    # ---- expressions ----------------------------------------------------------------
    TOKEN = re.compile(r"\s*(\$[0-9A-Fa-f]+|%[01]+|\d+|'.'|[A-Za-z_@.][A-Za-z0-9_@.]*|[-+*/&|()<>])")

    def eval(self, text):
        toks = []
        pos = 0
        text = text.strip()
        while pos < len(text):
            m = self.TOKEN.match(text, pos)
            if not m:
                raise AsmError('bad expression: %r' % text)
            toks.append(m.group(1))
            pos = m.end()
        self.toks, self.tp = toks, 0
        v = self.expr()
        if self.tp != len(toks):
            raise AsmError('bad expression: %r' % text)
        return v

    def peek(self):
        return self.toks[self.tp] if self.tp < len(self.toks) else None

    def take(self):
        t = self.toks[self.tp]
        self.tp += 1
        return t

    def expr(self):
        v = self.term()
        while self.peek() in ('+', '-', '&', '|'):
            op = self.take()
            r = self.term()
            v = {'+': v + r, '-': v - r, '&': v & r, '|': v | r}[op]
        return v

    def term(self):
        v = self.unary()
        while self.peek() in ('*', '/'):
            op = self.take()
            r = self.unary()
            v = v * r if op == '*' else v // r
        return v

    def unary(self):
        t = self.peek()
        if t == '<':
            self.take()
            return self.unary() & 0xFF
        if t == '>':
            self.take()
            return (self.unary() >> 8) & 0xFF
        if t == '-':
            self.take()
            return -self.unary()
        return self.atom()

    def atom(self):
        t = self.take()
        if t == '(':
            v = self.expr()
            if self.take() != ')':
                raise AsmError('missing )')
            return v
        if t.startswith('$'):
            return int(t[1:], 16)
        if t.startswith('%'):
            return int(t[1:], 2)
        if t[0].isdigit():
            return int(t)
        if t.startswith("'"):
            return ord(t[1])
        if t in self.symbols:
            return self.symbols[t]
        if self.final:
            raise AsmError('undefined symbol %s' % t)
        raise Unknown(t)

    def value(self, text, default=0x1000):
        try:
            return self.eval(text), True
        except Unknown:
            return default, False

    # ---- source --------------------------------------------------------------------
    @staticmethod
    def split_args(s):
        out, cur, q = [], '', None
        for c in s:
            if q:
                cur += c
                if c == q and not cur.endswith('\\' + q):
                    q = None
            elif c in '"':
                q = c
                cur += c
            elif c == ',':
                out.append(cur.strip())
                cur = ''
            else:
                cur += c
        if cur.strip():
            out.append(cur.strip())
        return out

    @staticmethod
    def string(s):
        body = s[1:-1]
        out = bytearray()
        i = 0
        while i < len(body):
            c = body[i]
            if c == '\\':
                n = body[i + 1]
                if n == 'r':
                    out.append(0x0D)
                    i += 2
                elif n == 'x':
                    out.append(int(body[i + 2:i + 4], 16))
                    i += 4
                else:
                    out.append(ord(n))
                    i += 2
            else:
                out.append(ord(c))
                i += 1
        return out

    def find(self, including, name):
        for d in [os.path.dirname(including)] + self.include_dirs:
            p = os.path.join(d, name)
            if os.path.exists(p):
                return p
        raise AsmError('cannot find %s' % name)

    def read(self, path):
        lines = []
        block = []
        for n, raw in enumerate(open(path, encoding='ascii'), 1):
            line = raw.rstrip('\n')
            if line.startswith(';'):
                block.append(line[1:].strip())
            else:
                m = re.match(r'^([A-Za-z_@][A-Za-z0-9_@.]*):', line)
                if m and block and not block[-1].startswith('----'):
                    self.notes[m.group(1)] = ' '.join(b for b in block if b and not b.startswith('===='))
                if line.strip():
                    block = []
            # strip comments outside strings
            q = False
            for i, c in enumerate(line):
                if c == '"':
                    q = not q
                elif c == ';' and not q:
                    line = line[:i]
                    break
            line = line.rstrip()
            m = re.match(r'\s*\.include\s+"(.+)"\s*$', line)
            if m:
                lines += self.read(self.find(path, m.group(1)))
            elif line.strip():
                lines.append((path, n, line))
        return lines

    def operand(self, mnem, op):
        """Return (mode, expression text)."""
        op = op.strip()
        if not op:
            return ('acc' if 'acc' in OPCODES.get(mnem, {}) else 'imp'), None
        if op.upper() == 'A':
            return 'acc', None
        if op.startswith('#'):
            return 'imm', op[1:]
        m = re.match(r'^\((.+),\s*[Xx]\)$', op)
        if m:
            return 'izx', m.group(1)
        m = re.match(r'^\((.+)\),\s*[Yy]$', op)
        if m:
            return 'izy', m.group(1)
        m = re.match(r'^\((.+)\)$', op)
        if m and mnem == 'JMP':
            return 'ind', m.group(1)
        force = op.startswith('a:')
        if force:
            op = op[2:]
        m = re.match(r'^(.+),\s*([XxYy])$', op)
        if m:
            return ('abs' if force else '') + m.group(2).lower(), m.group(1)
        return ('abs' if force else 'addr'), op

    def assemble(self, path):
        lines = self.read(path)
        for final in (False, True):
            self.final = final
            out = bytearray()
            org = None
            pc = None
            listing = []
            for src, n, line in lines:
                try:
                    m = re.match(r'^([A-Za-z_@][A-Za-z0-9_@.]*)\s*=\s*(.+)$', line.strip())
                    if m:
                        v, ok = self.value(m.group(2))
                        if ok:
                            self.symbols[m.group(1)] = v
                            self.defined[m.group(1)] = ('const', src)
                        continue
                    m = re.match(r'^([A-Za-z_@][A-Za-z0-9_@.]*):(.*)$', line.strip())
                    if m:
                        if pc is None:
                            raise AsmError('label before .org')
                        if not final and m.group(1) in self.symbols and self.symbols[m.group(1)] != pc:
                            raise AsmError('duplicate label %s' % m.group(1))
                        self.symbols[m.group(1)] = pc
                        self.defined[m.group(1)] = ('label', src)
                        line = m.group(2)
                        if not line.strip():
                            continue
                    parts = line.strip().split(None, 1)
                    word = parts[0]
                    rest = parts[1] if len(parts) > 1 else ''
                    start = pc
                    emitted = bytearray()
                    lw = word.lower()
                    if lw == '.org':
                        v = self.eval(rest)
                        if org is None:
                            org = v
                        elif v < pc:
                            raise AsmError('.org goes backwards')
                        else:
                            out += bytes(v - pc)
                        pc = v
                        continue
                    if lw in ('.byte', '.hiasc'):
                        for a in self.split_args(rest):
                            if a.startswith('"'):
                                s = self.string(a)
                                emitted += bytes(c | 0x80 for c in s) if lw == '.hiasc' else s
                            else:
                                v, _ = self.value(a, 0)
                                if final and not -128 <= v <= 255:
                                    raise AsmError('byte out of range: %s' % a)
                                emitted.append(v & 0xFF)
                    elif lw == '.word':
                        for a in self.split_args(rest):
                            v, _ = self.value(a, 0)
                            emitted += bytes((v & 0xFF, (v >> 8) & 0xFF))
                    elif lw == '.incbin':
                        args = self.split_args(rest)
                        blob = open(self.find(src, args[0][1:-1]), 'rb').read()
                        if len(args) > 1:
                            m2 = re.match(r'upto\s+(.+)$', args[1])
                            if not m2:
                                raise AsmError('expected: .incbin "file", upto address')
                            limit, _ = self.value(m2.group(1), pc + len(blob))
                            blob = blob[:max(0, limit - pc)]
                        emitted += blob
                    else:
                        emitted = self.instruction(word.upper(), rest, pc)
                    out += emitted
                    pc += len(emitted)
                    if final:
                        listing.append('%04X  %-12s %s' % (start, emitted[:4].hex(' ').upper(), line.strip()))
                except (AsmError, ValueError, KeyError, IndexError, FileNotFoundError) as e:
                    raise SystemExit('%s:%d: %s\n    %s' % (src, n, e, line.strip()))
        return org, bytes(out), listing

    def instruction(self, mnem, op, pc):
        if mnem in IMPLIED:
            return bytes([IMPLIED[mnem]])
        if mnem in BRANCH:
            v, ok = self.value(op, pc)
            d = v - (pc + 2)
            if self.final and not -128 <= d <= 127:
                raise AsmError('branch out of range')
            return bytes([BRANCH[mnem], d & 0xFF])
        if mnem not in OPCODES:
            raise AsmError('unknown instruction %s' % mnem)
        modes = OPCODES[mnem]
        mode, e = self.operand(mnem, op)
        if mode in ('acc', 'imp'):
            return bytes([modes[mode]])
        v, known = self.value(e)
        if mode == 'imm':
            if self.final and not -128 <= v <= 255:
                raise AsmError('immediate out of range')
            return bytes([modes['imm'], v & 0xFF])
        if mode in ('izx', 'izy'):
            return bytes([modes[mode], v & 0xFF])
        if mode == 'ind':
            return bytes([modes['ind'], v & 0xFF, v >> 8 & 0xFF])
        if mode in ('addr', 'x', 'y'):
            zp = {'addr': 'zp', 'x': 'zpx', 'y': 'zpy'}[mode]
            ab = {'addr': 'abs', 'x': 'abx', 'y': 'aby'}[mode]
            # the decision is made in the first pass and must not change in the second
            key = (mnem, op, pc)
            if not self.final:
                self.zp_choice = getattr(self, 'zp_choice', {})
                self.zp_choice[key] = known and 0 <= v < 0x100 and zp in modes
            mode = zp if self.zp_choice.get(key) else ab
        elif mode == 'absx':
            mode = 'abx'
        elif mode == 'absy':
            mode = 'aby'
        if mode not in modes:
            raise AsmError('%s has no %s mode' % (mnem, mode))
        if mode in ('zp', 'zpx', 'zpy'):
            return bytes([modes[mode], v & 0xFF])
        return bytes([modes[mode], v & 0xFF, v >> 8 & 0xFF])


def main():
    a = Assembler()
    while len(sys.argv) > 2 and sys.argv[1] == '-I':
        a.include_dirs.append(sys.argv[2])
        del sys.argv[1:3]
    org, data, listing = a.assemble(sys.argv[1])
    open(sys.argv[2], 'wb').write(data)
    if len(sys.argv) > 3:
        open(sys.argv[3], 'w').write('\n'.join(listing) + '\n')
    if len(sys.argv) > 4:
        with open(sys.argv[4], 'w') as f:
            f.write('name,address,kind,file,comment\n')
            for name, (kind, src) in sorted(a.defined.items(), key=lambda x: a.symbols[x[0]]):
                if os.path.basename(src) == 'game.inc':
                    continue
                f.write('%s,%04X,%s,%s,%s\n' % (name, a.symbols[name] & 0xFFFF, kind,
                                               os.path.basename(src), a.notes.get(name, '')))
    print('%s: $%04X-$%04X, %d bytes' % (os.path.basename(sys.argv[1]), org, org + len(data) - 1, len(data)))


if __name__ == '__main__':
    main()

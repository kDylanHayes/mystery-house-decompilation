#!/usr/bin/env python3
"""Recursive-descent code discovery for the Mystery House 6502 binaries.

usage: trace6502.py <program.json> <bin> <out.json> [listing.s [symbols.csv]]

The program description (see programs/*.json) gives the load address, entry points, jump
tables, the address of the inline-argument macro library, and labels. The output JSON tells the
Ghidra script exactly which bytes are code, which JSRs carry inline arguments (and so need a
fall-through override), and which inline arguments are strings or words. A plain listing with the
same interpretation is written when a path is given; it is handy for reading without Ghidra.

The macro library (a jump table of 9 entries at LIB) takes its operands inline after the JSR:
  LIB+$00 copy    X bytes             .word src, dst
  LIB+$03 add8    word += X            .word addr
  LIB+$06 add16   word += word         .word src, dst
  LIB+$09 compare X bytes at ($77)     .word addr      (result in $0851: 0 = equal)
  LIB+$0C args    (internal: $71 = pointer to caller's inline operands)
  LIB+$0F return  (internal: return to caller's caller, skipping X inline bytes; never returns)
  LIB+$12 inc16   word += 1            .word addr
  LIB+$15 print   inline text, high-bit ASCII, $00-terminated
  LIB+$18 mul8    word * X -> $0881    .word addr
"""
import pathlib
import json
import sys

OPS = {}
for entry in """
00 BRK imp|01 ORA izx|05 ORA zp|06 ASL zp|08 PHP imp|09 ORA imm|0A ASL acc|0D ORA abs|0E ASL abs
10 BPL rel|11 ORA izy|15 ORA zpx|16 ASL zpx|18 CLC imp|19 ORA aby|1D ORA abx|1E ASL abx
20 JSR abs|21 AND izx|24 BIT zp|25 AND zp|26 ROL zp|28 PLP imp|29 AND imm|2A ROL acc|2C BIT abs
2D AND abs|2E ROL abs|30 BMI rel|31 AND izy|35 AND zpx|36 ROL zpx|38 SEC imp|39 AND aby|3D AND abx
3E ROL abx|40 RTI imp|41 EOR izx|45 EOR zp|46 LSR zp|48 PHA imp|49 EOR imm|4A LSR acc|4C JMP abs
4D EOR abs|4E LSR abs|50 BVC rel|51 EOR izy|55 EOR zpx|56 LSR zpx|58 CLI imp|59 EOR aby|5D EOR abx
5E LSR abx|60 RTS imp|61 ADC izx|65 ADC zp|66 ROR zp|68 PLA imp|69 ADC imm|6A ROR acc|6C JMP ind
6D ADC abs|6E ROR abs|70 BVS rel|71 ADC izy|75 ADC zpx|76 ROR zpx|78 SEI imp|79 ADC aby|7D ADC abx
7E ROR abx|81 STA izx|84 STY zp|85 STA zp|86 STX zp|88 DEY imp|8A TXA imp|8C STY abs|8D STA abs
8E STX abs|90 BCC rel|91 STA izy|94 STY zpx|95 STA zpx|96 STX zpy|98 TYA imp|99 STA aby|9A TXS imp
9D STA abx|A0 LDY imm|A1 LDA izx|A2 LDX imm|A4 LDY zp|A5 LDA zp|A6 LDX zp|A8 TAY imp|A9 LDA imm
AA TAX imp|AC LDY abs|AD LDA abs|AE LDX abs|B0 BCS rel|B1 LDA izy|B4 LDY zpx|B5 LDA zpx|B6 LDX zpy
B8 CLV imp|B9 LDA aby|BA TSX imp|BC LDY abx|BD LDA abx|BE LDX aby|C0 CPY imm|C1 CMP izx|C4 CPY zp
C5 CMP zp|C6 DEC zp|C8 INY imp|C9 CMP imm|CA DEX imp|CC CPY abs|CD CMP abs|CE DEC abs|D0 BNE rel
D1 CMP izy|D5 CMP zpx|D6 DEC zpx|D8 CLD imp|D9 CMP aby|DD CMP abx|DE DEC abx|E0 CPX imm|E1 SBC izx
E4 CPX zp|E5 SBC zp|E6 INC zp|E8 INX imp|E9 SBC imm|EA NOP imp|EC CPX abs|ED SBC abs|EE INC abs
F0 BEQ rel|F1 SBC izy|F5 SBC zpx|F6 INC zpx|F8 SED imp|F9 SBC aby|FD SBC abx|FE INC abx
""".replace('\n', '|').split('|'):
    f = entry.split()
    if f:
        OPS[int(f[0], 16)] = (f[1], f[2])
SIZE = {'imp': 1, 'acc': 1, 'imm': 2, 'zp': 2, 'zpx': 2, 'zpy': 2, 'izx': 2, 'izy': 2, 'rel': 2,
        'abs': 3, 'abx': 3, 'aby': 3, 'ind': 3}
FMT = {'imp': '', 'acc': 'A', 'imm': '#$%02X', 'zp': '%s', 'zpx': '%s,X', 'zpy': '%s,Y',
       'izx': '(%s,X)', 'izy': '(%s),Y', 'abs': '%s', 'abx': '%s,X', 'aby': '%s,Y', 'ind': '(%s)',
       'rel': '%s'}

# inline operand layout per library entry offset: list of 'w' (word) / 's' (string)
LIB_ARGS = {0x00: 'ww', 0x03: 'w', 0x06: 'ww', 0x09: 'w', 0x12: 'w', 0x15: 's', 0x18: 'w'}
LIB_NORETURN = 0x0F


def h(s):
    return int(s, 16) if isinstance(s, str) else s


class Program:
    def __init__(self, desc, data):
        self.d = desc
        self.data = data
        self.base = h(desc['load'])
        self.end = self.base + len(data)
        self.lib = h(desc['lib']) if desc.get('lib') else None
        self.labels = {h(k): v for k, v in desc.get('labels', {}).items()}

    def byte(self, a):
        return self.data[a - self.base]

    def word(self, a):
        return self.byte(a) | self.byte(a + 1) << 8

    def inside(self, a):
        return self.base <= a < self.end

    def trace(self):
        # Routines written in the same style as the library fetch their inline operands with
        # LIB+$0C and leave with LDX #n / JSR LIB+$0F. Find them and re-trace until stable.
        self.argspec = {}
        if self.lib:
            self.argspec = {self.lib + k: v for k, v in LIB_ARGS.items()}
        for k, v in self.d.get('inline_args', {}).items():
            self.argspec[h(k)] = v
        # an older build of the library, still called by dead code; its address now holds data,
        # so calls to it are decoded but never followed
        self.text_len = {h(k): v for k, v in self.d.get('inline_text_length', {}).items()}
        self.no_follow = set()
        for old in self.d.get('old_libs', []):
            base = h(old)
            self.argspec.update({base + k: v for k, v in LIB_ARGS.items()})
            self.no_follow.update(base + 3 * i for i in range(9))
        while True:
            self.trace_once()
            found = self.find_inline_routines()
            if not found:
                return
            self.argspec.update(found)

    def find_inline_routines(self):
        if not self.lib:
            return {}
        entries = sorted(f for f in self.funcs if f in self.code)
        found = {}
        prev = None
        for a in sorted(self.code):
            if self.byte(a) == 0x20 and self.word(a + 1) == self.lib + LIB_NORETURN and prev is not None \
                    and self.byte(prev) == 0xA2:
                n = self.byte(prev + 1)
                owner = max((f for f in entries if f <= a), default=None)
                if owner is None or owner in self.argspec:
                    continue
                if not any(self.byte(c) == 0x20 and self.word(c + 1) == self.lib + 0x0C
                           for c in self.code if owner <= c <= a):
                    continue
                spec = 'w' * (n // 2) + 'b' * (n % 2)
                if found.get(owner, spec) != spec:
                    raise SystemExit('routine $%04X returns with different inline sizes' % owner)
                found[owner] = spec
            prev = a
        return found

    def trace_once(self):
        code = {}           # instruction address -> length
        inline = {}         # JSR address -> (fallthrough, [(addr, kind, len)])
        funcs = set(h(e) for e in self.d['entries'])
        jumps = set()
        tables = []
        for t in self.d.get('jump_tables', []):
            start, n = h(t['addr']), t['count']
            targets = [self.word(start + 2 * i) for i in range(n)]
            tables.append((start, n, targets, t.get('name')))
            for x in targets:
                if x:
                    funcs.add(x)
        if self.lib:
            funcs.update(self.lib + 3 * i for i in range(9))
        noreturn = set(h(a) for a in self.d.get('noreturn', []))
        always = set(h(a) for a in self.d.get('always_branches', []))
        if self.lib:
            noreturn.add(self.lib + LIB_NORETURN)
        todo = list(funcs)
        owned = set()
        while todo:
            pc = todo.pop()
            while self.inside(pc) and pc not in code:
                op = self.byte(pc)
                if op not in OPS:
                    raise SystemExit('invalid opcode $%02X at $%04X' % (op, pc))
                m, mode = OPS[op]
                n = SIZE[mode]
                for k in range(n):
                    if pc + k in owned:
                        raise SystemExit('overlapping code at $%04X' % (pc + k))
                    owned.add(pc + k)
                code[pc] = n
                nxt = pc + n
                if mode == 'rel':
                    r = self.byte(pc + 1)
                    todo.append((pc + 2 + (r - 256 if r > 127 else r)) & 0xFFFF)
                    if pc in always:
                        break
                if m == 'JSR':
                    tgt = self.word(pc + 1)
                    if self.inside(tgt) and tgt not in self.no_follow:
                        funcs.add(tgt)
                        todo.append(tgt)
                    if tgt in noreturn or (tgt in self.no_follow and tgt - LIB_NORETURN in [
                            h(o) for o in self.d.get('old_libs', [])]):
                        break
                    if tgt in self.argspec:
                        args = []
                        for kind in self.argspec[tgt]:
                            if kind == 'w':
                                args.append((nxt, 'w', 2))
                                nxt += 2
                            elif kind == 'b':
                                args.append((nxt, 'b', 1))
                                nxt += 1
                            else:
                                k = nxt
                                if pc in self.text_len:
                                    # text with digits patched in at run time: $00 in the file
                                    k = nxt + self.text_len[pc] - 1
                                while self.byte(k) != 0:
                                    k += 1
                                args.append((nxt, 's', k + 1 - nxt))
                                nxt = k + 1
                        for a, _, ln in args:
                            owned.update(range(a, a + ln))
                        inline[pc] = (nxt, args)
                if m == 'JMP':
                    if mode == 'abs':
                        tgt = self.word(pc + 1)
                        if self.inside(tgt):
                            todo.append(tgt)
                            jumps.add(tgt)
                    break
                if m in ('RTS', 'RTI', 'BRK'):
                    break
                pc = nxt
        self.code, self.inline, self.funcs, self.tables = code, inline, funcs, tables
        self.targets = set()
        self.noreturn = noreturn

    def name(self, a, zp=False):
        if a in self.labels:
            return self.labels[a]
        if a in self.targets:
            return 'L%04X' % a
        if a - 1 in self.labels and a - 1 not in self.funcs:
            return self.labels[a - 1] + '+1'
        return ('$%02X' if zp else '$%04X') % a

    def listing(self):
        out = []
        # local labels for branch and jump targets that have no name
        self.targets = set()
        for a in self.code:
            m, mode = OPS[self.byte(a)]
            if mode == 'rel':
                r = self.byte(a + 1)
                self.targets.add((a + 2 + (r - 256 if r > 127 else r)) & 0xFFFF)
            elif m == 'JMP' and mode == 'abs':
                self.targets.add(self.word(a + 1))
        self.targets -= set(self.labels) | self.funcs
        tables = {t[0]: t for t in self.tables}
        a = self.base
        while a < self.end:
            if a in self.labels or a in self.funcs:
                out.append('')
                out.append('%s:' % self.name(a) if a in self.labels else 'sub_%04X:' % a)
            elif a in self.targets:
                out.append('L%04X:' % a)
            if a in self.code:
                op = self.byte(a)
                m, mode = OPS[op]
                n = SIZE[mode]
                raw = self.data[a - self.base:a - self.base + n]
                if mode == 'rel':
                    r = raw[1]
                    arg = FMT[mode] % self.name((a + 2 + (r - 256 if r > 127 else r)) & 0xFFFF)
                elif mode == 'imm':
                    arg = FMT[mode] % raw[1]
                elif n == 2:
                    arg = FMT[mode] % self.name(raw[1], zp=True)
                elif n == 3:
                    arg = FMT[mode] % self.name(raw[1] | raw[2] << 8)
                else:
                    arg = FMT[mode]
                out.append('%04X  %-9s %s %s' % (a, ' '.join('%02X' % x for x in raw), m, arg))
                a += n
                if a - n in self.inline:
                    for addr, kind, ln in self.inline[a - n][1]:
                        if kind == 'w':
                            out.append('%04X  %02X %02X     .word %s' % (
                                addr, self.byte(addr), self.byte(addr + 1), self.name(self.word(addr))))
                        elif kind == 'b':
                            out.append('%04X  %02X        .byte $%02X' % (addr, self.byte(addr), self.byte(addr)))
                        else:
                            txt = bytes((b & 0x7F) or 0x23 for b in self.data[addr - self.base:addr - self.base + ln - 1])
                            out.append('%04X  ...       .text %s' % (addr, json.dumps(txt.decode('ascii'))))
                    a = self.inline[a - n][0]
                continue
            if a in tables:
                start, n, targets, nm = tables[a]
                for i, t in enumerate(targets):
                    out.append('%04X  %02X %02X     .word %s ; %s[%d]' % (
                        start + 2 * i, t & 0xFF, t >> 8, self.name(t) if t else '0', nm or 'table', i))
                a = start + 2 * n
                continue
            # data run up to the next code/label/table
            s = a
            while a < self.end and a not in self.code and a not in tables and (a == s or (
                    a not in self.labels and a not in self.funcs)) and a - s < 16:
                a += 1
            out.append('%04X  .byte %s' % (s, ','.join('$%02X' % self.byte(x) for x in range(s, a))))
        return '\n'.join(out) + '\n'

    def plan(self):
        return {
            'name': self.d['name'],
            'load': self.base,
            'length': len(self.data),
            'functions': sorted(self.funcs),
            'noreturn': sorted(self.noreturn),
            'code': sorted(self.code.items()),
            'inline': [{'call': c, 'fallthrough': ft, 'args': [{'addr': a, 'kind': k, 'len': ln} for a, k, ln in args]}
                       for c, (ft, args) in sorted(self.inline.items())],
            'jump_tables': [{'addr': s, 'count': n, 'targets': t, 'name': nm} for s, n, t, nm in self.tables],
            'lib': self.lib,
            'inline_routines': {'%04X' % a: v for a, v in sorted(self.argspec.items())},
            'data_only': [[h(a), h(b)] for a, b in self.d.get('data_only', [])],
            'always_branches': sorted(h(a) for a in self.d.get('always_branches', [])),
        }


def main():
    desc = json.loads(pathlib.Path(sys.argv[1]).read_text())
    data = pathlib.Path(sys.argv[2]).read_bytes()
    if len(sys.argv) > 5:
        # symbols CSV: address,name,type,comment
        for line in pathlib.Path(sys.argv[5]).read_text().splitlines(True):
            f = line.rstrip('\n').split(',', 3)
            if len(f) < 2 or line.startswith(('#', 'address,')) or not f[0].strip():
                continue
            desc.setdefault('labels', {})[f[0].strip()] = f[1].strip()
    p = Program(desc, data)
    p.trace()
    pathlib.Path(sys.argv[3]).write_text(json.dumps(p.plan()))
    if len(sys.argv) > 4:
        pathlib.Path(sys.argv[4]).write_text(p.listing())
    covered = sum(p.code.values()) + sum(ln for _, args in p.inline.values() for _, _, ln in args)
    print('%s: %d functions, %d instructions, %d inline-operand calls, %d/%d bytes code' % (
        desc['name'], len(p.funcs), len(p.code), len(p.inline), covered, len(data)))


if __name__ == '__main__':
    main()

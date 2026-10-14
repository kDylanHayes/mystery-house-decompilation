#!/usr/bin/env python3
"""Play Mystery House headlessly: a 6502 emulator that runs the built ADVENTURE and types
commands into it, for tests and walkthroughs.

usage: play.py <files dir> <commands.txt> [--transcript out.txt] [--screens dir]
                                          [--screen-hashes out.txt] [--max-steps N]

<files dir> holds the disk's files as dos33.py extracts them (build.sh makes extracted/).
<commands.txt> has one command per line ('#' starts a comment). The transcript is everything
the game prints, with each command echoed after the prompt; --screens saves the hi-res screen
at each prompt as PNG (screen_NNN.png), and --screen-hashes writes a short SHA-256 of the
hi-res page at each prompt, one per line (what the tests compare).

No Apple ROMs are needed: ADVENTURE only calls three Monitor routines and DOS, and those are
stood in for here:
  COUT ($FDED)            print a character; a line starting with CTRL-D is a DOS command
  GETLN ($FD6A), GETLN1   read a line into $0200: the next command, or the next line of the
                          file DOS is READing
  WAIT ($FCA8)            a delay: returns at once
  DOS commands            OPEN, READ MESSAGES,B$xxxx, BLOAD name[,A$xxxx], BSAVE name,A$xxxx,
                          L$xxxx, served from <files dir> (BSAVE keeps the file in memory)
  $03D0                   DOS warm start: the game has quit; the run ends
Anything else outside the program (an Applesoft error at $EE68, BRK) stops with an error.
The relocated hi-res code draws into $2000-$3FFF as on the real machine.
"""
import hashlib
import os
import pathlib
import re
import sys

COUT, GETLN, GETLN1, WAIT, HOME = 0xFDED, 0xFD6A, 0xFD6F, 0xFCA8, 0xFC58
DOS_WARM, APPLESOFT_ERROR = 0x03D0, 0xEE68

# opcode -> (mnemonic, addressing mode)
OPS = {}
for row in """
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
    f = row.split()
    if f:
        OPS[int(f[0], 16)] = (f[1], f[2])


class Stop(Exception):
    pass


class Machine:
    def __init__(self, files):
        self.files = files
        self.mem = bytearray(0x10000)
        self.a = self.x = self.y = 0
        self.sp = 0xFF
        self.n = self.v = self.d = self.i = self.z = self.c = 0
        self.pc = 0
        self.out = []              # transcript lines
        self.line = ''             # characters printed since the last CR
        self.commands = []
        self.reading = None        # (data, offset) while DOS READs a file
        self.saved = {}            # files written with BSAVE
        self.steps = 0
        self.prompts = 0
        self.on_prompt = None
        self.screens = []          # hash of the hi-res page at each prompt

    # ---- memory ------------------------------------------------------------------------
    def rd(self, a):
        return 0 if 0xC000 <= a < 0xC100 else self.mem[a]

    def wr(self, a, v):
        if not 0xC000 <= a < 0xC100:
            self.mem[a] = v

    def rw(self, a):
        return self.rd(a) | self.rd((a + 1) & 0xFFFF) << 8

    def push(self, v):
        self.mem[0x100 + self.sp] = v
        self.sp = (self.sp - 1) & 0xFF

    def pull(self):
        self.sp = (self.sp + 1) & 0xFF
        return self.mem[0x100 + self.sp]

    def rts(self):
        lo = self.pull()
        self.pc = ((self.pull() << 8 | lo) + 1) & 0xFFFF

    # ---- ROM and DOS -------------------------------------------------------------------
    def load(self, name, at=None):
        if name in self.saved:
            data, load = self.saved[name]
        else:
            raw = self.files.get(name)
            if raw is None:
                raise Stop('BLOAD %s: no such file' % name)
            data, load = raw
        at = load if at is None else at
        self.mem[at:at + len(data)] = data

    def dos(self, cmd):
        word, _, rest = cmd.partition(' ')
        if word in ('OPEN', 'CLOSE', ''):
            return
        if word == 'READ':
            name, _, off = rest.partition(',B$')
            data, _ = self.files[name.strip()]
            self.reading = (data, int(off, 16))
            return
        if word in ('BLOAD', 'BRUN'):
            parts = rest.split(',')
            at = None
            for p in parts[1:]:
                if p.startswith('A$'):
                    at = int(p[2:], 16)
            self.load(parts[0].strip(), at)
            return
        if word == 'BSAVE':
            parts = rest.split(',')
            a = int([p for p in parts if p.startswith('A$')][0][2:], 16)
            n = int([p for p in parts if p.startswith('L$')][0][2:], 16)
            self.saved[parts[0].strip()] = (bytes(self.mem[a:a + n]), a)
            return
        raise Stop('DOS command not supported: %s' % cmd)

    def cout(self, ch):
        c = ch & 0x7F
        if c == 0x0D:
            if self.line.startswith('\x04'):
                self.dos(self.line[1:].strip())
            else:
                self.out.append(self.line.rstrip())
            self.line = ''
        elif c == 0x04 and self.line == '':
            self.line = '\x04'
            self.reading = None          # CTRL-D ends a READ
        elif c >= 0x20 or c == 0x04:
            self.line += chr(c)

    def getln(self, prompt):
        if self.reading:
            data, off = self.reading
            end = data.index(0x8D, off)
            text = data[off:end]
            self.reading = (data, end + 1)
        else:
            if self.line.strip():
                self.out.append(self.line.rstrip())
            self.line = ''
            self.screens.append(hashlib.sha256(bytes(self.mem[0x2000:0x4000])).hexdigest()[:16])
            if self.on_prompt:
                self.on_prompt(self)
            if not self.commands:
                raise Stop('end of commands')
            cmd = self.commands.pop(0).upper()
            self.out.append('> ' + cmd)
            self.prompts += 1
            text = bytes(ord(c) | 0x80 for c in cmd)
        self.mem[0x200:0x200 + len(text)] = text
        self.mem[0x200 + len(text)] = 0x8D
        self.x = len(text)

    def trap(self):
        pc = self.pc
        if pc == COUT:
            self.cout(self.a)
        elif pc in (GETLN, GETLN1):
            self.getln(pc == GETLN)
        elif pc in (WAIT, HOME):
            self.a = 0
        elif pc == DOS_WARM:
            raise Stop('quit to DOS')
        elif pc == APPLESOFT_ERROR:
            raise Stop('Applesoft error (bad HPLOT/DRAW argument)')
        else:
            raise Stop('call to $%04X, which is not emulated' % pc)
        self.rts()

    # ---- CPU ---------------------------------------------------------------------------
    def flags(self):
        return (self.n << 7 | self.v << 6 | 0x20 | self.d << 3 | self.i << 2 | self.z << 1 | self.c)

    def setflags(self, p):
        self.n, self.v, self.d = p >> 7 & 1, p >> 6 & 1, p >> 3 & 1
        self.i, self.z, self.c = p >> 2 & 1, p >> 1 & 1, p & 1

    def run(self, max_steps):
        rd, wr, mem = self.rd, self.wr, self.mem
        traps = {COUT, GETLN, GETLN1, WAIT, HOME, DOS_WARM, APPLESOFT_ERROR}
        while True:
            pc = self.pc
            if pc in traps or pc >= 0xD000:
                self.trap()
                continue
            self.steps += 1
            if self.steps > max_steps:
                raise Stop('step limit reached at $%04X' % pc)
            op = mem[pc]
            if op not in OPS:
                raise Stop('undocumented opcode $%02X at $%04X' % (op, pc))
            m, mode = OPS[op]
            # operand address
            if mode == 'imp' or mode == 'acc':
                self.pc = pc + 1
                ea = None
            elif mode == 'imm':
                ea = pc + 1
                self.pc = pc + 2
            elif mode == 'zp':
                ea = mem[pc + 1]
                self.pc = pc + 2
            elif mode == 'zpx':
                ea = (mem[pc + 1] + self.x) & 0xFF
                self.pc = pc + 2
            elif mode == 'zpy':
                ea = (mem[pc + 1] + self.y) & 0xFF
                self.pc = pc + 2
            elif mode == 'abs':
                ea = mem[pc + 1] | mem[pc + 2] << 8
                self.pc = pc + 3
            elif mode == 'abx':
                ea = ((mem[pc + 1] | mem[pc + 2] << 8) + self.x) & 0xFFFF
                self.pc = pc + 3
            elif mode == 'aby':
                ea = ((mem[pc + 1] | mem[pc + 2] << 8) + self.y) & 0xFFFF
                self.pc = pc + 3
            elif mode == 'izx':
                z = (mem[pc + 1] + self.x) & 0xFF
                ea = mem[z] | mem[(z + 1) & 0xFF] << 8
                self.pc = pc + 2
            elif mode == 'izy':
                z = mem[pc + 1]
                ea = ((mem[z] | mem[(z + 1) & 0xFF] << 8) + self.y) & 0xFFFF
                self.pc = pc + 2
            elif mode == 'ind':
                a = mem[pc + 1] | mem[pc + 2] << 8
                ea = mem[a] | mem[(a & 0xFF00) | ((a + 1) & 0xFF)] << 8
                self.pc = pc + 3
            else:  # rel
                r = mem[pc + 1]
                ea = (pc + 2 + (r - 256 if r > 127 else r)) & 0xFFFF
                self.pc = pc + 2
            self.execute(m, mode, ea, rd, wr)

    def nz(self, v):
        self.n = v >> 7
        self.z = 1 if v == 0 else 0
        return v

    def execute(self, m, mode, ea, rd, wr):
        if m == 'LDA':
            self.a = self.nz(rd(ea))
        elif m == 'STA':
            wr(ea, self.a)
        elif m == 'LDX':
            self.x = self.nz(rd(ea))
        elif m == 'LDY':
            self.y = self.nz(rd(ea))
        elif m == 'STX':
            wr(ea, self.x)
        elif m == 'STY':
            wr(ea, self.y)
        elif m in ('BNE', 'BEQ', 'BPL', 'BMI', 'BCC', 'BCS', 'BVC', 'BVS'):
            take = {'BNE': not self.z, 'BEQ': self.z, 'BPL': not self.n, 'BMI': self.n,
                    'BCC': not self.c, 'BCS': self.c, 'BVC': not self.v, 'BVS': self.v}[m]
            if take:
                self.pc = ea
        elif m == 'JSR':
            ret = (self.pc - 1) & 0xFFFF
            self.push(ret >> 8)
            self.push(ret & 0xFF)
            self.pc = ea
        elif m == 'RTS':
            self.rts()
        elif m == 'JMP':
            self.pc = ea
        elif m in ('ADC', 'SBC'):
            if self.d:
                raise Stop('decimal mode is not emulated')
            v = rd(ea)
            if m == 'SBC':
                v ^= 0xFF
            r = self.a + v + self.c
            self.v = 1 if (~(self.a ^ v) & (self.a ^ r) & 0x80) else 0
            self.c = r >> 8
            self.a = self.nz(r & 0xFF)
        elif m in ('CMP', 'CPX', 'CPY'):
            reg = {'CMP': self.a, 'CPX': self.x, 'CPY': self.y}[m]
            r = reg - rd(ea)
            self.c = 1 if r >= 0 else 0
            self.nz(r & 0xFF)
        elif m == 'AND':
            self.a = self.nz(self.a & rd(ea))
        elif m == 'ORA':
            self.a = self.nz(self.a | rd(ea))
        elif m == 'EOR':
            self.a = self.nz(self.a ^ rd(ea))
        elif m == 'BIT':
            v = rd(ea)
            self.n, self.v = v >> 7, v >> 6 & 1
            self.z = 1 if (self.a & v) == 0 else 0
        elif m in ('ASL', 'LSR', 'ROL', 'ROR'):
            v = self.a if mode == 'acc' else rd(ea)
            if m == 'ASL':
                self.c, v = v >> 7, (v << 1) & 0xFF
            elif m == 'LSR':
                self.c, v = v & 1, v >> 1
            elif m == 'ROL':
                self.c, v = v >> 7, ((v << 1) | self.c) & 0xFF
            else:
                self.c, v = v & 1, (v >> 1) | (self.c << 7)
            self.nz(v)
            if mode == 'acc':
                self.a = v
            else:
                wr(ea, v)
        elif m in ('INC', 'DEC'):
            v = self.nz((rd(ea) + (1 if m == 'INC' else -1)) & 0xFF)
            wr(ea, v)
        elif m == 'INX':
            self.x = self.nz((self.x + 1) & 0xFF)
        elif m == 'INY':
            self.y = self.nz((self.y + 1) & 0xFF)
        elif m == 'DEX':
            self.x = self.nz((self.x - 1) & 0xFF)
        elif m == 'DEY':
            self.y = self.nz((self.y - 1) & 0xFF)
        elif m == 'TAX':
            self.x = self.nz(self.a)
        elif m == 'TAY':
            self.y = self.nz(self.a)
        elif m == 'TXA':
            self.a = self.nz(self.x)
        elif m == 'TYA':
            self.a = self.nz(self.y)
        elif m == 'TSX':
            self.x = self.nz(self.sp)
        elif m == 'TXS':
            self.sp = self.x
        elif m == 'PHA':
            self.push(self.a)
        elif m == 'PLA':
            self.a = self.nz(self.pull())
        elif m == 'PHP':
            self.push(self.flags() | 0x10)
        elif m == 'PLP':
            self.setflags(self.pull())
        elif m == 'CLC':
            self.c = 0
        elif m == 'SEC':
            self.c = 1
        elif m == 'CLD':
            self.d = 0
        elif m == 'SED':
            self.d = 1
        elif m == 'CLI':
            self.i = 0
        elif m == 'SEI':
            self.i = 1
        elif m == 'CLV':
            self.v = 0
        elif m == 'NOP':
            pass
        elif m == 'BRK':
            raise Stop('BRK at $%04X' % ((self.pc - 1) & 0xFFFF))
        else:
            raise Stop('%s is not emulated' % m)


def read_files(d):
    """The disk's files as dos33.py extracted them: name -> (data, load address)."""
    files = {}
    catalog = pathlib.Path(d, 'CATALOG.txt').read_text().splitlines()[1:]
    for line in catalog:
        m = re.match(r'^(\S)\s+\*?\s*\d+  (.{30})  (\$[0-9A-F]{4})?', line)
        ftype, name = m.group(1), m.group(2).strip()
        safe = name.replace(' ', '_')
        if ftype == 'B':
            load = int(m.group(3)[1:], 16)
            files[name] = (pathlib.Path(d, safe + '.bin').read_bytes(), load)
        elif ftype == 'T':
            files[name] = (pathlib.Path(d, safe + '.txt.bin').read_bytes(), None)
    return files


def play(files_dir, commands, max_steps=200_000_000, screens=None):
    m = Machine(read_files(files_dir))
    m.commands = list(commands)
    m.load('ADVENTURE')
    m.pc = 0x0800
    if screens:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import pictures
        os.makedirs(screens, exist_ok=True)

        def shot(mach):
            rows = pictures.hires_color(bytes(mach.mem[0x2000:0x4000]))
            pictures.png(os.path.join(screens, 'screen_%03d.png' % mach.prompts),
                         pictures.W * pictures.SCALE, pictures.H * pictures.SCALE, rows)
        m.on_prompt = shot
    try:
        m.run(max_steps)
    except Stop as e:
        reason = str(e)
    if m.line.strip():
        m.out.append(m.line.rstrip())
    return m, reason


def main():
    args = sys.argv[1:]
    opts = {}
    for k in ('--transcript', '--screens', '--screen-hashes', '--max-steps'):
        if k in args:
            i = args.index(k)
            opts[k] = args[i + 1]
            del args[i:i + 2]
    files_dir, cmd_file = args
    commands = [l.split('#')[0].strip() for l in pathlib.Path(cmd_file).read_text().splitlines()]
    commands = [c for c in commands if c]
    m, reason = play(files_dir, commands, int(opts.get('--max-steps', 200_000_000)), opts.get('--screens'))
    text = '\n'.join(m.out) + '\n'
    if '--screen-hashes' in opts:
        pathlib.Path(opts['--screen-hashes']).write_text('\n'.join(m.screens) + '\n')
    if '--transcript' in opts:
        pathlib.Path(opts['--transcript']).write_text(text)
    else:
        sys.stdout.write(text)
    print('-- stopped: %s after %d commands, %d instructions' % (reason, m.prompts, m.steps),
          file=sys.stderr)


if __name__ == '__main__':
    main()

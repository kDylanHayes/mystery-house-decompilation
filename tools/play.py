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
    __slots__ = ('files', 'mem', 'a', 'x', 'y', 'sp', 'n', 'v', 'd', 'i', 'z', 'c', 'pc', 'out',
                 'line', 'commands', 'reading', 'saved', 'steps', 'prompts', 'on_prompt',
                 'screens', 'executed', 'hooks')

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
        self.executed = None       # a set to record every executed address in (gamecov.py)
        self.hooks = {}            # address -> function(machine), called while recording

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
        m, handlers = self.mem, HANDLERS
        special = bytearray(0x10000)   # 1 where the emulator steps in instead of running code
        special[0xD000:] = b'\x01' * 0x3000
        for a in (COUT, GETLN, GETLN1, WAIT, HOME, DOS_WARM, APPLESOFT_ERROR):
            special[a] = 1
        executed, hooks = self.executed, self.hooks
        steps = self.steps
        try:
            while True:
                pc = self.pc
                if special[pc]:
                    self.steps = steps
                    self.trap()
                    continue
                if executed is not None:
                    executed.add(pc)
                    if pc in hooks:
                        hooks[pc](self)
                steps += 1
                if steps > max_steps:
                    raise Stop('step limit reached at $%04X' % pc)
                h = handlers[m[pc]]
                if h is None:
                    raise Stop('undocumented opcode $%02X at $%04X' % (m[pc], pc))
                h(self, m, pc)
        finally:
            self.steps = steps


# ---- the CPU: one generated function per opcode -------------------------------------------
# Each handler(machine, mem, pc) works out the operand address, steps the PC past the
# instruction, then does the operation. Reads of $C000-$C0FF (I/O) give 0 and writes there are
# dropped, as on the machine without its cards.

MODES = {  # mode: (operand address code, instruction length)
    'imp': ('', 1), 'acc': ('', 1),
    'imm': ('ea = pc + 1', 2),
    'zp': ('ea = m[pc + 1]', 2),
    'zpx': ('ea = (m[pc + 1] + c.x) & 0xFF', 2),
    'zpy': ('ea = (m[pc + 1] + c.y) & 0xFF', 2),
    'abs': ('ea = m[pc + 1] | m[pc + 2] << 8', 3),
    'abx': ('ea = ((m[pc + 1] | m[pc + 2] << 8) + c.x) & 0xFFFF', 3),
    'aby': ('ea = ((m[pc + 1] | m[pc + 2] << 8) + c.y) & 0xFFFF', 3),
    'izx': ('z = (m[pc + 1] + c.x) & 0xFF\nea = m[z] | m[(z + 1) & 0xFF] << 8', 2),
    'izy': ('z = m[pc + 1]\nea = ((m[z] | m[(z + 1) & 0xFF] << 8) + c.y) & 0xFFFF', 2),
    'ind': ('a = m[pc + 1] | m[pc + 2] << 8\nea = m[a] | m[(a & 0xFF00) | ((a + 1) & 0xFF)] << 8', 3),
    'rel': ('r = m[pc + 1]\nea = (pc + 2 + (r - 256 if r > 127 else r)) & 0xFFFF', 2),
}
READ = 'v = m[ea] if ea < 0xC000 or ea >= 0xC100 else 0'
WRITE = 'if ea < 0xC000 or ea >= 0xC100:\n    m[ea] = v'
NZ = 'c.n = v >> 7\nc.z = 1 if v == 0 else 0'
PUSH = 'm[0x100 + c.sp] = v\nc.sp = (c.sp - 1) & 0xFF'
PULL = 'c.sp = (c.sp + 1) & 0xFF\nv = m[0x100 + c.sp]'
BRANCH = {'BNE': 'not c.z', 'BEQ': 'c.z', 'BPL': 'not c.n', 'BMI': 'c.n',
          'BCC': 'not c.c', 'BCS': 'c.c', 'BVC': 'not c.v', 'BVS': 'c.v'}
FLAG_OPS = {'CLC': 'c.c = 0', 'SEC': 'c.c = 1', 'CLD': 'c.d = 0', 'SED': 'c.d = 1',
            'CLI': 'c.i = 0', 'SEI': 'c.i = 1', 'CLV': 'c.v = 0', 'NOP': ''}
SHIFTS = {'ASL': 'c.c = v >> 7\nv = (v << 1) & 0xFF',
          'LSR': 'c.c = v & 1\nv >>= 1',
          'ROL': 'o = c.c\nc.c = v >> 7\nv = ((v << 1) | o) & 0xFF',
          'ROR': 'o = c.c\nc.c = v & 1\nv = (v >> 1) | (o << 7)'}


def operation(op, mode):
    """The Python for one operation, after the operand address (ea) is known."""
    if op in ('LDA', 'LDX', 'LDY'):
        return '\n'.join([READ, 'c.%s = v' % op[2].lower(), NZ])
    if op in ('STA', 'STX', 'STY'):
        return 'v = c.%s\n%s' % (op[2].lower(), WRITE)
    if op in BRANCH:
        return 'if %s:\n    c.pc = ea' % BRANCH[op]
    if op == 'JSR':
        return 'r = (c.pc - 1) & 0xFFFF\nv = r >> 8\n%s\nv = r & 0xFF\n%s\nc.pc = ea' % (PUSH, PUSH)
    if op == 'RTS':
        return 'c.rts()'
    if op == 'JMP':
        return 'c.pc = ea'
    if op in ('ADC', 'SBC'):
        return '\n'.join(["if c.d:\n    raise Stop('decimal mode is not emulated')", READ,
                          'v ^= 0xFF' if op == 'SBC' else '',
                          'a = c.a\nr = a + v + c.c', 'c.v = 1 if (~(a ^ v) & (a ^ r) & 0x80) else 0',
                          'c.c = r >> 8\nv = r & 0xFF\nc.a = v', NZ])
    if op in ('CMP', 'CPX', 'CPY'):
        reg = {'CMP': 'a', 'CPX': 'x', 'CPY': 'y'}[op]
        return '\n'.join([READ, 'r = c.%s - v' % reg, 'c.c = 1 if r >= 0 else 0', 'v = r & 0xFF', NZ])
    if op in ('AND', 'ORA', 'EOR'):
        sym = {'AND': '&', 'ORA': '|', 'EOR': '^'}[op]
        return '\n'.join([READ, 'v = c.a %s v' % sym, 'c.a = v', NZ])
    if op == 'BIT':
        return '\n'.join([READ, 'c.n = v >> 7\nc.v = v >> 6 & 1', 'c.z = 1 if (c.a & v) == 0 else 0'])
    if op in SHIFTS:
        if mode == 'acc':
            return '\n'.join(['v = c.a', SHIFTS[op], NZ, 'c.a = v'])
        return '\n'.join([READ, SHIFTS[op], NZ, WRITE])
    if op in ('INC', 'DEC'):
        return '\n'.join([READ, 'v = (v %s 1) & 0xFF' % ('+' if op == 'INC' else '-'), NZ, WRITE])
    if op in ('INX', 'INY', 'DEX', 'DEY'):
        reg = op[2].lower()
        return '\n'.join(['v = (c.%s %s 1) & 0xFF' % (reg, '+' if op[0] == 'I' else '-'), 'c.%s = v' % reg, NZ])
    if op in ('TAX', 'TAY', 'TXA', 'TYA', 'TSX'):
        src, dst = {'TAX': ('a', 'x'), 'TAY': ('a', 'y'), 'TXA': ('x', 'a'), 'TYA': ('y', 'a'),
                    'TSX': ('sp', 'x')}[op]
        return '\n'.join(['v = c.%s' % src, 'c.%s = v' % dst, NZ])
    if op == 'TXS':
        return 'c.sp = c.x'
    if op == 'PHA':
        return 'v = c.a\n' + PUSH
    if op == 'PHP':
        return 'v = c.flags() | 0x10\n' + PUSH
    if op == 'PLA':
        return '\n'.join([PULL, 'c.a = v', NZ])
    if op == 'PLP':
        return PULL + '\nc.setflags(v)'
    if op in FLAG_OPS:
        return FLAG_OPS[op]
    if op == 'BRK':
        return "raise Stop('BRK at $%04X' % pc)"
    return "raise Stop('%s is not emulated')" % op


def compile_handlers():
    handlers = [None] * 256
    for code, (op, mode) in OPS.items():
        addr, length = MODES[mode]
        body = '\n'.join(l for l in (addr, 'c.pc = pc + %d' % length, operation(op, mode)) if l)
        src = 'def op_%02X(c, m, pc):\n' % code + '\n'.join('    ' + l for l in body.split('\n'))
        scope = {'Stop': Stop}
        exec(src, scope)
        handlers[code] = scope['op_%02X' % code]
    return handlers


HANDLERS = compile_handlers()


def read_commands(path):
    """A command script: one command per line, '#' starts a comment, blank lines skipped."""
    lines = [l.split('#')[0].strip() for l in pathlib.Path(path).read_text().splitlines()]
    return [l for l in lines if l]


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


def play(files_dir, commands, max_steps=200_000_000, screens=None, setup=None):
    """Run the game on commands; setup(machine), if given, runs first (gamecov.py uses it
    to start recording)."""
    m = Machine(read_files(files_dir))
    m.commands = list(commands)
    if setup:
        setup(m)
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
    commands = read_commands(cmd_file)
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

#!/usr/bin/env python3
"""What the disk shows before the loader: HELLO and MYSTERY.HELLO run on a model of the Apple's
text page, as a timeline a port can replay.

usage: boot.py <extracted dir>        print the timeline as JSON

The two programs are short Applesoft listings, but what they show comes from the Monitor's
text routines: HELLO narrows the text window with POKEs (WNDLFT, WNDTOP, WNDBTM at 32, 34, 35)
and lets COUT, the scroll and HOME's clearing make its animations. So this runs them on a model
of those routines that writes the text page's memory the way the ROM does ($0400-$07FF, rows
interleaved, so a window wider than the screen spills into other rows), and an interpreter for
the subset of Applesoft the two programs use. The Applesoft and Monitor ROMs are not public
domain, so the model follows the routines' documented behaviour; tests/test_boot.py checks the
screens it makes.

Times are milliseconds. A printed character waits as Applesoft's SPEED makes it (the Monitor's
WAIT with A = 256 - SPEED: (26 + 27A + 5A^2) / 2 microseconds). An empty FOR loop's step
(LOOP_MS) and the disk's speed (LOAD_MS_PER_BYTE) are estimates, not measurements.

The timeline (PORTING.md, "Before the game") is a list of steps, each with "at", the time since
the start or since the last key:
  {"display": "text" | "graphics"}    what the screen shows: the text page, or hi-res page 1
                                      full screen
  {"hgr": true}                       hi-res page 1 cleared to black
  {"row": r, "col": c, "text": s, "char_ms": d}
                                      s written on the text page from (r, c) rightwards, one
                                      character every d ms
  {"title": "1987", "ms": d}          the 1987 title arrives in hi-res page 1, in memory order,
                                      over d ms (BLOAD AUTO LOAD OBJ)
  {"key": true}                       waits for a key (GET)
The last step is MYSTERY.HELLO's CALL 4093, which starts the loader (with the text page as it
is): {"loader": true}.
"""
import json
import os
import pathlib
import re
import sys

LOOP_MS = 1.1               # one step of an empty FOR ... NEXT (estimate)
LOAD_MS_PER_BYTE = 0.8      # DOS 3.3 BLOAD (estimate: about 1.25 KB a second)
AUTO_LOAD_OBJ = (0x0FFD, 0x4000)   # where BLOAD AUTO LOAD OBJ writes; the title is $2000-$3FFF

WNDLFT, WNDWDTH, WNDTOP, WNDBTM = 32, 33, 34, 35


def text_address(row, col=0):
    """The text page address of a row and column (Monitor BASCALC)."""
    return 0x400 + (row & 7) * 0x80 + (row >> 3) * 0x28 + col


def text_position(addr):
    """(row, col) shown at a text page address, or None for the screen holes and memory
    beyond the page."""
    o = addr - 0x400
    if not 0 <= o < 0x400:
        return None
    third, col = divmod(o % 0x80, 40)
    return None if third == 3 else (o // 0x80 + 8 * third, col)


class Monitor:
    """The text page and the Monitor's text routines: COUT, CR, the scroll, HOME, clear to the
    end of the line, VTAB, with the window in WNDLFT, WNDWDTH, WNDTOP, WNDBTM."""

    def __init__(self, record):
        self.mem = {a: ' ' for a in range(0x400, 0x800)}
        self.left, self.width, self.top, self.bottom = 0, 40, 0, 24
        self.cv, self.ch = 23, 0
        self.record = record     # record(addr, char): every write to the text page

    def poke(self, a, v):
        if a == WNDLFT:
            self.left = v
        elif a == WNDWDTH:
            self.width = v
        elif a == WNDTOP:
            self.top = v
        elif a == WNDBTM:
            self.bottom = v

    def base(self, row):
        """VTABZ: BASL for a row, with the window's left edge added."""
        return text_address(row) + self.left

    def write(self, addr, c):
        self.mem[addr] = c
        self.record(addr, c)

    def settxt(self):
        """TEXT: the full window, the cursor on the bottom line (SETWND)."""
        self.left, self.width, self.top, self.bottom = 0, 40, 0, 24
        self.cv = 23

    def clreol(self, row, y):
        """CLEOLZ: spaces from Y to the window's width, at the row's BASL."""
        for i in range(y, self.width):
            self.write(self.base(row) + i, ' ')

    def home(self):
        """HOME: clear the window from its top row, cursor at its top left (CLEOP1)."""
        self.cv, self.ch = self.top, 0
        row = self.top
        while True:
            self.clreol(row, 0)
            row += 1
            if row >= self.bottom:
                break

    def scroll(self):
        """SCROLL: each row of the window from the next one, the bottom row cleared. With the
        window's top at or below its bottom, only the top row is cleared."""
        row = self.top
        while True:
            dst = self.base(row)
            row += 1
            if row >= self.bottom:
                for i in range(self.width):
                    self.write(dst + i, ' ')
                return
            src = self.base(row)
            for i in reversed(range(self.width)):
                self.write(dst + i, self.mem.get(src + i, ' '))

    def cr(self):
        """CROUT and LF: column 0, the next row, scrolling at the window's bottom."""
        self.ch = 0
        self.cv += 1
        if self.cv >= self.bottom:
            self.cv -= 1
            self.scroll()

    def cout(self, c):
        """COUT1: a character at the cursor, a carriage return past the window's width."""
        if c == '\r':
            self.cr()
            return
        self.write(self.base(self.cv) + self.ch, c)
        self.ch += 1
        if self.ch >= self.width:
            self.cr()


def wait_ms(speed):
    """The delay after each printed character at Applesoft's SPEED."""
    a = (256 - speed) & 0xFF or 256
    return (26 + 27 * a + 5 * a * a) / 2 / 1000


# LIST puts a space between a function's name and its parenthesis: RIGHT$ (A$,A)
TOKEN = re.compile(r'\s*(?:(\d+(?:\.\d+)?)|("[^"]*"?)|((?:LEN|RIGHT\$|LEFT\$|CHR\$)\s*\(|[A-Z][A-Z0-9]*\$?)|'
                   r'(<>|>=|<=|[-+*/=<>(),;]))')


def tokens(s):
    out, pos = [], 0
    while pos < len(s):
        if s[pos:].strip() == '':
            break
        m = TOKEN.match(s, pos)
        if not m:
            raise SyntaxError('cannot read %r' % s[pos:])
        tok = next(g for g in m.groups() if g is not None)
        out.append(tok if tok[0] == '"' else tok.replace(' ', ''))
        pos = m.end()
    return out


def var(name):
    """Applesoft keeps two letters of a name, and the $ of a string."""
    return name.rstrip('$')[:2] + ('$' if name.endswith('$') else '')


class Expr:
    """An expression of the subset the programs use: numbers, strings, variables, LEN,
    RIGHT$, LEFT$, CHR$, + - * / and comparisons."""

    def __init__(self, toks, env):
        self.t, self.i, self.env = toks, 0, env

    def peek(self):
        return self.t[self.i] if self.i < len(self.t) else None

    def take(self, want=None):
        tok = self.peek()
        if want is not None and tok != want:
            raise SyntaxError('expected %s, found %s' % (want, tok))
        self.i += 1
        return tok

    def expr(self):
        a = self.sum()
        if self.peek() in ('=', '<', '>', '<>', '<=', '>='):
            op, b = self.take(), self.sum()
            a = int({'=': a == b, '<': a < b, '>': a > b, '<>': a != b, '<=': a <= b,
                     '>=': a >= b}[op])
        return a

    def sum(self):
        a = self.term()
        while self.peek() in ('+', '-'):
            op, b = self.take(), self.term()
            a = a + b if op == '+' else a - b
        return a

    def term(self):
        a = self.factor()
        while self.peek() in ('*', '/'):
            op, b = self.take(), self.factor()
            a = a * b if op == '*' else a / b
        return a

    def factor(self):
        tok = self.take()
        if tok == '-':
            return -self.factor()
        if tok == '(':
            v = self.expr()
            self.take(')')
            return v
        if tok[0] == '"':
            return tok.strip('"')
        if tok[0].isdigit():
            return float(tok) if '.' in tok else int(tok)
        if tok.endswith('('):
            args = [self.expr()]
            while self.peek() == ',':
                self.take()
                args.append(self.expr())
            self.take(')')
            f = tok[:-1]
            if f == 'LEN':
                return len(args[0])
            if f == 'RIGHT$':
                return args[0][len(args[0]) - int(args[1]):] if args[1] else ''
            if f == 'LEFT$':
                return args[0][:int(args[1])]
            if f == 'CHR$':
                return chr(int(args[0]))
            raise SyntaxError('function %s' % f)
        return self.env.get(var(tok), '' if tok.endswith('$') else 0)


def statements(line):
    """A listing line split at the colons outside strings."""
    out, cur, quoted = [], '', False
    for c in line:
        if c == '"':
            quoted = not quoted
        if c == ':' and not quoted:
            out.append(cur.strip())
            cur = ''
        else:
            cur += c
    out.append(cur.strip())
    return [s for s in out if s]


def read_listing(path):
    """{line number: [statements]} from a listing as dos33.py writes it."""
    prog = {}
    for line in pathlib.Path(path).read_text().splitlines():
        m = re.match(r'(\d+) (.*)', line)
        if m:
            prog[int(m.group(1))] = statements(m.group(2))
    return prog


class Boot:
    """Runs HELLO, then MYSTERY.HELLO, and keeps the timeline."""

    def __init__(self, extracted):
        self.dir = extracted
        self.t = 0.0
        self.speed = 255
        self.steps = []
        self.writes = []         # (time, addr, char), turned into text steps
        self.mon = Monitor(lambda a, c: self.writes.append((self.t, a, c)))
        self.shown = {}          # what each (row, col) shows, as the steps have written it
        self.before_home = []    # the text page just before each HOME, for the tests
        self.notice = None       # the text page while GET waits

    def step(self, **kw):
        self.flush()
        self.steps.append({'at': round(self.t, 2), **kw})

    def show(self, display):
        if display != getattr(self, 'display', None):
            self.display = display
            self.step(display=display)

    def flush(self):
        """The text page writes since the last step, as runs on a row; a write that leaves
        the screen as it was is left out, unless it is inside a run."""
        run = None
        for t, addr, c in self.writes:
            pos = text_position(addr)
            if pos is None:
                continue
            follows = run and pos == (run['row'], run['col'] + len(run['text']))
            # the second character sets the run's pace; the rest must keep it
            paced = follows and (len(run['text']) == 1 or abs(t - run['last'] - run['char_ms']) < 1e-6)
            if self.shown.get(pos, ' ') == c and not paced:
                continue    # changes nothing on screen (kept inside a run, to keep it whole)
            self.shown[pos] = c
            if paced:
                if len(run['text']) == 1:
                    run['char_ms'] = t - run['last']
                run['text'] += c
                run['last'] = t
                continue
            if run:
                self.emit(run)
            run = {'at': t, 'row': pos[0], 'col': pos[1], 'text': c, 'char_ms': 0, 'last': t}
        if run:
            self.emit(run)
        self.writes = []

    def emit(self, run):
        self.steps.append({'at': round(run['at'], 2), 'row': run['row'], 'col': run['col'],
                           'text': run['text'], 'char_ms': round(run['char_ms'], 3)})

    def snapshot(self):
        """The text page as 24 lines of 40 characters."""
        return [''.join(self.mon.mem[text_address(r, c)] for c in range(40)) for r in range(24)]

    def output(self, c):
        self.mon.cout(c)
        self.t += wait_ms(self.speed)

    def run(self, name):
        prog = read_listing(os.path.join(self.dir, name.replace(' ', '_') + '.bas'))
        lines = sorted(prog)
        env, loops = {}, []
        li, si = 0, 0
        while li < len(lines):
            stmts = prog[lines[li]]
            if si >= len(stmts):
                li, si = li + 1, 0
                continue
            s = stmts[si]
            si += 1
            jump = self.statement(s, env, loops, (li, si))
            if jump == 'end':
                return
            if jump == 'skip line':
                li, si = li + 1, 0
            elif jump is not None:
                li, si = jump

    def dos(self, cmd):
        cmd = cmd.strip()
        if cmd.startswith('RUN '):
            self.run(cmd[4:])
            return 'end'
        if cmd.replace(' ', '') == 'BLOADAUTOLOADOBJ':
            start, end = AUTO_LOAD_OBJ
            self.t += (0x2000 - start) * LOAD_MS_PER_BYTE
            self.step(title='1987', ms=round(0x2000 * LOAD_MS_PER_BYTE, 2))
            self.t += (end - 0x2000) * LOAD_MS_PER_BYTE
            return None
        raise SyntaxError('DOS command %r' % cmd)

    def statement(self, s, env, loops, here):
        ev = lambda text: Expr(tokens(text), env).expr()
        word = re.match(r'[A-Z]+=?|&', s).group(0) if re.match(r'[A-Z]', s) else ''
        if s == 'TEXT':
            self.mon.settxt()
            self.show('text')
        elif s == 'HOME' or s == 'CALL -936':
            self.before_home.append(self.snapshot())
            self.mon.home()
        elif s == 'HGR':
            self.step(hgr=True)
        elif s == 'LIST':
            pass    # lists the program on the text page, hidden behind the full-screen picture
        elif s.startswith('POKE '):
            a, v = (ev(x) for x in s[5:].split(','))
            if a == -16302:
                self.show('graphics')    # MIXCLR: the picture without text lines
            else:
                self.mon.poke(a, v)
        elif s.startswith('SPEED='):
            self.speed = ev(s[6:])
        elif s.startswith('VTAB '):
            self.mon.cv = ev(s[5:]) - 1
        elif s.startswith('HTAB '):
            ch = ev(s[5:]) - 1
            while ch >= 40:
                ch -= 40
                self.output('\r')
            self.mon.ch = ch
        elif s.startswith('FOR '):
            m = re.match(r'FOR (\w+)=(.+?) TO (.+?)(?: STEP (.+))?$', s)
            v = var(m.group(1))
            env[v] = ev(m.group(2))
            loops[:] = [l for l in loops if l[0] != v]
            loops.append((v, ev(m.group(3)), ev(m.group(4)) if m.group(4) else 1, here))
        elif s.startswith('NEXT'):
            v, end, step, back = loops[-1]
            env[v] += step
            self.t += LOOP_MS
            if (step > 0 and env[v] <= end) or (step < 0 and env[v] >= end):
                return back
            loops.pop()
        elif s.startswith('IF '):
            m = re.match(r'IF (.+) THEN (.+)$', s)
            if not ev(m.group(1)):
                return 'skip line'
            return self.statement(m.group(2), env, loops, here)
        elif s.startswith('PRINT'):
            return self.print(s[5:], env)
        elif s.startswith('GET '):
            self.notice = self.snapshot()
            self.step(key=True)
            self.t = 0.0
        elif re.match(r'CALL ', s):
            if ev(s[5:]) == 4093:
                self.step(loader=True)
                return 'end'
            raise SyntaxError(s)
        elif re.match(r'[A-Z][A-Z0-9]*\$?=', s):
            name, value = s.split('=', 1)
            env[var(name.strip())] = ev(value)
        else:
            raise SyntaxError('statement %r (%s)' % (s, word))
        return None

    def print(self, rest, env):
        """PRINT: items one after another (; or nothing between them), then a carriage return
        unless it ends with ;. A line that starts with CTRL-D is a DOS command."""
        toks = tokens(rest)
        e = Expr(toks, env)
        text, newline = '', True
        while e.peek() is not None:
            if e.peek() == ';':
                e.take()
                newline = False
                continue
            newline = True
            text += str(e.expr())
        if text.startswith('\x04'):
            return self.dos(text[1:])
        for c in text + ('\r' if newline else ''):
            self.output(c)
        return None


def timeline(extracted):
    b = Boot(extracted)
    b.run('HELLO')
    return b


def replay(steps):
    """The text page after a list of steps, as 24 lines (for checking a timeline)."""
    page = [[' '] * 40 for _ in range(24)]
    for s in steps:
        if 'text' in s:
            for i, c in enumerate(s['text']):
                page[s['row']][s['col'] + i] = c
    return [''.join(r) for r in page]


def main():
    b = timeline(sys.argv[1])
    json.dump(b.steps, sys.stdout, indent=1)
    print()


if __name__ == '__main__':
    main()

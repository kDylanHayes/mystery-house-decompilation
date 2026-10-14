#!/usr/bin/env python3
"""List and build the disk's BASIC programs.

usage: basic.py build <source> <out.bin>        tokenize a program (Applesoft .bas or Integer .int)
       basic.py list <program.bin> <kind> <out>  make the source from a program (used once);
                                                 kind is applesoft or integer

Source format: one BASIC line per line, as LIST shows it (`10 TEXT : HOME`). Lines starting with
';' are comments. `#extra $0A` records bytes the program file holds after the program's end
(Applesoft's SAVE writes up to its variable pointer, one byte past the end marker).

Applesoft (.bas): the builder tokenizes the way Applesoft does: keywords become tokens ($80+),
spaces are dropped except inside strings and after REM / DATA, and each line is stored as
[link to the next line] [line number] [tokens] $00 with links for a program at $0801, then
$00 $00. A keyword spelled inside a variable name is tokenized too, exactly as on an Apple II.

Integer BASIC (.int): only what the disk's APPLESOFT file uses: PRINT "string" and END. Lines
are [length] [line number] [tokens] and, in this file, end with $00.
"""
import re
import sys

APPLESOFT = [
    'END', 'FOR', 'NEXT', 'DATA', 'INPUT', 'DEL', 'DIM', 'READ', 'GR', 'TEXT', 'PR#', 'IN#',
    'CALL', 'PLOT', 'HLIN', 'VLIN', 'HGR2', 'HGR', 'HCOLOR=', 'HPLOT', 'DRAW', 'XDRAW', 'HTAB',
    'HOME', 'ROT=', 'SCALE=', 'SHLOAD', 'TRACE', 'NOTRACE', 'NORMAL', 'INVERSE', 'FLASH',
    'COLOR=', 'POP', 'VTAB', 'HIMEM:', 'LOMEM:', 'ONERR', 'RESUME', 'RECALL', 'STORE', 'SPEED=',
    'LET', 'GOTO', 'RUN', 'IF', 'RESTORE', '&', 'GOSUB', 'RETURN', 'REM', 'STOP', 'ON', 'WAIT',
    'LOAD', 'SAVE', 'DEF', 'POKE', 'PRINT', 'CONT', 'LIST', 'CLEAR', 'GET', 'NEW', 'TAB(', 'TO',
    'FN', 'SPC(', 'THEN', 'AT', 'NOT', 'STEP', '+', '-', '*', '/', '^', 'AND', 'OR', '>', '=',
    '<', 'SGN', 'INT', 'ABS', 'USR', 'FRE', 'SCRN(', 'PDL', 'POS', 'SQR', 'RND', 'LOG', 'EXP',
    'COS', 'SIN', 'TAN', 'ATN', 'PEEK', 'LEN', 'STR$', 'VAL', 'ASC', 'CHR$', 'LEFT$', 'RIGHT$',
    'MID$']
REM, DATA = 0x80 + APPLESOFT.index('REM'), 0x80 + APPLESOFT.index('DATA')
INTEGER = {0x61: 'PRINT', 0x51: 'END'}
INT_QUOTE_OPEN, INT_QUOTE_CLOSE, INT_EOL = 0x28, 0x29, 0x00
BASE = 0x0801


def esc(c):
    return chr(c) if 0x20 <= c < 0x7F and c != 0x5C else '\\x%02X' % c


def unesc(s):
    return [int(m[2:], 16) if m.startswith('\\x') else ord(m)
            for m in re.findall(r'\\x[0-9A-Fa-f]{2}|.', s)]


def read_source(path):
    lines, extra = [], b''
    for n, raw in enumerate(open(path, encoding='ascii'), 1):
        line = raw.rstrip('\n')
        if not line.strip() or line.startswith(';'):
            continue
        if line.startswith('#extra'):
            extra = bytes(int(v.strip().lstrip('$'), 16) for v in line[6:].split(','))
            continue
        m = re.match(r'^(\d+) ?(.*)$', line)
        if not m:
            raise SystemExit('%s:%d: expected a line number' % (path, n))
        lines.append((int(m.group(1)), m.group(2)))
    return lines, extra


# ---- Applesoft --------------------------------------------------------------------------
def crunch(text):
    """Tokenize one line's text the way Applesoft's PARSE does."""
    out = bytearray()
    chars = unesc(text)
    i = 0
    literal = None      # None, 'string', 'rem', 'data'
    data_mode = False   # inside a DATA statement (a string there returns to 'data')
    while i < len(chars):
        c = chars[i]
        if literal == 'rem':
            out.append(c)
            i += 1
            continue
        if literal == 'string':
            out.append(c)
            if c == 0x22:
                literal = 'data' if data_mode else None
            i += 1
            continue
        if c == 0x22:
            out.append(c)
            literal = 'string'
            i += 1
            continue
        if literal == 'data':
            if c == ord(':'):
                literal = None
                data_mode = False
            out.append(c)
            i += 1
            continue
        if c == 0x20:
            i += 1
            continue
        if c == ord('?'):
            out.append(0x80 + APPLESOFT.index('PRINT'))
            i += 1
            continue
        # keyword match: spaces inside a keyword are skipped, first match in table order wins
        tok = None
        for t, word in enumerate(APPLESOFT):
            j, k = i, 0
            while k < len(word) and j < len(chars):
                if chars[j] == 0x20:
                    j += 1
                    continue
                if chars[j] != ord(word[k]):
                    break
                j += 1
                k += 1
            if k == len(word):
                if word == 'AT' and j < len(chars) and chars[j] == ord('N'):
                    continue   # ATN, not AT
                tok = (t, j)
                break
        if tok:
            out.append(0x80 + tok[0])
            i = tok[1]
            if 0x80 + tok[0] == REM:
                literal = 'rem'
            elif 0x80 + tok[0] == DATA:
                literal = 'data'
                data_mode = True
            continue
        out.append(c)
        i += 1
    return bytes(out)


def build_applesoft(lines, extra):
    out = bytearray()
    addr = BASE
    for num, text in lines:
        body = crunch(text)
        nxt = addr + 4 + len(body) + 1
        out += bytes((nxt & 0xFF, nxt >> 8, num & 0xFF, num >> 8)) + body + b'\x00'
        addr = nxt
    return bytes(out) + b'\x00\x00' + extra


def list_applesoft(prog):
    out = []
    pos = 0
    while prog[pos] or prog[pos + 1]:
        num = prog[pos + 2] | prog[pos + 3] << 8
        end = prog.index(0, pos + 4)
        text = ''
        literal = None
        in_data = False
        for b in prog[pos + 4:end]:
            if literal == 'rem':
                text += esc(b)
            elif literal == 'string':
                text += esc(b)
                if b == 0x22:
                    literal = 'data' if in_data else None
            elif b == 0x22:
                text += '"'
                literal = 'string'
            elif literal == 'data':
                text += esc(b)
                if b == ord(':'):
                    literal = None
            elif b >= 0x80:
                word = APPLESOFT[b - 0x80]
                if word in ('+', '-', '*', '/', '^', '>', '<', '='):
                    text += word
                else:
                    text += ('' if not text or text.endswith(' ') else ' ') + word + ' '
                if b == REM:
                    literal = 'rem'
                    text = text.rstrip(' ')
                elif b == DATA:
                    literal = 'data'
                    in_data = True
                    text = text.rstrip(' ')
            else:
                text += esc(b)
            if b != DATA and literal is None:
                in_data = False
        if literal in (None, 'data'):
            text = text.rstrip(' ')        # spaces outside strings are not stored anyway
        out.append('%d %s' % (num, text.lstrip(' ')))
        pos = end + 1
    extra = prog[pos + 2:]
    return out, extra


# ---- Integer BASIC ------------------------------------------------------------------------
def build_integer(lines, extra):
    out = bytearray()
    names = {v: k for k, v in INTEGER.items()}
    for num, text in lines:
        m = re.match(r'^(PRINT|END)\s*(?:"(.*)")?\s*$', text)
        if not m:
            raise SystemExit('Integer BASIC: only PRINT "..." and END are supported: %s' % text)
        body = bytes([names[m.group(1)]])
        if m.group(2) is not None:
            body += bytes([INT_QUOTE_OPEN] + [c | 0x80 for c in unesc(m.group(2))] + [INT_QUOTE_CLOSE])
        line = bytes((num & 0xFF, num >> 8)) + body + bytes([INT_EOL])
        out += bytes([len(line) + 1]) + line
    return bytes(out) + extra


def list_integer(prog):
    out = []
    pos = 0
    while pos < len(prog):
        n = prog[pos]
        num = prog[pos + 1] | prog[pos + 2] << 8
        body = prog[pos + 3:pos + n - 1]
        text = INTEGER[body[0]]
        if len(body) > 1:
            assert body[1] == INT_QUOTE_OPEN and body[-1] == INT_QUOTE_CLOSE
            text += ' "%s"' % ''.join(esc(c & 0x7F) for c in body[2:-1])
        out.append('%d %s' % (num, text))
        pos += n
    return out, b''


def main():
    if sys.argv[1] == 'build':
        src, out = sys.argv[2:4]
        lines, extra = read_source(src)
        data = build_integer(lines, extra) if src.endswith('.int') else build_applesoft(lines, extra)
        open(out, 'wb').write(data)
    elif sys.argv[1] == 'list':
        prog = open(sys.argv[2], 'rb').read()
        lines, extra = (list_integer if sys.argv[3] == 'integer' else list_applesoft)(prog)
        with open(sys.argv[4], 'w') as f:
            f.write('\n'.join(lines) + '\n')
            if extra:
                f.write('#extra %s\n' % ','.join('$%02X' % c for c in extra))
    else:
        raise SystemExit(__doc__)


if __name__ == '__main__':
    main()

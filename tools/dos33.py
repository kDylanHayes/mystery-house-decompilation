#!/usr/bin/env python3
"""Extract every file from an Apple II DOS 3.3 disk image (.do / .dsk, DOS sector order).

usage: dos33.py <disk.do> <outdir>                       extract every file
       dos33.py put <disk.do> <out.do> NAME=file ...        replace files' contents
                (a binary file needs file.load holding its hex load address; a text file's
                data must end with $00)

Binary (B) files are written without their 4-byte load-address/length header; the header is
recorded in <outdir>/CATALOG.txt. Applesoft (A) files are written both raw (.bas.bin) and
detokenized (.bas). Text (T) files have their high bits stripped and CRs turned into newlines.
"""
import os
import sys

SECTOR = 256
TYPES = {0x00: 'T', 0x01: 'I', 0x02: 'A', 0x04: 'B', 0x08: 'S', 0x10: 'R', 0x20: 'a', 0x40: 'b'}

APPLESOFT_TOKENS = [
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


def sector(disk, track, sec):
    off = (track * 16 + sec) * SECTOR
    return disk[off:off + SECTOR]


def read_file(disk, track, sec):
    """Follow a track/sector list chain and return the file's data sectors concatenated."""
    data = bytearray()
    while track:
        tsl = sector(disk, track, sec)
        for i in range(12, SECTOR, 2):
            t, s = tsl[i], tsl[i + 1]
            if t == 0 and s == 0:
                # sparse sector (random-access text files) or end of list
                data += bytes(SECTOR)
                continue
            data += sector(disk, t, s)
        track, sec = tsl[1], tsl[2]
    return bytes(data)


def catalog(disk):
    vtoc = sector(disk, 17, 0)
    track, sec = vtoc[1], vtoc[2]
    while track:
        cat = sector(disk, track, sec)
        for i in range(7):
            e = cat[11 + i * 35:11 + (i + 1) * 35]
            if e[0] in (0x00, 0xFF):
                continue
            name = bytes(b & 0x7F for b in e[3:33]).decode('ascii').rstrip()
            yield name, TYPES.get(e[2] & 0x7F, '?'), bool(e[2] & 0x80), e[0], e[1], e[33] | e[34] << 8
        track, sec = cat[1], cat[2]


def detokenize(prog, base=0x0801):
    out = []
    pos = 0
    while pos + 4 <= len(prog):
        link = prog[pos] | prog[pos + 1] << 8
        if link == 0:
            break
        line = prog[pos + 2] | prog[pos + 3] << 8
        pos += 4
        text = ''
        in_quote = in_rem = False
        while prog[pos] != 0:
            b = prog[pos]
            pos += 1
            if b >= 0x80 and not in_quote and not in_rem:
                tok = APPLESOFT_TOKENS[b - 0x80] if b - 0x80 < len(APPLESOFT_TOKENS) else '?'
                text += ' ' + tok + ' '
                if tok == 'REM':
                    in_rem = True
            else:
                c = chr(b & 0x7F)
                if c == '"':
                    in_quote = not in_quote
                text += c if c.isprintable() else '\\x%02X' % b
        pos += 1
        out.append('%d %s' % (line, ' '.join(text.split()) if not in_quote else text.strip()))
    return '\n'.join(out) + '\n'


# Integer BASIC tokens seen on this disk (the full table has ~128 entries)
INTEGER_TOKENS = {0x00: '', 0x01: '', 0x03: ':', 0x51: 'END', 0x61: 'PRINT ', 0x62: 'PRINT ', 0x63: 'PRINT '}


def list_integer(prog):
    """Integer BASIC: [length] [line lo hi] tokens... $01. Strings are $28 text $29 with the
    text in high-bit ASCII. Only the few tokens this disk uses are named."""
    out = []
    pos = 0
    while pos < len(prog) and prog[pos]:
        n = prog[pos]
        line = prog[pos + 1] | prog[pos + 2] << 8
        body = prog[pos + 3:pos + n]
        text, i = '', 0
        while i < len(body):
            b = body[i]
            if b == 0x28:
                j = body.index(0x29, i)
                text += '"' + ''.join(chr(c & 0x7F) if (c & 0x7F) >= 0x20 else '^' + chr((c & 0x7F) + 64)
                                      for c in body[i + 1:j]) + '"'
                i = j + 1
                continue
            text += INTEGER_TOKENS.get(b, '<%02X>' % b)
            i += 1
        out.append('%d %s' % (line, text.strip()))
        pos += n
    return '\n'.join(out) + '\n'


def safe(name):
    return name.replace(' ', '_').replace('/', '_')


def file_sectors(disk, track, sec):
    """(T/S list sectors, data sectors) of a file, in order."""
    lists, data = [], []
    while track:
        lists.append((track, sec))
        tsl = sector(disk, track, sec)
        for i in range(12, SECTOR, 2):
            if tsl[i] or tsl[i + 1]:
                data.append((tsl[i], tsl[i + 1]))
        track, sec = tsl[1], tsl[2]
    return lists, data


def bitmap(disk, t, s, free):
    """Mark sector (t, s) free or used in the VTOC bitmap."""
    off = 17 * 16 * SECTOR + 0x38 + 4 * t + (0 if s >= 8 else 1)
    bit = 1 << (s - 8 if s >= 8 else s)
    disk[off] = disk[off] | bit if free else disk[off] & ~bit


def allocate(disk):
    vtoc = 17 * 16 * SECTOR
    for t in list(range(18, 35)) + list(range(16, 2, -1)):
        for s in range(15, -1, -1):
            off = vtoc + 0x38 + 4 * t + (0 if s >= 8 else 1)
            if disk[off] & (1 << (s - 8 if s >= 8 else s)):
                bitmap(disk, t, s, False)
                return t, s
    raise SystemExit('disk full')


def put(disk, name, load, payload):
    """Replace file `name` with `payload`: a binary file loaded at `load`, or a text file
    when `load` is None. The file's existing sectors
    are reused in order (and bytes past the end of the data are left alone), so writing the
    original contents back reproduces the original image exactly."""
    vtoc = sector(disk, 17, 0)
    track, sec = vtoc[1], vtoc[2]
    while track:
        coff = (track * 16 + sec) * SECTOR
        for i in range(7):
            eo = coff + 11 + i * 35
            e = disk[eo:eo + 35]
            if e[0] in (0x00, 0xFF) or bytes(b & 0x7F for b in e[3:33]).decode().rstrip() != name:
                continue
            if load is None:
                # text file: the raw data, ended by $00 (the payload includes it)
                if e[2] & 0x7F != 0x00:
                    raise SystemExit('%s is not a text file; give its load address' % name)
                body = payload
            else:
                if e[2] & 0x7F != 0x04:
                    raise SystemExit('%s is not a binary file' % name)
                body = bytes([load & 0xFF, load >> 8, len(payload) & 0xFF, len(payload) >> 8]) + payload
            lists, data = file_sectors(disk, e[0], e[1])
            # Like DOS 3.3, a file never gives sectors back: saving a smaller file over a larger
            # one keeps the old sectors listed (the original disk has several such files). It only
            # gets new sectors when it grows.
            nd = max(len(data), (len(body) + SECTOR - 1) // SECTOR)
            nl = max(len(lists), (nd + 121) // 122)
            while len(data) < nd:
                data.append(allocate(disk))
            while len(lists) < nl:
                lists.append(allocate(disk))
            for k, (t, s) in enumerate(data):
                chunk = body[k * SECTOR:(k + 1) * SECTOR]   # empty for sectors past the data
                o = (t * 16 + s) * SECTOR
                disk[o:o + len(chunk)] = chunk
            for k, (t, s) in enumerate(lists):
                o = (t * 16 + s) * SECTOR
                nt, ns = lists[k + 1] if k + 1 < nl else (0, 0)
                disk[o + 1], disk[o + 2] = nt, ns
                disk[o + 5], disk[o + 6] = (k * 122) & 0xFF, (k * 122) >> 8
                for j in range(122):
                    ts = data[k * 122 + j] if k * 122 + j < nd else (0, 0)
                    disk[o + 12 + 2 * j], disk[o + 13 + 2 * j] = ts
            disk[eo], disk[eo + 1] = lists[0]
            disk[eo + 33], disk[eo + 34] = (nd + nl) & 0xFF, (nd + nl) >> 8
            return
        track, sec = disk[coff + 1], disk[coff + 2]
    raise SystemExit('no file %s on the disk' % name)


def main():
    if sys.argv[1] == 'put':
        disk = bytearray(open(sys.argv[2], 'rb').read())
        for arg in sys.argv[4:]:
            name, path = arg.split('=', 1)
            data = open(path, 'rb').read()
            # binary files need their load address in <file>.load; text files have none
            load = int(open(path + '.load').read(), 16) if os.path.exists(path + '.load') else None
            put(disk, name, load, data)
        open(sys.argv[3], 'wb').write(disk)
        return
    disk = open(sys.argv[1], 'rb').read()
    outdir = sys.argv[2]
    os.makedirs(outdir, exist_ok=True)
    lines = ['type locked sectors  name                            load   length']
    for name, ftype, locked, t, s, nsec in catalog(disk):
        raw = read_file(disk, t, s)
        fn = os.path.join(outdir, safe(name))
        load = length = None
        if ftype == 'B':
            load, length = raw[0] | raw[1] << 8, raw[2] | raw[3] << 8
            open(fn + '.bin', 'wb').write(raw[4:4 + length])
        elif ftype in 'AI':
            length = raw[0] | raw[1] << 8
            body = raw[2:2 + length]
            open(fn + '.bas.bin', 'wb').write(body)
            if ftype == 'A':
                open(fn + '.bas', 'w').write(detokenize(body))
            else:
                open(fn + '.bas', 'w').write(list_integer(body))
        elif ftype == 'T':
            end = raw.find(b'\x00')
            body = raw if end < 0 else raw[:end]
            open(fn + '.txt', 'w').write(''.join(
                '\n' if (b & 0x7F) == 0x0D else chr(b & 0x7F) for b in body))
            open(fn + '.txt.bin', 'wb').write(raw)
        else:
            open(fn + '.raw', 'wb').write(raw)
        lines.append('%-4s %-6s %7d  %-30s  %-6s %s' % (
            ftype, '*' if locked else '', nsec, name,
            '$%04X' % load if load is not None else '',
            '$%04X' % length if length is not None else ''))
    open(os.path.join(outdir, 'CATALOG.txt'), 'w').write('\n'.join(lines) + '\n')
    print('\n'.join(lines))


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Build the state snapshots STARTUP and SAVED GAME from src/startup.txt and src/saved_game.txt.

usage: savefile.py build <changes.txt> <base.bin> <adventure.syms.csv> <out.bin>
       savefile.py extract <file.bin> <base.bin> <adventure.syms.csv> <out.txt>
                                                         (used once to create the sources)

Both files are snapshots of $0830-$10FE (the engine's variables, the object table and the room
table), BLOADed over the running game: STARTUP by "play again", SAVED GAME by RESTORE (action
15 writes it with BSAVE SAVED GAME,A$830,L$8CF). Each is described as the bytes that differ
from a base image:
  STARTUP      base: the same range of the assembled ADVENTURE (its starting objects and
               rooms; only some variables differ, as saved when the file was made)
  SAVED GAME   base: STARTUP; the one on the disk is a game in progress
one change per line:

    CURONO = $1D                      a variable, by its name in src/adventure.s
    SWITCH+12 = $01                    a name plus an offset
    object 13 OROOM = $FE              a field of object 13 (field names from src/game.inc)
    room 3 RCURPIC = $36               a field of room 3

The build starts from the base, applies the lines and writes the file. Object and room fields
are found through the tables in the base, so they stay right if the tables change.
"""
import pathlib
import re
import sys

LOAD = 0x0830
OBJBASE, ROOMBASE, RTBLSIZ = 0x0900, 0x0D00, 10
OFIELDS = ['OBJECTNO', 'ONOUN', 'OROOM', 'OPIC', 'OSHAPE', 'OXCOORD', 'OYCOORD', 'OSTATUS', 'OMSG',
           'ONEXT', 'ORPICKT', 'ORPICSTA']
RFIELDS = ['RROOMNO', 'RMSG', 'RN', 'RS', 'RE', 'RW', 'RU', 'RD', 'RBASEPIC', 'RCURPIC']


def symbols(path):
    out = {}
    for line in pathlib.Path(path).read_text().split('\n')[1:]:
        if not line:
            continue
        name, addr, kind, src = line.split(',', 4)[:4]
        if src in ('apple2.inc', 'game.inc') or '.' in name:
            continue
        a = int(addr, 16)
        if LOAD <= a < 0x0900:
            out[name] = a
    return out


def objects(img):
    """object number -> address of its record"""
    out = {}
    a = OBJBASE
    while img[a - LOAD] != 0xFF:
        out[img[a - LOAD]] = a
        a += img[a - LOAD + 9]
    return out


def resolve(target, syms, img):
    m = re.fullmatch(r'object (\d+) (\w+)(?:\+(\d+))?', target)
    if m:
        obj = objects(img)[int(m.group(1))]
        f = OFIELDS.index(m.group(2)) if m.group(2) in OFIELDS else None
        if f is None:
            raise SystemExit('unknown object field %s' % m.group(2))
        return obj + f + int(m.group(3) or 0)
    m = re.fullmatch(r'room (\d+) (\w+)', target)
    if m:
        return ROOMBASE + RTBLSIZ * int(m.group(1)) + RFIELDS.index(m.group(2))
    m = re.fullmatch(r'([A-Za-z_]\w*)(?:\+(\d+))?', target)
    if m and m.group(1) in syms:
        return syms[m.group(1)] + int(m.group(2) or 0)
    m = re.fullmatch(r'\$([0-9A-Fa-f]{4})', target)
    if m:
        return int(m.group(1), 16)
    raise SystemExit('cannot resolve "%s"' % target)


def build(src, startup, symf, out):
    img = bytearray(pathlib.Path(startup).read_bytes())
    base = bytes(img)
    syms = symbols(symf)
    for n, line in enumerate(pathlib.Path(src).read_text().splitlines(True), 1):
        line = line.split(';')[0].strip()
        if not line:
            continue
        target, _, value = line.rpartition('=')
        addr = resolve(target.strip(), syms, base)
        img[addr - LOAD] = int(value.strip().lstrip('$'), 16)
    pathlib.Path(out).write_bytes(img)


def extract(saved, startup, symf, out):
    sv = pathlib.Path(saved).read_bytes()
    st = pathlib.Path(startup).read_bytes()
    syms = symbols(symf)
    by_addr = sorted((a, n) for n, a in syms.items())
    objs = {a: n for n, a in objects(st).items()}
    lines = ['; The bytes that differ from the base image (see tools/savefile.py). Variables are',
             '; named as in src/adventure.s; objects and rooms by number and field (src/game.inc).',
             '']
    for i, (a, b) in enumerate(zip(st, sv)):
        if a == b:
            continue
        addr = LOAD + i
        if addr >= OBJBASE and addr < ROOMBASE:
            start = max(o for o in objs if o <= addr)
            off = addr - start
            f = OFIELDS[min(off, 11)] + ('+%d' % (off - 11) if off > 11 else '')
            target = 'object %d %s' % (objs[start], f)
        elif addr >= ROOMBASE:
            r, f = divmod(addr - ROOMBASE, RTBLSIZ)
            target = 'room %d %s' % (r, RFIELDS[f])
        else:
            name, at = max(((n, x) for x, n in by_addr if x <= addr), key=lambda p: p[1])
            target = name + ('+%d' % (addr - at) if addr > at else '')
        lines.append('%-28s = $%02X    ; was $%02X' % (target, b, a))
    pathlib.Path(out).write_text('\n'.join(lines) + '\n')


def main():
    if sys.argv[1] == 'build':
        build(*sys.argv[2:6])
    elif sys.argv[1] == 'extract':
        extract(*sys.argv[2:6])
    else:
        raise SystemExit(__doc__)


if __name__ == '__main__':
    main()

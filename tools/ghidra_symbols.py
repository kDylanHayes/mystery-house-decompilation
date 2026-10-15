#!/usr/bin/env python3
"""Build the symbol list for the Ghidra pseudocode step.

usage: ghidra_symbols.py <assembler symbols.csv> <apple2.csv> <types.csv> <out.csv>

Names and function comments come from the source (the assembler's symbol table: every label,
and every address constant defined in the program's own .s file). ghidra/symbols/<program>.csv only
adds what Ghidra needs on top: data types and register parameters (func:X), matched to the
source by name (by address only for names the source does not define). ghidra/symbols/apple2.csv
names the ROM and I/O addresses. Output: address,name,type,comment for MysteryHouse.java.
"""
import pathlib
import sys


def read(path, cols):
    rows = []
    for line in pathlib.Path(path).read_text().splitlines(True):
        if line.startswith(('#', 'address,', 'name,')) or not line.strip():
            continue
        rows.append(line.rstrip('\n').split(',', cols - 1))
    return rows


def main():
    asm, apple2, types, out = sys.argv[1:5]
    # types by name first (they follow a symbol that moves when the source changes), by address
    # for anything the source does not name
    by_name, by_addr = {}, {}
    for r in read(types, 4):
        entry = (r[2].strip() if len(r) > 2 else '', r[3].strip() if len(r) > 3 else '')
        by_name[r[1].strip()] = entry
        by_addr[int(r[0], 16)] = entry
    rows = {}
    for a, n, t, c in ((r + ['', ''])[:4] for r in read(apple2, 4)):
        rows[(int(a, 16), n.strip())] = (t.strip(), c.strip())
    for name, addr, kind, src, note in ((r + [''] * 5)[:5] for r in read(asm, 5)):
        if src in ('apple2.inc', 'game.inc'):
            continue
        a = int(addr, 16)
        t, c = by_name.get(name) or by_addr.get(a, ('', ''))
        if '.' in name:          # local branch label
            t, c = '', ''
        rows[(a, name)] = (t, note or c)
    with open(out, 'w') as f:
        f.write('address,name,type,comment\n')
        for (a, n), (t, c) in sorted(rows.items()):
            f.write('%04X,%s,%s,%s\n' % (a, n, t, c))


if __name__ == '__main__':
    main()

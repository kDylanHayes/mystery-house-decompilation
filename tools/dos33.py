#!/usr/bin/env python3
"""Extract every file from an Apple II DOS 3.3 disk image (.do / .dsk, DOS sector order).

usage: dos33.py <disk.do> <outdir>                       extract every file
       dos33.py put <disk.do> <out.do> NAME=file ...        replace files' contents
                (a binary file needs file.load holding its hex load address; a text file's
                data must end with $00; a BASIC file is the tokenized program)

Binary (B) files are written without their 4-byte load-address/length header; the header is
recorded in <outdir>/CATALOG.txt. Applesoft (A) files are written both raw (.bas.bin) and
listed (.bas, by tools/basic.py, which can also rebuild them). Text (T) files have their high bits stripped and CRs turned into newlines.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import basic  # noqa: E402

SECTOR = 256
TYPES = {0x00: 'T', 0x01: 'I', 0x02: 'A', 0x04: 'B', 0x08: 'S', 0x10: 'R', 0x20: 'a', 0x40: 'b'}


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
            kind = e[2] & 0x7F
            if load is None and kind in (0x01, 0x02):
                # Integer BASIC / Applesoft program: a length, then the program
                body = bytes([len(payload) & 0xFF, len(payload) >> 8]) + payload
            elif load is None:
                # text file: the raw data, ended by $00 (the payload includes it)
                if kind != 0x00:
                    raise SystemExit('%s is a binary file; give its load address' % name)
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
            lines, extra = (basic.list_applesoft if ftype == 'A' else basic.list_integer)(body)
            open(fn + '.bas', 'w').write('\n'.join(lines) + '\n')
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

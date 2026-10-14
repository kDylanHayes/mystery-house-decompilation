#!/usr/bin/env python3
"""Build the DOS 3.3 disk image from src/disk/ and the built files.

usage: mkdisk.py build <src/disk dir> <out.do> NAME=file ...
       mkdisk.py extract <disk.do> <out src/disk dir>     (used once to create src/disk/)

src/disk/ holds:
  layout.txt    the disk's structure: the VTOC settings, the catalog sectors, and each file in
                catalog order with its type and the sectors it occupies (its track/sector list
                sectors and its data sectors, in order)
  dos33.bin     tracks 0-2: Apple DOS 3.3 as it was on the disk (12 KB, not decompiled)
  residue.bin   optional: bytes no structure accounts for (stale data in free sectors and in
                the unused ends of sectors). The project no longer has one: without it the
                disk is clean, with zeros there (see src/disk/README.md). `extract` writes one
                from a disk, which reproduces that disk exactly.

The build starts from an empty disk, lays down the residue, DOS, the VTOC (with a bitmap
computed from the layout), the catalog and the track/sector lists, then writes each file's
contents with dos33.put (NAME=file arguments as for `dos33.py put`). A file that has grown gets
extra sectors from the free ones; a smaller one keeps its sectors, as DOS does.

residue.bin is a list of records: 3-byte image offset, 2-byte length, the bytes.
"""
import pathlib
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dos33  # noqa: E402

SECTOR = 256
TRACKS, SECTORS = 35, 16
TYPES = {'T': 0x00, 'I': 0x01, 'A': 0x02, 'B': 0x04}


def off(t, s):
    return (t * SECTORS + s) * SECTOR


def ts(text):
    t, s = text.split(',')
    return int(t), int(s)


def parse_layout(path):
    lay = {'files': []}
    for n, raw in enumerate(pathlib.Path(path).read_text().splitlines(True), 1):
        line = raw.split(';')[0].strip()
        if not line:
            continue
        word, _, rest = line.partition(' ')
        if word == 'volume':
            lay['volume'] = int(rest)
        elif word == 'vtoc':
            lay['vtoc'] = dict(kv.split('=') for kv in rest.split())
        elif word == 'catalog':
            lay['catalog'] = [ts(x) for x in rest.split()]
        elif word == 'file':
            m = re.match(r'"([^"]+)"\s+(\w)\s+(locked\s+)?tslist=(\S+)\s+data=(.*)$', rest)
            if not m:
                raise SystemExit('%s:%d: bad file line' % (path, n))
            lay['files'].append({
                'name': m.group(1), 'type': m.group(2), 'locked': bool(m.group(3)),
                'tslist': [ts(x) for x in m.group(4).split(';')],
                'data': [ts(x) for x in m.group(5).split()]})
        else:
            raise SystemExit('%s:%d: unknown "%s"' % (path, n, word))
    return lay


def skeleton(lay, dos, residue):
    img = bytearray(TRACKS * SECTORS * SECTOR)
    p = 0
    while p < len(residue):
        o = residue[p] | residue[p + 1] << 8 | residue[p + 2] << 16
        n = residue[p + 3] | residue[p + 4] << 8
        img[o:o + n] = residue[p + 5:p + 5 + n]
        p += 5 + n
    img[0:len(dos)] = dos
    v = lay['vtoc']
    vt = off(17, 0)
    cat = ts(v['catalog'])
    img[vt] = int(v.get('byte0', '0'))    # DOS 3.3's INIT writes $04 here; DOS never reads it
    img[vt + 1], img[vt + 2] = cat
    img[vt + 3] = int(v['version'])
    img[vt + 6] = lay['volume']
    img[vt + 0x27] = int(v['max_pairs'])
    img[vt + 0x30] = int(v['last_track'])
    img[vt + 0x31] = int(v['direction']) & 0xFF
    img[vt + 0x34] = TRACKS
    img[vt + 0x35] = SECTORS
    img[vt + 0x36], img[vt + 0x37] = SECTOR & 0xFF, SECTOR >> 8
    used = {(t, s) for t in range(3) for s in range(SECTORS)} | {(17, 0)} | set(lay['catalog'])
    for f in lay['files']:
        used |= set(f['tslist']) | set(f['data'])
    for t in range(TRACKS):
        for s in range(SECTORS):
            o = vt + 0x38 + 4 * t + (0 if s >= 8 else 1)
            bit = 1 << (s - 8 if s >= 8 else s)
            img[o] = img[o] & ~bit if (t, s) in used else img[o] | bit
    # catalog: 7 entries per sector, in order
    entries = list(lay['files'])
    for k, (t, s) in enumerate(lay['catalog']):
        o = off(t, s)
        nt, ns = lay['catalog'][k + 1] if k + 1 < len(lay['catalog']) else (0, 0)
        img[o + 1], img[o + 2] = nt, ns
        for i in range(7):
            if not entries:
                break
            f = entries.pop(0)
            e = o + 11 + 35 * i
            img[e], img[e + 1] = f['tslist'][0]
            img[e + 2] = TYPES[f['type']] | (0x80 if f['locked'] else 0)
            name = f['name'].ljust(30).encode('ascii')
            img[e + 3:e + 33] = bytes(c | 0x80 for c in name)
            count = len(f['tslist']) + len(f['data'])
            img[e + 33], img[e + 34] = count & 0xFF, count >> 8
    if entries:
        raise SystemExit('the catalog has room for %d files' % (7 * len(lay['catalog'])))
    # track/sector lists
    for f in lay['files']:
        for k, (t, s) in enumerate(f['tslist']):
            o = off(t, s)
            nt, ns = f['tslist'][k + 1] if k + 1 < len(f['tslist']) else (0, 0)
            img[o + 1], img[o + 2] = nt, ns
            img[o + 5], img[o + 6] = (k * 122) & 0xFF, (k * 122) >> 8
            for j, (dt, ds) in enumerate(f['data'][k * 122:(k + 1) * 122]):
                img[o + 12 + 2 * j], img[o + 13 + 2 * j] = dt, ds
    return img


def put_files(img, args):
    for arg in args:
        name, path = arg.split('=', 1)
        data = pathlib.Path(path).read_bytes()
        load = int(pathlib.Path(path + '.load').read_text(), 16) if os.path.exists(path + '.load') else None
        dos33.put(img, name, load, data)


def build(srcdir, out, args):
    lay = parse_layout(os.path.join(srcdir, 'layout.txt'))
    dos = pathlib.Path(os.path.join(srcdir, 'dos33.bin')).read_bytes()
    rp = os.path.join(srcdir, 'residue.bin')
    residue = pathlib.Path(rp).read_bytes() if os.path.exists(rp) else b''
    img = skeleton(lay, dos, residue)
    put_files(img, args)
    pathlib.Path(out).write_bytes(img)


def extract(disk_path, out):
    disk = pathlib.Path(disk_path).read_bytes()
    os.makedirs(out, exist_ok=True)
    pathlib.Path(os.path.join(out, 'dos33.bin')).write_bytes(disk[:off(3, 0)])
    vt = disk[off(17, 0):off(17, 1)]
    lines = ['; The disk\'s structure (see tools/mkdisk.py): DOS 3.3, 35 tracks x 16 sectors.',
             '; Files are listed in catalog order with the sectors they occupy.',
             'volume %d' % vt[6],
             'vtoc byte0=%d catalog=%d,%d version=%d max_pairs=%d last_track=%d direction=%d' % (
                 vt[0], vt[1], vt[2], vt[3], vt[0x27], vt[0x30], vt[0x31] if vt[0x31] < 128 else vt[0x31] - 256)]
    cat = []
    t, s = vt[1], vt[2]
    while t:
        cat.append((t, s))
        c = disk[off(t, s):off(t, s) + SECTOR]
        t, s = c[1], c[2]
    lines.append('catalog ' + ' '.join('%d,%d' % x for x in cat))
    files = []
    for name, ftype, locked, t, s, n in dos33.catalog(disk):
        lists, data = dos33.file_sectors(disk, t, s)
        lines.append('file "%s" %s %stslist=%s data=%s' % (
            name, ftype, 'locked ' if locked else '', ';'.join('%d,%d' % x for x in lists),
            ' '.join('%d,%d' % x for x in data)))
        files.append((name, ftype, t, s))
    pathlib.Path(os.path.join(out, 'layout.txt')).write_text('\n'.join(lines) + '\n')
    # rebuild without residue, putting each file's own contents back, then keep what differs
    lay = parse_layout(os.path.join(out, 'layout.txt'))
    img = skeleton(lay, disk[:off(3, 0)], b'')
    for name, ftype, t, s in files:
        raw = dos33.read_file(disk, t, s)
        if ftype == 'B':
            load, length = raw[0] | raw[1] << 8, raw[2] | raw[3] << 8
            dos33.put(img, name, load, raw[4:4 + length])
        elif ftype in 'AI':
            length = raw[0] | raw[1] << 8
            dos33.put(img, name, None, raw[2:2 + length])
        else:
            end = raw.index(0) + 1
            dos33.put(img, name, None, raw[:end])
    res = bytearray()
    i = 0
    while i < len(disk):
        if disk[i] == img[i]:
            i += 1
            continue
        j = i
        while j < len(disk) and j - i < 0xFFFF and (disk[j] != img[j] or
                                                    (j + 1 < len(disk) and disk[j + 1] != img[j + 1])):
            j += 1
        res += bytes((i & 0xFF, i >> 8 & 0xFF, i >> 16, (j - i) & 0xFF, (j - i) >> 8)) + disk[i:j]
        i = j
    pathlib.Path(os.path.join(out, 'residue.bin')).write_bytes(res)
    print('%d files; residue %d bytes' % (len(files), len(res)))


def main():
    if sys.argv[1] == 'build':
        build(sys.argv[2], sys.argv[3], sys.argv[4:])
    elif sys.argv[1] == 'extract':
        extract(sys.argv[2], sys.argv[3])
    else:
        raise SystemExit(__doc__)


if __name__ == '__main__':
    main()

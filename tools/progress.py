#!/usr/bin/env python3
"""Matching progress, as an objdiff report: how much of the built game is the same as the
original, routine by routine and table by table.

usage: progress.py report <build dir> <files dir> <expected dir> <FILES.sha256> <out report.json>
       progress.py map <build dir> <files dir> <FILES.sha256> <expected dir> [--quiet]

objdiff (github.com/encounter/objdiff) is what most decompilations use to track progress, and
decomp.dev and other dashboards read its reports. It cannot diff 6502 code, so this tool does
the comparison itself and writes the same report format (objdiff's report.proto, version 2, as
JSON with the proto field names; 64-bit counts as strings):

  units      one per file on the disk. The two programs (ADVENTURE, AUTO LOAD OBJ) list their
             functions (routines: top-level labels whose range holds instructions) and data
             (every other top-level label: tables, rules, text, leftover memory); the other 28
             files are data, compared as whole files against disk/FILES.sha256.
  matching   an item matches when it assembles to the original's bytes, line by line of the
             listing, except that an operand naming a label is compared by the label's name
             rather than by its address (what objdiff does with relocations). So code that only
             moves, because something before it grew, still matches; a changed instruction or
             byte does not. Items are found by name in the original and in the build.
             An item's fuzzy_match_percent is how alike the two line sequences are (difflib),
             100 for a match; a unit's and the report's are the functions' weighted by code
             size, 100 with no code, the arithmetic objdiff and ByteMatch use. A unit is
             complete when its whole file is the original's.
  categories "programs" (the two programs) and "files" (the rest).

<expected dir> (disk/expected/) holds the original programs, which are public domain and the
same bytes as a matching build (tests/test_progress.py checks them against FILES.sha256), with
the listing and symbol table of the source that matched them, which name the items and the
labels the operands refer to. "map" writes them from a build, and refuses unless every file of
that build matches FILES.sha256; build.sh refreshes the listings and symbol tables after every
matching build, so renames reach them (the programs themselves never change).

build.sh writes build/report.json and prints the summary; CI uploads it as the artifact
1987_report (ByteMatch and decomp.dev look for <version>_report; the version is the 1987
public-domain release).
"""
import csv
import difflib
import json
import os
import re
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import diskfiles  # noqa: E402

REPORT_VERSION = 2
INSTRUCTION = re.compile(r'([0-9A-F]{4})  (?:[0-9A-F]{2} ){1,3}\s*[A-Z]{3}\b')   # a listing line with an instruction
PROGRAMS = [  # disk name, built file, listing / symbol table prefix, load address
    ('ADVENTURE', 'ADVENTURE.bin', 'adventure', 0x0800),
    ('AUTO LOAD OBJ', 'AUTO_LOAD_OBJ.bin', 'autoload', 0x0FFD),
]


def items(build_dir, prefix, load):
    """The top-level items of an assembled program: [(name, address, size, kind)], each from its
    label to the next top-level label (or the end of the file); kind 'code' if the listing has
    an instruction in it, else 'data'."""
    with open(os.path.join(build_dir, prefix + '.syms.csv')) as f:
        labels = sorted((int(r['address'], 16), r['name']) for r in csv.DictReader(f)
                        if r['kind'] == 'label' and '__' not in r['name'])
    binary = [b for n, b, p, _ in PROGRAMS if p == prefix][0]
    end = load + os.path.getsize(os.path.join(build_dir, binary))
    code = set()
    with open(os.path.join(build_dir, prefix + '.lst')) as f:
        for line in f:
            m = INSTRUCTION.match(line)
            if m:
                code.add(int(m.group(1), 16))
    out = []
    for i, (a, name) in enumerate(labels):
        if not load <= a < end:
            continue
        nxt = next((b for b, _ in labels[i + 1:] if b > a), end)
        nxt = min(nxt, end)
        if nxt > a:
            out.append((name, a, nxt - a, 'code' if any(a <= x < nxt for x in code) else 'data'))
    # labels at the same address: keep the first of each
    seen, unique = set(), []
    for it in out:
        if it[1] not in seen:
            seen.add(it[1])
            unique.append(it)
    return unique


IDENT = re.compile(r'[A-Za-z_@][A-Za-z0-9_@.]*')


class Program:
    """One assembled program: its bytes, listing lines, labels and top-level items."""

    def __init__(self, folder, binary, prefix, load):
        with open(os.path.join(folder, binary), 'rb') as f:
            self.data = f.read()
        self.load = load
        with open(os.path.join(folder, prefix + '.syms.csv')) as f:
            self.labels = {r['name'] for r in csv.DictReader(f) if r['kind'] == 'label'}
        self.lines = []                       # (address, source text) of every listing line
        with open(os.path.join(folder, prefix + '.lst')) as f:
            for line in f:
                if re.match(r'[0-9A-F]{4}  ', line):
                    self.lines.append((int(line[:4], 16), line[20:].rstrip('\n').strip()))
        self.items = {name: (a, n, kind) for name, a, n, kind in items(folder, prefix, load)}

    def tokens(self, a, n):
        """The item at a (n bytes) line by line: a line's bytes, or, when its source names a
        label, its first byte (the opcode, for an instruction) and the source text."""
        end = a + n
        starts = [x for x, _ in self.lines if a <= x < end]
        out = []
        for x, text in self.lines:
            if not a <= x < end:
                continue
            nxt = next((y for y in starts if y > x), end)
            raw = self.data[x - self.load:nxt - self.load]
            names = [w for w in IDENT.findall(re.sub(r'"[^"]*"', '', text)) if w in self.labels]
            if names and INSTRUCTION.match('%04X  %s' % (x, raw[:1].hex(' ').upper() + ' ' + text)):
                out.append((raw[:1], ' '.join(text.split())))
            elif names:
                out.append((None, ' '.join(text.split())))
            else:
                out.append((raw, None))
        return out


def measures(entries, complete):
    """objdiff Measures from [(kind, size, matched, fuzzy)]."""
    code = [e for e in entries if e[0] == 'code']
    data = [e for e in entries if e[0] == 'data']
    total_code, total_data = sum(e[1] for e in code), sum(e[1] for e in data)
    matched_code = sum(e[1] for e in code if e[2])
    matched_data = sum(e[1] for e in data if e[2])
    # as objdiff (and ByteMatch, decomp.dev) count it: the functions' match, weighted by their
    # size; 100 when there is no code
    fuzzy = sum(e[1] * e[3] for e in code) / total_code if total_code else 100.0
    pct = lambda a, b: 100.0 * a / b if b else 100.0
    return {
        'fuzzy_match_percent': round(fuzzy, 4),
        'total_code': str(total_code), 'matched_code': str(matched_code),
        'matched_code_percent': round(pct(matched_code, total_code), 4),
        'total_data': str(total_data), 'matched_data': str(matched_data),
        'matched_data_percent': round(pct(matched_data, total_data), 4),
        'total_functions': len(code), 'matched_functions': sum(1 for e in code if e[2]),
        'matched_functions_percent': round(pct(sum(1 for e in code if e[2]), len(code)), 4),
        'complete_code': str(total_code if complete else 0),
        'complete_code_percent': 100.0 if complete and total_code else 0.0,
        'complete_data': str(total_data if complete else 0),
        'complete_data_percent': 100.0 if complete and total_data else 0.0,
        'total_units': 1, 'complete_units': 1 if complete else 0,
    }


def add(total, m):
    """Sum unit measures into report or category measures (percentages recomputed by finish)."""
    for k in ('total_code', 'matched_code', 'total_data', 'matched_data', 'complete_code', 'complete_data'):
        total[k] = str(int(total.get(k, '0')) + int(m[k]))
    for k in ('total_functions', 'matched_functions', 'total_units', 'complete_units'):
        total[k] = total.get(k, 0) + m[k]
    size = int(m['total_code'])            # fuzzy is weighted by code, as objdiff sums it
    total['_fuzzy'] = total.get('_fuzzy', 0.0) + m['fuzzy_match_percent'] * size
    total['_size'] = total.get('_size', 0) + size


def finish(total):
    pct = lambda a, b: round(100.0 * a / b, 4) if b else 100.0
    size = total.pop('_size', 0)
    total['fuzzy_match_percent'] = round(total.pop('_fuzzy', 0.0) / size, 4) if size else 100.0
    total['matched_code_percent'] = pct(int(total['matched_code']), int(total['total_code']))
    total['matched_data_percent'] = pct(int(total['matched_data']), int(total['total_data']))
    total['matched_functions_percent'] = pct(total['matched_functions'], total['total_functions'])
    total['complete_code_percent'] = pct(int(total['complete_code']), int(total['total_code']))
    total['complete_data_percent'] = pct(int(total['complete_data']), int(total['total_data']))
    return total


def file_matches(files_dir, sums):
    """disk name -> (size, matches FILES.sha256) for every file of the disk."""
    import hashlib
    want = {}
    with open(sums) as f:
        for line in f:
            h, name = line.rstrip('\n').split('  ', 1)
            want[name] = h
    out = {}
    for disk_name, _, _, name in diskfiles.FILES:
        data = diskfiles.content(os.path.join(files_dir, name), name)
        out[disk_name] = (len(data), hashlib.sha256(data).hexdigest() == want.get(disk_name))
    return out


def report(build_dir, files_dir, expected_dir, sums):
    files = file_matches(files_dir, sums)
    units, totals, cats = [], {}, {'programs': {}, 'files': {}}
    for disk_name, binary, prefix, load in PROGRAMS:
        want = Program(expected_dir, binary, prefix, load)
        got = Program(build_dir, binary, prefix, load)
        identical = want.data == got.data
        entries, functions, data = [], [], []
        for name, (a, n, kind) in sorted(want.items.items(), key=lambda kv: kv[1][0]):
            if identical:
                same, fuzzy = True, 100.0
            elif name in got.items:
                old, new = want.tokens(a, n), got.tokens(got.items[name][0], got.items[name][1])
                same = old == new
                fuzzy = 100.0 if same else 100.0 * difflib.SequenceMatcher(None, old, new, autojunk=False).ratio()
            else:
                same, fuzzy = False, 0.0
            entries.append((kind, n, same, fuzzy))
            item = {'name': name, 'size': str(n), 'fuzzy_match_percent': round(fuzzy, 4),
                    'address': str(a - load), 'metadata': {'virtual_address': str(a)}}
            (functions if kind == 'code' else data).append(item)
        complete = files[disk_name][1]
        m = measures(entries, complete)
        code = [e for e in entries if e[0] == 'code']
        units.append({
            'name': disk_name, 'measures': m,
            'sections': [{'name': '.text', 'size': m['total_code'],
                          'fuzzy_match_percent': section_fuzzy(code)},
                         {'name': '.data', 'size': m['total_data'],
                          'fuzzy_match_percent': section_fuzzy([e for e in entries if e[0] == 'data'])}],
            'functions': functions,
            'metadata': {'complete': complete, 'source_path': 'src/%s.s' % prefix,
                         'progress_categories': ['programs']},
        })
        add(totals, m)
        add(cats['programs'], m)
    names = [p[0] for p in PROGRAMS]
    for disk_name, (size, same) in files.items():
        if disk_name in names:
            continue
        m = measures([('data', size, same, 100.0 if same else 0.0)], same)
        units.append({'name': disk_name, 'measures': m,
                      'sections': [{'name': '.data', 'size': str(size),
                                    'fuzzy_match_percent': 100.0 if same else 0.0}],
                      'functions': [],
                      'metadata': {'complete': same, 'progress_categories': ['files']}})
        add(totals, m)
        add(cats['files'], m)
    return {
        'measures': finish(totals),
        'units': units,
        'version': REPORT_VERSION,
        'categories': [{'id': 'programs', 'name': 'Programs (ADVENTURE, AUTO LOAD OBJ)', 'measures': finish(cats['programs'])},
                       {'id': 'files', 'name': 'Data files', 'measures': finish(cats['files'])}],
    }


def section_fuzzy(entries):
    size = sum(e[1] for e in entries)
    return round(sum(e[1] * e[3] for e in entries) / size, 4) if size else 100.0


def summary(r):
    m = r['measures']
    return ('progress: %d/%d functions, %s/%s code bytes, %s/%s data bytes match the original '
            '(fuzzy %.2f%%); %d/%d files complete' % (
                m['matched_functions'], m['total_functions'], m['matched_code'], m['total_code'],
                m['matched_data'], m['total_data'], m['fuzzy_match_percent'],
                m['complete_units'], m['total_units']))


def write_map(build_dir, files_dir, sums, expected_dir, quiet=False):
    files = file_matches(files_dir, sums)
    if not all(same for _, same in files.values()):
        sys.exit('map: the build does not match FILES.sha256; maps must come from a matching build')
    os.makedirs(expected_dir, exist_ok=True)
    for _, binary, prefix, _ in PROGRAMS:
        for name in (binary, prefix + '.lst', prefix + '.syms.csv'):
            shutil.copyfile(os.path.join(build_dir, name), os.path.join(expected_dir, name))
    if not quiet:
        print('expected programs, listings and symbol tables written to %s' % expected_dir)


def main():
    if len(sys.argv) == 7 and sys.argv[1] == 'report':
        r = report(*sys.argv[2:6])
        with open(sys.argv[6], 'w') as f:
            json.dump(r, f, indent=1)
        print(summary(r))
    elif len(sys.argv) in (6, 7) and sys.argv[1] == 'map':
        write_map(*sys.argv[2:6], quiet=sys.argv[6:] == ['--quiet'])
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Generate assembler source for a Mystery House binary. Used once to create the first version
of src/adventure.s and src/autoload.s; after that src/ is the source of truth and is edited by
hand. Kept to show how the source was made: it does not know about the later hand edits (names,
comments, the decoded dead code) or the generated message and picture tables, so running it
again would not reproduce the current source.

usage: gen_source.py <program> <bin> <plan.json> <symbols.csv> <out.s> <data dir>
       program: adventure | autoload

Code comes from the trace plan (tools/trace6502.py), names from the symbols CSV, and the game's
tables are written out structurally (rules with named opcodes, lengths computed from labels).
Leftover memory with no meaning (stale buffers, fill, screen images) becomes .incbin files in
<data dir>. The output reassembles byte-for-byte; build.sh checks that.
"""
import pathlib
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gamedata as gd  # noqa: E402
from trace6502 import OPS, SIZE  # noqa: E402


def ident(word):
    s = ''.join(c if c.isalnum() else '_' for c in word.upper()).strip('_')
    return s or 'NONE'


class Gen:
    def __init__(self, prog, data, plan, symfile):
        self.prog = prog
        self.d = data
        self.base = plan['load']
        self.end = self.base + len(data)
        self.plan = plan
        self.items = {}      # address -> (kind, length, payload)
        self.syms = {}       # address -> name
        self.comments = {}   # address -> comment
        self.types = {}
        for line in pathlib.Path(symfile).read_text().splitlines(True):
            if line.startswith(('#', 'address,')) or not line.strip():
                continue
            f = line.rstrip('\n').split(',', 3)
            a = int(f[0], 16)
            self.syms[a] = f[1].strip()
            self.types[a] = f[2].strip() if len(f) > 2 else ''
            if len(f) > 3 and f[3].strip():
                self.comments[a] = f[3].strip()
        self.funcs = set(plan['functions'])
        self.code = dict((a, n) for a, n in plan['code'])
        self.inline = {c['call']: c for c in plan['inline']}
        self.tables = {t['addr']: t for t in plan['jump_tables']}
        self.lines = []
        self.labels = {}     # address -> label emitted in the source
        self.consts = {}     # name -> value, emitted as constants
        self.targets = set()

    def b(self, a):
        return self.d[a - self.base]

    def w(self, a):
        return self.b(a) | self.b(a + 1) << 8

    # ---- naming ----------------------------------------------------------------------
    def sym(self, v, zp_ok=False):
        """Expression for value v as an address operand."""
        if v in self.labels:
            return self.labels[v]
        for name, val in self.const_by_value.get(v, []):
            return name
        if v - 1 in self.labels and self.base <= v - 1 and (v - 1) not in self.funcs:
            return self.labels[v - 1] + '+1'
        for name, val in self.const_by_value.get(v - 1, []):
            return name + '+1'
        if self.base <= v < self.end:
            near = max((a for a in self.labels if a <= v), default=None)
            if near is not None and v - near < 0x100:
                return '%s+%d' % (self.labels[near], v - near)
        return '$%02X' % v if v < 0x100 else '$%04X' % v

    # ---- layout --------------------------------------------------------------------------
    def plan_items(self, structured):
        """structured: list of (start, end, kind, arg)."""
        for a, n in self.code.items():
            self.items[a] = ('ins', n, None)
        for c in self.inline.values():
            for arg in c['args']:
                self.items[arg['addr']] = ('arg', arg['len'], arg['kind'])
        for a, t in self.tables.items():
            for i in range(t['count']):
                self.items[a + 2 * i] = ('tword', 2, None)
        for s, e, kind, arg in structured:
            for a in range(s, e):
                if a in self.items:
                    raise SystemExit('structured region %s overlaps code at $%04X' % (kind, a))
            self.items[s] = ('struct', e - s, (kind, arg))
        # branch/jump/call targets get labels
        for a in self.code:
            m, mode = OPS[self.b(a)]
            if mode == 'rel':
                r = self.b(a + 1)
                self.targets.add((a + 2 + (r - 256 if r > 127 else r)) & 0xFFFF)
            elif m in ('JMP', 'JSR') and mode == 'abs':
                self.targets.add(self.w(a + 1))
        for c in self.inline.values():
            for arg in c['args']:
                if arg['kind'] == 'w':
                    self.targets.add(self.w(arg['addr']))
        for t in self.tables.values():
            self.targets.update(x for x in t['targets'] if x)

    def boundaries(self):
        """Addresses where a label can go: item starts and every byte of plain data."""
        owned = {}
        for a, (k, n, p) in self.items.items():
            for i in range(n):
                owned[a + i] = a
        self.owner = owned
        ok = set(a for a in range(self.base, self.end) if a not in owned or owned[a] == a)
        return ok

    def decide_names(self, extra_labels):
        ok = self.boundaries()
        for a, name in list(self.syms.items()) + list(extra_labels.items()):
            if self.base <= a < self.end and a in ok:
                self.labels[a] = name
            else:
                self.consts[name] = a
        for a in self.funcs:
            if self.base <= a < self.end and a not in self.labels and a in ok:
                self.labels[a] = 'sub_%04X' % a
        for a in self.targets:
            if self.base <= a < self.end and a not in self.labels:
                if a in ok and a in self.code:
                    self.labels[a] = 'L%04X' % a
        self.const_by_value = {}
        for n, v in self.consts.items():
            self.const_by_value.setdefault(v, []).append((n, v))

    # ---- emitters --------------------------------------------------------------------
    def emit(self, s=''):
        self.lines.append(s)

    def text_chunks(self, a, n):
        """.hiasc / .byte lines for n bytes of high-bit text, split at labels."""
        out = []
        cur, start = '', a
        def flush():
            nonlocal cur
            if cur:
                out.append((start, '.hiasc "%s"' % cur))
                cur = ''
        for i in range(n):
            x = a + i
            if x in self.labels and i:
                flush()
                out.append((x, None))
            if not cur:
                start = x
            c = self.b(x)
            lo = c & 0x7F
            if c & 0x80 and 0x20 <= lo < 0x7F and lo not in (0x22, 0x5C):
                cur += chr(lo)
            elif c & 0x80 and lo == 0x0D:
                cur += '\\r'
            elif c & 0x80 and lo < 0x20:
                cur += '\\x%02X' % lo
            else:
                flush()
                out.append((x, '.byte $%02X' % c))
                start = x + 1
        flush()
        return out

    def label_line(self, a):
        if a in self.labels:
            if a in self.comments and (a in self.funcs or self.types.get(a, '').startswith('func')):
                self.emit()
                for chunk in wrap(self.comments[a]):
                    self.emit('; ' + chunk)
            elif a in self.funcs:
                self.emit()
            self.emit('%s:' % self.labels[a])

    def instr(self, a):
        op = self.b(a)
        m, mode = OPS[op]
        n = SIZE[mode]
        if mode in ('imp',):
            return '        %s' % m
        if mode == 'acc':
            return '        %s A' % m
        if mode == 'imm':
            return '        %s #$%02X' % (m, self.b(a + 1))
        if mode == 'rel':
            r = self.b(a + 1)
            t = (a + 2 + (r - 256 if r > 127 else r)) & 0xFFFF
            return '        %s %s' % (m, self.labels.get(t, '$%04X' % t))
        v = self.b(a + 1) if n == 2 else self.w(a + 1)
        s = self.sym(v)
        if n == 3 and v < 0x100 and mode != 'ind':
            s = 'a:' + s
        fmt = {'zp': '%s', 'zpx': '%s,X', 'zpy': '%s,Y', 'izx': '(%s,X)', 'izy': '(%s),Y',
               'abs': '%s', 'abx': '%s,X', 'aby': '%s,Y', 'ind': '(%s)'}[mode]
        return '        %s %s' % (m, fmt % s)

    def data_bytes(self, a, n):
        """Plain bytes, 16 per line, split at labels; long label-free runs become .incbin."""
        i = 0
        while i < n:
            x = a + i
            if self.after_blob:
                self.emit('        .org $%04X' % x)
                self.after_blob = False
            self.label_line(x)
            j = i + 1
            size = type_size(self.types.get(x, '')) if x in self.labels else None
            if size:
                # a declared variable: just its own bytes, the rest is a separate run
                j = min(n, i + size)
                j = next((k for k in range(i + 1, j) if (a + k) in self.labels), j)
            else:
                while j < n and (a + j) not in self.labels:
                    j += 1
            run = j - i
            blob_ok = x not in self.labels or self.labels[x] in BLOB_LABELS
            if run >= 128 and self.datadir and blob_ok:
                blob = self.d[x - self.base:x - self.base + run]
                name = '%s.bin' % self.labels[x] if x in self.labels else '%s_%04X.bin' % (self.prog, x)
                pathlib.Path(os.path.join(self.datadir, name)).write_bytes(blob)
                if x in self.labels:
                    what = ''
                elif all(c == 0 for c in blob) or all(blob[k] == blob[k % 4] for k in range(len(blob))):
                    what = 'fill'
                else:
                    what = 'leftover memory, not used by the code (see NOTES.md)'
                self.emit('        .incbin "data/%s"    ; $%04X-$%04X %s' % (name, x, x + run - 1, what))
                self.after_blob = True
            else:
                if x not in self.labels and run >= 16:
                    self.emit('; leftover memory, not used: lines here can be deleted to make room')
                for k in range(i, j, 16):
                    e = min(j, k + 16)
                    self.emit('        .byte ' + ','.join('$%02X' % self.b(a + q) for q in range(k, e)))
            i = j

    def generate(self, structured, header, datadir):
        self.datadir = datadir
        self.after_blob = False
        for line in header:
            self.emit(line)
        self.emit()
        self.emit('; ---- addresses outside the image or inside other items ----')
        for name, v in sorted(self.consts.items(), key=lambda x: x[1]):
            com = self.comments.get(v, '')
            self.emit('%-24s = $%04X%s' % (name, v, ('    ; ' + com) if com and len(com) < 70 else ''))
        self.emit()
        self.emit('        .org $%04X' % self.base)
        a = self.base
        pending = []
        while a < self.end:
            it = self.items.get(a)
            if it is None:
                # plain data up to the next item
                e = a
                while e < self.end and e not in self.items:
                    e += 1
                self.data_bytes(a, e - a)
                a = e
                continue
            kind, n, p = it
            if kind == 'struct' or self.after_blob:
                # pinned: the engine refers to these addresses as immediate bytes, and an edit that
                # grows the code or data in front must fail loudly instead of moving them
                self.emit('        .org $%04X' % a)
                self.after_blob = False
            self.label_line(a)
            if kind == 'ins':
                self.emit(self.instr(a))
            elif kind == 'arg':
                if p == 'w':
                    self.emit('        .word %s' % self.sym(self.w(a)))
                elif p == 'b':
                    self.emit('        .byte $%02X' % self.b(a))
                else:
                    for x, txt in self.text_chunks(a, n):
                        if txt is None:
                            self.emit('%s:' % self.labels[x])
                        else:
                            self.emit('        ' + txt)
            elif kind == 'tword':
                v = self.w(a)
                self.emit('        .word %s' % (self.sym(v) if v else '0'))
            elif kind == 'struct':
                getattr(self, 'struct_' + p[0])(a, n, p[1])
            a += n
        return '\n'.join(self.lines) + '\n'

    # ---- Mystery House tables ---------------------------------------------------------
    def setup_game(self):
        g = gd.Game.__new__(gd.Game)
        g.d = self.d
        self.g = g
        self.verbs = g.words(gd.VERBS)
        self.nouns = g.words(gd.NOUNS)
        self.vname = names([v[0] for v in self.verbs], 'V_', {39: 'V_PROFANITY'})
        self.nname = names([n[0] for n in self.nouns], 'N_', {})

    def struct_words(self, a, n, which):
        groups = self.verbs if which == 'verbs' else self.nouns
        nm = self.vname if which == 'verbs' else self.nname
        x = a
        for i, ws in enumerate(groups, 1):
            self.emit('        .hiasc "%-8s"            ; %s = %d' % (ws[0], nm[i], i))
            if self.b(x + 8) == 0xFF:
                x += 8
                break
            self.emit('        .byte %d' % (len(ws) - 1))
            for s in ws[1:]:
                self.emit('        .hiasc "%-8s"' % s)
            x += 9 + 8 * (len(ws) - 1)
        self.emit('        .byte $FF')
        assert x + 1 == a + n, (hex(x), hex(a + n))

    def room(self, r):
        return {gd.CARRYING: 'CARRIED', gd.NOWHERE: 'NOWHERE'}.get(r, str(r))

    def struct_objects(self, a, n, _):
        x = a
        self.emit('; id  noun  room  pic  shape  x  y  status  msg  length  npics  pics...')
        while self.b(x) != 0xFF:
            ln = self.b(x + 9)
            rec = [self.b(x + k) for k in range(ln)]
            lab = 'obj_%02d' % rec[0]
            nxt = 'obj_%02d' % (rec[0] + 1) if self.b(x + ln) != 0xFF else 'obj_end'
            self.emit('%s: .byte %d, %s, %s, %d, %d, %d, %d, %s, %d, %s-%s, %d%s' % (
                lab, rec[0], self.nname[rec[1]], self.room(rec[2]), rec[3], rec[4], rec[5], rec[6],
                ['OMOVABLE', 'OMOVED', 'OFIXED'][rec[7]], rec[8], nxt, lab, rec[10],
                ''.join(', %d' % p for p in rec[11:])))
            x += ln
        self.emit('obj_end: .byte $FF')
        assert x + 1 == a + n

    def struct_rooms(self, a, n, _):
        self.emit(';      no  msg  N  S  E  W  U  D  base cur')
        msgs = self.msgs
        for r in range((n) // 10):
            rec = [self.b(a + 10 * r + k) for k in range(10)]
            desc = gd.short(msgs.get(rec[1], ''), 50) if r else 'unused'
            self.emit('        .byte %s   ; %d %s' % (', '.join('%d' % v for v in rec), r, desc))

    def struct_rules(self, a, n, which):
        g = self.g
        rules = g.rules(a)
        nm = self.namer
        for i, r in enumerate(rules):
            lab = 'rule_%04X' % r['addr']
            nxt = 'rule_%04X' % rules[i + 1]['addr'] if i + 1 < len(rules) else '%s_end' % which
            head = []
            if r['room'] != gd.ANY:
                head.append(nm.room(r['room']))
            if r['verb'] != gd.ANY:
                head.append(nm.verb(r['verb']))
            if r['noun'] != gd.ANY:
                head.append(nm.noun(r['noun']))
            self.emit()
            self.emit('; %s' % (', '.join(head) if head else 'always'))
            self.emit('%s:' % lab)
            self.emit('        .byte %s, %s, %s, %s-%s, %d, %d' % (
                'ANY' if r['room'] == gd.ANY else r['room'],
                'ANY' if r['verb'] == gd.ANY else self.vname[r['verb']],
                'ANY' if r['noun'] == gd.ANY else self.nname[r['noun']],
                nxt, lab, len(r['conditions']), len(r['actions'])))
            for op, args in r['conditions']:
                self.emit('        .byte C_%s%s     ; if %s' % (gd.CONDITIONS[op][0], ''.join(
                    ', %d' % v for v in args), gd.CONDITIONS[op][2](args, nm)))
            for op, args in r['actions']:
                self.emit('        .byte A_%s%s     ; %s' % (gd.ACTIONS[op][0], ''.join(
                    ', %d' % v for v in args), gd.ACTIONS[op][2](args, nm)))
        self.emit('%s_end:' % which)
        self.emit('        .byte $FF')

    def struct_picdir(self, a, n, _):
        self.emit('; block, offset within the block (entry 0 is unused)')
        for i in range(n // 3):
            x = a + 3 * i
            off = self.w(x + 1)
            self.emit('        .byte $%02X, <$%04X, >$%04X   ; picture %d' % (self.b(x), off, off, i))

    def struct_msgindex(self, a, n, _):
        for i in range(n // 2):
            t = self.msgs.get(i, '(unused)') if i else '(unused)'
            self.emit('        .word $%04X   ; %d %s' % (self.w(a + 2 * i), i, t[:60]))

    def struct_shapes(self, a, n, _):
        cnt = self.b(a)
        self.emit('        .byte %d, %d' % (cnt, self.b(a + 1)))
        for i in range((n - 2) // 2):
            off = self.w(a + 2 + 2 * i)
            self.emit('        .word shape_%d-shape_table' % (i + 1))
            self.extra[a + off] = 'shape_%d' % (i + 1)


# labelled regions that are opaque images rather than data to read
BLOB_LABELS = {'title_1980', 'title_1987', 'stale_hglin_copy'}


def type_size(t):
    base, n = t, 1
    if '[' in t:
        base, n = t[:t.index('[')], int(t[t.index('[') + 1:-1])
    return {'byte': 1, 'word': 2, 'ptr': 2}.get(base, 0) * n or None


def names(heads, prefix, special):
    out, seen = {}, {}
    for i, h in enumerate(heads, 1):
        n = special.get(i) or prefix + ident({'?': 'QMARK'}.get(h, h))
        if n in seen:
            seen[n] += 1
            n = '%s_%d' % (n, seen[n])
        else:
            seen[n] = 1
        out[i] = n
    return out


def wrap(s, n=96):
    words, out, cur = s.split(), [], ''
    for w in words:
        if len(cur) + len(w) + 1 > n:
            out.append(cur)
            cur = w
        else:
            cur = (cur + ' ' + w).strip()
    if cur:
        out.append(cur)
    return out


def main():
    prog, binf, planf, symf, out, datadir = sys.argv[1:7]
    data = pathlib.Path(binf).read_bytes()
    plan = json.loads(pathlib.Path(planf).read_text())
    os.makedirs(datadir, exist_ok=True)
    gen = Gen(prog, data, plan, symf)
    gen.extra = {}
    header = [
        '; %s - generated by tools/gen_source.py from the original binary, then maintained by hand.' % plan['name'],
        '; Assemble with tools/asm6502.py; build.sh checks the result against the original.',
    ]
    structured = []
    if prog == 'adventure':
        gen.setup_game()
        g = gen.g
        ext = os.path.dirname(binf)
        g.msgfile = pathlib.Path(os.path.join(ext, 'MESSAGES.txt.bin')).read_bytes()
        gen.msgs = g.messages()
        gen.namer = gd.Namer(gen.verbs, gen.nouns, g.rooms(), g.objects(), gen.msgs)
        def table_end(s):
            x = s
            while gen.b(x) != 0xFF:
                x += gen.b(x + 3)
            return x + 1
        def words_end(s):
            x = s
            while True:
                x += 8
                c = gen.b(x)
                if c == 0xFF:
                    return x + 1
                x += 1 + 8 * c
                if gen.b(x) == 0xFF:
                    return x + 1
        obj_end = gd.OBJBASE
        while gen.b(obj_end) != 0xFF:
            obj_end += gen.b(obj_end + 9)
        nrooms = len(g.rooms()) + 1
        structured = [
            (gd.OBJBASE, obj_end + 1, 'objects', None),
            (gd.ROOMBASE, gd.ROOMBASE + 10 * nrooms, 'rooms', None),
            (gd.NOUNS, words_end(gd.NOUNS), 'words', 'nouns'),
            (gd.VERBS, words_end(gd.VERBS), 'words', 'verbs'),
            (gd.TURN_RULES, table_end(gd.TURN_RULES), 'rules', 'turn_rules'),
            (gd.CMD_RULES, table_end(gd.CMD_RULES), 'rules', 'command_rules'),
            (gd.PICDIR, gd.PICDIR + 3 * (len(g.picture_directory()) + 1), 'picdir', None),
            (gd.MSGINDEX, gd.MSGINDEX + 0x150, 'msgindex', None),
            (gd.SHAPES, gd.SHAPES + 2 + 2 * 7, 'shapes', None),
        ]
        # shape labels are needed before names are decided
        for i in range(7):
            gen.extra[gd.SHAPES + gen.w(gd.SHAPES + 2 + 2 * i)] = 'shape_%d' % (i + 1)
        header += ['', '        .include "apple2.inc"', '        .include "game.inc"']
        write_game_inc(gen, os.path.join(os.path.dirname(out), 'game.inc'))
    else:
        header += ['', '        .include "apple2.inc"']
    gen.plan_items(structured)
    gen.decide_names(gen.extra)
    # constants already provided by the include files
    for n in INC_NAMES:
        gen.consts.pop(n, None)
    gen.const_by_value = {}
    for n, v in list(gen.consts.items()) + [(k, v) for k, v in INC_VALUES.items()]:
        gen.const_by_value.setdefault(v, []).append((n, v))
    text = gen.generate(structured, header, datadir)
    pathlib.Path(out).write_text(text)
    print('%s: %d lines' % (out, text.count('\n')))


INC_NAMES = set()
INC_VALUES = {}


def load_inc(path, values=True):
    for line in pathlib.Path(path).read_text().splitlines(True):
        line = line.split(';')[0]
        if '=' in line:
            n, v = line.split('=')
            INC_NAMES.add(n.strip())
            if values:
                v = v.strip()
                INC_VALUES[n.strip()] = int(v[1:], 16) if v.startswith('$') else int(v)


def write_game_inc(gen, path):
    L = ['; Constants for the game database: vocabulary, rule opcodes, object states.', '']
    L.append('ANY      = $FE    ; rule header: matches any room / verb / noun')
    L.append('CARRIED  = $FE    ; object room: in the inventory')
    L.append('NOWHERE  = $FD    ; object room: not in the game yet / gone')
    L.append('OMOVABLE = 0      ; object status (names from the original source)')
    L.append('OMOVED   = 1')
    L.append('OFIXED   = 2')
    L.append('')
    L.append('; conditions (tbl_conditions)')
    for op, (n, k, _) in sorted(gd.CONDITIONS.items()):
        L.append('C_%-16s = %d    ; %d operand(s)' % (n, op, k))
    L.append('')
    L.append('; actions (tbl_actions; handler ACnn00 with nn = op + 10)')
    for op, (n, k, _) in sorted(gd.ACTIONS.items()):
        L.append('A_%-16s = %d    ; %d operand(s)' % (n, op, k))
    L.append('')
    L.append('; verbs (verb_table)')
    for i, ws in enumerate(gen.verbs, 1):
        L.append('%-16s = %d    ; %s' % (gen.vname[i], i, ', '.join(ws)))
    L.append('')
    L.append('; nouns (noun_table)')
    for i, ws in enumerate(gen.nouns, 1):
        L.append('%-16s = %d    ; %s' % (gen.nname[i], i, ', '.join(w or '(blank)' for w in ws)))
    pathlib.Path(path).write_text('\n'.join(L) + '\n')
    load_inc(path, values=False)


if __name__ == '__main__':
    inc = os.path.join(os.path.dirname(sys.argv[5]), 'apple2.inc')
    if os.path.exists(inc):
        load_inc(inc)
    main()

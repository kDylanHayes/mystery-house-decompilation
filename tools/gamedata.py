#!/usr/bin/env python3
"""Decode Mystery House's game database from the ADVENTURE image into readable text and JSON.

usage: gamedata.py <extracted dir> <out dir> [adventure.syms.csv]

Everything the engine needs at run time is inside the ADVENTURE file ($0800-$7CFF); this tool
reads the tables at their run-time addresses (see NOTES.md for the layouts) plus the MESSAGES
text file. With the assembler's symbol table it finds the tables by name (the source lets them
move); without it, it uses the original addresses. It writes:
  messages.txt      every message by number, as the game prints it
  vocabulary.txt    verb and noun groups with their numbers and synonyms
  rooms.txt         room descriptions, exits and pictures
  objects.txt       object table with locations, pictures and states
  rules.txt         the turn and command rule scripts, decompiled to pseudocode
  map.txt, map.dot  every room's exits and the passages rules make (map.dot is Graphviz)
  gamedata.json     all of the above in machine-readable form, plus what a port needs: each
                    picture's strokes, each shape's vectors, the floor slots, the state a new
                    game starts in, the disk's saved game, the loader's menu and
                    instruction pages, and the two title pictures as 280 x 192 bitmaps
                    (PORTING.md describes every field)
"""
import pathlib
import json
import os
import re
import sys

LOAD = 0x0800

# Run-time addresses of the tables in the original (names follow the original source where it
# survives); use_symbols() replaces them with the addresses of a build.
VERBS = 0x4000        # verb groups
NOUNS = 0x1700        # noun groups
OBJBASE = 0x0900      # object records, linked by ONEXT, ended by $FF
ROOMBASE = 0x0D00     # room records, RTBLSIZ = 10 bytes, indexed by room number
SWITCH = 0x083A       # game flags (SWITCH,Y)
TURN_RULES = 0x4400   # rules run after every command
CMD_RULES = 0x4500    # rules matched against the command; first that runs wins
PICDIR = 0x5300       # picture directory: (block, offset) triples, picture numbers from 1
MSGINDEX = 0x5500     # message index: byte offsets into MESSAGES, numbers from 1
SHAPES = 0x5700       # Applesoft shape table used for small objects
FLOOR_SLOTS = 0x70FF  # (x, y) positions for dropped objects, in order of drawing
INIT_SWITCHES = 0x61FF  # the 20 switches as init_game sets them for a new game
CURONO = 0x0852       # the game's state that a save file holds, besides the two tables
TURNS = 0x0853
LAMPSTAT = 0x089D
VERB = 0x0834
NOUN = 0x0835
SHOWN_PICTURE = 0x0839  # the picture on screen, which VIEW_IS tests
SAVE_START = 0x0830   # SAVE GAME writes $0830-$10FE

# AUTO LOAD OBJ, the 1987 loader: where it loads and starts, its print routine, and the Monitor
# routines it calls between pages
LOADER = 0x0FFD
LOADER_PRINT = 0x1C15
HOME, GETLN1 = 0xFC58, 0xFD6F

ROOM_FIELDS = ['RROOMNO', 'RMSG', 'RN', 'RS', 'RE', 'RW', 'RU', 'RD', 'RBASEPIC', 'RCURPIC']
DIRS = ['north', 'south', 'east', 'west', 'up', 'down']
OSTATUS = {0: 'OMOVABLE', 1: 'OMOVED', 2: 'OFIXED'}
CARRYING = 0xFE
NOWHERE = 0xFD
ANY = 0xFE            # wildcard in rule headers

# messages built into the code (SUB_7400) rather than read from MESSAGES
BUILTIN_MESSAGES = {
    0x07: 'IT IS GETTING DARK',
    0x25: 'I DONT UNDERSTAND WHAT YOU MEAN',
    0x7F: 'IM NOT CARRYING THAT',
    0x89: 'I CANT GO IN THAT DIRECTION',
}

# symbol in src/adventure.s -> the variable here holding its address
TABLE_SYMBOLS = {'verb_table': 'VERBS', 'noun_table': 'NOUNS', 'OBJBASE': 'OBJBASE',
                 'ROOMBASE': 'ROOMBASE', 'SWITCH': 'SWITCH', 'turn_rules': 'TURN_RULES',
                 'command_rules': 'CMD_RULES', 'picture_directory': 'PICDIR',
                 'message_index': 'MSGINDEX', 'shape_table': 'SHAPES', 'floor_slots': 'FLOOR_SLOTS',
                 'init_switches': 'INIT_SWITCHES', 'CURONO': 'CURONO', 'turns': 'TURNS',
                 'LAMPSTAT': 'LAMPSTAT', 'verb': 'VERB', 'noun': 'NOUN',
                 'shown_picture': 'SHOWN_PICTURE'}


def use_symbols(path):
    """Take the tables' addresses from the assembler's symbol table (name,address,...)."""
    found = {}
    for line in pathlib.Path(path).read_text().splitlines()[1:]:
        name, addr = line.split(',')[:2]
        if name in TABLE_SYMBOLS:
            found[TABLE_SYMBOLS[name]] = int(addr, 16)
    missing = set(TABLE_SYMBOLS.values()) - set(found)
    if missing:
        raise SystemExit('%s has no address for %s' % (path, ', '.join(sorted(missing))))
    globals().update(found)


def switch_names():
    """SW_* names from src/game.inc, if it is there: switch number -> name."""
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'src', 'game.inc')
    names = {}
    if os.path.exists(path):
        for line in pathlib.Path(path).read_text().splitlines():
            m = re.match(r'^(SW_\w+)\s*=\s*(\d+)', line)
            if m:
                names[int(m.group(2))] = m.group(1)
    return names


SWITCHES = switch_names()


def sw(n):
    return SWITCHES.get(n, 'switch[%d]' % n)


# Condition opcodes (dispatch table at $5AB7). Each entry: (name, operand count, formatter)
CONDITIONS = {
    3: ('OBJ_IN_ROOM', 2, lambda a, n: '%s is in %s' % (n.obj(a[0]), n.room(a[1]))),
    5: ('TURNS_GT', 1, lambda a, n: 'turn > %d' % a[0]),
    6: ('SWITCH_EQ', 2, lambda a, n: '%s == %d' % (sw(a[0]), a[1])),
    9: ('VIEW_IS', 1, lambda a, n: 'current picture == %d' % a[0]),
    10: ('OBJ_PIC_IS', 2, lambda a, n: '%s picture == %d' % (n.obj(a[0]), a[1])),
}

# Action opcodes (dispatch table at $6535); handler labels are the original ACnn00 names.
ACTIONS = {
    1: ('ADD_SWITCH', 2, lambda a, n: '%s += %d' % (sw(a[1]), a[0])),
    2: ('SUB_SWITCH', 2, lambda a, n: '%s -= %d' % (sw(a[1]), a[0])),
    3: ('SET_SWITCH', 2, lambda a, n: '%s = %d' % (sw(a[0]), a[1])),
    4: ('INVENTORY', 0, lambda a, n: 'list objects carried'),
    5: ('PUT_OBJ', 2, lambda a, n: 'put %s in %s' % (n.obj(a[0]), n.room(a[1]))),
    6: ('GOTO_ROOM', 1, lambda a, n: 'go to %s' % n.room(a[0])),
    7: ('SET_VIEW', 1, lambda a, n: 'show picture %d' % a[0]),
    8: ('SET_BASE_VIEW', 1, lambda a, n: 'make picture %d the room view' % a[0]),
    9: ('MESSAGE', 1, lambda a, n: 'say %s' % n.msg(a[0])),
    10: ('LAMP_ON', 0, lambda a, n: 'light on'),
    11: ('LAMP_OFF', 0, lambda a, n: 'light off'),
    12: ('UNUSED_12', 0, lambda a, n: 'crash (BRK)'),
    13: ('QUIT', 0, lambda a, n: 'say %s; exit to DOS' % n.msg(0x8C)),
    14: ('UNUSED_14', 0, lambda a, n: 'crash (BRK)'),
    15: ('SAVE_GAME', 0, lambda a, n: 'save game'),
    16: ('RESTORE_GAME', 0, lambda a, n: 'restore game'),
    17: ('GAME_OVER', 0, lambda a, n: 'ask to play again'),
    18: ('PLACE_OBJ', 4, lambda a, n: 'put %s in %s at (%d,%d)' % (n.obj(a[0]), n.room(a[1]), a[2], a[3])),
    19: ('SET_OBJ_PIC', 2, lambda a, n: 'draw %s as picture %d' % (n.obj(a[1]), a[0])),
    20: ('RESET_VIEW', 0, lambda a, n: 'show the room view'),
    21: ('GO_N', 0, lambda a, n: 'go north'),
    22: ('GO_S', 0, lambda a, n: 'go south'),
    23: ('GO_E', 0, lambda a, n: 'go east'),
    24: ('GO_W', 0, lambda a, n: 'go west'),
    25: ('GO_U', 0, lambda a, n: 'go up'),
    26: ('GO_D', 0, lambda a, n: 'go down'),
    27: ('GET', 0, lambda a, n: 'take the named object'),
    28: ('DROP', 0, lambda a, n: 'drop the named object'),
    29: ('SET_ROOM_VIEW', 2, lambda a, n: 'set %s view to picture %d' % (n.room(a[0]), a[1])),
}


class Game:
    def __init__(self, extracted):
        self.dir = extracted
        self.d = pathlib.Path(os.path.join(extracted, 'ADVENTURE.bin')).read_bytes()
        self.msgfile = pathlib.Path(os.path.join(extracted, 'MESSAGES.txt.bin')).read_bytes()

    def b(self, a):
        return self.d[a - LOAD]

    def w(self, a):
        return self.b(a) | self.b(a + 1) << 8

    def text(self, a, n):
        return bytes(c & 0x7F for c in self.d[a - LOAD:a - LOAD + n]).decode('ascii')

    # --- vocabulary -------------------------------------------------------------------
    def words(self, base):
        """Groups as the parser at $6458 walks them: word, synonym count, synonyms; $00 = no
        synonyms; $FF ends the table. The group number is the word's id."""
        groups = []
        a = base
        while True:
            words = [self.text(a, 8).rstrip()]
            a += 8
            n = self.b(a)
            if n == 0xFF:
                groups.append(words)
                break
            a += 1
            for _ in range(n):
                words.append(self.text(a, 8).rstrip())
                a += 8
            groups.append(words)
            if self.b(a) == 0xFF:
                break
        return groups

    # --- messages ---------------------------------------------------------------------
    def messages(self):
        # one index entry per message in the MESSAGES file (its records end with $8D; $00 ends it)
        end = self.msgfile.index(b'\x00') if b'\x00' in self.msgfile else len(self.msgfile)
        count = self.msgfile[:end].count(b'\x8d') + 1
        out = {}
        for n in range(1, count):
            off = self.w(MSGINDEX + 2 * n)
            end = self.msgfile.find(b'\x8d', off)
            out[n] = bytes(c & 0x7F for c in self.msgfile[off:end]).decode('ascii')
        for n, t in BUILTIN_MESSAGES.items():
            out[n] = t
        return out

    # --- rooms and objects --------------------------------------------------------------
    def rooms(self):
        rooms = []
        n = 1
        while True:
            a = ROOMBASE + n * 10
            rec = [self.b(a + k) for k in range(10)]
            if rec[0] != n:
                break
            rooms.append(dict(zip(ROOM_FIELDS, rec)))
            n += 1
        return rooms

    def objects(self):
        objs = []
        a = OBJBASE
        while self.b(a) != 0xFF:
            n = self.b(a + 9)
            rec = [self.b(a + k) for k in range(n)]
            objs.append({
                'addr': a, 'OBJECTNO': rec[0], 'noun': rec[1], 'OROOM': rec[2], 'OPIC': rec[3],
                'shape': rec[4] == 1, 'OXCOORD': rec[5], 'OYCOORD': rec[6], 'OSTATUS': rec[7],
                'OMSG': rec[8], 'ONEXT': rec[9], 'ORPICKT': rec[10], 'ORPICSTA': rec[11:11 + rec[10]],
            })
            a += n
        return objs

    def picture_directory(self):
        pics = {}
        a = PICDIR + 3     # entry 0 is unused (SUB_7200 indexes PICDIR + 3 * n)
        n = 1
        while True:
            blk, off = self.b(a), self.w(a + 1)
            if blk == 0 or blk > 19:
                break
            pics[n] = (blk, off)
            a += 3
            n += 1
        return pics

    def picture(self, blk, off):
        """A picture's strokes as draw_picture reads them: a 00 00 pair starts a new stroke
        (the pen is lifted: its first point is plotted, the rest are lines from the point before),
        FF FF ends the picture. 'continues' is true when the picture does not start with 00 00:
        its first stroke then goes on from wherever the pen was (only picture 92)."""
        data = pathlib.Path(os.path.join(self.dir, 'BLOCK%d.bin' % blk)).read_bytes()
        strokes, cur, continues = [], None, data[off:off + 2] != b'\x00\x00'
        if continues:
            cur = []
            strokes.append(cur)
        while True:
            x, y = data[off], data[off + 1]
            off += 2
            if x == 0xFF and y == 0xFF:
                break
            if x == 0 and y == 0:
                cur = []
                strokes.append(cur)
                continue
            cur.append([x, y])
        return {'continues': continues, 'strokes': [st for st in strokes if st]}

    def shapes(self):
        """The shape table as DRAW reads it (scale 1, rotation 0): for each shape, its vectors
        in order as [plot, direction] (plot 1 = plot the pen's pixel before moving; direction
        0 up, 1 right, 2 down, 3 left). Each byte holds up to three vectors, taken while the
        rest of the byte is non-zero; the third has no plot bit."""
        count = self.b(SHAPES)
        out = {}
        for n in range(1, count + 1):
            p = SHAPES + self.w(SHAPES + 2 * n)
            vectors = []
            while self.b(p):
                v = self.b(p)
                while v:
                    vectors.append([1 if v & 4 else 0, v & 3])
                    v >>= 3
                p += 1
            out[n] = vectors
        return out

    def saved_state(self, name):
        """A state snapshot file (SAVED GAME: $0830-$10FE, what RESTORE GAME loads) as the
        state a port keeps: room, turn, switches, light, the last verb and noun and the picture
        on screen (the turn rules that run after a RESTORE see them), and every object's and
        room's changeable fields."""
        snap = pathlib.Path(os.path.join(self.dir, name)).read_bytes()
        at = lambda a: snap[a - SAVE_START]
        objects = []
        for o in self.objects():
            a = o['addr']
            objects.append({'OBJECTNO': o['OBJECTNO'], 'OROOM': at(a + 2), 'OPIC': at(a + 3),
                            'OXCOORD': at(a + 5), 'OYCOORD': at(a + 6), 'OSTATUS': at(a + 7)})
        rooms = [{'RROOMNO': n, 'RBASEPIC': at(ROOMBASE + 10 * n + 8), 'RCURPIC': at(ROOMBASE + 10 * n + 9)}
                 for n in range(1, len(self.rooms()) + 1)]
        return {'room': at(CURONO), 'turn': at(TURNS) | at(TURNS + 1) << 8,
                'switches': [at(SWITCH + i) for i in range(20)], 'light': at(LAMPSTAT) == 0,
                'verb': at(VERB), 'noun': at(NOUN),
                'shown_picture': at(SHOWN_PICTURE), 'objects': objects, 'rooms': rooms}

    def loader_text(self):
        """The loader's menu prompt and instruction pages, read from its code in byte order:
        each JSR to its print routine is followed by $00-terminated text, JSR GETLN1 waits for
        a line, JSR HOME clears the screen and starts a page. Each is a list of lines, split at
        the carriage returns as printed (so leading empty lines are kept): the menu is the text
        before the first wait, each page the text after a HOME."""
        code = pathlib.Path(os.path.join(self.dir, 'AUTO_LOAD_OBJ.bin')).read_bytes()
        lengths = {0xAD: 3, 0xA2: 2, 0x9A: 1, 0xC9: 2, 0xD0: 2, 0xF0: 2, 0x4C: 3, 0x20: 3}
        p, events, text = 0, [], []
        while code[p] != 0x60:                       # up to run_adventure's RTS
            op = code[p]
            if op not in lengths:
                raise SystemExit('loader: unexpected opcode $%02X at $%04X' % (op, LOADER + p))
            if op == 0x20:
                target = code[p + 1] | code[p + 2] << 8
                p += 3
                if target == LOADER_PRINT:
                    end = code.index(0, p)
                    text.append(bytes(c & 0x7F for c in code[p:end]).decode('ascii'))
                    p = end + 1
                elif target in (HOME, GETLN1):
                    events.append((''.join(text), target))
                    text = []
                continue
            p += lengths[op]
        menu = events[0][0].split('\r')
        pages = [t.split('\r') for (t, _), (_, after) in zip(events[1:], events) if after == HOME]
        return {'menu': menu, 'pages': pages}

    def titles(self):
        """The two title pictures as 280 x 192 bitmaps: the 1987 Sierra title in AUTO LOAD OBJ's
        $2000-$3FFF and the 1980 On-Line Systems title in ADVENTURE's. Each row of 'pixels' is 35
        bytes in hex, eight pixels a byte with the leftmost in bit 7 (1 = lit). Each row of
        'colour_bits' is the hi-res bytes' bit 7 (the colour group, which shifts NTSC artefact
        colour) for the row's 40 groups of 7 pixels: 5 bytes in hex, leftmost group in bit 7."""
        auto = pathlib.Path(os.path.join(self.dir, 'AUTO_LOAD_OBJ.bin')).read_bytes()
        pages = {'1987': auto[0x2000 - LOADER:0x4000 - LOADER],
                 '1980': self.d[0x2000 - LOAD:0x4000 - LOAD]}
        return {name: hires_bitmap(page) for name, page in pages.items()}

    # --- rules ------------------------------------------------------------------------
    def rules(self, base):
        """Rule layout (interpreter at $5A55): room, verb, noun ($FE = any), length, number of
        conditions, number of actions, conditions [op, args...], actions [op, args...]."""
        rules = []
        a = base
        while self.b(a) != 0xFF:
            room, verb, noun, ln, nc, na = (self.b(a + k) for k in range(6))
            p = a + 6
            conds, acts = [], []
            for _ in range(nc):
                op = self.b(p)
                if op not in CONDITIONS:
                    raise SystemExit('unknown condition %d at $%04X' % (op, p))
                k = CONDITIONS[op][1]
                conds.append((op, [self.b(p + 1 + i) for i in range(k)]))
                p += 1 + k
            for _ in range(na):
                op = self.b(p)
                if op not in ACTIONS:
                    raise SystemExit('unknown action %d at $%04X' % (op, p))
                k = ACTIONS[op][1]
                acts.append((op, [self.b(p + 1 + i) for i in range(k)]))
                p += 1 + k
            if p - a != ln:
                raise SystemExit('rule at $%04X: length %d but parsed %d' % (a, ln, p - a))
            rules.append({'addr': a, 'room': room, 'verb': verb, 'noun': noun,
                          'conditions': conds, 'actions': acts})
            a += ln
        return rules


class Namer:
    def __init__(self, verbs, nouns, rooms, objs, msgs):
        self.verbs, self.nouns, self.msgs = verbs, nouns, msgs
        self.rooms = {r['RROOMNO']: r for r in rooms}
        self.objs = {o['OBJECTNO']: o for o in objs}

    def verb(self, n):
        if n == ANY or not 0 < n <= len(self.verbs):
            return 'any verb' if n == ANY else 'verb %d' % n
        ws = self.verbs[n - 1]
        return ws[1] if len(ws[0]) == 1 and len(ws) > 1 else ws[0]

    def noun(self, n):
        return 'any noun' if n == ANY else self.nouns[n - 1][0] if 0 < n <= len(self.nouns) else 'noun %d' % n

    def room(self, n):
        if n == CARRYING:
            return 'inventory'
        if n == NOWHERE:
            return 'nowhere'
        r = self.rooms.get(n)
        if not r:
            return 'room %d' % n
        return 'room %d (%s)' % (n, short(self.msgs.get(r['RMSG'], '')))

    def obj(self, n):
        o = self.objs.get(n)
        if not o:
            return 'object %d' % n
        return 'object %d (%s)' % (n, self.noun(o['noun']))

    def msg(self, n):
        return 'msg %d "%s"' % (n, self.msgs.get(n, '?'))


def write_map(out, rooms, rules, msgs, nm):
    """map.txt and map.dot: every room with its compass exits and the passages rules make
    (GO DOOR, GO HOLE, ...), with the conditions they need."""
    passages = {}
    for r in rules:
        if r['room'] == ANY:
            continue
        for op, args in r['actions']:
            if op == 6:   # GOTO_ROOM
                need = [CONDITIONS[c][2](a, nm) for c, a in r['conditions']]
                what = ' '.join(x for x in (nm.verb(r['verb']) if r['verb'] != ANY else '',
                                            nm.noun(r['noun']) if r['noun'] != ANY else '') if x)
                passages.setdefault(r['room'], []).append((what, args[0], need))
    lines = ['# Every room: its compass exits (the room table) and the passages rules make, with',
             '# what they need. Rooms with no way out on the compass are left by such a passage.', '']
    dot = ['digraph mystery_house {', '  node [shape=box, fontname="Helvetica", fontsize=10];',
           '  edge [fontname="Helvetica", fontsize=8];']
    for r in rooms:
        n = r['RROOMNO']
        lines.append('room %d  %s' % (n, short(msgs.get(r['RMSG'], ''), 70)))
        dot.append('  r%d [label="%d\\n%s"];' % (n, n, short(msgs.get(r['RMSG'], ''), 30).replace('"', "'")))
        for i, k in enumerate(ROOM_FIELDS[2:8]):
            if r[k]:
                lines.append('    %-6s -> %d' % (DIRS[i], r[k]))
                dot.append('  r%d -> r%d [label="%s"];' % (n, r[k], DIRS[i][0].upper()))
        seen = set()
        for what, to, need in passages.get(n, []):
            key = (what, to, tuple(need))
            if key in seen:
                continue
            seen.add(key)
            lines.append('    %-6s -> %d%s' % (what, to, ('   (if %s)' % ', '.join(need)) if need else ''))
            dot.append('  r%d -> r%d [label="%s", style=dashed];' % (n, to, what))
        lines.append('')
    dot.append('}')
    pathlib.Path(os.path.join(out, 'map.txt')).write_text('\n'.join(lines))
    pathlib.Path(os.path.join(out, 'map.dot')).write_text('\n'.join(dot) + '\n')


def short(s, n=40):
    s = s.replace('YOU ARE ', '').split('.')[0]
    return s if len(s) <= n else s[:n - 3] + '...'


def pack_bits(bits):
    """A list of 0/1, a multiple of 8 long, as hex bytes with the first bit in bit 7."""
    return bytes(sum(b << (7 - k) for k, b in enumerate(bits[i:i + 8]))
                 for i in range(0, len(bits), 8)).hex().upper()


def hires_bitmap(page):
    """An 8 KB hi-res page as {'pixels': 192 rows, 'colour_bits': 192 rows} (Game.titles)."""
    pixels, colour = [], []
    for y in range(192):
        base = (y & 7) * 0x400 + ((y >> 3) & 7) * 0x80 + (y >> 6) * 0x28
        row = page[base:base + 40]
        pixels.append(pack_bits([(b >> k) & 1 for b in row for k in range(7)]))
        colour.append(pack_bits([b >> 7 for b in row]))
    return {'pixels': pixels, 'colour_bits': colour}


def compact_json(data):
    """JSON indented by one space, but with each list of numbers on one line, and each list of
    such lists (a picture's stroke, a shape's vectors) too, so the picture data stays small."""
    text = json.dumps(data, indent=1)
    nums = re.compile(r'\[\s+(-?\d+(?:,\s+-?\d+)*)\s+\]')
    text = nums.sub(lambda m: '[' + re.sub(r'\s+', '', m.group(1)).replace(',', ', ') + ']', text)
    lists = re.compile(r'\[\s+(\[[-\d, ]*\](?:,\s+\[[-\d, ]*\])*)\s+\]')
    text = lists.sub(lambda m: '[' + re.sub(r',\s+\[', ', [', m.group(1)) + ']', text)
    return text


def main():
    if len(sys.argv) > 3:
        use_symbols(sys.argv[3])
    g = Game(sys.argv[1])
    out = sys.argv[2]
    os.makedirs(out, exist_ok=True)
    verbs, nouns = g.words(VERBS), g.words(NOUNS)
    msgs = g.messages()
    rooms, objs = g.rooms(), g.objects()
    pics = g.picture_directory()
    turn_rules, cmd_rules = g.rules(TURN_RULES), g.rules(CMD_RULES)
    nm = Namer(verbs, nouns, rooms, objs, msgs)

    with open(os.path.join(out, 'messages.txt'), 'w') as f:
        f.write('# Messages by number. Numbers marked * are built into the code at $7400.\n')
        for n in sorted(msgs):
            f.write('%3d%s %s\n' % (n, '*' if n in BUILTIN_MESSAGES else ' ', msgs[n]))

    with open(os.path.join(out, 'vocabulary.txt'), 'w') as f:
        f.write('# Only the first 8 letters of a word are significant. A command is VERB NOUN or a\n'
                '# verb alone: the parser (read_command) looks the first word up in the verb table\n'
                '# and the second in the noun table (a missing noun is noun 70, eight spaces).\n\nVERBS ($%04X)\n' % VERBS)
        for i, ws in enumerate(verbs, 1):
            f.write('%3d  %s\n' % (i, ', '.join(ws)))
        f.write('\nNOUNS ($%04X)\n' % NOUNS)
        for i, ws in enumerate(nouns, 1):
            f.write('%3d  %s\n' % (i, ', '.join(ws)))

    with open(os.path.join(out, 'rooms.txt'), 'w') as f:
        f.write('# Room table at $0D00 (RTBLSIZ = 10 bytes per room).\n')
        for r in rooms:
            exits = ', '.join('%s->%d' % (DIRS[i], r[k]) for i, k in enumerate(ROOM_FIELDS[2:8]) if r[k])
            f.write('\nroom %d  picture %d\n  %s\n  exits: %s\n' % (
                r['RROOMNO'], r['RBASEPIC'], msgs.get(r['RMSG'], '?'), exits or 'none'))
            here = [o for o in objs if o['OROOM'] == r['RROOMNO']]
            if here:
                f.write('  objects: %s\n' % ', '.join(nm.obj(o['OBJECTNO']) for o in here))

    with open(os.path.join(out, 'objects.txt'), 'w') as f:
        f.write('# Object table at $0900. Status: OMOVABLE = can be taken, not yet moved (drawn as\n'
                '# part of the listed room pictures); OMOVED = taken or dropped (drawn in a floor\n'
                '# slot); OFIXED = cannot be taken.\n')
        for o in objs:
            f.write('\nobject %d  %s\n  where: %s\n  drawn as %s %d at (%d,%d), status %s\n' % (
                o['OBJECTNO'], ', '.join(nouns[o['noun'] - 1]), nm.room(o['OROOM']),
                'shape' if o['shape'] else 'picture', o['OPIC'], o['OXCOORD'], o['OYCOORD'],
                OSTATUS.get(o['OSTATUS'], o['OSTATUS'])))
            if o['OMSG']:
                f.write('  inventory text: %s\n' % msgs.get(o['OMSG'], '?'))
            if o['ORPICSTA']:
                f.write('  visible in pictures: %s\n' % ', '.join(map(str, o['ORPICSTA'])))

    def write_rules(f, title, rules):
        f.write('%s\n%s\n' % (title, '=' * len(title)))
        for r in rules:
            head = []
            if r['room'] != ANY:
                head.append('in %s' % nm.room(r['room']))
            if r['verb'] != ANY:
                head.append('verb %s' % nm.verb(r['verb']))
            if r['noun'] != ANY:
                head.append('noun %s' % nm.noun(r['noun']))
            f.write('\n$%04X  %s\n' % (r['addr'], ' and '.join(head) if head else 'always'))
            for op, args in r['conditions']:
                f.write('         if %s\n' % CONDITIONS[op][2](args, nm))
            for op, args in r['actions']:
                f.write('           %s\n' % ACTIONS[op][2](args, nm))
        f.write('\n')

    with open(os.path.join(out, 'rules.txt'), 'w') as f:
        f.write('# Game logic. After each command the engine scans the command rules ($%04X)\n'
                '# for the first one whose room/verb/noun and conditions match, runs its actions and\n'
                '# stops ("I DONT UNDERSTAND WHAT YOU MEAN" if none match). It then runs every\n'
                '# matching turn rule ($%04X). SW_* are the game flags at $%04X (src/game.inc).\n\n'
                % (CMD_RULES, TURN_RULES, SWITCH))
        write_rules(f, 'COMMAND RULES ($%04X)' % CMD_RULES, cmd_rules)
        write_rules(f, 'TURN RULES ($%04X)' % TURN_RULES, turn_rules)

    write_map(out, rooms, cmd_rules, msgs, nm)

    def enc(rules):
        return [{**r, 'conditions': [{'op': CONDITIONS[o][0], 'args': a} for o, a in r['conditions']],
                 'actions': [{'op': ACTIONS[o][0], 'args': a} for o, a in r['actions']]} for r in rules]

    pathlib.Path(os.path.join(out, 'gamedata.json')).write_text(compact_json({
        'verbs': verbs, 'nouns': nouns, 'messages': msgs, 'rooms': rooms, 'objects': objs,
        'pictures': {n: {'block': b, 'offset': o, **g.picture(b, o)} for n, (b, o) in pics.items()},
        'shapes': g.shapes(),
        'command_rules': enc(cmd_rules), 'turn_rules': enc(turn_rules),
        'floor_slots': [(g.b(FLOOR_SLOTS + 2 * i), g.b(FLOOR_SLOTS + 2 * i + 1)) for i in range(21)],
        # a new game (init_game): room 1, turn 1, light on, switches from init_switches
        # (tests/test_analysis.py checks this against the game at its first prompt)
        'start': {'room': 1, 'turn': 1, 'switches': [g.b(INIT_SWITCHES + i) for i in range(20)],
                  'light': True},
        # the 1987 loader's menu and instruction pages (PORTING.md, "Before the game")
        'loader': g.loader_text(),
        # the saved game on the disk: what RESTORE GAME loads before any SAVE GAME
        'saved_game': g.saved_state('SAVED_GAME.bin'),
        # the 1987 and 1980 title pictures (PORTING.md, "Before the game")
        'titles': g.titles(),
        'addresses': {k: globals()[k] for k in sorted(TABLE_SYMBOLS.values())},
    }))
    print('%d verbs, %d nouns, %d messages, %d rooms, %d objects, %d pictures, %d command rules, '
          '%d turn rules' % (len(verbs), len(nouns), len(msgs), len(rooms), len(objs), len(pics),
                             len(cmd_rules), len(turn_rules)))


if __name__ == '__main__':
    main()

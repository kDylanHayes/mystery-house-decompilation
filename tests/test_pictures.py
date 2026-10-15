"""tools/pictures.py draws exactly what the game draws: every picture, every shape and every
room is drawn by the game's own routines (draw_picture, draw_shape, draw_room) on the
emulator and by the Python renderer, and the pixels must be the same. This makes pictures.py
the reference for the drawing algorithm (a port can follow it) and the PNGs in assets/ exact."""
import copy
import csv
import hashlib
import json
import os
import tempfile
import unittest

import helpers
import pictures  # noqa: E402 (helpers puts tools/ on the path)
import play

RETURN = 0xBFF0           # an address the game never runs: a routine called here returns to it


class Drawing(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        b = helpers.build()
        with open(os.path.join(b, 'adventure.syms.csv')) as f:
            cls.syms = {r['name']: int(r['address'], 16) for r in csv.DictReader(f)}
        out = tempfile.mkdtemp(prefix='mh-pictures-')
        helpers.tool('gamedata.py', os.path.join(b, 'files'), out, os.path.join(b, 'adventure.syms.csv'))
        with open(os.path.join(out, 'gamedata.json')) as f:
            cls.gd = json.load(f)
        files = os.path.join(b, 'files')
        cls.blocks = {}
        for n in range(1, 20):
            with open(os.path.join(files, 'BLOCK%d.bin' % n), 'rb') as f:
                cls.blocks[n] = f.read()
        with open(os.path.join(files, 'ADVENTURE.bin'), 'rb') as f:
            adv = f.read()
        cls.table = adv[cls.gd['addresses']['SHAPES'] - 0x0800:]
        # the game, started and waiting at its first prompt: everything is set up
        cls.m, reason = play.play(files, [])
        assert reason == 'end of commands', reason

    def call(self, name, a=0, x=0, y=0):
        """Run one of the game's routines to its RTS."""
        m = self.m
        ret = RETURN - 1
        m.mem[0x100 + m.sp] = ret >> 8
        m.sp = (m.sp - 1) & 0xFF
        m.mem[0x100 + m.sp] = ret & 0xFF
        m.sp = (m.sp - 1) & 0xFF
        m.a, m.x, m.y, m.pc = a, x, y, self.syms[name]

        def back(mach):
            raise play.Stop('returned')
        m.executed, m.hooks = set(), {RETURN: back}
        try:
            m.run(m.steps + 50_000_000)
        except play.Stop as e:
            self.assertEqual(str(e), 'returned')
        m.executed, m.hooks = None, {}

    def poke(self, name, value):
        self.m.mem[self.syms[name]] = value

    def screen(self):
        return pictures.hires_pixels(bytes(self.m.mem[0x2000:0x4000]))

    def assertSame(self, cv, what):
        game = self.screen()
        if bytes(game) != bytes(cv.px):
            diff = [(i % pictures.W, i // pictures.W) for i in range(len(game)) if game[i] != cv.px[i]]
            self.fail('%s: %d pixels differ, first %s' % (what, len(diff), diff[:5]))

    def picture(self, n, dx, dy):
        self.call('hgr')
        self.poke('shown_picture', n)
        self.poke('draw_dx', dx)
        self.poke('draw_dy', dy)
        self.poke('pen_up', 1)
        self.call('draw_picture')
        self.poke('draw_dx', 0)
        self.poke('draw_dy', 0)
        cv = pictures.Canvas()
        p = self.gd['pictures'][str(n)]
        pictures.draw_picture(cv, self.blocks[p['block']], p['offset'], dx, dy)
        return cv

    def test_colours_are_applesofts(self):
        # a row filled as Applesoft's HCOLOR fills it: a byte holds 7 dots, so the pattern
        # alternates between even and odd bytes to keep its dots in every other column. Dots in
        # the even columns ($55, $2A, ...) are violet, in the odd ones ($2A, $55, ...) green;
        # with bit 7 set ($D5, $AA / $AA, $D5) blue and orange.
        violet, green, blue, orange = (255, 68, 253), (20, 245, 60), (20, 207, 253), (255, 106, 60)
        for pair, colour in (((0x55, 0x2A), violet), ((0x2A, 0x55), green),
                             ((0xD5, 0xAA), blue), ((0xAA, 0xD5), orange)):
            page = bytearray(0x2000)
            page[0:40] = bytes(pair) * 20                      # row 0
            row = pictures.hires_color(bytes(page))[0]
            lit = {tuple(row[i:i + 3]) for i in range(0, len(row), 3) if any(row[i:i + 3])}
            self.assertEqual(lit, {colour}, [hex(b) for b in pair])

    def test_every_picture(self):
        for n in range(1, len(self.gd['pictures']) + 1):
            self.assertSame(self.picture(n, 0, 0), 'picture %d' % n)

    def test_offsets_wrap_and_clamp(self):
        # the offset is added in 8 bits: past 255 a point wraps round, then x is clamped to
        # 255 and y to 160
        for n in range(1, len(self.gd['pictures']) + 1):
            self.assertSame(self.picture(n, 150, 90), 'picture %d at (150, 90)' % n)

    def test_a_picture_that_continues_the_last_line(self):
        # picture 92 has no 00 00 at its start: its first point is a line from the pen
        self.call('hgr')
        self.call('hposn', a=30, x=40, y=0)
        self.poke('shown_picture', 92)
        self.poke('pen_up', 0)
        self.call('draw_picture')
        cv = pictures.Canvas()
        cv.x = cv.sx = 40
        cv.y = cv.sy = 30
        cv.pen_up = False
        p = self.gd['pictures']['92']
        pictures.draw_picture(cv, self.blocks[p['block']], p['offset'])
        self.assertSame(cv, 'picture 92 from (40, 30)')

    def test_every_shape(self):
        for n in range(1, self.table[0] + 1):
            for x, y in ((100, 100), (7, 20), (250, 150)):
                self.call('hgr')
                self.poke('var_shape', n)
                self.poke('var_x', x)
                self.poke('var_y', y)
                self.call('draw_shape')
                cv = pictures.Canvas()
                pictures.draw_shape(cv, self.table, n, x, y)
                self.assertSame(cv, 'shape %d at (%d, %d)' % (n, x, y))

    def test_every_room_as_first_seen(self):
        # draw_room with the objects where the game starts them: what assets/rooms/ shows
        for room in self.gd['rooms']:
            n = room['RROOMNO']
            self.poke('CURONO', n)
            self.poke('LAMPSTAT', 0)
            self.call('draw_room')
            cv = pictures.room_canvas(self.gd, self.blocks, self.table, n)
            self.assertSame(cv, 'room %d' % n)



    def test_gamedata_json_is_enough_to_draw(self):
        # a port reads pictures and shapes from gamedata.json alone: drawing them from there
        # must give what the game draws
        for n, p in self.gd['pictures'].items():
            cv = pictures.Canvas()
            cv.pen_up = not p['continues']    # a continuing picture goes on from the pen, (0, 0)
            pictures.draw_picture(cv, self.blocks[p['block']], p['offset'])
            port = pictures.Canvas()
            for i, stroke in enumerate(p['strokes']):
                for j, (x, y) in enumerate(stroke):
                    if j == 0 and not (i == 0 and p['continues']):
                        port.plot(x, y)
                    else:
                        port.line(x, y)
            self.assertEqual(bytes(port.px), bytes(cv.px), 'picture %s' % n)
        for n, vectors in self.gd['shapes'].items():
            cv = pictures.Canvas()
            pictures.draw_shape(cv, self.table, int(n), 100, 100)
            port = pictures.Canvas()
            x, y = 100, 100
            for plot, d in vectors:
                if plot:
                    port.set(x, y)
                x, y = x + (0, 1, 0, -1)[d], y + (-1, 0, 1, 0)[d]
            self.assertEqual(bytes(port.px), bytes(cv.px), 'shape %s' % n)

class Screens(unittest.TestCase):
    """The screen at every command prompt of every play script, recomposed in Python from the
    game state at that moment (room, its current picture, objects, light) with pictures.py,
    must have the pixels the game showed (the pixel hashes a port compares, PORTING.md). This
    checks the rules for what is on screen, not just the drawing."""

    @classmethod
    def setUpClass(cls):
        Drawing.setUpClass.__func__(cls)
        cls.fields = {}
        with open(os.path.join(helpers.SRC, 'game.inc')) as f:
            for line in f:
                p = line.split(';')[0].split('=')
                if len(p) == 2 and p[0].strip().isidentifier():
                    try:
                        cls.fields[p[0].strip()] = int(p[1].strip().replace('$', '0x'), 0)
                    except ValueError:
                        pass

    def state(self, mem):
        """gamedata as it stands in the state bytes ($0800-$10FF)."""
        f, gd = self.fields, copy.deepcopy(self.gd)
        at = lambda a: mem[a - 0x0800]
        for o in gd['objects']:
            a = o['addr']
            for k in ('OROOM', 'OPIC', 'OXCOORD', 'OYCOORD', 'OSTATUS'):
                o[k] = at(a + f[k])
            o['shape'] = at(a + f['OSHAPE']) == 1
            o['ORPICSTA'] = [at(a + f['ORPICSTA'] + i) for i in range(at(a + f['ORPICKT']))]
        for r in gd['rooms']:
            a = self.syms['ROOMBASE'] + r['RROOMNO'] * f['RTBLSIZ']
            for k in ('RBASEPIC', 'RCURPIC'):
                r[k] = at(a + f[k])
        return gd

    def check(self, name):
        m = helpers.played(name)[0]
        pen, drawn, checked = pictures.Canvas(), -1, 0
        for i, (command, redraws, mem) in enumerate(helpers.prompt_states(name)):
            if not command or redraws == drawn:
                continue                      # not a fresh draw_room: nothing new to compare
            drawn = redraws
            cv = pictures.Canvas()
            cv.x, cv.y, cv.sx, cv.sy, cv.pen_up = pen.x, pen.y, pen.sx, pen.sy, pen.pen_up
            if mem[self.syms['LAMPSTAT'] - 0x0800] == 0:      # lit: draw_room draws
                pictures.room_canvas(self.state(mem), self.blocks, self.table,
                                     mem[self.syms['CURONO'] - 0x0800], cv)
            pen = cv
            got = hashlib.sha256(bytes(cv.px[:pictures.W * 160])).hexdigest()[:16]
            self.assertEqual(got, m.pixels[i], '%s, prompt %d' % (name, i))
            checked += 1
        return checked

    def test_every_screen_of_every_script(self):
        total = sum(self.check(name) for name in helpers.SCRIPTS)
        self.assertGreater(total, 500)

if __name__ == '__main__':
    unittest.main()

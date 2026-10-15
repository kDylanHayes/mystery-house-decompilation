#!/usr/bin/env python3
"""Render Mystery House's graphics.

usage: pictures.py <extracted dir> <gamedata.json> <out dir>

Writes, under <out dir>:
  pictures/pic_NN.png + .svg   every vector picture in the directory, drawn at the origin
  shapes/shape_N.png           the Applesoft shapes at $5700 (small objects)
  rooms/room_NN.png            each room as it first appears: room picture plus the objects
                               the engine draws there at the start of the game
  screens/title_1987.png       the Sierra title screen in AUTO LOAD OBJ ($2000-$3FFF), shown by
                               the 1987 public-domain loader
  screens/title_1980.png       the original On-Line Systems title screen: ADVENTURE loads over
                               hi-res page 1, so its $2000-$3FFF bytes are on screen while it loads

Picture format (drawn by SUB_7A00): a list of (x, y) byte pairs. The pair 00 00 means "the next
point starts a new line" (HPLOT x,y); any other pair continues the line (HPLOT TO x,y). FF FF ends
the picture. Points are offset by the object position and clamped to x <= 255, y <= 160.
"""
import pathlib
import json
import os
import struct
import sys
import zlib

W, H = 280, 192
SCALE = 2
LOAD = 0x0800
SHAPES = 0x5700        # the shape table in the original; gamedata.json gives a build's


def png(path, width, height, rows):
    """rows: list of bytes objects, RGB, width*3 each."""
    raw = b''.join(b'\x00' + r for r in rows)

    def chunk(t, data):
        return struct.pack('>I', len(data)) + t + data + struct.pack('>I', zlib.crc32(t + data) & 0xFFFFFFFF)
    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
                + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))


class Canvas:
    """A 280 x 192 one-bit screen with the game's drawing routines (the relocated Applesoft
    HPLOT, HGLIN and DRAW in ADVENTURE), pixel for pixel; tests/test_pictures.py checks every
    picture and shape against the game's own code on the emulator.

    Like Applesoft, the pen has a logical position (hgr_x, hgr_y: where HGLIN measures a line
    from) and a screen position (where the next point is plotted). They differ only after DRAW,
    which moves the screen position alone. pen_up is the game's flag: set by a 00 00 pair in a
    picture, it makes the next point an HPLOT rather than a line, and it carries over from one
    picture to the next (only picture 92 starts without 00 00).

    A pixel off the screen is dropped; the Apple's routines would wrap the pen round to the
    other side instead. The game never draws there (pictures are clamped to 255 x 160 and the
    shapes sit well inside), so the difference never shows."""

    def __init__(self):
        self.px = bytearray(W * H)
        self.x = self.y = 0          # logical pen (hgr_x, hgr_y)
        self.sx = self.sy = 0        # screen pen
        self.pen_up = True

    def set(self, x, y):
        if 0 <= x < W and 0 <= y < H:
            self.px[y * W + x] = 1

    def plot(self, x, y):
        """HPLOT x,y: move both pens there and plot."""
        self.x, self.y = self.sx, self.sy = x, y
        self.set(x, y)

    def line(self, x1, y1):
        """HPLOT TO x1,y1 (Applesoft HGLIN): |dx| + |dy| single steps from the screen pen.

        Each step is one pixel across or one pixel up or down, and the start is plotted
        again. err starts at dx - dy; the step goes across while err >= 0 (then err -= dy)
        and up or down otherwise (then err += dx). dx and dy are measured from the logical
        pen. DRAW moves only the screen pen, so a following line starts there."""
        dx, dy = abs(x1 - self.x), abs(y1 - self.y)
        step_x = -1 if x1 < self.x else 1
        step_y = 1 if y1 > self.y else -1
        x, y = self.sx, self.sy
        err = dx - dy
        self.set(x, y)
        for _ in range(dx + dy):
            if err >= 0:
                x += step_x
                err -= dy
            else:
                y += step_y
                err += dx
            self.set(x, y)
        self.x, self.y = x1, y1
        self.sx, self.sy = x, y

    def save(self, path, height=H, fg=(255, 255, 255), bg=(0, 0, 0)):
        rows = []
        for y in range(height):
            r = bytearray()
            for x in range(W):
                r += bytes(fg if self.px[y * W + x] else bg) * SCALE
            rows += [bytes(r)] * SCALE
        png(path, W * SCALE, height * SCALE, rows)


MAX_X, MAX_Y = 0xFF, 0xA0     # draw_picture clamps points to the 256 x 161 picture area


def picture_points(data, off):
    """Yield (pen_down, x, y) for a picture starting at data[off]; pen_down is None for the
    first point when the picture does not start with 00 00 (it depends on the pen)."""
    move = None
    while True:
        x, y = data[off], data[off + 1]
        off += 2
        if x == 0xFF and y == 0xFF:
            return
        if x == 0 and y == 0:
            move = True
            continue
        yield (None if move is None else not move), x, y
        move = False


def draw_picture(cv, data, off, dx=0, dy=0):
    """draw_picture: each point offset by (dx, dy) in 8 bits (so it wraps past 255), then
    clamped to MAX_X / MAX_Y; HPLOT after a 00 00 pair, HPLOT TO otherwise."""
    while True:
        x, y = data[off], data[off + 1]
        off += 2
        if x == 0xFF and y == 0xFF:
            return
        if x == 0 and y == 0:
            cv.pen_up = True
            continue
        x, y = min((x + dx) & 0xFF, MAX_X), min((y + dy) & 0xFF, MAX_Y)
        if cv.pen_up:
            cv.plot(x, y)
            cv.pen_up = False
        else:
            cv.line(x, y)


def picture_svg(path, data, off):
    paths, cur = [], []
    for down, x, y in picture_points(data, off):
        if down is not True and cur:
            paths.append(cur)
            cur = []
        cur.append((x, y))
    if cur:
        paths.append(cur)
    d = ' '.join('M' + ' L'.join('%d %d' % p for p in pts) for pts in paths)
    with open(path, 'w') as f:
        f.write('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 280 192" width="560" height="384">'
                '<rect width="280" height="192" fill="#000"/>'
                '<path d="%s" fill="none" stroke="#fff" stroke-width="1" stroke-linecap="square"/></svg>\n' % d)


def draw_shape(cv, table, n, x, y):
    """Applesoft DRAW with SCALE=1, ROT=0 (draw_shape): HPOSN at (x, y), then each byte holds
    vectors A (bits 0-2), B (3-5) and C (6-7, move only); bit 2 of a vector means plot before
    moving, bits 0-1 the direction (up, right, down, left). Vectors are taken while the
    remaining byte is non-zero. Only the screen pen moves."""
    cv.x, cv.y = cv.sx, cv.sy = x, y
    p = table[2 + 2 * (n - 1)] | table[3 + 2 * (n - 1)] << 8
    while table[p]:
        b = table[p]
        while b:
            v = b & 7
            if v & 4:
                cv.set(cv.sx, cv.sy)
            cv.sx, cv.sy = cv.sx + (0, 1, 0, -1)[v & 3], cv.sy + (-1, 0, 1, 0)[v & 3]
            b >>= 3
        p += 1


def hires_color(mem):
    """Decode an 8 KB hi-res page with the usual NTSC artifact-colour approximation: a lone
    dot in an even column is violet (blue with the byte's bit 7 set), in an odd column green
    (orange), as Applesoft's HCOLOR bytes have it ($55 violet, $2A green, $D5 blue, $AA orange);
    two dots side by side are white."""
    colors = {(0, 0): (0, 0, 0), (0, 1): (255, 68, 253), (0, 2): (20, 245, 60),
              (1, 1): (20, 207, 253), (1, 2): (255, 106, 60)}
    rows = []
    for y in range(H):
        base = (y & 7) * 0x400 + ((y >> 3) & 7) * 0x80 + (y >> 6) * 0x28
        bits, pal = [], []
        for c in range(40):
            b = mem[base + c]
            for k in range(7):
                bits.append((b >> k) & 1)
                pal.append(b >> 7)
        r = bytearray()
        for x in range(W):
            on = bits[x]
            if on and ((x > 0 and bits[x - 1]) or (x < W - 1 and bits[x + 1])):
                c = (255, 255, 255)
            elif on:
                c = colors[(pal[x], 1 if x % 2 == 0 else 2)]
            elif 0 < x < W - 1 and bits[x - 1] and bits[x + 1]:
                c = colors[(pal[x], 1 if (x - 1) % 2 == 0 else 2)]   # fill between two dots
            else:
                c = (0, 0, 0)
            r += bytes(c) * SCALE
        rows += [bytes(r)] * SCALE
    return rows


def hires_pixels(page):
    """The pixels of an 8 KB hi-res page as a W x H array of 0/1 (bit 7, the colour group, is
    left out), so a screen can be compared with a Canvas."""
    px = bytearray(W * H)
    for y in range(H):
        base = (y & 7) * 0x400 + ((y >> 3) & 7) * 0x80 + (y >> 6) * 0x28
        for c in range(40):
            b = page[base + c]
            for k in range(7):
                px[y * W + c * 7 + k] = (b >> k) & 1
    return px


def room_canvas(gd, blocks, table, roomno, cv=None):
    """Draw a room the way draw_room does, with the objects as they are in gd: the room's
    current picture, then each object in the room in object-table order. An OMOVED object
    (taken and dropped) goes in the next floor slot, and only in the room's permanent view;
    any other object is drawn at its own position when the picture is in its ORPICSTA list."""
    cv = cv or Canvas()
    pics = {int(k): (v['block'], v['offset']) for k, v in gd['pictures'].items()}
    room = gd['rooms'][roomno - 1]
    pic = room['RCURPIC']
    blk, off = pics[pic]
    draw_picture(cv, blocks[blk], off)
    slot = 0
    for o in gd['objects']:
        if o['OROOM'] != roomno:
            continue
        if o['OSTATUS'] == 1:
            if room['RBASEPIC'] != room['RCURPIC']:
                continue
            x, y = gd['floor_slots'][slot]
            slot += 1
        elif pic in o['ORPICSTA']:
            x, y = o['OXCOORD'], o['OYCOORD']
        else:
            continue
        if o['shape']:
            draw_shape(cv, table, o['OPIC'], x, y)
        else:
            b2, o2 = pics[o['OPIC']]
            draw_picture(cv, blocks[b2], o2, x, y)
    return cv


def main():
    ext, gd, out = sys.argv[1], json.loads(pathlib.Path(sys.argv[2]).read_text()), sys.argv[3]
    adv = pathlib.Path(os.path.join(ext, 'ADVENTURE.bin')).read_bytes()
    blocks = {n: pathlib.Path(os.path.join(ext, 'BLOCK%d.bin' % n)).read_bytes() for n in range(1, 20)}
    for sub in ('pictures', 'shapes', 'rooms', 'screens'):
        os.makedirs(os.path.join(out, sub), exist_ok=True)

    pics = {int(k): (v['block'], v['offset']) for k, v in gd['pictures'].items()}
    for n, (blk, off) in sorted(pics.items()):
        cv = Canvas()
        draw_picture(cv, blocks[blk], off)
        cv.save(os.path.join(out, 'pictures', 'pic_%02d.png' % n), height=161)
        picture_svg(os.path.join(out, 'pictures', 'pic_%02d.svg' % n), blocks[blk], off)

    table = adv[gd.get('addresses', {}).get('SHAPES', SHAPES) - LOAD:]
    nshapes = table[0]
    for n in range(1, nshapes + 1):
        cv = Canvas()
        draw_shape(cv, table, n, 100, 100)
        on = [(i % W, i // W) for i, v in enumerate(cv.px) if v]
        x0, x1 = min(p[0] for p in on) - 2, max(p[0] for p in on) + 2
        y0, y1 = min(p[1] for p in on) - 2, max(p[1] for p in on) + 2
        rows = []
        for y in range(y0, y1 + 1):
            r = bytearray()
            for x in range(x0, x1 + 1):
                r += bytes((255, 255, 255) if cv.px[y * W + x] else (0, 0, 0)) * 4
            rows += [bytes(r)] * 4
        png(os.path.join(out, 'shapes', 'shape_%d.png' % n), (x1 - x0 + 1) * 4, (y1 - y0 + 1) * 4, rows)

    # rooms in their starting state, as draw_room and draw_objects draw them
    for room in gd['rooms']:
        cv = room_canvas(gd, blocks, table, room['RROOMNO'])
        cv.save(os.path.join(out, 'rooms', 'room_%02d.png' % room['RROOMNO']), height=161)

    auto = pathlib.Path(os.path.join(ext, 'AUTO_LOAD_OBJ.bin')).read_bytes()
    png(os.path.join(out, 'screens', 'title_1987.png'), W * SCALE, H * SCALE,
        hires_color(auto[0x2000 - 0x0FFD:0x4000 - 0x0FFD]))
    png(os.path.join(out, 'screens', 'title_1980.png'), W * SCALE, H * SCALE,
        hires_color(adv[0x2000 - LOAD:0x4000 - LOAD]))
    print('%d pictures, %d shapes, %d rooms' % (len(pics), nshapes, len(gd['rooms'])))


if __name__ == '__main__':
    main()

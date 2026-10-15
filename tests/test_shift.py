"""The source is shiftable: insert padding in front of the tables and the engine, so nearly
everything after the hi-res page moves to a new address, and the game must still play exactly
the same. This is what lets the code and data grow without being pinned in place."""
import os
import shutil
import tempfile
import unittest

import helpers
import play
from test_play import commands, expected

PAD = 37                               # odd, so nothing stays aligned to a page or a word
BEFORE = ['noun_table:', 'verb_table:', 'command_rules:', '; ==== the engine', 'draw_picture:']


def symbols(build_dir):
    out = {}
    with open(os.path.join(build_dir, 'adventure.syms.csv')) as f:
        for line in list(f)[1:]:
            name, addr = line.split(',')[:2]
            out[name] = int(addr, 16)
    return out


class Shifted(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        src = os.path.join(tempfile.mkdtemp(prefix='mh-shift-'), 'src')
        shutil.copytree(helpers.SRC, src)
        path = os.path.join(src, 'adventure.s')
        with open(path) as f:
            text = f.read()
        pad = '        .byte %s    ; shift test padding\n' % ','.join(['$EA'] * PAD)
        for marker in BEFORE:
            i = text.index('\n' + marker) + 1
            text = text[:i] + pad + text[i:]
        with open(path, 'w') as f:
            f.write(text)
        cls.original = helpers.build()
        cls.shifted = helpers.build(src)
        cls.m, cls.reason = play.play(os.path.join(cls.shifted, 'files'), commands('walkthrough.txt'))

    def test_things_really_moved(self):
        a, b = symbols(self.original), symbols(self.shifted)
        self.assertEqual(b['noun_table'] - a['noun_table'], PAD)
        # the noun table's padding is absorbed before the pinned hi-res page at $2000
        self.assertEqual(b['verb_table'] - a['verb_table'], PAD)
        self.assertEqual(b['picture_directory'] - a['picture_directory'], 2 * PAD)
        self.assertEqual(b['MESSLSTR'] - a['MESSLSTR'], 3 * PAD)
        self.assertEqual(b['draw_picture'] - a['draw_picture'], 4 * PAD)
        # pinned: the load address, the tables inside the saved state, the hi-res page
        for name in ('start', 'OBJBASE', 'ROOMBASE', 'title_1980'):
            self.assertEqual(a[name], b[name], name)

    def test_the_file_still_fits(self):
        with open(os.path.join(self.shifted, 'ADVENTURE.bin'), 'rb') as f:
            self.assertLessEqual(0x0800 + len(f.read()), 0x7D00)

    def test_the_game_plays_the_same(self):
        self.assertEqual(self.reason, 'quit to DOS')
        self.assertEqual(self.m.out, expected('walkthrough.expected.txt'))
        self.assertEqual(self.m.screens, expected('walkthrough.screens.txt'))


if __name__ == '__main__':
    unittest.main()

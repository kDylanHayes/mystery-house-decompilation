"""The message, picture and saved-state formats: each source builds and round-trips."""
import os
import shutil
import tempfile
import unittest

import helpers
import msgfile
import picfile
import savefile


def read(path):
    with open(path, 'rb') as f:
        return f.read()


class Messages(unittest.TestCase):
    def test_round_trip(self):
        d = tempfile.mkdtemp()
        msgfile.build(os.path.join(helpers.SRC, 'messages.txt'), os.path.join(d, 'M'), os.path.join(d, 'm.inc'))
        msgfile.extract(read(os.path.join(d, 'M')), os.path.join(d, 'again.txt'))
        msgfile.build(os.path.join(d, 'again.txt'), os.path.join(d, 'M2'), os.path.join(d, 'm2.inc'))
        self.assertEqual(read(os.path.join(d, 'M')), read(os.path.join(d, 'M2')))

    def test_format(self):
        d = tempfile.mkdtemp()
        src = os.path.join(d, 'm.txt')
        with open(src, 'w') as f:
            f.write('; comment\n1 OK\n2 " "\n')
        msgfile.build(src, os.path.join(d, 'M'), os.path.join(d, 'm.inc'))
        self.assertEqual(read(os.path.join(d, 'M')), b'\xcf\xcb\x8d\xa0\x8d\x00')
        with open(os.path.join(d, 'm.inc')) as f:
            self.assertIn('.word $0003   ; 2', f.read())

    def test_numbers_must_be_in_order(self):
        d = tempfile.mkdtemp()
        src = os.path.join(d, 'm.txt')
        with open(src, 'w') as f:
            f.write('1 A\n3 B\n')
        with self.assertRaises(SystemExit):
            msgfile.build(src, os.path.join(d, 'M'), os.path.join(d, 'm.inc'))


class Pictures(unittest.TestCase):
    def test_round_trip(self):
        d = tempfile.mkdtemp()
        out1, out2 = os.path.join(d, 'a'), os.path.join(d, 'b')
        picfile.build(os.path.join(helpers.SRC, 'pictures'), out1, os.path.join(d, 'p1.inc'))
        # extract needs an ADVENTURE with the directory: use the test build's
        b = helpers.build()
        ext = os.path.join(d, 'ext')
        os.makedirs(ext)
        shutil.copy(os.path.join(b, 'ADVENTURE.bin'), ext)
        for n in range(1, 20):
            shutil.copy(os.path.join(out1, 'BLOCK%d.bin' % n), ext)
        picfile.extract(ext, os.path.join(d, 'src'))
        picfile.build(os.path.join(d, 'src'), out2, os.path.join(d, 'p2.inc'))
        for n in range(1, 20):
            self.assertEqual(read(os.path.join(out1, 'BLOCK%d.bin' % n)),
                             read(os.path.join(out2, 'BLOCK%d.bin' % n)), n)

    def test_format(self):
        d = tempfile.mkdtemp()
        os.makedirs(os.path.join(d, 'src'))
        with open(os.path.join(d, 'src', 'block01.txt'), 'w') as f:
            f.write('picture 1\n  line 1,2 3,4\n  cont 5,6\n\nleftover $2A\n')
        picfile.build(os.path.join(d, 'src'), d, os.path.join(d, 'p.inc'))
        self.assertEqual(read(os.path.join(d, 'BLOCK1.bin')),
                         bytes([0, 0, 1, 2, 3, 4, 5, 6, 0xFF, 0xFF, 0x2A]))

    def test_unstorable_point(self):
        d = tempfile.mkdtemp()
        os.makedirs(os.path.join(d, 'src'))
        with open(os.path.join(d, 'src', 'block01.txt'), 'w') as f:
            f.write('picture 1\n  line 0,0 3,4\n')
        with self.assertRaises(SystemExit):
            picfile.build(os.path.join(d, 'src'), d, os.path.join(d, 'p.inc'))


class SavedStates(unittest.TestCase):
    def test_both_snapshots_round_trip(self):
        b = helpers.build()
        syms = os.path.join(b, 'adventure.syms.csv')
        d = tempfile.mkdtemp()
        for name, base in (('STARTUP', 'adventure_state.bin'), ('SAVED_GAME', 'STARTUP.bin')):
            savefile.extract(os.path.join(b, name + '.bin'), os.path.join(b, base), syms, os.path.join(d, 'x.txt'))
            savefile.build(os.path.join(d, 'x.txt'), os.path.join(b, base), syms, os.path.join(d, 'x.bin'))
            self.assertEqual(read(os.path.join(d, 'x.bin')), read(os.path.join(b, name + '.bin')), name)

    def test_names_resolve(self):
        b = helpers.build()
        base = read(os.path.join(b, 'STARTUP.bin'))
        syms = savefile.symbols(os.path.join(b, 'adventure.syms.csv'))
        self.assertEqual(savefile.resolve('room_no', syms, base), 0x0852)
        self.assertEqual(savefile.resolve('SWITCH+12', syms, base), 0x083A + 12)
        self.assertEqual(savefile.resolve('room 3 RCURPIC', syms, base), 0x0D00 + 30 + 9)
        self.assertEqual(savefile.resolve('object 1 OROOM', syms, base), 0x0900 + 2)


if __name__ == '__main__':
    unittest.main()

"""boot.py: HELLO and MYSTERY.HELLO on the model of the Monitor's text routines, and the
timeline gamedata.json exports from it."""
import json
import os
import tempfile
import unittest

import helpers
import boot


class Monitor(unittest.TestCase):
    def setUp(self):
        self.writes = []
        self.m = boot.Monitor(lambda a, c: self.writes.append((a, c)))

    def row(self, r):
        return ''.join(self.m.mem[boot.text_address(r, c)] for c in range(40)).rstrip()

    def test_rows_are_interleaved(self):
        self.assertEqual([boot.text_address(r) for r in (0, 1, 8, 16, 23)],
                         [0x400, 0x480, 0x428, 0x450, 0x7D0])
        self.assertEqual(boot.text_position(0x7D0 + 5), (23, 5))
        self.assertIsNone(boot.text_position(0x478))      # a screen hole
        self.assertIsNone(boot.text_position(0x800))

    def test_scroll_in_a_window(self):
        self.m.poke(boot.WNDTOP, 20)
        self.m.home()
        for c in 'ONE\rTWO\rTHREE\rFOUR\rFIVE\r':
            self.m.cout(c)
        # the carriage returns after FOUR and FIVE each scroll the four rows
        self.assertEqual([self.row(r) for r in range(20, 24)], ['THREE', 'FOUR', 'FIVE', ''])
        self.assertEqual((self.m.cv, self.m.ch), (23, 0))

    def test_an_empty_window_only_clears_its_top_row(self):
        # HELLO's first window: top = bottom = 7, the cursor on row 6 above it
        self.m.poke(boot.WNDTOP, 7)
        self.m.poke(boot.WNDBTM, 7)
        self.m.cv = 6
        for c in 'AB\r':
            self.m.cout(c)
        self.assertEqual((self.row(6), self.m.cv), ('AB', 6))

    def test_a_window_past_column_40_spills_into_another_row(self):
        # HOME with WNDLFT = 10 clears 40 bytes from row 8's column 10: the last 10 are row
        # 16's columns 0-9, while row 8's own first columns stay
        for r in (8, 16):
            self.m.write(boot.text_address(r, 3), 'X')
        self.m.poke(boot.WNDLFT, 10)
        self.m.poke(boot.WNDTOP, 8)
        self.m.poke(boot.WNDBTM, 9)
        self.m.home()
        self.assertEqual((self.row(8), self.row(16)), ('   X', ''))

    def test_speed(self):
        self.assertAlmostEqual(boot.wait_ms(210), 5.924)
        self.assertAlmostEqual(boot.wait_ms(250), 0.184)


class Timeline(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.files = os.path.join(helpers.build(), 'files')
        cls.boot = boot.timeline(cls.files)

    def test_hello_ends_with_the_credits(self):
        # the screen just before HELLO's last HOME (line 400): the four lines its animations
        # leave, at the places the text window put them
        screen = self.boot.before_home[-2]
        shown = {r: line.rstrip() for r, line in enumerate(screen) if line.strip()}
        self.assertEqual(shown, {6: '       THE PUBLIC DOMAIN EXCHANGE',
                                 8: '            2074C WALSH AVE.',
                                 9: '          SANTA CLARA, CA 95050',
                                 10: '            (408) 496-0624'})

    def test_the_address_starts_with_the_street_scrolled_away(self):
        # the first time round (window rows 21-22) the carriage return after the second line
        # scrolls the window, so only the city shows
        shown = {r: line.rstrip() for r, line in enumerate(self.boot.before_home[2]) if line.strip()}
        self.assertEqual(shown[21], '          SANTA CLARA, CA 95050')
        self.assertNotIn(20, shown)

    def test_the_notice_wraps_at_40_columns(self):
        notice = [line.rstrip() for line in self.boot.notice]
        self.assertEqual(notice[:4], ['     FROM A GREAT MOMENT IN HISTORY:',
                                      'MYSTERY HOUSE, THE FIRST GRAPHIC',
                                      'ADVENTURE, WAS CREATED IN 1980 BY SIERRA',
                                      'ON-LINE FOUNDERS KEN AND ROBERTA'])
        self.assertEqual(notice[20], 'PLAYED IT.')

    def test_gamedata_has_the_timeline(self):
        out = tempfile.mkdtemp(prefix='mh-boot-')
        helpers.tool('gamedata.py', self.files, out, os.path.join(helpers.build(), 'adventure.syms.csv'))
        with open(os.path.join(out, 'gamedata.json')) as f:
            steps = json.load(f)['boot']
        key = next(i for i, s in enumerate(steps) if s.get('key'))
        # replayed, the text steps make the screen GET waits on, and then the loader starts
        self.assertEqual(boot.replay(steps[:key]), self.boot.notice)
        self.assertEqual(steps[key + 1:], [{'at': 0.0, 'loader': True}])
        times = [s['at'] for s in steps[:key + 1]]
        self.assertEqual(times, sorted(times))
        kinds = [k for s in steps for k in s if k != 'at']
        self.assertEqual(kinds.count('title'), 1)
        title = next(s for s in steps if 'title' in s)
        hgr = next(s for s in steps if 'hgr' in s)
        self.assertLess(hgr['at'], title['at'])


if __name__ == '__main__':
    unittest.main()

"""The bug-fix build (./build.sh --bugfix, the .ifdef BUGFIX blocks in src/adventure.s): the
script in tests/play/bugfix.txt is played on it and on the original, and each documented bug
must be fixed in the one and present in the other (NOTES.md, "Bug-fix build")."""
import csv
import os
import unittest

import helpers
import play  # noqa: E402 (helpers puts tools/ on the path)

SCRIPT = os.path.join(helpers.PLAY, 'bugfix.txt')


def expected(name):
    with open(os.path.join(helpers.PLAY, name)) as f:
        return f.read().splitlines()


def run(build_dir):
    """Play the script; also note where the restore action leaves the action pointer."""
    with open(os.path.join(build_dir, 'adventure.syms.csv')) as f:
        syms = {r['name']: int(r['address'], 16) for r in csv.DictReader(f)}
    restored = []

    def setup(m):
        m.executed = set()               # hooks run only while recording
        m.hooks[syms['AC2600']] = lambda mach: restored.append(None)
        m.hooks[syms['AC9000']] = lambda mach: (restored.append(mach.rw(syms['AWORK']))
                                                if restored and restored[-1] is None else None)

    m, reason = play.play(os.path.join(build_dir, 'files'), play.read_commands(SCRIPT), setup=setup)
    return m, reason, [r for r in restored if r is not None], syms


def reply(m, command, nth=0):
    """The lines the game printed for the nth time a command was typed."""
    starts = [i for i, l in enumerate(m.out) if l == '> ' + command]
    i = starts[nth] + 1
    end = next(j for j in range(i, len(m.out)) if m.out[j].startswith('> '))
    return m.out[i:end]


class BugFix(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.orig = run(helpers.build())
        cls.fixed = run(helpers.build(defines=('BUGFIX',)))

    def test_transcript_and_screens(self):
        m, reason, _, _ = self.fixed
        self.assertEqual(m.out, expected('bugfix.expected.txt'))
        self.assertEqual(m.screens, expected('bugfix.screens.txt'))
        self.assertEqual(reason, 'quit to DOS')

    def test_open_trunk_says_it_is_open(self):
        self.assertEqual(reply(self.orig[0], 'OPEN TRUNK')[0], 'IT IS LOCKED')
        self.assertEqual(reply(self.fixed[0], 'OPEN TRUNK')[0], 'IT IS OPEN')

    def test_storage_room_window_ends_the_game(self):
        self.assertNotIn('WOULD YOU LIKE TO PLAY AGAIN', reply(self.orig[0], 'GO WINDOW'))
        self.assertIn('WOULD YOU LIKE TO PLAY AGAIN', reply(self.fixed[0], 'GO WINDOW'))

    def test_joe_keeps_his_eyes(self):
        # the screen before and after stabbing at Joe without the dagger
        i = play.read_commands(SCRIPT).index('WITH DAGGER')
        orig, fixed = self.orig[0].screens, self.fixed[0].screens
        self.assertNotEqual(orig[i], orig[i + 1])
        self.assertEqual(fixed[i], fixed[i + 1])

    def test_it_stays_dark_after_turn_255(self):
        last = len([c for c in play.read_commands(SCRIPT) if c == 'SLEEP']) - 1
        self.assertNotIn("IT IS DARK, YOU CAN'T SEE", reply(self.orig[0], 'SLEEP', last))
        self.assertIn("IT IS DARK, YOU CAN'T SEE", reply(self.fixed[0], 'SLEEP', last))

    def test_restore_puts_back_the_action_pointer(self):
        # AC2600 saves AWORK (its own action, 6 bytes into the RESTORE GAME rule) across the
        # BLOAD and puts it back; the original writes both bytes into the low byte
        for m, _, restored, syms in (self.orig, self.fixed):
            self.assertEqual(len(restored), 2)
        action = self.fixed[3]['rule_5250'] + 6
        self.assertEqual(self.fixed[2], [action, action])
        self.assertNotEqual(self.orig[2][0], self.orig[3]['rule_5250'] + 6)


if __name__ == '__main__':
    unittest.main()

"""Play the game: every script in tests/play/ must give the recorded text and screens, and
together they must exercise the recorded set of code and rules. This runs the built ADVENTURE
on the 6502 in tools/play.py, so it checks the engine, the rules, the messages and the pictures
together. Each script is played once per test run (helpers.played) and shared with the other
tests.

When a change is meant to alter what the game does, regenerate the expected files (the
commands are in tests/play/README.md) and check the difference."""
import os
import unittest

import helpers
import gamecov  # noqa: E402 (helpers puts tools/ on the path)


def expected(name):
    with open(os.path.join(helpers.PLAY, name)) as f:
        return f.read().splitlines()


class Scripts(unittest.TestCase):
    """Each script's transcript and the hi-res screen at every prompt, as recorded."""

    def check(self, name):
        m, reason, _, _ = helpers.played(name)
        self.assertEqual(m.out, expected(name + '.expected.txt'))
        self.assertEqual(m.screens, expected(name + '.screens.txt'))
        return m, reason

    def test_walkthrough_wins(self):
        m, reason = self.check('walkthrough')
        self.assertIn('CONGRATULATIONS YOU HAVE BEATEN', '\n'.join(m.out))
        self.assertEqual(reason, 'quit to DOS')

    def test_unknown_words(self):
        # each reply copies the typed word into a message template inside read_command
        self.check('errors')

    def test_house(self):
        m, reason = self.check('house')
        self.assertEqual(reason, 'quit to DOS')

    def test_deaths(self):
        m, reason = self.check('deaths')
        # 12 deaths that end the game and 4 QUITs; the storage-room window kills you without
        # asking (a bug in the rule), and the script ends with the rude word
        self.assertEqual(m.out.count('WOULD YOU LIKE TO PLAY AGAIN'), 16)
        self.assertEqual(reason, 'quit to DOS')


class Coverage(unittest.TestCase):
    """What the scripts exercise together (tools/gamecov.py): everything not listed in
    tests/play/coverage.expected.txt runs, and the listed code and rules are the ones that cannot
    (NOTES.md, "Test coverage"). A new script that reaches more, or a change that loses some,
    shows up here."""

    def test_report(self):
        executed, ran = set(), set()
        for name in helpers.SCRIPTS:
            _, _, e, r = helpers.played(name)
            executed |= e
            ran |= r
        rules = os.path.join(helpers.ROOT, 'assets', 'text', 'rules.txt')
        report = gamecov.report(helpers.build(), executed, ran, rules)
        self.assertEqual(report.splitlines(), expected('coverage.expected.txt'))


if __name__ == '__main__':
    unittest.main()

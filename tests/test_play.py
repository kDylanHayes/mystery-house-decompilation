"""Play the game: the walkthrough in tests/play/ must win, with the same text and the same
screens as recorded. This runs the built ADVENTURE on the 6502 in tools/play.py, so it checks
the engine, the rules, the messages and the pictures together."""
import os
import unittest

import helpers
import play

HERE = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'play')


def commands(name):
    with open(os.path.join(HERE, name)) as f:
        lines = [l.split('#')[0].strip() for l in f]
    return [l for l in lines if l]


def expected(name):
    with open(os.path.join(HERE, name)) as f:
        return f.read().splitlines()


class Walkthrough(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.m, cls.reason = play.play(os.path.join(helpers.build(), 'files'), commands('walkthrough.txt'))

    def test_the_game_is_won(self):
        text = '\n'.join(self.m.out)
        self.assertIn('CONGRATULATIONS YOU HAVE BEATEN', text)
        self.assertEqual(self.reason, 'quit to DOS')

    def test_the_transcript_is_unchanged(self):
        self.assertEqual(self.m.out, expected('walkthrough.expected.txt'))

    def test_the_screens_are_unchanged(self):
        self.assertEqual(self.m.screens, expected('walkthrough.screens.txt'))


class UnknownWords(unittest.TestCase):
    """Words the game does not know: the replies are built by patching the word into a message
    template inside the code, and must come out as recorded."""

    def test_replies(self):
        m, reason = play.play(os.path.join(helpers.build(), 'files'), commands('errors.txt'))
        self.assertEqual(m.out, expected('errors.expected.txt'))
        self.assertEqual(m.screens, expected('errors.screens.txt'))


if __name__ == '__main__':
    unittest.main()

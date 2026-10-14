"""The BASIC tokenizer and lister."""
import os
import tempfile
import unittest

import helpers
import basic

TOK = {w: 0x80 + i for i, w in enumerate(basic.APPLESOFT)}


class Crunch(unittest.TestCase):
    def test_keywords_and_spaces(self):
        self.assertEqual(basic.crunch('PRINT A'), bytes([TOK['PRINT'], ord('A')]))

    def test_keywords_found_across_spaces(self):
        # Applesoft ignores spaces while matching keywords: H O M E is HOME
        self.assertEqual(basic.crunch('H O M E'), bytes([TOK['HOME']]))

    def test_strings_are_literal(self):
        self.assertEqual(basic.crunch('PRINT "HOME  IS"'),
                         bytes([TOK['PRINT']]) + b'"HOME  IS"')

    def test_rem_is_literal(self):
        self.assertEqual(basic.crunch('REM  PRINT IT'), bytes([TOK['REM']]) + b'  PRINT IT')

    def test_data_is_literal_up_to_a_colon(self):
        self.assertEqual(basic.crunch('DATA PRINT, 2:PRINT'),
                         bytes([TOK['DATA']]) + b' PRINT, 2:' + bytes([TOK['PRINT']]))

    def test_question_mark_is_print(self):
        self.assertEqual(basic.crunch('?1'), bytes([TOK['PRINT'], ord('1')]))

    def test_atn_is_not_at(self):
        self.assertEqual(basic.crunch('X=ATN(1)'),
                         b'X' + bytes([TOK['='], TOK['ATN']]) + b'(1)')

    def test_keyword_inside_a_name_is_tokenized_like_an_apple_ii(self):
        # SCORE contains OR: Applesoft tokenizes it, which is why such names are avoided
        self.assertIn(TOK['OR'], basic.crunch('SCORE=1'))


class Programs(unittest.TestCase):
    def test_every_program_lists_back_to_its_source(self):
        for name in ('HELLO.bas', 'MYSTERY.HELLO.bas', 'PIC_SIZES.bas', 'APPLESOFT.int'):
            path = os.path.join(helpers.SRC, 'basic', name)
            lines, extra = basic.read_source(path)
            build = basic.build_integer if name.endswith('.int') else basic.build_applesoft
            data = build(lines, extra)
            listed, _ = (basic.list_integer if name.endswith('.int') else basic.list_applesoft)(data)
            self.assertEqual(listed, ['%d %s' % l for l in lines], name)

    def test_applesoft_line_links_assume_0801(self):
        data = basic.build_applesoft([(10, 'END'), (20, 'END')], b'')
        self.assertEqual(data[:2], bytes([0x07, 0x08]))       # $0801 + 6 bytes
        self.assertEqual(data[-2:], b'\x00\x00')

    def test_integer_basic_subset(self):
        lines = [(10, 'PRINT "HI"'), (20, 'END')]
        data = basic.build_integer(lines, b'')
        self.assertEqual(basic.list_integer(data)[0], ['10 PRINT "HI"', '20 END'])
        with self.assertRaises(SystemExit):
            basic.build_integer([(10, 'GOTO 10')], b'')


if __name__ == '__main__':
    unittest.main()

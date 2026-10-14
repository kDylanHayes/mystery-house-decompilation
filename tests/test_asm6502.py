"""The assembler: addressing modes, expressions, directives and errors."""
import os
import tempfile
import unittest

import helpers  # noqa: F401  (puts tools/ on the path)
import asm6502


def assemble(text, files=None, include_dirs=()):
    d = tempfile.mkdtemp()
    for name, data in (files or {}).items():
        with open(os.path.join(d, name), 'wb' if isinstance(data, bytes) else 'w') as f:
            f.write(data)
    path = os.path.join(d, 'test.s')
    with open(path, 'w') as f:
        f.write(text)
    a = asm6502.Assembler()
    a.include_dirs = list(include_dirs)
    org, data, _ = a.assemble(path)
    return org, data


class AddressingModes(unittest.TestCase):
    def test_zero_page_is_chosen_when_the_value_is_known(self):
        _, b = assemble('zp = $85\n .org $1000\n LDA zp\n LDA zp,X\n LDA (zp),Y\n LDA (zp,X)\n')
        self.assertEqual(b, bytes([0xA5, 0x85, 0xB5, 0x85, 0xB1, 0x85, 0xA1, 0x85]))

    def test_absolute(self):
        _, b = assemble(' .org $1000\n STA $0852\n LDA $0900,Y\n JMP ($0087)\n')
        self.assertEqual(b, bytes([0x8D, 0x52, 0x08, 0xB9, 0x00, 0x09, 0x6C, 0x87, 0x00]))

    def test_forced_absolute(self):
        _, b = assemble('zp = $85\n .org $1000\n LDA a:zp\n STA a:zp,X\n')
        self.assertEqual(b, bytes([0xAD, 0x85, 0x00, 0x9D, 0x85, 0x00]))

    def test_forward_label_is_absolute(self):
        _, b = assemble(' .org $1000\n JSR later\nlater:\n RTS\n')
        self.assertEqual(b, bytes([0x20, 0x03, 0x10, 0x60]))

    def test_implied_accumulator_and_immediate(self):
        _, b = assemble(' .org $1000\n ASL A\n LSR\n LDX #$0A\n TXS\n')
        self.assertEqual(b, bytes([0x0A, 0x4A, 0xA2, 0x0A, 0x9A]))

    def test_branches_both_ways(self):
        _, b = assemble(' .org $1000\nback:\n BNE fwd\n BEQ back\nfwd:\n RTS\n')
        self.assertEqual(b, bytes([0xD0, 0x02, 0xF0, 0xFC, 0x60]))

    def test_local_labels_with_dots(self):
        _, b = assemble(' .org $1000\nf:\nf.loop:\n DEX\n BNE f.loop\n')
        self.assertEqual(b, bytes([0xCA, 0xD0, 0xFD]))


class Expressions(unittest.TestCase):
    def test_low_high_and_arithmetic(self):
        _, b = assemble('T = $0D00\n .org $1000\n LDA #<T\n LDA #>T\n .byte 10*4+2, T/256, $F0|$0F, $FF&$0F\n')
        self.assertEqual(b, bytes([0xA9, 0x00, 0xA9, 0x0D, 42, 0x0D, 0xFF, 0x0F]))

    def test_label_differences(self):
        _, b = assemble(' .org $1000\na:\n .byte b-a\n .word $1234\nb:\n')
        self.assertEqual(b, bytes([3, 0x34, 0x12]))

    def test_characters(self):
        _, b = assemble(" .org $1000\n CMP #'N'|$80\n")
        self.assertEqual(b, bytes([0xC9, 0xCE]))


class Directives(unittest.TestCase):
    def test_hiasc_sets_bit_7_and_escapes(self):
        _, b = assemble(' .org $1000\n .hiasc "OK\\r\\x04"\n .byte "A", 0\n')
        self.assertEqual(b, bytes([0xCF, 0xCB, 0x8D, 0x84, 0x41, 0x00]))

    def test_org_pads_with_zeros(self):
        org, b = assemble(' .org $1000\n .byte 1\n .org $1003\n .byte 2\n')
        self.assertEqual((org, b), (0x1000, bytes([1, 0, 0, 2])))

    def test_incbin_upto_cuts_the_blob(self):
        files = {'blob.bin': bytes(range(10))}
        _, b = assemble(' .org $1000\n .byte $AA\n .incbin "blob.bin", upto $1004\n .org $1004\n .byte $BB\n', files)
        self.assertEqual(b, bytes([0xAA, 0, 1, 2, 0xBB]))
        _, b = assemble(' .org $1000\n .incbin "blob.bin", upto $2000\n', files)
        self.assertEqual(b, bytes(range(10)))

    def test_include_searches_extra_directories(self):
        inc = tempfile.mkdtemp()
        with open(os.path.join(inc, 'gen.inc'), 'w') as f:
            f.write('VALUE = $42\n')
        _, b = assemble(' .include "gen.inc"\n .org $1000\n .byte VALUE\n', include_dirs=[inc])
        self.assertEqual(b, bytes([0x42]))

    def test_comments_do_not_cut_strings(self):
        _, b = assemble(' .org $1000\n .hiasc "A;B"   ; comment\n')
        self.assertEqual(b, bytes([0xC1, 0xBB, 0xC2]))


class Errors(unittest.TestCase):
    def check_error(self, text, words):
        with self.assertRaises(SystemExit) as e:
            assemble(text)
        self.assertIn(words, str(e.exception))

    def test_org_going_backwards(self):
        self.check_error(' .org $1000\n .byte 1,2,3\n .org $1001\n', '.org goes backwards')

    def test_branch_out_of_range(self):
        self.check_error(' .org $1000\n BNE far\n .incbin "x"\nfar:\n', 'cannot find x')
        self.check_error(' .org $1000\n BNE far\n .org $1100\nfar:\n', 'branch out of range')

    def test_undefined_symbol(self):
        self.check_error(' .org $1000\n LDA nowhere\n', 'undefined symbol nowhere')

    def test_mode_that_does_not_exist(self):
        self.check_error(' .org $1000\n STA #$01\n', 'STA has no')


if __name__ == '__main__':
    unittest.main()

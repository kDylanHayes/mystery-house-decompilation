"""The sources are standard ca65: if ca65 and ld65 (cc65 2.18+) are installed, they must build
exactly the same programs as the build's own assembler. Skipped when they are not (CI installs
them)."""
import os
import shutil
import subprocess
import unittest

import helpers


@unittest.skipUnless(shutil.which('ca65') and shutil.which('ld65'), 'ca65/ld65 not installed')
class Ca65(unittest.TestCase):
    def build_with_ca65(self, name, start):
        b = helpers.build()
        o = os.path.join(b, 'ca65')
        os.makedirs(o, exist_ok=True)
        subprocess.run(['ca65', '-I', helpers.SRC, '-I', os.path.join(b, 'gen'), '--bin-include-dir',
                        helpers.SRC, '-o', os.path.join(o, name + '.o'), os.path.join(helpers.SRC, name + '.s')],
                       check=True)
        out = os.path.join(o, name + '.bin')
        subprocess.run(['ld65', '-C', os.path.join(helpers.SRC, 'ld65.cfg'), '-S', start, '-o', out,
                        os.path.join(o, name + '.o')], check=True)
        with open(out, 'rb') as f:
            return f.read()

    def own(self, name):
        with open(os.path.join(helpers.build(), name), 'rb') as f:
            return f.read()

    def test_adventure(self):
        self.assertEqual(self.build_with_ca65('adventure', '0x0800'), self.own('ADVENTURE.bin'))

    def test_autoload(self):
        self.assertEqual(self.build_with_ca65('autoload', '0x0FFD'), self.own('AUTO_LOAD_OBJ.bin'))


if __name__ == '__main__':
    unittest.main()

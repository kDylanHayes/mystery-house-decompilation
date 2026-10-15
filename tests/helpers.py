"""Shared setup for the tests: paths, and a build of every game file into a temporary directory
(the same steps as build.sh, without the assets and Ghidra)."""
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS = os.path.join(ROOT, 'tools')
SRC = os.path.join(ROOT, 'src')
sys.path.insert(0, TOOLS)


def tool(*args):
    """Run a tool and return its stdout; fail the test with its stderr on an error."""
    r = subprocess.run([sys.executable, '-I', os.path.join(TOOLS, args[0])] + list(args[1:]),
                       capture_output=True, text=True)
    if r.returncode:
        raise AssertionError('%s failed:\n%s%s' % (args[0], r.stdout, r.stderr))
    return r.stdout


_built = {}


def build(src=SRC):
    """Build everything from a source tree (once per test run); returns the build directory."""
    if src in _built:
        return _built[src]
    SRC = src
    b = tempfile.mkdtemp(prefix='mh-test-')
    g = os.path.join(b, 'gen')
    os.makedirs(g)
    tool('msgfile.py', 'build', os.path.join(SRC, 'messages.txt'), os.path.join(g, 'MESSAGES.bin'),
         os.path.join(g, 'messages.inc'))
    tool('picfile.py', 'build', os.path.join(SRC, 'pictures'), g, os.path.join(g, 'pictures.inc'))
    for f in ('HELLO', 'MYSTERY.HELLO', 'PIC_SIZES'):
        tool('basic.py', 'build', os.path.join(SRC, 'basic', f + '.bas'), os.path.join(g, f + '.bin'))
    tool('basic.py', 'build', os.path.join(SRC, 'basic', 'APPLESOFT.int'), os.path.join(g, 'APPLESOFT.bin'))
    tool('asm6502.py', '-I', g, os.path.join(SRC, 'adventure.s'), os.path.join(b, 'ADVENTURE.bin'),
         os.path.join(b, 'adventure.lst'), os.path.join(b, 'adventure.syms.csv'))
    tool('asm6502.py', os.path.join(SRC, 'autoload.s'), os.path.join(b, 'AUTO_LOAD_OBJ.bin'))
    tool('diskfiles.py', 'make', b, SRC)
    with open(os.path.join(b, 'put.txt')) as f:
        put = [l.rstrip('\n') for l in f]
    tool('mkdisk.py', 'build', os.path.join(SRC, 'disk'), os.path.join(b, 'mystery_house.do'), *put)
    tool('dos33.py', os.path.join(b, 'mystery_house.do'), os.path.join(b, 'files'))
    _built[src] = b
    return b

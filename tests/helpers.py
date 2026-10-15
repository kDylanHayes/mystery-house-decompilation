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


def build(src=SRC, defines=()):
    """Build everything from a source tree (once per test run), with the names in defines
    given to the assembler (-D, as build.sh --bugfix does); returns the build directory."""
    key = (src, tuple(defines))
    if key in _built:
        return _built[key]
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
    flags = [a for d in defines for a in ('-D', d)]
    tool('asm6502.py', '-I', g, *flags, os.path.join(SRC, 'adventure.s'), os.path.join(b, 'ADVENTURE.bin'),
         os.path.join(b, 'adventure.lst'), os.path.join(b, 'adventure.syms.csv'))
    tool('asm6502.py', os.path.join(SRC, 'autoload.s'), os.path.join(b, 'AUTO_LOAD_OBJ.bin'),
         os.path.join(b, 'autoload.lst'), os.path.join(b, 'autoload.syms.csv'))
    tool('diskfiles.py', 'make', b, SRC)
    with open(os.path.join(b, 'put.txt')) as f:
        put = [l.rstrip('\n') for l in f]
    tool('mkdisk.py', 'build', os.path.join(SRC, 'disk'), os.path.join(b, 'mystery_house.do'), *put)
    tool('dos33.py', os.path.join(b, 'mystery_house.do'), os.path.join(b, 'files'))
    _built[key] = b
    return b


PLAY = os.path.join(ROOT, 'tests', 'play')
SCRIPTS = ['walkthrough', 'errors', 'house', 'deaths', 'intro']    # the scripts in tests/play
BOOT = {'intro'}              # played from the 1987 loader (play.py --boot)
_played = {}
_states = {}


def played(name):
    """Play tests/play/<name>.txt on the build of src/ (once per test run), recording what runs;
    returns (machine, stop reason, executed addresses, addresses of the rules that ran)."""
    if name not in _played:
        import gamecov
        import play
        b = build()
        states = _states[name] = []
        redraws = [0]

        def more(m, syms):
            # at each prompt: was it a command prompt (GETLN), how many times the room has
            # been drawn so far, and the game state ($0800-$10FF: variables, objects, rooms)
            m.hooks[syms['draw_room']] = lambda mach: redraws.__setitem__(0, redraws[0] + 1)
            m.on_prompt = lambda mach: states.append((mach.pc == play.GETLN, redraws[0],
                                                      bytes(mach.mem[0x0800:0x1100])))
        _played[name] = gamecov.play_recorded(b, os.path.join(b, 'files'), os.path.join(PLAY, name + '.txt'), more,
                                              boot=name in BOOT)
    return _played[name]


def prompt_states(name):
    """For each prompt of a played script: (command prompt?, room redraws so far, state bytes
    $0800-$10FF)."""
    played(name)
    return _states[name]

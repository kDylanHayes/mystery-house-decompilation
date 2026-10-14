#!/usr/bin/env python3
"""Make the files the build derives from other built files, list everything for the disk, and
compare a built disk's files with the original's.

usage: diskfiles.py make <build dir> <src dir>
       diskfiles.py compare <built files dir> <original extracted dir>

make expects in <build dir>: ADVENTURE.bin and AUTO_LOAD_OBJ.bin (assembled), gen/MESSAGES.bin
(tools/msgfile.py), gen/BLOCK1-19.bin (tools/picfile.py) and gen/HELLO.bin, MYSTERY.HELLO.bin,
PIC_SIZES.bin, APPLESOFT.bin (tools/basic.py), and the assembler's adventure.syms.csv. It writes:

  BLOCK_DIRECTORY.bin, MESSAGE_OBJECT.bin
                    the disk's copies of ADVENTURE's picture directory ($5300) and message index
                    ($5500), cut from the assembled ADVENTURE (at least the original 304 and 336
                    bytes, longer if the tables grew); the game never reads them
  STARTUP.bin       the state "play again" loads: ADVENTURE's $0830-$10FE with the changes in
                    src/startup.txt (tools/savefile.py)
  SAVED_GAME.bin    the saved game: STARTUP with the changes in src/saved_game.txt
  put.txt           NAME=path lines for mkdisk.py / dos33.py put (a .load file next to each
                    binary holds its load address)

compare prints whether each of the rebuilt files matches the original disk's.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import savefile  # noqa: E402

STATE = 0x08CF    # length of the $0830 snapshots

# disk name, file in the build, load address (None = text or BASIC), name in an extracted dir
FILES = [
    ('ADVENTURE', 'ADVENTURE.bin', 0x0800, 'ADVENTURE.bin'),
    ('AUTO LOAD OBJ', 'AUTO_LOAD_OBJ.bin', 0x0FFD, 'AUTO_LOAD_OBJ.bin'),
    ('MESSAGES', 'gen/MESSAGES.bin', None, 'MESSAGES.txt.bin'),
    ('BLOCK DIRECTORY', 'BLOCK_DIRECTORY.bin', 0x4000, 'BLOCK_DIRECTORY.bin'),
    ('MESSAGE OBJECT', 'MESSAGE_OBJECT.bin', 0x5000, 'MESSAGE_OBJECT.bin'),
    ('STARTUP', 'STARTUP.bin', 0x0830, 'STARTUP.bin'),
    ('SAVED GAME', 'SAVED_GAME.bin', 0x0830, 'SAVED_GAME.bin'),
    ('HELLO', 'gen/HELLO.bin', None, 'HELLO.bas.bin'),
    ('MYSTERY.HELLO', 'gen/MYSTERY.HELLO.bin', None, 'MYSTERY.HELLO.bas.bin'),
    ('PIC SIZES', 'gen/PIC_SIZES.bin', None, 'PIC_SIZES.bas.bin'),
    ('APPLESOFT', 'gen/APPLESOFT.bin', None, 'APPLESOFT.bas.bin'),
] + [('BLOCK%d' % n, 'gen/BLOCK%d.bin' % n, 0x4400, 'BLOCK%d.bin' % n) for n in range(1, 20)]


def make(b, src):
    adv = open(os.path.join(b, 'ADVENTURE.bin'), 'rb').read()

    def entries(inc, kind):
        return sum(1 for l in open(os.path.join(b, 'gen', inc)) if l.strip().startswith(kind))
    dir_len = max(0x130, 3 * entries('pictures.inc', '.byte'))
    idx_len = max(0x150, 2 * entries('messages.inc', '.word'))
    open(os.path.join(b, 'BLOCK_DIRECTORY.bin'), 'wb').write(adv[0x5300 - 0x800:0x5300 - 0x800 + dir_len])
    open(os.path.join(b, 'MESSAGE_OBJECT.bin'), 'wb').write(adv[0x5500 - 0x800:0x5500 - 0x800 + idx_len])
    base = os.path.join(b, 'adventure_state.bin')
    open(base, 'wb').write(adv[0x0830 - 0x800:0x0830 - 0x800 + STATE])
    syms = os.path.join(b, 'adventure.syms.csv')
    savefile.build(os.path.join(src, 'startup.txt'), base, syms, os.path.join(b, 'STARTUP.bin'))
    savefile.build(os.path.join(src, 'saved_game.txt'), os.path.join(b, 'STARTUP.bin'), syms,
                   os.path.join(b, 'SAVED_GAME.bin'))
    with open(os.path.join(b, 'put.txt'), 'w') as put:
        for disk_name, path, load, _ in FILES:
            full = os.path.join(b, path)
            if load is not None:
                open(full + '.load', 'w').write('%04X' % load)
            put.write('%s=%s\n' % (disk_name, os.path.abspath(full)))


def compare(built, orig):
    changed = []
    for disk_name, _, load, name in FILES:
        new = open(os.path.join(built, name), 'rb').read()
        old = open(os.path.join(orig, name), 'rb').read()
        if name.endswith('.txt.bin'):
            # text files are extracted as whole sectors: compare up to the end of the text
            n = old.index(b'\x00') + 1
            same = new[:n] == old[:n] and new.index(b'\x00') + 1 == n
        else:
            same = new == old
        if not same:
            changed.append(disk_name)
    if changed:
        print('changed from the original: %s' % ', '.join(changed))
    else:
        print('all %d files match the original' % len(FILES))


def main():
    if sys.argv[1] == 'make':
        make(sys.argv[2], sys.argv[3])
    elif sys.argv[1] == 'compare':
        compare(sys.argv[2], sys.argv[3])
    else:
        raise SystemExit(__doc__)


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Collect the files the build rebuilds, compare them with the originals, and list them for
dos33.py put.

usage: diskfiles.py <build dir> <extracted dir>

Expects in <build dir>: ADVENTURE.bin and AUTO_LOAD_OBJ.bin (assembled), gen/MESSAGES.bin
(tools/msgfile.py), gen/BLOCK1-19.bin (tools/picfile.py) and the BASIC programs
gen/HELLO.bin, MYSTERY.HELLO.bin, PIC_SIZES.bin, APPLESOFT.bin (tools/basic.py). Writes:

  files/            a copy of <extracted dir> with every rebuilt file in place, for the
                    asset tools (gamedata.py, pictures.py)
  STARTUP.bin       the starting state for "play again": the original's variables, then
                    ADVENTURE's object and room tables
  BLOCK_DIRECTORY.bin, MESSAGE_OBJECT.bin
                    the disk's copies of ADVENTURE's picture directory ($5300, 304 bytes in the
                    original) and message index ($5500, 336 bytes), cut from the assembled
                    ADVENTURE; the game never reads them, but they are kept in step
  put.txt           NAME=path lines for dos33.py put (with a .load file next to each binary)

and prints, per file, whether it matches the original.
"""
import os
import shutil
import sys

# disk name, file in the build, load address (None = text file), extracted name
FILES = [
    ('ADVENTURE', 'ADVENTURE.bin', 0x0800, 'ADVENTURE.bin'),
    ('AUTO LOAD OBJ', 'AUTO_LOAD_OBJ.bin', 0x0FFD, 'AUTO_LOAD_OBJ.bin'),
    ('MESSAGES', 'gen/MESSAGES.bin', None, 'MESSAGES.txt.bin'),
    ('BLOCK DIRECTORY', 'BLOCK_DIRECTORY.bin', 0x4000, 'BLOCK_DIRECTORY.bin'),
    ('MESSAGE OBJECT', 'MESSAGE_OBJECT.bin', 0x5000, 'MESSAGE_OBJECT.bin'),
    ('STARTUP', 'STARTUP.bin', 0x0830, 'STARTUP.bin'),
    ('HELLO', 'gen/HELLO.bin', None, 'HELLO.bas.bin'),
    ('MYSTERY.HELLO', 'gen/MYSTERY.HELLO.bin', None, 'MYSTERY.HELLO.bas.bin'),
    ('PIC SIZES', 'gen/PIC_SIZES.bin', None, 'PIC_SIZES.bas.bin'),
    ('APPLESOFT', 'gen/APPLESOFT.bin', None, 'APPLESOFT.bas.bin'),
] + [('BLOCK%d' % n, 'gen/BLOCK%d.bin' % n, 0x4400, 'BLOCK%d.bin' % n) for n in range(1, 20)]


def main():
    b, ext = sys.argv[1], sys.argv[2]
    adv = open(os.path.join(b, 'ADVENTURE.bin'), 'rb').read()
    # the copies are at least as long as the originals (304 and 336 bytes) and grow with the tables
    def entries(inc, kind):
        return sum(1 for l in open(os.path.join(b, 'gen', inc)) if l.strip().startswith(kind))
    dir_len = max(0x130, 3 * entries('pictures.inc', '.byte'))
    idx_len = max(0x150, 2 * entries('messages.inc', '.word'))
    open(os.path.join(b, 'BLOCK_DIRECTORY.bin'), 'wb').write(adv[0x5300 - 0x800:0x5300 - 0x800 + dir_len])
    open(os.path.join(b, 'MESSAGE_OBJECT.bin'), 'wb').write(adv[0x5500 - 0x800:0x5500 - 0x800 + idx_len])
    # STARTUP is the state "play again" BLOADs ($0830-$10FE): the original's variables
    # ($0830-$08FF, saved mid-game; init_game resets them), then the starting objects, rooms and
    # what follows from the assembled ADVENTURE, so edits to those tables reach a new game too
    st = open(os.path.join(ext, 'STARTUP.bin'), 'rb').read()
    open(os.path.join(b, 'STARTUP.bin'), 'wb').write(
        st[:0x0900 - 0x0830] + adv[0x0900 - 0x0800:0x0830 + len(st) - 0x0800])
    files = os.path.join(b, 'files')
    shutil.rmtree(files, ignore_errors=True)
    shutil.copytree(ext, files)
    changed = []
    with open(os.path.join(b, 'put.txt'), 'w') as put:
        for disk_name, path, load, orig in FILES:
            full = os.path.join(b, path)
            data = open(full, 'rb').read()
            old = open(os.path.join(ext, orig), 'rb').read()
            if orig.endswith('.txt.bin'):
                # the extracted text file is whole sectors: the text, its $00, then the rest
                same = old[:len(data)] == data
            elif load is None:
                same = old == data          # BASIC program
            else:
                same = old == data
                open(full + '.load', 'w').write('%04X' % load)
            if not same:
                changed.append(disk_name)
            shutil.copy(full, os.path.join(files, orig))
            put.write('%s=%s\n' % (disk_name, os.path.abspath(full)))
    if changed:
        print('changed from the original: %s' % ', '.join(changed))
    else:
        print('all %d rebuilt files match the original' % len(FILES))


if __name__ == '__main__':
    main()

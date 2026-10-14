# Working on the source

How the project fits together and how to change the game. For how the engine works, see
[NOTES.md](NOTES.md).

## Build and check

```
./build.sh
```

Needs only python3. The build:

1. builds the `MESSAGES` file from `src/messages.txt` (`tools/msgfile.py`), the 19 `BLOCK`
   picture files from `src/pictures/` (`tools/picfile.py`), with the tables `ADVENTURE` includes
   for them (`build/gen/messages.inc`, `pictures.inc`), and the four BASIC programs from
   `src/basic/` (`tools/basic.py`);
2. assembles `src/adventure.s` and `src/autoload.s` into `build/` with `tools/asm6502.py`;
3. makes the files derived from those (`tools/diskfiles.py`): `BLOCK DIRECTORY` and
   `MESSAGE OBJECT`, the disk's copies of two `ADVENTURE` tables; `STARTUP`, the state "play
   again" loads, and `SAVED GAME`, from `src/startup.txt` and `src/saved_game.txt`
   (`tools/savefile.py`);
4. builds the disk image `build/mystery_house.do` around all 30 files from `src/disk/`
   (`tools/mkdisk.py`: the catalog, the free-space map, each file's sectors, and DOS 3.3 on
   tracks 0-2), and extracts it into `extracted/`; everything DOS reads is as on the original,
   so it boots like the original in an Apple II emulator;
5. checks each file against the original disk's (`disk/FILES.sha256`) and the image against
   `disk/SHA256`, the hash of the clean disk (see `disk/README.md`);
6. regenerates `assets/` (text, pictures, rooms) from the built disk, so edits show up there;
7. if `GHIDRA_INSTALL_DIR` points at Ghidra 12.1.x, regenerates the C pseudocode in `decomp/`.

With unmodified source it must say "all 30 files match the original" and
"build/mystery_house.do: matches disk/SHA256". Keep it that way for any change that is meant
to be a cleanup (renames, comments, constants): those never change the bytes.
`./build.sh --check` turns a mismatch into an error.

## Tests and CI

```
python3 -m unittest discover -s tests
```

`tests/` (standard library only) covers the tools: the assembler's addressing modes,
expressions, directives and errors; the BASIC tokenizer's Applesoft rules and a round trip of
every program; the message, picture and saved-state formats; the full build against the
recorded hashes; and the disk writer (files growing, shrinking, the free-space map).

`.github/workflows/build.yml` runs on every push and pull request: the tests, then
`./build.sh --check`, then a check that the committed generated files (`assets/`,
`extracted/`) are what the source produces (PNGs excepted: their compressed bytes depend on the
zlib version). The built disk is attached to each run as an artifact.

## The source

`src/adventure.s` is the program: variables, data tables and engine, in address order, with
a memory map at the top. `src/messages.txt` and `src/pictures/` are the game's text and
pictures, which live in separate files on the disk, and `src/basic/` the BASIC programs that
start it. `src/game.inc` holds the constants for the data (vocabulary ids
`V_*`/`N_*`, rule opcodes `C_*`/`A_*`, record field offsets, message numbers) and
`src/apple2.inc` the hardware, Monitor and DOS addresses. `src/autoload.s` is the 1987 loader.

Assembler syntax (see `tools/asm6502.py`): `label:`, `name = value`, `.org`, `.byte`, `.word`,
`.hiasc "text"` (Apple II high-bit text), `.incbin` (with `, upto addr` to cut it short so it
fits before a table), `.include` (also searched in `-I` directories), and `a:` to force
absolute addressing. Expressions take `+ - * / & |`, `<` (low byte) and `>` (high byte).

Conventions:

* Names in CAPITALS (`CUROOM`, `ZWORK`, `OBJBASE`, `AC1600`, `RBASEPIC`, ...) are the original
  author's, recovered from the binary. Everything else is named after what it does.
* Local labels are scoped with a dot: `draw_picture.next_point` belongs to `draw_picture`.
* Routines that take operands inline after the `JSR` keep them as `.word` / `.hiasc` lines
  straight after the call (the `rt_*` library, `lookup_word`).
* Tables are pinned with `.org`: the engine loads some table addresses as immediate bytes
  (`LDA #>OBJBASE`), so they must not move. If an edit makes something grow into the next
  table, the assembler stops with ".org goes backwards". Delete lines from the "leftover memory"
  just before that table to make room (or `.incbin` a shorter blob).
* Names and routine comments live only in `src/`. The Ghidra step reads them from the
  assembler's symbol table; `symbols/*.csv` only adds Ghidra data types and register parameters.

## Changing the game

After any change, `./build.sh` makes a new `build/mystery_house.do` to boot in an emulator, and
`assets/` shows the result (`assets/text/rules.txt`, `assets/rooms/`, `assets/pictures/`).

**A rule.** Rules are in `command_rules` (tried in order, first match wins) and `turn_rules`
(all matches run). Each is

```
rule_4538:
        .byte 2, V_OPEN, N_DOOR, rule_4543-rule_4538, 1, 1   ; room, verb, noun, length, #conditions, #actions
        .byte C_SWITCH_EQ, 12, 1                             ; if switch[12] == 1
        .byte A_MESSAGE, 129                                 ; say message 129
```

`ANY` matches any room, verb or noun. The length is computed from the labels, so only the
condition and action counts need updating. The opcodes and their operands are listed in
`src/game.inc` and NOTES.md ("Rules: the game logic").

**An object or room.** One `.byte` line per record in `OBJBASE` / `ROOMBASE`; the field order is
in the comment above each table and in `src/game.inc`. Both tables also reach `STARTUP`, which
is what "play again" reloads.

**A word.** The verb and noun tables are groups of a head word and its synonyms, 8 characters
each, high-bit text. A group's position is its id, so add new groups at the end of a table
(before the `$FF`) and add a matching `V_`/`N_` constant to `src/game.inc`.

**A message.** `src/messages.txt` has one message per line, numbered from 1 in order:

```
2 OK
129 IT IS OPEN
```

Edit the text, or add new numbers at the end and use them from a rule (`A_MESSAGE, 168`). Text
is upper case; quote a message that starts or ends with a space (`167 " "`). Messages 7, 37, 127
and 137 are never shown: `print_message` prints built-in text for those numbers. The build
writes the `MESSAGES` file and the offset table the engine uses (`message_index`) from it.

**A picture.** `src/pictures/blockNN.txt` holds the pictures stored in file `BLOCKNN`, in order;
pictures are numbered across all the blocks. Each `line` row is one polyline:

```
picture 1
  line 14,7 253,7 253,149 13,149 13,7
  line 14,104 253,104
```

A `cont` row carries on from the last point without lifting the pen (long rows are wrapped this
way). The picture area is 255 x 160. Rooms and objects refer to pictures by number
(`RBASEPIC`, `OPIC`, `ORPICSTA`). Add pictures at the end of `block19.txt`: it uses 264 of the
1280 bytes a block may have (a block must fit a $500-byte cache slot).

**Room for more.** Adding messages or pictures makes their tables in `ADVENTURE` longer; the
leftover bytes after them shrink to make room (`.incbin ..., upto`), so no other change is
needed until that space runs out: about 70 more pictures, and about 10 more messages. For more
messages, delete the dead code that follows the message index (`dead_init_tail` to
`dead_disk_error`, about 150 bytes; nothing calls it).

**A BASIC program.** `src/basic/` holds the disk's BASIC programs as listings: `HELLO.bas`
(the start-up credits), `MYSTERY.HELLO.bas` (loads the title and shows the 1987 notice),
`PIC_SIZES.bas` (a developer tool) in Applesoft, and `APPLESOFT.int`, a two-line Integer BASIC
program. Edit them like any BASIC listing; `tools/basic.py` tokenizes them the way Applesoft
does (spaces outside strings are dropped, keywords are found even inside names). The `#extra`
line keeps the byte the original SAVE wrote after each program. The Integer BASIC builder only
knows `PRINT "..."` and `END`.

**The starting state and the saved game.** `src/startup.txt` (what "play again" loads) and
`src/saved_game.txt` (the saved game on the disk) list the bytes that differ from a base: the
assembled `ADVENTURE` for `STARTUP`, and `STARTUP` for the saved game. Each line names what it
changes, by variable name or by object/room number and field:

```
room_no                      = $12
object 13 OROOM              = $FE
```

**The disk.** `src/disk/layout.txt` lists the 30 files with the sectors they occupy; files may
grow or shrink, but adding or removing a file, or a new `BLOCK` file, is not supported.

## Layout

| Path | What | Made by |
|---|---|---|
| `src/` | the source: programs, `messages.txt`, `pictures/`, `basic/`, `startup.txt`, `saved_game.txt`, `disk/` (`src/data/README.md` and `src/disk/README.md` describe the binary pieces) | hand |
| `disk/` | the hashes the build checks: each original file, and the clean disk image | reference |
| `build.sh` | the build | hand |
| `tools/` | the build tools (see `tools/README.md`) | hand |
| `tests/` | tests for the tools and the build | hand |
| `.github/workflows/` | CI: tests, matching build, generated files up to date | hand |
| `ghidra_scripts/` | the Ghidra post-script for the optional pseudocode | hand |
| `programs/` | code-tracing settings for the Ghidra step (see `programs/README.md`) | hand |
| `symbols/` | Ghidra data types and register parameters (see `symbols/README.md`) | hand |
| `original_source/` | the 1980 source fragments found in the binary (an archive) | once |
| `extracted/` | every file from the built disk; BASIC listed as text | build |
| `assets/` | game text, pictures, rooms, shapes, title screens | build |
| `decomp/` | C pseudocode (see `decomp/README.md`) | build, with Ghidra |
| `build/` | built binaries, listings, symbol tables, the disk image (not committed) | build |

## What is public domain

Mystery House, its loader and the BASIC programs were released into the public domain in 1987,
and that is all this project holds. The one exception is DOS 3.3, Apple's operating system on
tracks 0-2 (`src/disk/dos33.bin`), kept as an untouched binary only so the built disk boots; it
is not decompiled. The original disk image also held stale fragments of other, copyrighted
software in its unused sectors; they were dropped, so the build makes a clean disk with its own
hash, and the original image is no longer in the repository. `disk/README.md` explains the
change and records the original's hash.

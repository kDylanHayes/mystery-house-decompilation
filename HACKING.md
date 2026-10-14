# Working on the source

How the project fits together and how to change the game. For how the engine works, see
[NOTES.md](NOTES.md).

## Build and check

```
./build.sh
```

Needs only python3. The build:

1. extracts the original disk (`disk/mystery_house.do`) into `extracted/`;
2. builds the `MESSAGES` file from `src/messages.txt` (`tools/msgfile.py`) and the 19 `BLOCK`
   picture files from `src/pictures/` (`tools/picfile.py`), with the tables `ADVENTURE` includes
   for them (`build/gen/messages.inc`, `pictures.inc`);
3. assembles `src/adventure.s` and `src/autoload.s` into `build/` with `tools/asm6502.py`;
4. checks all 25 rebuilt files against the originals (`tools/diskfiles.py`; this includes
   `BLOCK DIRECTORY` and `MESSAGE OBJECT`, the disk's copies of two `ADVENTURE` tables, and
   `STARTUP`, the starting state "play again" loads, which takes `ADVENTURE`'s object and room
   tables) and
   writes them into a copy of the disk, `build/mystery_house.do`, which boots in any Apple II
   emulator, then reports whether the disk is identical to the original;
5. regenerates `assets/` (text, pictures, rooms) from the built files, so edits show up there,
   and `original_source/` from the original binary;
6. if `GHIDRA_INSTALL_DIR` points at Ghidra 12.1.x, regenerates the C pseudocode in `decomp/`.

With unmodified source it must say "all 25 rebuilt files match the original" and "identical to
the original disk". Keep it that way for any change that is meant to be a cleanup (renames, comments,
constants): those never change the bytes.

## The source

`src/adventure.s` is the program: variables, data tables and engine, in address order, with
a memory map at the top. `src/messages.txt` and `src/pictures/` are the game's text and
pictures, which live in separate files on the disk. `src/game.inc` holds the constants for the data (vocabulary ids
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
`src/game.inc` and NOTES.md ("Rules: the game logic"); `assets/text/rules.txt` shows every
rule in plain words after a build.

**An object or room.** One `.byte` line per record in `OBJBASE` / `ROOMBASE`; the field order is
in the comment above each table and in `src/game.inc`. The build copies both tables into
`STARTUP` too, which is what "play again" reloads.

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
way). The picture area is 255 x 160. Add pictures at the end of `block19.txt` (it uses 264 of
the 1280 bytes a block may have: each block must fit a $500-byte cache slot). New block files
are not supported: the disk writer only replaces files that are already on the disk. `assets/pictures/` shows every picture after a build. Rooms and
objects refer to pictures by number (`RBASEPIC`, `OPIC`, `ORPICSTA`).

Adding messages or pictures makes their tables in `ADVENTURE` longer; the leftover bytes after
them shrink to make room (`.incbin ..., upto`), so no other change is needed until that space
runs out: about 70 more pictures, and about 10 more messages. For more messages, delete the
dead code that follows the message index (`dead_init_tail` to `dead_disk_error`, about 150
bytes; nothing calls it).

## Layout

| Path | What | Made by |
|---|---|---|
| `src/` | the source: programs, `messages.txt`, `pictures/` (see `src/data/README.md` for the binary pieces) | hand |
| `disk/` | the original disk image and its SHA-256 | input |
| `build.sh` | the build | hand |
| `tools/` | the build tools (see `tools/README.md`) | hand |
| `ghidra_scripts/` | the Ghidra post-script for the optional pseudocode | hand |
| `programs/` | code-tracing settings for the Ghidra step (see `programs/README.md`) | hand |
| `symbols/` | Ghidra data types and register parameters (see `symbols/README.md`) | hand |
| `original_source/` | the 1980 source fragments found in the binary | build |
| `extracted/` | every file from the original disk | build |
| `assets/` | game text, pictures, rooms, shapes, title screens | build |
| `decomp/` | C pseudocode (see `decomp/README.md`) | build, with Ghidra |
| `build/` | built binaries, listings, symbol tables, the disk image (not committed) | build |

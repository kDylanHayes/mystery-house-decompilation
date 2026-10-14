# Working on the source

How the project fits together and how to change the game. For how the engine works, see
[NOTES.md](NOTES.md).

## Build and check

```
./build.sh
```

Needs only python3. The build:

1. extracts the original disk (`disk/mystery_house.do`) into `extracted/`;
2. assembles `src/adventure.s` and `src/autoload.s` into `build/` with `tools/asm6502.py`
   and reports whether each matches the original file;
3. writes both into a copy of the disk, `build/mystery_house.do`, which boots in any Apple II
   emulator, and reports whether the disk is identical to the original;
4. regenerates `assets/` (text, pictures, rooms) from the built files, so edits to the tables
   show up there, and `original_source/` from the original binary;
5. if `GHIDRA_INSTALL_DIR` points at Ghidra 12.1.x, regenerates the C pseudocode in `decomp/`.

With unmodified source it must say "matches the original" twice and "identical to the original
disk". Keep it that way for any change that is meant to be a cleanup (renames, comments,
constants): those never change the bytes.

## The source

`src/adventure.s` is the whole game: variables, data tables and engine, in address order, with
a memory map at the top. `src/game.inc` holds the constants for the data (vocabulary ids
`V_*`/`N_*`, rule opcodes `C_*`/`A_*`, record field offsets, message numbers) and
`src/apple2.inc` the hardware, Monitor and DOS addresses. `src/autoload.s` is the 1987 loader.

Assembler syntax (see `tools/asm6502.py`): `label:`, `name = value`, `.org`, `.byte`, `.word`,
`.hiasc "text"` (Apple II high-bit text), `.incbin`, `.include`, and `a:` to force absolute
addressing. Expressions take `+ - * / & |`, `<` (low byte) and `>` (high byte).

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
in the comment above each table and in `src/game.inc`.

**A word.** The verb and noun tables are groups of a head word and its synonyms, 8 characters
each, high-bit text. A group's position is its id, so add new groups at the end of a table
(before the `$FF`) and add a matching `V_`/`N_` constant to `src/game.inc`.

**Messages and pictures** live in other files on the disk (`MESSAGES`, `BLOCK1`-`BLOCK19`) and
the build copies them from the original disk unchanged; there is no tool yet to rebuild them.
The engine finds message *n* through `message_index` and picture *n* through
`picture_directory`.

## Layout

| Path | What | Made by |
|---|---|---|
| `src/` | the source (see `src/data/README.md` for the binary pieces) | hand |
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

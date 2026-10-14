# Mystery House decompilation

Decompilation of *Hi-Res Adventure #1: Mystery House* (Apple II, 1980; public domain since 1987).
README.md covers the layout, NOTES.md explains how the engine works.

## Build

`./build.sh` needs only python3. It builds the messages, pictures and programs from `src/`, checks all 25 files against the originals,
writes `build/mystery_house.do` (bootable) and regenerates `assets/` and `extracted/`. Run it after
every change; for unmodified source it must report "all 25 rebuilt files match the original" and
"identical to the original disk".

Ghidra (optional): with `GHIDRA_INSTALL_DIR=/path/to/ghidra_12.1.x` the
build also regenerates the C pseudocode in `decomp/*.c`.

## Where things live

- `src/adventure.s`, `src/autoload.s`, `src/messages.txt`, `src/pictures/`: the source of truth
  (programs, text, pictures). Edit these, not generated files.
- `src/game.inc`: verb/noun/condition/action constants used by the rule tables.
- Names and routine comments live only in `src/`. Rename or document there; the Ghidra step takes
  them from the assembler's symbol table. `symbols/*.csv` only adds Ghidra data types and register
  parameters (`func:X`); its name column is informational.
- Local labels are scoped with a dot (`draw_picture.next_point`). Every label has a name; keep it
  that way.
- HACKING.md is the guide to the source, the build and editing the game; each folder has a
  README.md. Update them when something they describe changes.
- `tools/gen_source.py` produced `src/` once from the original binary; don't rerun it over
  hand edits.
- `original_source/`: the author's 1980 source fragments found in the binary (decoded + raw
  tokenized bytes), regenerated from the original disk; keep it.
- Generated, don't hand-edit: `assets/`, `extracted/`, `decomp/`, `build/` (ignored).

## Conventions

- The engine passes operands inline after `JSR` (the `rt_*` macro library at `$7600`); the
  tracer and the source keep those as `.word` / `.hiasc` lines after the call.
- Tables are pinned with `.org` because the engine loads their addresses as immediates. If an edit
  overflows into the next table, delete lines from the "leftover memory" just before it.
- Names in CAPITALS (`CUROOM`, `ZWORK`, `AC1600`, ...) are the original author's, recovered from
  the binary; keep them.

# Mystery House decompilation

Decompilation of *Hi-Res Adventure #1: Mystery House* (Apple II, 1980; public domain since 1987).
README.md covers the layout, NOTES.md explains how the engine works.

## Build

`./build.sh` needs only python3. It builds every file of the game and the disk image
(`build/mystery_house.do`) from `src/`, checks each file against the original's hash
(`disk/FILES.sha256`) and the image against `disk/SHA256`, and regenerates `assets/` and
`extracted/`. Run it after every change; for unmodified source it must report "all 30 files
match the original" and "build/mystery_house.do: matches disk/SHA256". The disk is the clean one
(no stale third-party data; see `disk/README.md`), so its hash differs from the TOSEC original's.

`./build.sh --check` fails unless everything matches (CI runs it). Run the tests with
`python3 -m unittest discover -s tests`; add tests when a tool gains a feature or a bug is fixed. The play-through test
(`tests/test_play.py`) plays the solution on the emulated game; `tools/play.py` plays any
command script against the built game, which is the way to check a change to the engine or the
rules.

Ghidra (optional): with `GHIDRA_INSTALL_DIR=/path/to/ghidra_12.1.x` the
build also regenerates the C pseudocode in `decomp/*.c`.

## Where things live

- Everything in `src/` is the source of truth: the programs (`*.s`), `messages.txt`,
  `pictures/`, `basic/`, `startup.txt`, `saved_game.txt` and `disk/` (layout, DOS 3.3 binary,
  DOS 3.3 kept as an untouched binary). Keep only public-domain material in the repo: no
original disk image, no residue. Edit these, not generated files.
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
  tokenized bytes), recovered from the original disk; it is an archive and the build does not
  touch it; keep it.
- Generated, don't hand-edit: `assets/`, `extracted/`, `decomp/`, `build/` (ignored).

Licence: the game is public domain (1987 release); the project's own work is under the
Unlicense (`LICENSE`); DOS 3.3 (`src/disk/dos33.bin`) is Apple's and excluded.

## Conventions

- The engine passes operands inline after `JSR` (the `rt_*` macro library at `$7600`); the
  tracer and the source keep those as `.word` / `.hiasc` lines after the call.
- The source is shiftable: always refer to addresses by name (`.word label`, `#<label`), never
  as numbers. Only `$0800`, `OBJBASE`, `ROOMBASE` and `$2000` are pinned. `tests/test_shift.py`
  pads the source and replays the game; it fails if anything still depends on a fixed address.
- Names in CAPITALS (`CUROOM`, `ZWORK`, `AC1600`, ...) are the original author's, recovered from
  the binary; keep them.

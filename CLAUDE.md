# Mystery House decompilation

Decompilation of *Hi-Res Adventure #1: Mystery House* (Apple II, 1980; public domain since 1987).
README.md covers the layout, NOTES.md explains how the engine works.

## Build

`./build.sh` needs only python3. It assembles `src/*.s`, checks the binaries against the originals,
writes `build/mystery_house.do` (bootable) and regenerates `assets/` and `extracted/`. Run it after
every change; for unmodified source it must report "matches the original" for both programs and
"identical to the original disk".

Ghidra (optional): with `GHIDRA_INSTALL_DIR=/path/to/ghidra_12.1.x` the
build also regenerates the C pseudocode in `decomp/*.c`.

## Where things live

- `src/adventure.s`, `src/autoload.s`: the source of truth. Edit these, not generated files.
- `src/game.inc`: verb/noun/condition/action constants used by the rule tables.
- `symbols/*.csv`: names, types and comments for the Ghidra pseudocode. They duplicate the names in
  `src/`, so a rename needs both.
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

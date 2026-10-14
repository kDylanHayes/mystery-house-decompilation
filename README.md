# Mystery House decompilation

A decompilation of *Hi-Res Adventure #1: Mystery House* (Ken and Roberta Williams, On-Line
Systems, 1980) for the Apple II, from the 1987 public-domain release. It covers the 6502 code
and the whole game: every room, object, word, message, rule and picture.

![The front yard](assets/rooms/room_01.png)

See [NOTES.md](NOTES.md) for how the engine works.

## What's here

| Path | Contents |
|---|---|
| `decomp/adventure.c` | Ghidra pseudocode for the game engine, every function named |
| `src/adventure.s`, `src/autoload.s` | **reassemblable source**, byte-identical to the originals |
| `decomp/autoload.c` | the 1987 loader / instructions program (`AUTO LOAD OBJ`) |
| `original_source/` | 313 lines of the **original 1980 source**, recovered from stale memory inside the binary: decoded (`fragments.s`) and the raw tokenized bytes (`raw/`) |
| `extracted/APPLESOFT.bas` etc. | the disk's BASIC programs listed as text |
| `assets/text/rules.txt` | the game logic: all 358 rules decompiled to readable pseudocode |
| `assets/text/rooms.txt`, `objects.txt`, `vocabulary.txt`, `messages.txt` | the game database |
| `assets/text/gamedata.json` | all of the above, machine-readable |
| `assets/pictures/` | all 97 vector pictures as PNG and SVG |
| `assets/rooms/` | each of the 41 rooms as first seen, with its objects |
| `assets/shapes/` | the 6 Applesoft shapes |
| `assets/screens/` | the 1980 and 1987 title screens |
| `extracted/` | every file from the disk (binaries without headers, BASIC listed as text) |
| `symbols/` | names, types and comments applied to the decompilation |
| `programs/` | load address, entry points and jump tables for each binary |
| `tools/`, `ghidra_scripts/` | the pipeline |

<p>
<img src="assets/screens/title_1980.png" width="45%"> <img src="assets/screens/title_1987.png" width="45%">
</p>
<p>
<img src="assets/rooms/room_03.png" width="45%"> <img src="assets/rooms/room_04.png" width="45%">
</p>

## Building

```
./build.sh
```

Needs only python3. `src/adventure.s` and `src/autoload.s` are the source of truth: the build
assembles them with `tools/asm6502.py`, checks the binaries against the originals, writes them
into a copy of the disk (`build/mystery_house.do`, bootable, identical to the original when the
source is unmodified) and regenerates `assets/` from the result.

Editing: rules, objects, rooms and vocabulary are written out structurally in `src/adventure.s`
with named constants (`src/game.inc`); rule and object lengths are computed from labels. Tables
are pinned with `.org` because the engine refers to some of them by immediate address; if an edit
grows into the next table the assembler stops with ".org goes backwards" - delete lines from the
"leftover memory" just before it to make room.

Optional: with `GHIDRA_INSTALL_DIR` set to Ghidra 12.1.x the build also regenerates the C
pseudocode in `decomp/` (from `symbols/*.csv`, which carry the same names as `src/`).
`tools/gen_source.py` is the one-time generator that produced `src/` from the original binary.

## Source

The disk image is the TOSEC dump
*Hi-Res Adventure 1 - Mystery House (1980)(On-Line Systems)(PD).do*. Sierra On-Line released
the game into the public domain in 1987.

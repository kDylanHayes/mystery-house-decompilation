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
| `decomp/adventure.s` | annotated disassembly of `ADVENTURE` (code, inline operands, tables) |
| `decomp/autoload.c`, `.s` | the 1987 loader / instructions program (`AUTO LOAD OBJ`) |
| `decomp/source_fragments.s` | 313 lines of the **original 1980 source**, recovered from stale memory inside the binary |
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

Everything under `decomp/`, `assets/` and `extracted/` is generated from the disk image:

```
GHIDRA_INSTALL_DIR=/path/to/ghidra_12.1.x ./build.sh [disk/mystery_house.do]
```

It needs python3 (standard library only), a JDK 21+ and Ghidra 12.1.x. The disk image is checked
against `disk/SHA256`.

1. `tools/dos33.py` extracts the DOS 3.3 disk and lists the BASIC programs.
2. `tools/gamedata.py` decodes the game database and the rule scripts.
3. `tools/pictures.py` renders the pictures, shapes, rooms and title screens.
4. `tools/source_fragments.py` recovers the original source fragments.
5. `tools/trace6502.py` finds the code by recursive descent. The engine passes operands inline
   after `JSR` (see NOTES.md), which ordinary auto-analysis gets wrong, so the tracer works out
   which bytes are code and writes a plan.
6. `ghidra_scripts/MysteryHouse.java` disassembles exactly that plan in Ghidra, applies
   `symbols/`, and exports the pseudocode with the inline operands shown as call arguments
   (`rt_print("ENTER COMMAND")`, `lookup_word(&verb_table)`).

To rename something, edit `symbols/*.csv` and rebuild.

## Source

The disk image is the TOSEC dump
*Hi-Res Adventure 1 - Mystery House (1980)(On-Line Systems)(PD).do*. Sierra On-Line released
the game into the public domain in 1987.

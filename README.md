# Mystery House decompilation

A complete decompilation of *Hi-Res Adventure #1: Mystery House* (Ken and Roberta Williams,
On-Line Systems, 1980) for the Apple II, from the 1987 public-domain release: assembler source
that rebuilds the original files byte for byte, every routine named and documented, and the
whole game database (rooms, objects, words, messages, rules and pictures) decoded.

![The front yard](assets/rooms/room_01.png)

```
./build.sh
```

Needs only python3. It builds every file of the game from source (the programs, the messages
and the pictures), checks them against the originals, writes a bootable disk
(`build/mystery_house.do`) and regenerates the assets.

## Documentation

* [HACKING.md](HACKING.md): the source, the build, and how to change the game
* [NOTES.md](NOTES.md): how the engine works: the rule interpreter, data formats, graphics,
  messages, the original source found in the binary, bugs and leftovers
* a README.md in each folder: [`src/data`](src/data/README.md), [`tools`](tools/README.md),
  [`programs`](programs/README.md), [`symbols`](symbols/README.md),
  [`decomp`](decomp/README.md), [`original_source`](original_source/README.md),
  [`disk`](disk/README.md)

## What's here

| Path | Contents |
|---|---|
| `src/adventure.s` | the game: engine and data, **reassemblable**, byte-identical to `ADVENTURE` |
| `src/autoload.s` | the 1987 loader and instructions (`AUTO LOAD OBJ`) |
| `src/messages.txt` | the game's 167 messages, one per line; builds the `MESSAGES` file |
| `src/pictures/` | the 97 pictures as editable point lists; build the `BLOCK1`-`BLOCK19` files |
| `src/game.inc`, `src/apple2.inc` | named constants: vocabulary, rule opcodes, record layouts; hardware and ROM |
| `original_source/` | 313 lines of the **original 1980 source**, recovered from stale memory inside the binary |
| `assets/text/rules.txt` | the game logic: all 358 rules in plain words |
| `assets/text/` | rooms, objects, vocabulary, messages; `gamedata.json` has all of it |
| `assets/pictures/` | the 97 vector pictures as PNG and SVG |
| `assets/rooms/` | each of the 41 rooms as first seen, with its objects |
| `assets/shapes/`, `assets/screens/` | the 6 shapes; the 1980 and 1987 title screens |
| `decomp/` | C pseudocode from Ghidra, for reading (optional build step) |
| `extracted/` | every file from the disk; BASIC programs listed as text |

<p>
<img src="assets/screens/title_1980.png" width="45%"> <img src="assets/screens/title_1987.png" width="45%">
</p>
<p>
<img src="assets/rooms/room_03.png" width="45%"> <img src="assets/rooms/room_04.png" width="45%">
</p>

## Source

The disk image is the TOSEC dump
*Hi-Res Adventure 1 - Mystery House (1980)(On-Line Systems)(PD).do*. Sierra On-Line released
the game into the public domain in 1987.

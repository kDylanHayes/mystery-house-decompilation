# tools

Everything is python3 with the standard library only. Each script's docstring has the details.

| Tool | Used by | Does |
|---|---|---|
| `asm6502.py` | build | the 6502 assembler for `src/`; also writes a listing and the symbol table |
| `msgfile.py` | build | builds the `MESSAGES` file and the message index from `src/messages.txt` (`extract` made the source) |
| `picfile.py` | build | builds `BLOCK1`-`BLOCK19` and the picture directory from `src/pictures/` (`extract` made the source) |
| `basic.py` | build | tokenizes the BASIC programs in `src/basic/` (Applesoft, and the Integer BASIC subset the disk uses); `list` made the sources |
| `savefile.py` | build | builds `STARTUP` and `SAVED GAME` from `src/startup.txt` and `src/saved_game.txt` (changes to a base image) |
| `diskfiles.py` | build | makes the files derived from other built files (table copies, `STARTUP`, `SAVED GAME`) and the list for the disk; `verify` checks a built disk's files against `disk/FILES.sha256` (`hashes` recorded those from the original) |
| `mkdisk.py` | build | builds the disk image from `src/disk/` and the built files; `extract` made `src/disk/` (and can write a `residue.bin` to reproduce an original image exactly; the project has none) |
| `dos33.py` | build | extracts a DOS 3.3 disk (lists BASIC as text), and `put` writes binary, text and BASIC files back into one (keeping each file's sectors, as DOS does) |
| `gamedata.py` | build | decodes the game database (vocabulary, rooms, objects, messages, rules) into `assets/text/` |
| `pictures.py` | build | renders the pictures, shapes, rooms and title screens into `assets/` |
| `source_fragments.py` | once | recovered the original source fragments into `original_source/` |
| `play.py` | tests | plays the built game on a 6502 emulator with scripted commands (no ROMs needed): transcript, screens |
| `trace6502.py` | Ghidra step | finds the code in a binary (inline operands, jump tables) and writes a plan for Ghidra |
| `ghidra_symbols.py` | Ghidra step | merges the assembler's names and comments with `symbols/*.csv` for Ghidra |
| `gen_source.py` | once | generated the first version of `src/` from the original binaries. Kept for reference; running it again would overwrite the hand-edited source |

`ghidra_scripts/MysteryHouse.java` is the Ghidra post-script: it disassembles exactly what the
tracer found, applies the symbols and exports the pseudocode to `decomp/`.

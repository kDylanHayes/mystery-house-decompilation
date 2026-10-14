# tools

Everything is python3 with the standard library only. Each script's docstring has the details.

| Tool | Used by | Does |
|---|---|---|
| `asm6502.py` | build | the 6502 assembler for `src/`; also writes a listing and the symbol table |
| `msgfile.py` | build | builds the `MESSAGES` file and the message index from `src/messages.txt` (`extract` made the source) |
| `picfile.py` | build | builds `BLOCK1`-`BLOCK19` and the picture directory from `src/pictures/` (`extract` made the source) |
| `basic.py` | build | tokenizes the BASIC programs in `src/basic/` (Applesoft, and the Integer BASIC subset the disk uses); `list` made the sources |
| `diskfiles.py` | build | collects the rebuilt files, cuts the two table copies from `ADVENTURE`, builds `STARTUP` (the "play again" state) with `ADVENTURE`'s object and room tables, compares everything with the originals |
| `dos33.py` | build | extracts a DOS 3.3 disk (lists BASIC as text), and `put` writes binary, text and BASIC files back into one (keeping each file's sectors, as DOS does) |
| `gamedata.py` | build | decodes the game database (vocabulary, rooms, objects, messages, rules) into `assets/text/` |
| `pictures.py` | build | renders the pictures, shapes, rooms and title screens into `assets/` |
| `source_fragments.py` | build | recovers the original source fragments into `original_source/` |
| `trace6502.py` | Ghidra step | finds the code in a binary (inline operands, jump tables) and writes a plan for Ghidra |
| `ghidra_symbols.py` | Ghidra step | merges the assembler's names and comments with `symbols/*.csv` for Ghidra |
| `gen_source.py` | once | generated the first version of `src/` from the original binaries. Kept for reference; running it again would overwrite the hand-edited source |

`ghidra_scripts/MysteryHouse.java` is the Ghidra post-script: it disassembles exactly what the
tracer found, applies the symbols and exports the pseudocode to `decomp/`.

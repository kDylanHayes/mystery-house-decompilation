# src/data

Binary pieces that `src/adventure.s` and `src/autoload.s` include with `.incbin`. None of
them is read by the game's code: they are images, or stale memory that was saved inside the
files in 1980/1987. They are kept so the build reproduces the original files byte for byte.
The "leftover" blobs can be deleted (or shortened) to make room in front of a pinned table.

| File | Address | Contents |
|---|---|---|
| `title_1980.bin` | `$2000-$3FFF` | hi-res page 1 inside ADVENTURE: the original On-Line Systems title screen, on screen while the file loads (`assets/screens/title_1980.png`) |
| `title_1987.bin` | `$2000-$3FFF` | hi-res page 1 inside AUTO LOAD OBJ: the Sierra title screen of the 1987 release (`assets/screens/title_1987.png`) |
| `adventure_0B9D.bin` | `$0B9D-$0CFF` | after the object table: tokenized original source (the action handler table, `.DA AC3100` ...) |
| `adventure_0EA4.bin` | `$0EA4-$16FF` | after the room table: tokenized original source (inventory, AC1410 ...; decoded in `original_source/`) |
| `adventure_1C61.bin` | `$1C61-$1FFF` | after the noun table: tokenized original source (AC2810 ... AC3000) |
| `adventure_4343.bin` | `$4343-$43FF` | after the verb table: part of the assembler's symbol table (AC1300 ... with their addresses) |
| `adventure_4475.bin` | `$4475-$44FF` | after the turn rules: more of the symbol table (AC3000 ...) |
| `adventure_5426.bin` | `$5426-$54FF` | after the picture directory: stale text from an older build (`TAKE`, `ENTER COMMAND`); included `upto $5500`, so it shrinks when pictures are added |
| `adventure_56EC.bin` | `$56EC-$56FF` | fill before the shape table; included `upto $5700`, so it shrinks when messages are added (the message index grows) |
| `adventure_6234.bin` | `$6234-$62FF` | after the disk-error handler: the symbol table entries for the record fields (`OMOVABLE`, `RBASEPIC`, ...) |
| `adventure_5BB9.bin`, `adventure_5E19.bin`, `adventure_6E01.bin`, `adventure_712A.bin`, `adventure_77CC.bin`, `adventure_7A72.bin` | | fill (`00 00 FF FF` repeating) between routines and after the last one |
| `stale_hglin_copy.bin` | `$7956-$79FF` | a leftover partial copy of the Applesoft line routine |
| `autoload_1DCC.bin` | `$1DCC-$1FFF` | in AUTO LOAD OBJ: an older copy of part of the instruction text |

NOTES.md ("Original source", "Dead code and other leftovers") says more about the leftovers.

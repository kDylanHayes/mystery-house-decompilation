# How Mystery House works

Notes from decompiling the 1987 public-domain release of *Hi-Res Adventure #1: Mystery House*
(On-Line Systems, 1980) for the Apple II. Addresses are run-time addresses. Names in CAPITALS
are the author's own, recovered from the binary (see "Original source" below).

## Boot sequence

1. DOS runs `HELLO` (Applesoft): a scrolling credit for The Public Domain Exchange, then
   `RUN MYSTERY.HELLO`.
2. `MYSTERY.HELLO` does `HGR`, `BLOAD AUTO LOAD OBJ` (which covers `$0FFD-$3FFF` and so
   puts the Sierra title picture on hi-res page 1), prints the 1987 public-domain notice and
   `CALL 4093` (`$0FFD`).
3. `AUTO LOAD OBJ` asks *G for game or I for instructions*, shows eight pages of instructions
   if asked, then prints `CTRL-D BRUN ADVENTURE`.
4. `ADVENTURE` loads at `$0800-$7CFF`. Its bytes at `$2000-$3FFF` are hi-res page 1, so the
   original **1980 On-Line Systems title screen** appears while it loads
   (`assets/screens/title_1980.png`). Entry `$0800` resets the stack, points `fake_vartab` at
   `$0800` and jumps to `main` (`$5E00`).

`PIC SIZES` is a leftover developer utility: it BLOADs each `BLOCKn` and prints DOS's
last-BLOAD-length (`$AA60`).

## Main loop (`main`, $5E00)

```
init_game()                    reset state, OPEN MESSAGES, hi-res mixed mode
loop:
  draw_room()                  picture + objects if LAMPSTAT == 0, then the room description
  read_command()               verb and noun numbers, or complain and re-prompt
  run_rules()                  command rules, then turn rules
  nothing()                    an empty hook ($6E00: RTS)
  turns += 1
```

The whole game is one ~4.5 KB engine plus data. Almost everything in the image is data:

| Address | Contents |
|---|---|
| `$0800-$08FF` | variables (the start-up code at `$0800` is overwritten by the HPLOT/DRAW variables) |
| `$0900` | `OBJBASE`: object table |
| `$0D00` | `ROOMBASE`: room table |
| `$1700` | noun table |
| `$2000-$3FFF` | hi-res page 1 |
| `$4000` | verb table |
| `$4400` | turn rules |
| `$4500` | command rules |
| `$5300` | picture directory |
| `$5500` | message index |
| `$5700` | Applesoft shape table |
| `$5A00-$7A71` | the engine |
| `$7D00-$95FF` | picture cache (5 slots, not in the file) |

## The macro library ($7600)

The engine is written in a style that passes operands *inline* after the `JSR`, through a
nine-entry jump table:

| Entry | Name | Operation | Inline operands |
|---|---|---|---|
| `$7600` | `rt_copy` | copy X bytes | `.word src, dst` |
| `$7603` | `rt_add8` | word += X | `.word addr` |
| `$7606` | `rt_add16` | word += word | `.word src, dst` |
| `$7609` | `rt_compare` | compare X bytes at `(AWORK)` with addr; `cmp_result` = 0 if equal | `.word addr` |
| `$760C` | `rt_args` | point `rt_operands` at the caller's operands | |
| `$760F` | `rt_return` | return to the caller's caller, skipping X operand bytes (never returns) | |
| `$7612` | `rt_inc16` | word += 1 | `.word addr` |
| `$7615` | `rt_print` | print inline text | `$00`-terminated |
| `$7618` | `rt_mul8` | `mul_result` = word * X | `.word addr` |

Engine routines can use the same convention by calling `rt_args` and leaving through
`LDX #n / JSR rt_return`; `lookup_word` does (`JSR lookup_word / .word verb_table`).
`tools/trace6502.py` finds such routines automatically. `AUTO LOAD OBJ` has its own copy of the
library at `$1C00`.

## Parser

`get_line` reads a line with the Monitor's GETLN. Pressing RETURN on an empty line flips between
the picture and a full-screen text page so you can review earlier messages. `next_word` takes
the next blank-separated word and keeps its first 8 characters. `lookup_word` walks a word table:

```
group:  word[8]  count  synonym[8] * count       count $00 = no synonyms; $FF ends the table
```

The group number is the word's id. The first word is looked up in the verb table, the second in
the noun table. An unknown word produces `I DONT KNOW HOW TO <word> SOMETHING` (or
`... <verb> A <noun>`) by patching the words into the message text.

## Rooms and objects

Room record (`RTBLSIZ` = 10 bytes, `ROOMBASE + 10 * n`):

| Offset | Name | |
|---|---|---|
| 0 | `RROOMNO` | room number |
| 1 | `RMSG` | description message |
| 2-7 | `RN RS RE RW RU RD` | exits (room numbers, 0 = none) |
| 8 | `RBASEPIC` | the room's permanent view |
| 9 | `RCURPIC` | the view shown now (close-ups via `LOOK x` change it) |

Object record (variable length; `ONEXT` is the record length; `$FF` ends the table):

| Offset | Name | |
|---|---|---|
| 0 | `OBJECTNO` | |
| 1 | | noun number |
| 2 | `OROOM` | room, `$FE` = carried, `$FD` = nowhere |
| 3 | `OPIC` | picture (or shape) number |
| 4 | | 1 = draw with the Applesoft shape table instead of a vector picture |
| 5, 6 | `OXCOORD OYCOORD` | position |
| 7 | `OSTATUS` | `OMOVABLE` 0, `OMOVED` 1, `OFIXED` 2 |
| 8 | `OMSG` | text listed by INVENTORY |
| 9 | `ONEXT` | record length |
| 10 | `ORPICKT` | number of pictures the object appears in |
| 11.. | `ORPICSTA` | those picture numbers |

`draw_objects` draws an object at its own position when the picture on screen is in its
`ORPICSTA` list. An object that has been dropped (`OMOVED`) is instead drawn at the next free
position from `floor_slots` (`$70FF`), and only in the room's permanent view.

## Rules: the game logic

All puzzles are data. A rule is

```
room verb noun length ncond nact  cond...  action...      ($FE in room/verb/noun = any)
```

`run_command_rules` tries the command rules (`$4500`) in order; the first whose header and
conditions match runs its actions and ends the search. If none matches the game says
`I DONT UNDERSTAND WHAT YOU MEAN`. `run_turn_rules` then runs *every* matching turn rule
(`$4400`): match timers, darkness, the winning check.

Conditions (`tbl_conditions`, `$5AB7`):

| Op | Meaning |
|---|---|
| 3 | object X is in room Y |
| 5 | turn > X (only while the turn counter is below 256; see below) |
| 6 | `SWITCH[X]` == Y |
| 9 | the picture on screen is X |
| 10 | object X is drawn as picture Y |

Actions (`tbl_actions`, `$6535`; the handler for action *n* is labelled `AC(n+10)00` in the
original source and every handler leaves through `AC9000` with X = operand bytes used):

| Op | Handler | Meaning |
|---|---|---|
| 1 | AC1100 | `SWITCH[Y] += X` |
| 2 | AC1200 | `SWITCH[Y] -= X` |
| 3 | AC1300 | `SWITCH[X] = Y` |
| 4 | AC1400 | list objects carried |
| 5 | AC1500 | put object X in room Y |
| 6 | AC1600 | move to room X |
| 7 | AC1700 | show picture X |
| 8 | AC1800 | make picture X the room's permanent view |
| 9 | AC1900 | print message X |
| 10, 11 | AC2000, AC2100 | light on / off (`LAMPSTAT`) |
| 12, 14 | AC2200, AC2400 | unused (`BRK`) |
| 13 | AC2300 | quit to DOS |
| 15, 16 | AC2500, AC2600 | save / restore (`BSAVE SAVED GAME,A$830,L$8CF`) |
| 17 | AC2700 | game over: play again? (`BLOAD STARTUP` restores the initial state) |
| 18 | AC2800 | put object X in room Y at (x, y) |
| 19 | AC2900 | object Y is drawn as picture X |
| 20 | AC3000 | back to the permanent view |
| 21-26 | AC3100-AC3600 | go N S E W U D (ends the action list) |
| 27, 28 | AC3700, AC3800 | take / drop the named object |
| 29 | AC3900 | set room X's views to picture Y |

`assets/text/rules.txt` has all 358 rules decompiled. Every rule's length byte agrees with the
operands decoded, which checks the operand counts above.

The 20 `SWITCH` bytes (`$083A`) are the game's flags. A few, from how the rules use them:
`SWITCH[3]` is the lit match's remaining turns (`LIGHT MATCHES` sets it to 4), `SWITCH[12]` the front door, `SWITCH[16]` set
after turn 35 once it is dark.

## Pictures

Pictures are line drawings. `picture_directory` (`$5300 + 3n`) gives each picture's `BLOCKn`
file and byte offset. A picture is a list of byte pairs:

```
x y      continue the line to (x, y)        (HPLOT TO)
00 00    the next point starts a new line   (HPLOT)
FF FF    end
```

`draw_picture` adds the object offset and clamps to 255 x 160 (the bottom four text lines stay
free). Lines are drawn by a relocated copy of the Applesoft hi-res routines (`$6A00-$6DB8`:
HGR, HPOSN, HPLOT, HGLIN, DRAW), which read their arguments from Applesoft-style variables the
engine keeps at `$0800` (`var_x` `$0805`, `var_y` `$080C`, `var_hcolor` `$0815`, `var_shape`
`$081F`). Applesoft's own hi-res variables (`$E0-$EA`) were moved to `$0320-$032A`, and the
copy fixes DRAW's scale at 1: where Applesoft called its variable reader for `SCALE=`, the
3-byte `JSR` became `LDA #$01 / NOP` (the `LDY #$32` before it is left over).

The copy carries more of Applesoft than the game uses. `HPLOT0`, `HLINRL` (a line relative to
0,0), `HFIND` (screen position back to X/Y), `XDRAW0` with its plot step, and the `HCOLOR`/
`BKGND` and `XDRAW` command wrappers are all there and never called; the source names them and
marks them "not called by the game". The tables after `HGLIN` are Applesoft's `MSKTBL` (the
pixel bits, `$6BE3`), a `$1C` constant that `MOVE.UP.OR.DOWN` tests with `BIT` (`$6BEA`), and
the `COS` table `DRAW0` uses (`$6BEB`). `HPOSN` reads `MSKTBL` as `LDA $6AEA,X` with X between
`$F9` and `$FF`, i.e. through an address that lies inside the code before it.

The 19 `BLOCK` files are not loaded at their BSAVE address (`$4400`). `load_picture` keeps a
five-slot cache at `$7D00 $8200 $8700 $8C00 $9100`, evicts the least recently used block, and
loads by patching the digits of `BLOAD BLOCKnn,A$xxxx` in its own code before printing it.

Small objects (the notes, the matches, the welcome mat and a door) use a 6-shape Applesoft shape table at
`$5700`.

## Messages

`print_message` handles four messages itself (`$07`, `$25`, `$7F`, `$89`). For the rest it looks
up the byte offset in `message_index` (`$5500`; the `MESSAGE OBJECT` file is a copy), turns it
into hex in `READ MESSAGES,B$xxxx` (self-modifying again) and reads one line from the `MESSAGES`
text file, which `init_game` OPENs. `word_wrap` breaks the line at 39 columns. A room
description is printed without the short pause that follows other messages.

## Original source

When `ADVENTURE` was saved, memory still held the author's tools:

* **Tokenized source** (`$0880-$2000`, where the room table and nouns don't cover it): the action
  handlers `AC1100`-`AC3000` with comments such as `; MOVE TO ROOM X`,
  `; MULT NEW ROOM # BY ENT SIZE` and `; WOOPEE! WE'VE GOT IT!`. Each line is
  `[len] [opcode token] [mode] operand [$BB comment] $0D`, with labels as a separate 10-byte
  record. `tools/source_fragments.py` recovers it to `original_source/` (decoded text and the raw tokenized bytes).
* **Symbol table** pieces (`$4348`, `$6232`): `AC1300`... with their addresses, and the record
  field names `OMOVABLE OMOVED OFIXED OMSG ONEXT ORPICKT ORPICSTA RROOMNO RMSG RN RS RE RW RU
  RD RBASEPIC RCURPIC RTBLSIZ DRBLK DROFFSE(T)`.

The stale symbol addresses are one byte lower than the shipped handlers (`AC1300` = `$65A7`,
the handler is at `$65A8`), so the source in memory was from a slightly earlier assembly. The
fragments match the shipped code instruction for instruction otherwise. The opcode tokens
(`$CD` LDA, `$D0` STA, `$CB` JSR, `$D8` `.DA`, ...) were identified by lining fragments up
with the assembled code.

## Quirks found along the way

* `cond_turns_gt` fails whenever the turn counter's high byte is non-zero, so every
  "turn > N" condition (darkness, `IT IS GETTING DARK`) stops being true from turn 256.
* `AC2600` (restore game) means to put back the action pointer it saved before the BLOAD, but
  stores both bytes into the low byte (`STA action_ptr` at `$670E` and `$6713`); the high byte
  keeps the value just loaded from the save file.
* Actions 12 and 14 are a bare `BRK`; so are "object not found" in `find_object`, `AC1500`
  and `AC2900` (the source comments it `;UH-OH, KABOOM!`).
* The `ACNEWROM` exit (`go` actions) returns through `stop_actions`, so a movement action
  ends its rule's action list. It also builds the new `CUROOM` from `act_word1` after clearing
  only its high byte: the low byte is never loaded with the room number, so `CUROOM` is wrong
  until `draw_room` rebuilds it from `room_no` at the start of the next turn. The turn rules run
  in between, but none of them reads `CUROOM` after a move.
* `AC2600` also zeroes the picture cache table, so every block is loaded again after a restore.
* `disk_error_handler` (`$6215`) prints its message and then "returns" into `$6232`, the
  OPEN-once flag, because the text's terminator is the byte before it. After `init_game` that
  byte is `$FF`, an undocumented 3-byte opcode on the 6502 that swallows the `RTS`, followed by
  the leftover symbol table; a disk error does not come back cleanly. The older handler kept in
  the dead code (`dead_disk_error`, `$56CE`) has its `RTS` straight after the text, so the bug
  came in when the flag byte was added.
* Verb 33 is `UNLIGHT` with the synonym `OFF`, but `OFF` is verb 32 and is matched first, so
  the synonym can never be reached. `SCORE` (40) and `DONE` (43) are in the dictionary but no
  rule uses them. Verb 39 is a group of four profanities; its only rule prints one line and
  quits to DOS.
* Shapes 1 and 5 in the shape table are never used. `hgr_collisions` (`$032A`) is written but
  never read; so is `done_word` (`$0865`).

## Dead code and other leftovers

Besides the source fragments, the image holds pieces of older builds that nothing reaches:

* `dead_init_tail` (`$5651`) is an older copy of the end of `init_game`. It calls the macro
  library at `$4A00` (the library's address in that build; the bytes there are now command
  rules), puts the shape table at `$6D00` and sets the DOS language flag (`$AAB6`).
* `dead_read_message` (`$5912`-`$59F0`) is an older message reader using the same old library.
  Its variables at `$5A01`-`$5A0B` are now the start of `run_rules`, and its hex-digit table
  (`$59F1`) has room for `0`-`E` only before the engine begins at `$5A00`.
* `$69CA` holds two lines of a tokenized Applesoft program:
  `10000 DATA 81,"YOU ARE IN A STORAGE ROOM"` and the start of line 10010. 81 is the storage
  room's message number in the shipped game, so it looks like a BASIC prototype that already
  used the final message numbering.
* `$7956` is a stale copy of the Applesoft line routine, and the Applesoft entry points
  `HPLOT0` (`$6A7A`), `XDRAW` (`$6C9A`) and two command wrappers (`$6D31`, `$6D44`) are never
  called.

* On the disk, several files own more sectors than their data needs (`BLOCK19` holds 268
  bytes in three data sectors). DOS 3.3 never frees sectors when a file is saved over a larger
  one, so these are traces of earlier, bigger versions. `tools/dos33.py put` keeps them the same
  way, which is why a rebuilt disk is identical to the original.

These are decompiled with the rest (`dead_*` in `decomp/adventure.c`) because they show how
the engine changed between builds.

## Self-modifying DOS commands

Two `rt_print` strings are completed at run time: `BLOAD BLOCK##,A$####` (`cache_load_block`)
and `READ MESSAGES,B$####` (`read_message_line`). The digits are `$00` in the file, so a
disassembler that ends the string at the first `$00` stops in the middle of the text and misses
the code after it (the cache bookkeeping at `$734A` and the `$0200` save/restore at `$751E`).
`programs/adventure.json` gives those strings their real length; listings show the patched
digits as `#`.

## Cross-check

An independent write-up of the same binary (`DECOMP.md`, supplied separately) agrees with these
notes on the record layouts, the condition and action opcodes, message numbering and the
turn-255 quirk. It pointed to the dead code above and to the code hidden behind the patched DOS
strings, both added here. Where they differ: it describes `$2000-$3FFF` as mostly zeros (true
by count, but those bytes are the 1980 title screen) and lists verb 33 without its `OFF`
synonym.

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
| `$7603` | `BUMPIT` | word += X | `.word addr` |
| `$7606` | `BUMP16` | word += word | `.word src, dst` |
| `$7609` | `rt_compare` | compare X bytes at `(WORK)` with addr; `cmp_result` = 0 if equal | `.word addr` |
| `$760C` | `rt_args` | point `rt_operands` at the caller's operands | |
| `$760F` | `rt_return` | return to the caller's caller, skipping X operand bytes (never returns) | |
| `$7612` | `rt_inc16` | word += 1 | `.word addr` |
| `$7615` | `rt_print` | print inline text | `$00`-terminated |
| `$7618` | `MULTIPLY` | `mul_result` = word * X | `.word addr` |

The names `BUMPIT`, `BUMP16` and `MULTIPLY` are the original ones: the source fragments call
them (`JSR BUMPIT / ADR ZAWORK`, `JSR MULTIPLY / ADR AWORK3`, `JSR BUMP16 / ADR AWORK3 / ADR AWORK2`).
The others' original names did not survive.

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

## Solution

`tests/play/walkthrough.txt` is a complete solution (78 commands); `tests/test_play.py` plays it
on the emulated game and checks it wins with the recorded text and screens. The puzzle chain, as
the rules (`assets/text/rules.txt`) define it:

1. Go in by the front door (`GO STAIRS`, `OPEN DOOR`, `GO DOOR`); it locks behind you
   (`SW_FRONT_DOOR_LOCKED`). The way out needs the key on Tom's body in the basement.
2. Kitchen: the matches are in the cabinet (`OPEN CABINET`, `LOOK CABINET`), the pitcher in the
   refrigerator; fill it at the sink (`FAUCET ON`, `GET WATER`).
3. Dining room: carrying the lit candle you trip on the rug and start a fire (`SW_RUG_FIRE`);
   `POUR WATER` puts it out (otherwise the next command kills you) and the burnt hole holds the
   trunk key (`LOOK HOLE`, `GET KEY`).
4. Attic: the sledgehammer. Storage room: `UNLOCK TRUNK` with that key, `OPEN TRUNK`,
   `LOOK TRUNK`, `GET GUN`. The gun has one shot (`SW_GUN_FIRED`): fire it anywhere else and it
   is wasted.
5. Bathroom (through the study): the towel.
6. Kitchen: `MOVE CABINET` shows bricks (`SW_CABINET_MOVED`); `BREAK WALL` with the
   sledgehammer opens a hole to the pantry, the passage and the basement. `WIPE ALGAE` with the
   towel shows a loose brick; `GET BRICKS` finds the jewels. Tom's body has the front-door key.
7. The basement's other hole leads to a tunnel and the pine tree; at the top, `LOOK TELESCOPE`
   sees a trapdoor in the attic ceiling, which puts it in the attic. Back through the forest
   (`OPEN DOOR` from outside to get into the kitchen).
8. Attic: `OPEN TRAPDOOR`, `GO TRAPDOOR` to the tower. Daisy is the killer: `SHOOT GUN` (any
   other weapon, or an empty gun, and she stabs you). `SW_DAISY_DEAD`.
9. Back down, `UNLOCK DOOR`, `OPEN DOOR`, and out to the front yard with the jewels: the turn
   rule there wins the game.

It gets dark after turn 36 (`SW_DARK_WARNED`; `LAMPSTAT` off) unless you carry the lit candle;
the darkness only hides the pictures, and `GET` still works because it depends on the room's
current picture, not on the light.

`assets/text/map.txt` lists every room's exits and the passages rules make (`map.dot` draws it
with Graphviz).

## Pictures

Pictures are line drawings. `picture_directory` (`$5300 + 3n`) gives each picture's `BLOCKn`
file and byte offset. A picture is a list of byte pairs:

```
x y      continue the line to (x, y)        (HPLOT TO)
00 00    the next point starts a new line   (HPLOT)
FF FF    end
```

`draw_picture` adds the object offset in 8 bits (a coordinate past 255 wraps round) and
clamps to 255 x 160 (the bottom four text lines stay free). Each 00 00 sets `pen_up`, which
carries over between pictures; picture 92 does not start with 00 00, so its first stroke is a
line from wherever the previous picture left the pen. HGLIN's lines are 4-connected
staircases (one pixel across or down per step), not Bresenham lines; `tools/pictures.py`
draws them the same way and `tests/test_pictures.py` checks it against the game, pixel for
pixel. PORTING.md has the algorithm. Lines are drawn by a relocated copy of the Applesoft hi-res routines (`$6A00-$6DB8`:
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

`MESSLSTR` handles four messages itself (`$07`, `$25`, `$7F`, `$89`). For the rest it looks
up the byte offset in `message_index` (`$5500`; the `MESSAGE OBJECT` file is a copy), turns it
into hex in `READ MESSAGES,B$xxxx` (self-modifying again) and reads one line from the `MESSAGES`
text file, which `init_game` OPENs. `word_wrap` breaks the line at 39 columns. A room
description is printed without the short pause that follows other messages.

## Shiftable source

The engine loads several table addresses as immediate pairs (`LDA #<OBJBASE / LDA #>OBJBASE`)
and keeps five pointers to tables inside its code (`command_rules_addr`, `objbase_addr`, ...).
The source writes all of them as names, so the tables and code can move; only `$0800`,
`OBJBASE`, `ROOMBASE` (inside the saved state) and the hi-res page are pinned.
`tests/test_shift.py` pads the source in five places, moving nearly every routine and table,
and plays the full solution on the result: same text, same screens.

## Original names

The source fragments name more than the action handlers. Lining their instructions up with the
shipped code gives the original names of these variables, which `src/adventure.s` uses:

| Name | Address | Use |
|---|---|---|
| `WORK` | `$77` | the rule cursor (`run_actions` copies it to `AWORK`) |
| `AWORK` | `$0890` | the current action |
| `AWORK1` | `$0892` | an action's X operand, saved |
| `AWORK2`, `AWORK3` | `$0894`, `$0896` | action scratch words (`AC1600`: `ROOMBASE` and room * `RTBLSIZ`) |
| `AX`, `AY`, `AX1`, `AY1` | `$0899`-`$089C` | the four operands of `AC2800` / `AC2900` |
| `CURONO` | `$0852` | the current room number |
| `CUROOM`, `ZWORK`, `ZAWORK` | `$83`, `$85`, `$87` | the current room record, action and object pointers |
| `SWITCH`, `LAMPSTAT`, `OBJBASE`, `ROOMBASE` | | flags, light, the two tables |
| `BUMPIT`, `BUMP16`, `MULTIPLY`, `MESSLSTR` | | the add-X, add-word and multiply macros and the message printer |

The naming is consistent: a `Z` prefix for zero-page pointers, `A` for absolute variables.

## Original source

When `ADVENTURE` was saved, memory still held the author's tools, here the LISA assembler's
source buffer and symbol table (see "The assembler" below):

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
fragments match the shipped code instruction for instruction otherwise.

### The assembler: LISA

The source was written with **LISA** (Lazer's Interactive Symbolic Assembler, by Randall Hyde).
The opcode tokens were first worked out by lining the fragments up with the assembled code;
they then turned out to match LISA's tokenized format exactly:

* **Every token agrees.** All 17 found here have the values in LISA v2's mnemonic table
  (`$86` BNE, `$87` BEQ, `$96` BRK, `$99` CLC, `$AC` TAX, `$AD` TAY, `$C0` ADC, `$C4` CMP,
  `$CA` JMP, `$CB` JSR, `$CD` LDA, `$CE` LDX, `$CF` LDY, `$D0` STA, `$D1` STX, `$D2` STY,
  `$D8` ADR). The table is ordered by LISA's own mnemonic list (it has LISA-only entries such
  as `BSB`, `RTN` and the SWEET16 opcodes), so a chance match with another assembler is not
  plausible.
* **The line layout agrees.** Each line is a length byte, the mnemonic token, an operand-mode
  byte (`$00` none, `$01` absolute, `$02` immediate, `$05` `(zp),Y`, `$07` `abs,Y`,
  `$20` literal), the operand as text, `$BB` (high-ASCII `;`) before a comment, then `$0D`.
  Labels are padded to 8 characters.
* **The syntax agrees.** It is LISA's: `/` takes an address's high byte (`LDA /ROOMBASE`), and
  `ADR` emits a word (the action table, the inline operands after `JSR BUMPIT`).
* **The history agrees.** LISA was first sold by Programma International. When Programma
  closed in 1980, On-Line Systems, the Williamses' company, took it over; On-Line's own manual
  for LISA 2.5 survives (1982).

There is one difference. A label here is a separate 10-byte record (`$0A`, the name padded to
8, `: `) ahead of its statement. LISA v2's saved files keep the label inline in the line. What
survived in `ADVENTURE` is LISA's memory buffer from early 1980, not a saved file, and possibly
from an earlier version (1.x), so the identification rests on the token table, which matches
exactly. `tools/source_fragments.py` decodes with LISA's full table.

References: the LISA v2 format notes and decoder in CiderPress II
(`FileConv/Code/LisaAsm-notes.md`, `LisaAsm.cs`); the LISA 2.5 manual published by On-Line
Systems (Internet Archive, *LISAAssemblerVersion2.5ManualPhotocopySource*); the LISA history
at programma.applearchives.com.

## Quirks found along the way

* `cond_turns_gt` fails whenever the turn counter's high byte is non-zero, so every
  "turn > N" condition (darkness, `IT IS GETTING DARK`) stops being true from turn 256.
* `AC2600` (restore game) means to put back the action pointer it saved before the BLOAD, but
  stores both bytes into the low byte (`STA AWORK` at `$670E` and `$6713`); the high byte
  keeps the value just loaded from the save file.
* Actions 12 and 14 are a bare `BRK`; so are "object not found" in `find_object`, `AC1500`
  and `AC2900` (the source comments it `;UH-OH, KABOOM!`).
* The `ACNEWROM` exit (`go` actions) returns through `stop_actions`, so a movement action
  ends its rule's action list. It also builds the new `CUROOM` from `AWORK2` after clearing
  only its high byte: the low byte is never loaded with the room number, so `CUROOM` is wrong
  until `draw_room` rebuilds it from `CURONO` at the start of the next turn. The turn rules run
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

Found by the play scripts (`tests/play/`):

* Jumping out of the storage-room window (`rule_4FEB`) prints `YOU ARE DEAD.` but the game
  carries on: unlike the same rule in the attic (`rule_4F16`), it has no "ask to play again".
* `OPEN TRUNK` on the open trunk answers `IT IS LOCKED`: `rule_4F4B` ("if unlocked, say it is
  locked") comes before `rule_4F56` ("if the open trunk is here, say it is open"), and the trunk
  can only be open once it is unlocked, so `rule_4F56` never runs.
* `WITH DAGGER` in the cemetery without the dagger (`rule_4ADD`) says `YOU ARE NOT CARRYING
  IT` and also removes object 26, the dots that are Joe's open eyes (they become X's when he is
  killed), so he is drawn without them from then on.
* Rules that test the picture on screen (most doors and gates) depend on what was shown last:
  after `LOOK SINK`, `READ NOTE` and the like the close-up is the current picture, and the door
  rules no longer match until `LOOK ROOM` or a move. In the dark (after turn 36 without a lit
  match or candle) the room is not drawn at all, so those doors can be neither opened nor used.
* `GET` only takes what the current picture shows: the matches after `LOOK CABINET`, the
  pitcher after `LOOK REFRIGERATOR`, the trunk key after `LOOK HOLE`.

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

* `STARTUP` looks like it was made with SAVE GAME at the start of a game: its saved variables
  say the last command parsed was verb 34 (SAVE), noun 88 (GAME).
* The disk's free sectors hold fragments of other software that was on the disk before the
  1987 master was copied: Bob Bishop's *Dung Beetles*, cracking-group title screens, a fast
  loader and pieces of DOS. They are not part of the game, and the project does not keep them:
  the built disk has zeros there (`disk/README.md`).

These are decompiled with the rest (`dead_*` in `decomp/adventure.c`) because they show how
the engine changed between builds.

## Self-modifying DOS commands

Two `rt_print` strings are completed at run time: `BLOAD BLOCK##,A$####` (`cache_load_block`)
and `READ MESSAGES,B$####` (`read_message_line`). The digits are `$00` in the file, so a
disassembler that ends the string at the first `$00` stops in the middle of the text and misses
the code after it (the cache bookkeeping at `$734A` and the `$0200` save/restore at `$751E`).
`ghidra/programs/adventure.json` gives those strings their real length; listings show the patched
digits as `#`.

## Test coverage

`tests/play/` plays the solution, a tour of every room, every death and ending, and the unknown
words on the emulated game, and `tools/gamecov.py` records what runs (the report is
`tests/play/coverage.expected.txt`). Together they run 347 of the 348 command rules, all 10
turn rules and 1855 of the 2120 instructions. What never runs cannot run in the shipped game:

* `rule_4F56`, which the trunk quirk above makes unreachable;
* the dead code: `dead_*` and `old_read_digits` (see "Dead code and other leftovers");
* `disk_error_handler` and the `messages_open` byte after it, which run only on a disk error;
* `AC1100` (add to a switch: no rule uses action 1) and `AC2200`/`AC2400`, the `BRK`s that
  stand for the unused actions 12 and 14;
* the parts of the Applesoft hi-res copy the game does not use (`hplot0`, `hlinrl`, `xdraw0`
  and the XDRAW plot, `hcolor_bkgnd`, `hfind`), and `quantity_error`, its bad-argument exit.

## Bug-fix build

`./build.sh --bugfix` assembles the `.ifdef BUGFIX` blocks in `src/adventure.s`, which fix the
bugs above that change what the game does, each next to the original code:

| Bug | Fix |
|---|---|
| `cond_turns_gt` fails from turn 256, so the dark lifts and "turn > N" rules stop | a non-zero high byte passes the test |
| `AC2600` (restore game) writes both bytes of the action pointer into its low byte | the high byte goes to `AWORK+1` |
| The storage-room window (`rule_4FEB`) says `YOU ARE DEAD` and play goes on | the rule ends the game, as the attic window does |
| `OPEN TRUNK` on the open trunk (`rule_4F4B`) says `IT IS LOCKED` | it says `IT IS OPEN` |
| `WITH DAGGER` at Joe without the dagger (`rule_4ADD`) erases his eyes | the rule only says `YOU ARE NOT CARRYING IT` |

`tests/test_bugfix.py` plays `tests/play/bugfix.txt` on both builds and checks each one. Left as
they are: the disk-error handler that returns into the flag byte (what a clean return should
do depends on DOS, which the tests do not run), and quirks that change nothing a player sees
(the `CUROOM` low byte after a move, the unreachable `OFF` synonym, the unused actions).

## Cross-check

An independent write-up of the same binary (`DECOMP.md`, supplied separately) agrees with these
notes on the record layouts, the condition and action opcodes, message numbering and the
turn-255 quirk. It pointed to the dead code above and to the code hidden behind the patched DOS
strings, both added here. Where they differ: it describes `$2000-$3FFF` as mostly zeros (true
by count, but those bytes are the 1980 title screen) and lists verb 33 without its `OFF`
synonym.

# Tests

```bash
python3 -m unittest discover -s tests
```

Standard library only; run from the repository root as shown (a test file run on its own cannot
import `helpers.py`). The whole suite takes about two minutes, most of it playing the
scripts in `play/` on the emulator. `helpers.py` builds every game file from `src/` into a
temporary directory once per run, and plays each script once, recording what runs, for the
tests that need it.

| File | Checks |
|---|---|
| `test_asm6502.py` | the assembler: addressing modes, expressions, directives, errors |
| `test_ca65.py` | ca65 and ld65 build the same programs (skipped without cc65) |
| `test_basic.py` | the BASIC tokenizer, and every program listing back to its source |
| `test_boot.py` | `boot.py`'s text routines (windows, scrolling, the rows a wide window spills into), the screens HELLO and MYSTERY.HELLO make, and `gamedata.json`'s `boot` timeline replaying to them |
| `test_formats.py` | the message, picture and saved-state formats round trip |
| `test_disk.py` | the full build against the recorded hashes; the disk writer, and a stale-data residue showing only in free sectors |
| `test_play.py` | each script in `play/` gives the recorded transcript and screens (`intro.txt` from the 1987 loader); together they exercise the recorded code and rules (`play/coverage.expected.txt`) |
| `test_bugfix.py` | the bug-fix build (`./build.sh --bugfix`): `play/bugfix.txt` on both builds, each with recorded transcript and screens, each bug present in the original and fixed in the other |
| `test_shift.py` | padding the source moves the code and tables, and the game plays and decodes the same |
| `test_pictures.py` | `pictures.py` against the game's own drawing on the emulator: every picture (also offset, to check the wrap and clamp), every shape, every room, and the screen at every command prompt of every script rebuilt from the game state; `gamedata.json` alone is enough to draw |
| `test_analysis.py` | `gamedata.py` against the symbol table and the running game (the start state, the saved game after RESTORE, the loader pages as printed), `trace6502.py` against the listing and what the game executes, `source_fragments.py` against `original_source/`, and `gen_source.py` (which made the first `src/`) still giving source that reassembles to the same bytes |

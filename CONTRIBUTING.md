# Contributing

Thanks for helping. This project has one firm rule: **the build must keep reproducing the
original game byte for byte**, unless a change is a deliberate edit to the game. Everything
below follows from that rule. [HACKING.md](HACKING.md) explains the source and the build in
detail, and [NOTES.md](NOTES.md) explains how the engine works.

## Setup

You need python3 and nothing else. These are optional:

* cc65 (2.18 or later) to run `tools/ca65_check.sh`. CI runs it anyway.
* Ghidra 12.1.x (`GHIDRA_INSTALL_DIR`) to regenerate `decomp/`.

## Before you open a pull request

Run these checks, in this order (`./build.sh --check` clears `build/`, so the bug-fix build
comes after it):

```bash
./build.sh --check
```

```bash
python3 -m unittest discover -s tests
```

```bash
./build.sh --bugfix
```

```bash
tools/ca65_check.sh
```

1. `./build.sh --check` must say "all 30 files match the original" and
   "build/mystery_house.do: matches disk/SHA256".
2. The tests take about two minutes. Run them from the repository root as shown;
   running a single test file directly cannot import `tests/helpers.py`.
3. `./build.sh --bugfix` builds the game with the documented bugs fixed into `build/bugfix/`.
4. `tools/ca65_check.sh` checks both builds with ca65 and ld65. It needs cc65; skip it if you
   don't have it, CI will run it.

Commit the regenerated `assets/` and `extracted/` along with the source change: CI fails if they
are not what the source produces. Never edit them by hand, and the same goes for `decomp/` and
`build/`.

## Kinds of change

**Cleanups:** names, comments, constants and documentation. These must never change a byte. If
the build stops matching, the change replaced a value with something that is not equal to it.

**Fixing a bug in the game:** put the fix in an `.ifdef BUGFIX` block with the original code in
its `.else` (HACKING.md, "Changing the game"). The default build still matches, and
`./build.sh --bugfix` builds the fixed game. Document the bug in NOTES.md and show the fix in
`tests/play/bugfix.txt` and `tests/test_bugfix.py`.

**Changing the game** in other ways: rules, text, pictures or engine code. The hashes will no
longer match, so this kind of change does not belong on `main` as it stands. Open an issue
first, and put the work on a branch or a fork. HACKING.md ("Changing the game") shows how. Check it with
`tools/play.py`, and update the expected files in `tests/play/` (its README has the commands)
only when the difference is the one you meant to make. New behaviour should come with commands
in a play script that exercise it; `tools/gamecov.py` shows what a script reaches.

**Tools and tests:** when a tool gains a feature or a bug is fixed, add a test to `tests/`
(standard library `unittest` only, no extra dependencies).

**Research:** a new finding about the engine, the original names or the disk goes in NOTES.md,
together with the evidence for it.

## Conventions

* The source is standard ca65 syntax, the subset that `tools/asm6502.py` implements (see
  HACKING.md, "The source"). If you need a construct outside that subset, add it to both the
  assembler and its tests.
* Names in CAPITALS (`CUROOM`, `ZWORK`, `AC1600`, ...) are the original author's, recovered
  from the binary. Don't rename them. Everything else is named after what it does, in
  `snake_case`.
* Labels inside a routine are `routine__local`, and every label has a name.
* Refer to code and data by name, never by a fixed address, so the source stays shiftable
  (`tests/test_shift.py` checks this). The only pinned addresses are `$0800`, `OBJBASE`,
  `ROOMBASE` and `$2000`.
* Operands passed inline after a `JSR` stay as `.word` / `hiasc` lines right after the call.
* Names and routine comments live only in `src/`. `ghidra/symbols/*.csv` only adds Ghidra types and
  register parameters. `tools/gen_source.py` is historical: don't rerun it over the source.
* `original_source/` is an archive of the author's 1980 source fragments. Keep it as it is.
* Every folder has a README.md. Update it, together with HACKING.md and NOTES.md, when something
  they describe changes.

## Public domain only

The game was released into the public domain in 1987, and the repository holds only that and
this project's own work. Please don't add:

* the original disk image or any file copied from it rather than built;
* the stale fragments of other software found on the original disk (`disk/README.md`);
* any further copyrighted code or data, such as Apple ROMs or other games.

DOS 3.3 (`src/disk/dos33.bin`) is Apple's. It stays an untouched binary so the disk boots, and
it is not decompiled.

By contributing, you release your work under the Unlicense, like the rest of the project
(`LICENSE`).

## Commits and pull requests

Write a short summary line in the imperative ("Name the picture cache routines"). In the body,
say what changed and why, and state whether the build still matches. Keep each commit to one
topic. CI runs on every push and pull request: the tests, `./build.sh --check`, the ca65 check,
and a check that the generated files are up to date.

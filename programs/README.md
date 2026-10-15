# programs

Settings for `tools/trace6502.py`, which finds the code in each binary for the optional Ghidra
pseudocode step. (The build itself assembles `src/` and does not use these.) One JSON file per
program. Places are named by the source's symbols (`tbl_actions`, `cache_load_block.bload`,
`start+13`), so the descriptions stay right when the source moves things; four hex digits give
a fixed address.

| Field | Meaning |
|---|---|
| `name`, `file` | the program's name and its file among the built disk's files (`build/files/`) |
| `load` | load address |
| `entries` | addresses to trace from: the entry point, plus routines reached only through a vector or never called (dead code, unused Applesoft routines) so they get pseudocode too |
| `lib` | address of the macro library's jump table; calls to it carry inline operands |
| `old_libs` | an older build's library address, called only by dead code; calls are decoded but not followed |
| `jump_tables` | dispatch tables: address, number of words, name |
| `always_branches` | conditional branches that are always taken (Applesoft's `BVC` loop in HGLIN) |
| `data_only` | address ranges Ghidra treats as data (ADVENTURE's start-up code, which the HPLOT/DRAW variables overwrite) |
| `inline_text_length` | `rt_print` calls whose text has digits patched in at run time (`$00` in the file); the length includes the terminator |
| `labels` | extra labels for the tracer's listing (normally empty: names come from `src/`) |

The tracer also finds routines that use the inline-operand convention themselves (they call
`rt_args` and leave with `LDX #n / JSR rt_return`) and works out how many operand bytes they
take.

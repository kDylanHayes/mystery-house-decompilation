# ghidra

Inputs to the optional Ghidra step of the build (`GHIDRA_INSTALL_DIR` set), which writes the C
pseudocode in `decomp/`. Nothing else in the build needs them, except that the tests also run
the code tracer with `programs/adventure.json`.

| Folder | Contents |
|---|---|
| `programs/` | how to trace each program for Ghidra: entry points, jump tables, inline operands (`tools/trace6502.py`; see `programs/README.md`) |
| `symbols/` | Ghidra data types and register parameters, added to the names and comments the assembler takes from `src/` (`tools/ghidra_symbols.py`; see `symbols/README.md`) |
| `scripts/` | `MysteryHouse.java`, the post-script: it disassembles exactly what the tracer found, applies the symbols and writes the pseudocode for every function |

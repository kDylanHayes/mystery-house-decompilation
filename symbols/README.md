# symbols

Extra information for the optional Ghidra pseudocode step. Names and routine comments come from
`src/` (the assembler's symbol table, merged by `tools/ghidra_symbols.py`); these files add what
Ghidra needs on top.

`address,name,type,comment`, one row per address:

* `type`: `byte`, `word`, `ptr`, or an array such as `byte[20]`, applied as a data type;
  `func` makes the address a function; `func:X` (or `func:A`, `func:A/X`) also declares
  parameters passed in registers, so calls show them (`print_message(0x89)`).
* `comment`: used for addresses `src/` has no comment for (zero-page and low-memory variables).
* `name`: how the type is matched to the source: by name, so it follows a symbol that moves
  (by address only for places the source does not name, such as zero page and the ROM).

| File | For |
|---|---|
| `apple2.csv` | hardware switches, Monitor ROM and Applesoft/DOS entry points (both programs) |
| `adventure.csv` | ADVENTURE |
| `autoload.csv` | AUTO LOAD OBJ |

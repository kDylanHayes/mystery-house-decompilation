# Original source fragments

When `ADVENTURE` was saved to disk in 1980, part of its memory still held the author's assembler
source buffer. These are the pieces that survived, recovered from the original binary:

| File | Contents |
|---|---|
| `fragments.s` | the 313 surviving lines, decoded to text: the action handlers `AC1100`-`AC3000` with the author's comments (`; MOVE TO ROOM X`, `; WOOPEE! WE'VE GOT IT!`, ...) and labels (`CUROOM`, `ROOMBASE`, `ZWORK`, `LAMPSTAT`, ...) |
| `raw/fragment_XXXX.bin` | each fragment's bytes exactly as stored in the binary, still tokenized; `XXXX` is the run-time address |

The text between fragments was overwritten before the file was saved. The tokenized format and
the opcode token table are described in `tools/source_fragments.py` and NOTES.md ("Original
source").

This is an archive: `build.sh` does not touch it. It was recovered from the original `ADVENTURE`
with `tools/source_fragments.py`, which works on any copy of the file that still has those bytes
(the built one does, as long as the "leftover memory" in `src/` has not been deleted).

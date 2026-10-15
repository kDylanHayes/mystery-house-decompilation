#!/bin/sh
# Assemble src/ with the standard cc65 tools (ca65 + ld65, 2.18 or later) and check that they
# produce exactly the same programs as the build's own assembler. Run ./build.sh first: it
# generates the message and picture tables (build/gen/) that ADVENTURE includes.
#
# usage: tools/ca65_check.sh            (needs ca65 and ld65 on PATH)
set -eu
HERE=$(cd "$(dirname "$0")/.." && pwd)
B="$HERE/build"
O="$B/ca65"
[ -f "$B/ADVENTURE.bin" ] || { echo "run ./build.sh first" >&2; exit 1; }
mkdir -p "$O"
status=0
for p in adventure:ADVENTURE:0x0800 autoload:AUTO_LOAD_OBJ:0x0FFD; do
	src=${p%%:*}; rest=${p#*:}; out=${rest%%:*}; start=${rest#*:}
	ca65 -I "$HERE/src" -I "$B/gen" --bin-include-dir "$HERE/src" -o "$O/$src.o" "$HERE/src/$src.s"
	ld65 -C "$HERE/src/ld65.cfg" -S "$start" -o "$O/$out.bin" "$O/$src.o"
	if cmp -s "$O/$out.bin" "$B/$out.bin"; then
		echo "$out: ca65 + ld65 build it byte for byte"
	else
		echo "$out: ca65 + ld65 output differs from the build" >&2
		cmp "$O/$out.bin" "$B/$out.bin" >&2 || true
		status=1
	fi
done
exit $status

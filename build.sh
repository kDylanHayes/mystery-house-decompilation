#!/bin/sh
# Build Mystery House from source.
#
# usage: ./build.sh
# needs: python3 only. If GHIDRA_INSTALL_DIR points at Ghidra 12.1.x, the C pseudocode in
#        decomp/ is regenerated as well (optional).
#
# Builds every file of the game from src/ and the disk image around them (build/mystery_house.do,
# bootable), then regenerates the assets from the built disk. If the original disk image is in
# disk/, it is used only to check the result and to recover original_source/.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ORIG="$HERE/disk/mystery_house.do"
B="$HERE/build"
G="$B/gen"
rm -rf "$B" "$HERE/assets"
mkdir -p "$G"

# messages, pictures and BASIC first: the first two generate tables ADVENTURE includes
python3 -I "$HERE/tools/msgfile.py" build "$HERE/src/messages.txt" "$G/MESSAGES.bin" "$G/messages.inc"
python3 -I "$HERE/tools/picfile.py" build "$HERE/src/pictures" "$G" "$G/pictures.inc"
for f in HELLO MYSTERY.HELLO PIC_SIZES; do
	python3 -I "$HERE/tools/basic.py" build "$HERE/src/basic/$f.bas" "$G/$f.bin"
done
python3 -I "$HERE/tools/basic.py" build "$HERE/src/basic/APPLESOFT.int" "$G/APPLESOFT.bin"
python3 -I "$HERE/tools/asm6502.py" -I "$G" "$HERE/src/adventure.s" "$B/ADVENTURE.bin" "$B/adventure.lst" "$B/adventure.syms.csv"
python3 -I "$HERE/tools/asm6502.py" "$HERE/src/autoload.s" "$B/AUTO_LOAD_OBJ.bin" "$B/autoload.lst" "$B/autoload.syms.csv"

# the files made from other built files (STARTUP, SAVED GAME, the table copies), then the disk
python3 -I "$HERE/tools/diskfiles.py" make "$B" "$HERE/src"
set --
while IFS= read -r f; do set -- "$@" "$f"; done < "$B/put.txt"
python3 -I "$HERE/tools/mkdisk.py" build "$HERE/src/disk" "$B/mystery_house.do" "$@"
python3 -I "$HERE/tools/dos33.py" "$B/mystery_house.do" "$B/files" > /dev/null

# check against the original disk, if it is here
if [ -f "$ORIG" ]; then
	rm -rf "$HERE/extracted"
	python3 -I "$HERE/tools/dos33.py" "$ORIG" "$HERE/extracted" > /dev/null
	python3 -I "$HERE/tools/diskfiles.py" compare "$B/files" "$HERE/extracted"
	[ "$(shasum -a 256 "$B/mystery_house.do" | cut -d' ' -f1)" = "$(cat "$HERE/disk/SHA256")" ] \
		&& echo "build/mystery_house.do: identical to the original disk" \
		|| echo "build/mystery_house.do: differs from the original disk"
	# the original source left in memory, from the original binary: it is kept even if the
	# leftover memory in src/ is deleted to make room
	python3 -I "$HERE/tools/source_fragments.py" "$HERE/extracted/ADVENTURE.bin" "$HERE/original_source"
else
	echo "no original disk image in disk/: built without checking against it"
fi

# assets come from the built disk, so edits show up in them
python3 -I "$HERE/tools/gamedata.py" "$B/files" "$HERE/assets/text"
python3 -I "$HERE/tools/pictures.py" "$B/files" "$HERE/assets/text/gamedata.json" "$HERE/assets"

[ -n "${GHIDRA_INSTALL_DIR:-}" ] || { echo "GHIDRA_INSTALL_DIR not set: decomp/*.c left as is"; exit 0; }
W="$B/ghidra"
mkdir -p "$W"
for prog in adventure autoload; do
	file=$(python3 -I -c "import json,sys; print(json.load(open(sys.argv[1]))['file'])" "$HERE/programs/$prog.json")
	load=$(python3 -I -c "import json,sys; print(json.load(open(sys.argv[1]))['load'])" "$HERE/programs/$prog.json")
	# names and comments from src/, types and register parameters from symbols/
	python3 -I "$HERE/tools/ghidra_symbols.py" "$B/$prog.syms.csv" "$HERE/symbols/apple2.csv" \
		"$HERE/symbols/$prog.csv" "$W/$prog.symbols.csv"
	python3 -I "$HERE/tools/trace6502.py" "$HERE/programs/$prog.json" "$B/files/$file" "$W/$prog.plan.json"
	"$GHIDRA_INSTALL_DIR/support/analyzeHeadless" "$W" "$prog" \
		-import "$B/files/$file" -overwrite \
		-loader BinaryLoader -loader-baseAddr "0x$load" -processor 6502:LE:16:default \
		-noanalysis -scriptPath "$HERE/ghidra_scripts" \
		-postScript MysteryHouse.java "$W/$prog.plan.json" "$W/$prog.symbols.csv" "$HERE/decomp/$prog.c" \
		-deleteProject > "$W/$prog.log" 2>&1
	grep -E "MysteryHouse.java> .*decompiled|ERROR" "$W/$prog.log" || true
done

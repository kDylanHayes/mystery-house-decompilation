#!/bin/sh
# Build Mystery House from source.
#
# usage: ./build.sh [disk.do]      (default: disk/mystery_house.do, the original image)
# needs: python3 only. If GHIDRA_INSTALL_DIR points at Ghidra 12.1.x, the C pseudocode in
#        decomp/ is regenerated as well (optional).
#
# Builds every file of the game from src/ (the two programs, the MESSAGES file, the 19 picture
# files, the BASIC programs, STARTUP and the two table copies), checks them against the originals, writes them into a copy
# of the disk image (build/mystery_house.do, bootable) and regenerates the assets from them.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
DISK=${1:-"$HERE/disk/mystery_house.do"}
B="$HERE/build"
G="$B/gen"
rm -rf "$B" "$HERE/extracted" "$HERE/assets"
mkdir -p "$G"

python3 -I "$HERE/tools/dos33.py" "$DISK" "$HERE/extracted" > /dev/null

# messages and pictures first: they generate the tables ADVENTURE includes
python3 -I "$HERE/tools/msgfile.py" build "$HERE/src/messages.txt" "$G/MESSAGES.bin" "$G/messages.inc"
python3 -I "$HERE/tools/picfile.py" build "$HERE/src/pictures" "$G" "$G/pictures.inc"
for f in HELLO MYSTERY.HELLO PIC_SIZES; do
	python3 -I "$HERE/tools/basic.py" build "$HERE/src/basic/$f.bas" "$G/$f.bin"
done
python3 -I "$HERE/tools/basic.py" build "$HERE/src/basic/APPLESOFT.int" "$G/APPLESOFT.bin"
python3 -I "$HERE/tools/asm6502.py" -I "$G" "$HERE/src/adventure.s" "$B/ADVENTURE.bin" "$B/adventure.lst" "$B/adventure.syms.csv"
python3 -I "$HERE/tools/asm6502.py" "$HERE/src/autoload.s" "$B/AUTO_LOAD_OBJ.bin" "$B/autoload.lst" "$B/autoload.syms.csv"

# compare with the originals, then write everything into a copy of the disk
python3 -I "$HERE/tools/diskfiles.py" "$B" "$HERE/extracted"
set --
while IFS= read -r f; do set -- "$@" "$f"; done < "$B/put.txt"
python3 -I "$HERE/tools/dos33.py" put "$DISK" "$B/mystery_house.do" "$@"
[ "$(shasum -a 256 "$B/mystery_house.do" | cut -d' ' -f1)" = "$(cat "$HERE/disk/SHA256")" ] \
	&& echo "build/mystery_house.do: identical to the original disk" \
	|| echo "build/mystery_house.do: modified disk"

# assets come from the built files, so edits show up in them
python3 -I "$HERE/tools/gamedata.py" "$B/files" "$HERE/assets/text"
python3 -I "$HERE/tools/pictures.py" "$B/files" "$HERE/assets/text/gamedata.json" "$HERE/assets"
# the original source left in memory: always taken from the original binary, so it is kept even
# if the leftover memory in src/ is deleted to make room
python3 -I "$HERE/tools/source_fragments.py" "$HERE/extracted/ADVENTURE.bin" "$HERE/original_source"

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

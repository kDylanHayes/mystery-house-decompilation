#!/bin/sh
# Build Mystery House from source.
#
# usage: ./build.sh [--check | --bugfix]
#        --check: exit with an error unless every file and the disk image match the recorded
#        hashes (for CI and for cleanups that must not change the bytes)
#        --bugfix: build the game with its documented bugs fixed (the .ifdef BUGFIX blocks in
#        src/adventure.s; NOTES.md, "Bug-fix build") into build/bugfix/: the disk image
#        build/bugfix/mystery_house.do and its files in build/bugfix/files. It does not match
#        the original, so nothing is checked and the normal build, extracted/ and assets/ are
#        left alone.
# needs: python3 only. If GHIDRA_INSTALL_DIR points at Ghidra 12.1.x, the C pseudocode in
#        decomp/ is regenerated as well (optional).
#
# Builds every file of the game from src/ and the disk image around them (build/mystery_house.do,
# bootable), checks each file against the original disk's (disk/FILES.sha256) and the image
# against disk/SHA256, writes the matching progress (build/report.json, objdiff's format),
# extracts the built disk into extracted/ and regenerates the assets.
set -eu
CHECK=0
BUGFIX=0
case "${1:-}" in
--check) CHECK=1 ;;
--bugfix) BUGFIX=1 ;;
"") ;;
*) echo "usage: ./build.sh [--check | --bugfix]" >&2; exit 2 ;;
esac
HERE=$(cd "$(dirname "$0")" && pwd)
if [ $BUGFIX = 1 ]; then
	B="$HERE/build/bugfix"
	DEFINE="-D BUGFIX"
	rm -rf "$B"
else
	B="$HERE/build"
	DEFINE=""
	rm -rf "$B" "$HERE/assets"
fi
G="$B/gen"
mkdir -p "$G"

# messages, pictures and BASIC first: the first two generate tables ADVENTURE includes
python3 -I "$HERE/tools/msgfile.py" build "$HERE/src/messages.txt" "$G/MESSAGES.bin" "$G/messages.inc"
python3 -I "$HERE/tools/picfile.py" build "$HERE/src/pictures" "$G" "$G/pictures.inc"
for f in HELLO MYSTERY.HELLO PIC_SIZES; do
	python3 -I "$HERE/tools/basic.py" build "$HERE/src/basic/$f.bas" "$G/$f.bin"
done
python3 -I "$HERE/tools/basic.py" build "$HERE/src/basic/APPLESOFT.int" "$G/APPLESOFT.bin"
python3 -I "$HERE/tools/asm6502.py" -I "$G" $DEFINE "$HERE/src/adventure.s" "$B/ADVENTURE.bin" "$B/adventure.lst" "$B/adventure.syms.csv"
python3 -I "$HERE/tools/asm6502.py" "$HERE/src/autoload.s" "$B/AUTO_LOAD_OBJ.bin" "$B/autoload.lst" "$B/autoload.syms.csv"

# the files made from other built files (STARTUP, SAVED GAME, the table copies), then the disk
python3 -I "$HERE/tools/diskfiles.py" make "$B" "$HERE/src"
set --
while IFS= read -r f; do set -- "$@" "$f"; done < "$B/put.txt"
python3 -I "$HERE/tools/mkdisk.py" build "$HERE/src/disk" "$B/mystery_house.do" "$@"
if [ $BUGFIX = 1 ]; then
	python3 -I "$HERE/tools/dos33.py" "$B/mystery_house.do" "$B/files" > /dev/null
	echo "build/bugfix/mystery_house.do: the game with its documented bugs fixed (not the original)"
	exit 0
fi
rm -rf "$HERE/extracted"
python3 -I "$HERE/tools/dos33.py" "$B/mystery_house.do" "$HERE/extracted" > /dev/null

# check: each file against the original disk's (disk/FILES.sha256), the image against the clean
# disk's hash (disk/SHA256)
MATCH=1
python3 -I "$HERE/tools/diskfiles.py" verify "$HERE/extracted" "$HERE/disk/FILES.sha256" || MATCH=0
if [ "$(python3 -I -c "import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())" "$B/mystery_house.do")" = "$(cat "$HERE/disk/SHA256")" ]; then
	echo "build/mystery_house.do: matches disk/SHA256"
else
	echo "build/mystery_house.do: differs from disk/SHA256"
	MATCH=0
fi
# matching progress, routine by routine, as an objdiff report (tools/progress.py); a matching
# build also refreshes the listings and symbol tables in disk/expected/, so renames reach them
if [ $MATCH = 1 ]; then
	python3 -I "$HERE/tools/progress.py" map "$B" "$HERE/extracted" "$HERE/disk/FILES.sha256" "$HERE/disk/expected" --quiet
fi
python3 -I "$HERE/tools/progress.py" report "$B" "$HERE/extracted" "$HERE/disk/expected" "$HERE/disk/FILES.sha256" "$B/report.json"
if [ $CHECK = 1 ] && [ $MATCH = 0 ]; then
	echo "check failed: the build does not match the recorded hashes" >&2
	exit 1
fi

# assets come from the built disk, so edits show up in them
python3 -I "$HERE/tools/gamedata.py" "$HERE/extracted" "$HERE/assets/text" "$B/adventure.syms.csv"
python3 -I "$HERE/tools/pictures.py" "$HERE/extracted" "$HERE/assets/text/gamedata.json" "$HERE/assets"

[ -n "${GHIDRA_INSTALL_DIR:-}" ] || { echo "GHIDRA_INSTALL_DIR not set: decomp/*.c left as is"; exit 0; }
W="$B/ghidra"
mkdir -p "$W"
for prog in adventure autoload; do
	file=$(python3 -I -c "import json,sys; print(json.load(open(sys.argv[1]))['file'])" "$HERE/ghidra/programs/$prog.json")
	load=$(python3 -I -c "import json,sys; print(json.load(open(sys.argv[1]))['load'])" "$HERE/ghidra/programs/$prog.json")
	# names and comments from src/, types and register parameters from ghidra/symbols/
	python3 -I "$HERE/tools/ghidra_symbols.py" "$B/$prog.syms.csv" "$HERE/ghidra/symbols/apple2.csv" \
		"$HERE/ghidra/symbols/$prog.csv" "$W/$prog.symbols.csv"
	python3 -I "$HERE/tools/trace6502.py" --symbols "$B/$prog.syms.csv" "$HERE/ghidra/programs/$prog.json" "$HERE/extracted/$file" "$W/$prog.plan.json"
	"$GHIDRA_INSTALL_DIR/support/analyzeHeadless" "$W" "$prog" \
		-import "$HERE/extracted/$file" -overwrite \
		-loader BinaryLoader -loader-baseAddr "0x$load" -processor 6502:LE:16:default \
		-noanalysis -scriptPath "$HERE/ghidra/scripts" \
		-postScript MysteryHouse.java "$W/$prog.plan.json" "$W/$prog.symbols.csv" "$HERE/decomp/$prog.c" \
		-deleteProject > "$W/$prog.log" 2>&1
	grep -E "MysteryHouse.java> .*decompiled|ERROR" "$W/$prog.log" || true
done

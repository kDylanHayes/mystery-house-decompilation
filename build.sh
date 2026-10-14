#!/bin/sh
# Rebuild everything from the Mystery House disk image.
#
# usage: ./build.sh [disk.do]      (default: disk/mystery_house.do)
# needs: python3, a JDK 21+, and Ghidra 12.1.x (GHIDRA_INSTALL_DIR must point at it)
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
DISK=${1:-"$HERE/disk/mystery_house.do"}
: "${GHIDRA_INSTALL_DIR:?set GHIDRA_INSTALL_DIR to your Ghidra 12.1.x directory}"

sha=$(shasum -a 256 "$DISK" | cut -d' ' -f1)
EXPECT=$(cat "$HERE/disk/SHA256")
[ "$sha" = "$EXPECT" ] || { echo "Unexpected disk image (sha256 $sha)" >&2; exit 1; }

WORK="$HERE/work"
rm -rf "$WORK" "$HERE/extracted" "$HERE/decomp" "$HERE/assets"
mkdir -p "$WORK/ghidra" "$HERE/decomp"

python3 -I "$HERE/tools/dos33.py" "$DISK" "$HERE/extracted" > /dev/null
python3 -I "$HERE/tools/gamedata.py" "$HERE/extracted" "$HERE/assets/text"
python3 -I "$HERE/tools/pictures.py" "$HERE/extracted" "$HERE/assets/text/gamedata.json" "$HERE/assets"
python3 -I "$HERE/tools/source_fragments.py" "$HERE/extracted/ADVENTURE.bin" "$HERE/decomp/source_fragments.s"

for prog in adventure autoload; do
	file=$(python3 -I -c "import json,sys; print(json.load(open(sys.argv[1]))['file'])" "$HERE/programs/$prog.json")
	load=$(python3 -I -c "import json,sys; print(json.load(open(sys.argv[1]))['load'])" "$HERE/programs/$prog.json")
	cat "$HERE/symbols/apple2.csv" "$HERE/symbols/$prog.csv" > "$WORK/$prog.symbols.csv"
	python3 -I "$HERE/tools/trace6502.py" "$HERE/programs/$prog.json" "$HERE/extracted/$file" \
		"$WORK/$prog.plan.json" "$HERE/decomp/$prog.s" "$WORK/$prog.symbols.csv"
	"$GHIDRA_INSTALL_DIR/support/analyzeHeadless" "$WORK/ghidra" "$prog" \
		-import "$HERE/extracted/$file" -overwrite \
		-loader BinaryLoader -loader-baseAddr "0x$load" -processor 6502:LE:16:default \
		-noanalysis -scriptPath "$HERE/ghidra_scripts" \
		-postScript MysteryHouse.java "$WORK/$prog.plan.json" "$WORK/$prog.symbols.csv" "$HERE/decomp/$prog.c" \
		-deleteProject > "$WORK/ghidra_$prog.log" 2>&1
	grep -E "MysteryHouse.java>|ERROR|Exception" "$WORK/ghidra_$prog.log" || true
done

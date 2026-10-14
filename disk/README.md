# disk

`mystery_house.do` is the input: the TOSEC dump *Hi-Res Adventure 1 - Mystery House
(1980)(On-Line Systems)(PD).do*, an Apple II DOS 3.3 disk (35 tracks, 16 sectors, DOS sector
order). Sierra On-Line released the game into the public domain in 1987. `SHA256` is its hash.

The build does not need it: everything is built from `src/`. When it is here, `build.sh` checks
each built file and the whole built image against it, and recovers `original_source/` from it.

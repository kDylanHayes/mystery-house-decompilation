# src/disk

What `tools/mkdisk.py` needs, besides the built files, to make the disk image.

| File | Contents |
|---|---|
| `layout.txt` | the disk's structure: the VTOC settings (volume, catalog start, DOS's allocation state), the 15 catalog sectors, and each file in catalog order with its type and the sectors it occupies (its track/sector list, then its data sectors in order). The free-space bitmap and the catalog entries are generated from it. |
| `dos33.bin` | tracks 0-2 (12 KB): Apple DOS 3.3 as it was on the disk, which boots the machine and loads DOS. This is Apple's operating system, not part of the public-domain game, and it is kept as a binary, not decompiled. |
| `residue.bin` | bytes that no structure accounts for, so the image comes out identical to the original: stale data in the 145 sectors DOS lists as free, in the unused ends of sectors, and in the sectors some files keep from earlier, larger versions. |

The residue is not part of Mystery House. The free sectors still hold fragments of whatever was on
the disk before the 1987 master was copied: parts of Bob Bishop's *Dung Beetles*, cracking-group
title screens ("BROKEN BY BLACK BART", "CRACKED BY THE NOWHERE MAN"), a fast loader, and pieces
of DOS source and messages. It is kept only for byte-for-byte fidelity; an empty `residue.bin`
(zero bytes) makes a clean disk that works the same.

Adding a file is not supported: the layout lists the existing 30 files. A file that grows gets
free sectors (`dos33.put`); one that shrinks keeps its sectors, as DOS does.

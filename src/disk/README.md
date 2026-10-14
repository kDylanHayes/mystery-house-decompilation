# src/disk

What `tools/mkdisk.py` needs, besides the built files, to make the disk image.

| File | Contents |
|---|---|
| `layout.txt` | the disk's structure: the VTOC settings (volume, catalog start, DOS's allocation state, and the `$04` DOS's INIT writes in its first byte), the 15 catalog sectors, and each file in catalog order with its type and the sectors it occupies (its track/sector list, then its data sectors in order). The free-space bitmap and the catalog entries are generated from it. |
| `dos33.bin` | tracks 0-2 (12 KB): Apple DOS 3.3 as it was on the disk, which boots the machine and loads DOS. This is Apple's operating system, not part of the public-domain game; it is kept as an untouched binary so the disk boots, and it is not decompiled. |

Every byte not covered by these and the built files is zero: free sectors, the unused ends of
sectors, the spare bytes of the catalog and track/sector lists. The original disk had stale
data from other software in those places; see `disk/README.md` for why it was dropped.
`mkdisk.py` still accepts a `residue.bin` here (written by `mkdisk.py extract`) to reproduce an
original image exactly; the project does not include one.

Adding a file is not supported: the layout lists the existing 30 files. A file that grows gets
free sectors (`dos33.put`); one that shrinks keeps its sectors, as DOS does.

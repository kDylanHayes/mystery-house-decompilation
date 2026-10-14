# disk

The hashes the build checks against. The original disk image is no longer kept here.

| File | Contents |
|---|---|
| `SHA256` | the SHA-256 of the disk the build makes, `build/mystery_house.do`: `425f97d8dde1e8d6e5a5631136e2fb5d42d3c9f89c9f2215d3c6732f93e5020e` |
| `FILES.sha256` | the SHA-256 of each of the 30 files on the original disk (a text file up to its end marker), so every built file is still checked byte for byte against the original |

## Why the disk changed

The project started from the TOSEC dump *Hi-Res Adventure 1 - Mystery House (1980)(On-Line
Systems)(PD).do* (SHA-256 `5e94463cf131fd16db831dc360adcb02aaada491e8d8325d2b447051b1ea4771`),
and the build used to reproduce that image byte for byte. Besides the public-domain game, that
image carries 34,433 bytes of stale data that DOS never reads: 32,975 bytes in the sectors DOS
lists as free and 1,458 in the unused ends of file sectors. They are fragments of other,
copyrighted software that was on the disk before the 1987 master was copied (Bob Bishop's
*Dung Beetles*, cracking-group title screens, a fast loader, pieces of DOS).

This project keeps only public-domain material, so those bytes were dropped: the build now
leaves them as zeros, and the original image was taken out of the repository. Everything DOS
reads is unchanged: the 30 files (checked against `FILES.sha256`), the catalog, the track/sector
lists, the volume table of contents and DOS 3.3 itself on tracks 0-2. So the built disk works
exactly as the original, and its hash is the clean one in `SHA256`.

`tools/mkdisk.py extract` can still turn an original image into `src/disk/` plus a
`residue.bin`, with which the build would reproduce that image exactly; the repository does not
use one. The image itself and the removed bytes remain in this repository's git history from
before the change.

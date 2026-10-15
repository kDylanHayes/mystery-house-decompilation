"""The disk: the full build matches the recorded hashes, and files can grow and shrink."""
import hashlib
import os
import shutil
import tempfile
import unittest

import helpers
import diskfiles
import dos33


def read(path):
    with open(path, 'rb') as f:
        return f.read()


class FullBuild(unittest.TestCase):
    def test_disk_matches_the_recorded_hash(self):
        b = helpers.build()
        with open(os.path.join(helpers.ROOT, 'disk', 'SHA256')) as f:
            want = f.read().strip()
        self.assertEqual(hashlib.sha256(read(os.path.join(b, 'mystery_house.do'))).hexdigest(), want)

    def test_every_file_matches_the_original(self):
        b = helpers.build()
        out = helpers.tool('diskfiles.py', 'verify', os.path.join(b, 'files'),
                           os.path.join(helpers.ROOT, 'disk', 'FILES.sha256'))
        self.assertIn('all %d files match' % len(diskfiles.FILES), out)

    def test_extracted_catalog_lists_all_files(self):
        with open(os.path.join(helpers.build(), 'files', 'CATALOG.txt')) as f:
            text = f.read()
        for name, *_ in diskfiles.FILES:
            self.assertIn(' %s ' % name, text)

    def test_catalog_lists_all_files(self):
        disk = read(os.path.join(helpers.build(), 'mystery_house.do'))
        names = [name for name, *_ in dos33.catalog(disk)]
        self.assertEqual(sorted(names), sorted(n for n, *_ in diskfiles.FILES))


class Put(unittest.TestCase):
    def setUp(self):
        self.disk = bytearray(read(os.path.join(helpers.build(), 'mystery_house.do')))

    def file(self, name):
        for n, ftype, locked, t, s, count in dos33.catalog(bytes(self.disk)):
            if n == name:
                return dos33.read_file(bytes(self.disk), t, s), count, dos33.file_sectors(bytes(self.disk), t, s)
        raise KeyError(name)

    def test_a_binary_file_can_grow(self):
        data = bytes(range(256)) * 10                       # 2560 bytes: more sectors than BLOCK19 has
        _, before, _ = self.file('BLOCK19')
        dos33.put(self.disk, 'BLOCK19', 0x4400, data)
        raw, after, _ = self.file('BLOCK19')
        self.assertEqual(raw[:4], bytes([0x00, 0x44, len(data) & 0xFF, len(data) >> 8]))
        self.assertEqual(raw[4:4 + len(data)], data)
        self.assertGreater(after, before)

    def test_a_shrinking_file_keeps_its_sectors(self):
        _, before, _ = self.file('BLOCK1')
        dos33.put(self.disk, 'BLOCK1', 0x4400, b'\x00\x00\x01\x02\xff\xff')
        raw, after, _ = self.file('BLOCK1')
        self.assertEqual(raw[2:4], bytes([6, 0]))
        self.assertEqual(after, before)

    def test_text_and_basic_files(self):
        dos33.put(self.disk, 'MESSAGES', None, b'\xc8\xc9\x8d\x00')
        raw, _, _ = self.file('MESSAGES')
        self.assertEqual(raw[:4], b'\xc8\xc9\x8d\x00')
        dos33.put(self.disk, 'HELLO', None, b'\x00\x00\x0a')
        raw, _, _ = self.file('HELLO')
        self.assertEqual(raw[:5], b'\x03\x00\x00\x00\x0a')

    def test_wrong_file_types_are_refused(self):
        with self.assertRaises(SystemExit):
            dos33.put(self.disk, 'MESSAGES', 0x4000, b'x')
        with self.assertRaises(SystemExit):
            dos33.put(self.disk, 'NO SUCH FILE', 0x4000, b'x')

    def test_the_free_space_map_stays_consistent(self):
        dos33.put(self.disk, 'BLOCK19', 0x4400, bytes(4000))
        used = {(17, 0)} | {(17, s) for s in range(1, 16)} | {(t, s) for t in range(3) for s in range(16)}
        for n, ftype, locked, t, s, count in dos33.catalog(bytes(self.disk)):
            lists, data = dos33.file_sectors(bytes(self.disk), t, s)
            used |= set(lists) | set(data)
        vtoc = 17 * 16 * 256
        for t in range(35):
            for s in range(16):
                o = vtoc + 0x38 + 4 * t + (0 if s >= 8 else 1)
                free = bool(self.disk[o] & (1 << (s - 8 if s >= 8 else s)))
                self.assertEqual(free, (t, s) not in used, (t, s))



class Residue(unittest.TestCase):
    """mkdisk.py lays src/disk/residue.bin (stale bytes no structure accounts for) under
    everything else, so the original image, stale data and all, could be rebuilt from one. The
    project has no residue; here a made-up one fills every free sector."""

    def test_residue_fills_the_free_sectors_and_nothing_else(self):
        b = helpers.build()
        clean = read(os.path.join(b, 'mystery_house.do'))
        vtoc = 17 * 16 * 256
        free = [t * 16 + sec for t in range(35) for sec in range(16)
                if clean[vtoc + 0x38 + 4 * t + (0 if sec >= 8 else 1)] >> (sec - 8 if sec >= 8 else sec) & 1]
        self.assertTrue(free)
        d = tempfile.mkdtemp(prefix='mh-residue-')
        disk = os.path.join(d, 'disk')
        shutil.copytree(os.path.join(helpers.SRC, 'disk'), disk)
        with open(os.path.join(disk, 'residue.bin'), 'wb') as f:
            for n in free:
                o = n * 256
                f.write(bytes([o & 0xFF, o >> 8 & 0xFF, o >> 16, 0, 1]) + bytes([n & 0xFF]) * 256)
        with open(os.path.join(b, 'put.txt')) as f:
            put = [l.rstrip('\n') for l in f]
        image = os.path.join(d, 'stale.do')
        helpers.tool('mkdisk.py', 'build', disk, image, *put)
        stale = read(image)
        for n in range(35 * 16):
            sector = stale[n * 256:(n + 1) * 256]
            want = bytes([n & 0xFF]) * 256 if n in free else clean[n * 256:(n + 1) * 256]
            self.assertEqual(sector, want, 'sector %d' % n)
        # the files read back from it are the same
        out = os.path.join(d, 'files')
        helpers.tool('dos33.py', image, out)
        for name in sorted(os.listdir(os.path.join(b, 'files'))):
            self.assertEqual(read(os.path.join(out, name)), read(os.path.join(b, 'files', name)), name)

if __name__ == '__main__':
    unittest.main()

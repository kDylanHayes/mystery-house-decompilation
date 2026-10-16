"""tools/progress.py: the matching-progress report in objdiff's format. On the source as it is,
everything matches; with one routine changed (and everything after it moved), only that
routine, and the file it is in, stop matching."""
import hashlib
import json
import os
import shutil
import tempfile
import unittest

import helpers
import diskfiles  # noqa: E402 (helpers puts tools/ on the path)

EXPECTED = os.path.join(helpers.ROOT, 'disk', 'expected')
SUMS = os.path.join(helpers.ROOT, 'disk', 'FILES.sha256')


def run_report(build_dir):
    out = os.path.join(tempfile.mkdtemp(prefix='mh-progress-'), 'report.json')
    helpers.tool('progress.py', 'report', build_dir, os.path.join(build_dir, 'files'), EXPECTED, SUMS, out)
    with open(out) as f:
        return json.load(f)


def unit(report, name):
    return next(u for u in report['units'] if u['name'] == name)


class Matching(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.report = run_report(helpers.build())

    def test_expected_programs_are_the_original(self):
        want = {}
        with open(SUMS) as f:
            for line in f:
                h, name = line.rstrip('\n').split('  ', 1)
                want[name] = h
        for disk_name, binary in (('ADVENTURE', 'ADVENTURE.bin'), ('AUTO LOAD OBJ', 'AUTO_LOAD_OBJ.bin')):
            with open(os.path.join(EXPECTED, binary), 'rb') as f:
                self.assertEqual(hashlib.sha256(f.read()).hexdigest(), want[disk_name])

    def test_everything_matches(self):
        m = self.report['measures']
        self.assertEqual(m['fuzzy_match_percent'], 100.0)
        self.assertEqual(m['matched_functions'], m['total_functions'])
        self.assertEqual(m['matched_code'], m['total_code'])
        self.assertEqual(m['matched_data'], m['total_data'])
        self.assertEqual(m['complete_units'], len(diskfiles.FILES))
        self.assertGreater(m['total_functions'], 150)

    def test_objdiff_report_format(self):
        # objdiff's report.proto, version 2, JSON with the proto field names, 64-bit counts as
        # strings
        r = self.report
        self.assertEqual(r['version'], 2)
        self.assertEqual({c['id'] for c in r['categories']}, {'programs', 'files'})
        for key in ('total_code', 'matched_code', 'total_data', 'matched_data', 'complete_code'):
            self.assertIsInstance(r['measures'][key], str)
        adv = unit(r, 'ADVENTURE')
        self.assertEqual([s['name'] for s in adv['sections']], ['.text', '.data'])
        f = next(x for x in adv['functions'] if x['name'] == 'draw_picture')
        self.assertEqual(f['fuzzy_match_percent'], 100.0)
        self.assertIn('virtual_address', f['metadata'])
        self.assertEqual(adv['metadata']['progress_categories'], ['programs'])


class OneRoutineChanged(unittest.TestCase):
    """Insert a NOP into `nothing` (called every turn): it no longer matches, nor does
    ADVENTURE as a file, but every routine after it, moved by a byte, still does."""

    @classmethod
    def setUpClass(cls):
        src = os.path.join(tempfile.mkdtemp(prefix='mh-progress-src-'), 'src')
        shutil.copytree(helpers.SRC, src)
        path = os.path.join(src, 'adventure.s')
        with open(path) as f:
            text = f.read()
        old = 'nothing:\n        RTS\n'
        assert old in text
        with open(path, 'w') as f:
            f.write(text.replace(old, 'nothing:\n        NOP\n        RTS\n'))
        cls.report = run_report(helpers.build(src))

    def test_only_that_routine_differs(self):
        adv = unit(self.report, 'ADVENTURE')
        changed = [f['name'] for f in adv['functions'] if f['fuzzy_match_percent'] < 100]
        self.assertEqual(changed, ['nothing'])
        nothing = next(f for f in adv['functions'] if f['name'] == 'nothing')
        self.assertGreater(nothing['fuzzy_match_percent'], 0)
        self.assertFalse(adv['metadata']['complete'])
        self.assertEqual(adv['measures']['matched_functions'], adv['measures']['total_functions'] - 1)

    def test_the_rest_is_untouched(self):
        self.assertTrue(unit(self.report, 'AUTO LOAD OBJ')['metadata']['complete'])
        self.assertTrue(unit(self.report, 'MESSAGES')['metadata']['complete'])
        m = self.report['measures']
        self.assertLess(m['fuzzy_match_percent'], 100.0)
        self.assertEqual(m['complete_units'], m['total_units'] - 1)


if __name__ == '__main__':
    unittest.main()

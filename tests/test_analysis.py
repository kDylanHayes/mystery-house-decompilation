"""The analysis tools: gamedata.py (the game database), trace6502.py (code discovery for the
Ghidra step) and source_fragments.py (the original source in the binary). Each is checked
against something independent: the assembler's symbol table and listing, and what the game
actually executes while the play scripts run (helpers.played)."""
import csv
import json
import os
import re
import tempfile
import unittest

import helpers
import gamecov  # noqa: E402 (helpers puts tools/ on the path)


def symbols(build_dir):
    with open(os.path.join(build_dir, 'adventure.syms.csv')) as f:
        return {r['name']: int(r['address'], 16) for r in csv.DictReader(f)}


class GameData(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        b = helpers.build()
        cls.out = tempfile.mkdtemp(prefix='mh-gamedata-')
        helpers.tool('gamedata.py', os.path.join(b, 'files'), cls.out, os.path.join(b, 'adventure.syms.csv'))
        with open(os.path.join(cls.out, 'gamedata.json')) as f:
            cls.data = json.load(f)
        cls.syms = symbols(b)

    def text(self, name):
        with open(os.path.join(self.out, name)) as f:
            return f.read()

    def test_table_sizes(self):
        d = self.data
        self.assertEqual([len(d[k]) for k in ('verbs', 'nouns', 'messages', 'rooms', 'objects', 'pictures',
                                              'command_rules', 'turn_rules')],
                         [43, 89, 167, 41, 54, 97, 348, 10])

    def test_rules_are_where_the_assembler_put_them(self):
        # the decoder walks the rule tables by their length bytes; every rule it finds must
        # start at one of the source's rule_XXXX labels, and every label must be found
        found = {r['addr'] for r in self.data['command_rules'] + self.data['turn_rules']}
        labels = {a for n, a in self.syms.items() if gamecov.RULE.match(n)}
        self.assertEqual(found, labels)

    def test_a_rule(self):
        # the porch door: in room 2, GO DOOR, if the door is open: into the hall, which locks
        rule = next(r for r in self.data['command_rules'] if r['addr'] == self.syms['rule_4567'])
        self.assertEqual((rule['room'], rule['verb'], rule['noun']), (2, 1, 25))
        self.assertEqual(rule['conditions'], [{'op': 'SWITCH_EQ', 'args': [12, 1]}])
        self.assertEqual([a['op'] for a in rule['actions']], ['GOTO_ROOM', 'SET_SWITCH', 'MESSAGE'])
        self.assertIn('go to room 3 (IN AN ENTRY HALL)', self.text('rules.txt'))

    def test_rooms_and_map(self):
        room1 = self.data['rooms'][0]
        self.assertEqual((room1['RROOMNO'], room1['RU']), (1, 2))
        self.assertIn('    GO TREE -> 5\n', self.text('map.txt'))
        self.assertIn('-> 19', self.text('map.txt'))      # the hole the sledgehammer makes

    def test_start_is_how_the_game_starts(self):
        # the state init_game leaves, read from the game waiting at its first prompt
        import play
        m, reason = play.play(os.path.join(helpers.build(), 'files'), [])
        self.assertEqual(reason, 'end of commands')
        at = lambda name, n=1: list(m.mem[self.syms[name]:self.syms[name] + n])
        start = self.data['start']
        self.assertEqual(at('CURONO'), [start['room']])
        self.assertEqual(at('turns', 2), [start['turn'] & 0xFF, start['turn'] >> 8])
        self.assertEqual(at('SWITCH', 20), start['switches'])
        self.assertEqual(at('LAMPSTAT'), [0 if start['light'] else 1])

    def test_saved_game_is_what_restore_loads(self):
        # the game's memory just after RESTORE GAME's BLOAD (at the action's exit, before the
        # turn rules run) holds what saved_game says
        import play
        syms, seen = self.syms, []

        def setup(m):
            m.executed = set()
            m.hooks[syms['AC2600']] = lambda mach: seen.append(None)
            m.hooks[syms['AC9000']] = lambda mach: (seen.append(bytes(mach.mem))
                                                    if seen and seen[-1] is None else None)
        play.play(os.path.join(helpers.build(), 'files'), ['RESTORE GAME'], setup=setup)
        mem = seen[-1]
        f, sg = self.fields(), self.data['saved_game']
        self.assertEqual(mem[syms['CURONO']], sg['room'])
        self.assertEqual(mem[syms['turns']] | mem[syms['turns'] + 1] << 8, sg['turn'])
        self.assertEqual(list(mem[syms['SWITCH']:syms['SWITCH'] + 20]), sg['switches'])
        self.assertEqual(mem[syms['LAMPSTAT']] == 0, sg['light'])
        self.assertEqual((mem[syms['verb']], mem[syms['noun']]), (sg['verb'], sg['noun']))
        for o, saved in zip(self.data['objects'], sg['objects']):
            self.assertEqual(saved['OBJECTNO'], o['OBJECTNO'])
            for k in ('OROOM', 'OPIC', 'OXCOORD', 'OYCOORD', 'OSTATUS'):
                self.assertEqual(mem[o['addr'] + f[k]], saved[k], (o['OBJECTNO'], k))
        for r in sg['rooms']:
            a = syms['ROOMBASE'] + r['RROOMNO'] * f['RTBLSIZ']
            self.assertEqual((mem[a + f['RBASEPIC']], mem[a + f['RCURPIC']]), (r['RBASEPIC'], r['RCURPIC']))

    def test_loader_pages_are_what_it_prints(self):
        # the intro script plays the loader: each page in gamedata.json is what the transcript
        # shows after the matching <HOME>, up to the RETURN that ends the page
        out = helpers.played('intro')[0].out
        homes = [i for i, l in enumerate(out) if l == '<HOME>']
        pages = self.data['loader']['pages']
        self.assertEqual(len(homes), len(pages))
        for i, page in zip(homes, pages):
            end = next(j for j in range(i + 1, len(out)) if out[j].startswith('>'))
            self.assertEqual(out[i + 1:end], [l.rstrip() for l in page])
        menu = [l.rstrip() for l in self.data['loader']['menu']]
        x = out.index('> X')
        self.assertEqual(out[x - len(menu):x], menu)

    def fields(self):
        names = {}
        with open(os.path.join(helpers.SRC, 'game.inc')) as f:
            for line in f:
                p = line.split(';')[0].split('=')
                if len(p) == 2 and p[0].strip().isidentifier():
                    try:
                        names[p[0].strip()] = int(p[1].strip().replace('$', '0x'), 0)
                    except ValueError:
                        pass
        return names

    def test_json_is_compact(self):
        # number lists, points and strokes are written on one line each, not a number a line
        with open(os.path.join(self.out, 'gamedata.json')) as f:
            lines = f.read().splitlines()
        self.assertEqual([l for l in lines if re.fullmatch(r'\s*-?\d+,?', l)], [])

    def test_vocabulary_and_messages(self):
        self.assertIn(' 26  WITH, USE, SHOOT, FIRE\n', self.text('vocabulary.txt'))
        self.assertIn('CONGRATULATIONS YOU HAVE BEATEN', self.text('messages.txt'))


class Tracer(unittest.TestCase):
    """trace6502.py decides which bytes are code for Ghidra, by following the program from its
    entry points. It must find every instruction the game executes, and agree with the
    assembler's listing except in code nothing reaches."""

    @classmethod
    def setUpClass(cls):
        b = helpers.build()
        out = os.path.join(tempfile.mkdtemp(prefix='mh-trace-'), 'plan.json')
        helpers.tool('trace6502.py', '--symbols', os.path.join(b, 'adventure.syms.csv'),
                     os.path.join(helpers.ROOT, 'ghidra', 'programs', 'adventure.json'),
                     os.path.join(b, 'ADVENTURE.bin'), out)
        with open(out) as f:
            cls.plan = json.load(f)
        cls.traced = {a for a, _ in cls.plan['code']}
        cls.listed = gamecov.instructions(os.path.join(b, 'adventure.lst'))
        cls.syms = symbols(b)

    def routine(self, addr):
        """The routine (top-level label) an address is in."""
        return max((a, n) for n, a in self.syms.items() if a <= addr and '__' not in n
                   and not gamecov.RULE.match(n))[1]

    def test_everything_executed_was_traced(self):
        executed = set()
        for name in helpers.SCRIPTS:
            executed |= helpers.played(name)[2]
        executed = {a for a in executed if 0x0800 <= a < 0x7D00}
        self.assertEqual(executed - self.traced, set())

    def test_tracer_and_listing_agree(self):
        # the listing has the dead disk-error handler, which nothing calls; the tracer reads
        # the messages_open flag byte as an instruction, since rt_print returns into it
        self.assertEqual({self.routine(a) for a in self.listed - self.traced}, {'dead_disk_error', 'messages_open'})
        self.assertEqual({self.routine(a) for a in self.traced - self.listed}, {'messages_open'})

    def test_inline_operand_calls(self):
        # every JSR to a routine that takes inline operands is found, outside dead code
        routines = {int(a, 16) for a in self.plan['inline_routines']}
        calls = set()
        with open(os.path.join(helpers.build(), 'adventure.lst')) as f:
            for line in f:
                m = re.match(r'([0-9A-F]{4})  20 ([0-9A-F]{2}) ([0-9A-F]{2})\s+JSR ', line)
                if m and int(m.group(3) + m.group(2), 16) in routines:
                    calls.add(int(m.group(1), 16))
        traced = {c['call'] for c in self.plan['inline']}
        self.assertEqual({self.routine(a) for a in calls - traced}, {'dead_disk_error'})
        self.assertEqual(traced - calls, set())


class SourceFragments(unittest.TestCase):
    def test_the_archive_comes_back(self):
        # original_source/ was recovered from the original ADVENTURE; the built one still holds
        # the same stale bytes, so decoding it must give the archive exactly
        out = tempfile.mkdtemp(prefix='mh-fragments-')
        helpers.tool('source_fragments.py', os.path.join(helpers.build(), 'ADVENTURE.bin'), out)
        archive = os.path.join(helpers.ROOT, 'original_source')
        names = ['fragments.s'] + ['raw/' + n for n in sorted(os.listdir(os.path.join(archive, 'raw')))]
        self.assertEqual(sorted(os.listdir(os.path.join(out, 'raw'))), sorted(os.listdir(os.path.join(archive, 'raw'))))
        for n in names:
            with open(os.path.join(out, n), 'rb') as a, open(os.path.join(archive, n), 'rb') as b:
                self.assertEqual(a.read(), b.read(), n)



class GenSource(unittest.TestCase):
    """tools/gen_source.py made the first src/ from the binaries (trace plan + names). It is
    not run any more, but must still work: its output for each program reassembles to the same
    bytes."""

    def check(self, prog, binary):
        b = helpers.build()
        d = tempfile.mkdtemp(prefix='mh-gensource-')
        ghidra = os.path.join(helpers.ROOT, 'ghidra')
        plan, syms, out = (os.path.join(d, n) for n in ('plan.json', 'symbols.csv', prog + '.s'))
        helpers.tool('trace6502.py', '--symbols', os.path.join(b, prog + '.syms.csv'),
                     os.path.join(ghidra, 'programs', prog + '.json'), os.path.join(b, binary), plan)
        helpers.tool('ghidra_symbols.py', os.path.join(b, prog + '.syms.csv'),
                     os.path.join(ghidra, 'symbols', 'apple2.csv'), os.path.join(ghidra, 'symbols', prog + '.csv'), syms)
        helpers.tool('gen_source.py', prog, os.path.join(b, 'files', binary), plan, syms, out, os.path.join(d, 'data'))
        helpers.tool('asm6502.py', '-I', os.path.join(b, 'gen'), '-I', helpers.SRC, out, os.path.join(d, 'out.bin'))
        with open(os.path.join(d, 'out.bin'), 'rb') as f, open(os.path.join(b, binary), 'rb') as g:
            self.assertEqual(f.read(), g.read())

    def test_adventure(self):
        self.check('adventure', 'ADVENTURE.bin')

    def test_autoload(self):
        self.check('autoload', 'AUTO_LOAD_OBJ.bin')

if __name__ == '__main__':
    unittest.main()

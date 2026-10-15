#!/usr/bin/env python3
"""Measure how much of ADVENTURE a set of play scripts exercises.

usage: gamecov.py <build dir> <files dir> <script.txt>... [--rules rules.txt] [--detail]

A script named intro.txt is played from the loader (play.py --boot); the others from the game.

<build dir> holds adventure.lst and adventure.syms.csv (build/, as build.sh leaves it);
<files dir> the disk's files (extracted/). Each script is played from a fresh start with
tools/play.py while every executed address is recorded, and so is every rule whose actions
run (the rule at rule_ptr when run_actions is entered).

The report (stdout) gives:
  instructions   how many of the program's instructions ran (from the listing)
  rules          how many command and turn rules ran their actions
  routines       every routine (a label without '__') none of whose instructions ran
  rules          every rule that never ran, described from --rules (assets/text/rules.txt)
--detail adds each partly covered routine with its count. The report is deterministic, so
tests/play/coverage.expected.txt records it for the scripts in tests/play/ and
tests/test_play.py checks it.
"""
import csv
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import play  # noqa: E402

RULE = re.compile(r'^rule_[0-9A-F]{4}$')


def instructions(listing):
    """Address of every instruction in an asm6502 listing (data lines are not counted)."""
    out = set()
    with open(listing) as f:
        for line in f:
            m = re.match(r'([0-9A-F]{4})  (?:[0-9A-F]{2} ){1,3}\s*[A-Z]{3}\b', line)
            if m:
                out.add(int(m.group(1), 16))
    return out


def symbols(path):
    with open(path) as f:
        return {r['name']: int(r['address'], 16) for r in csv.DictReader(f)}


def rule_text(path):
    """'$4510' -> the rule's description, one line, from rules.txt."""
    if not path:
        return {}
    text = {}
    with open(path) as f:
        for block in f.read().split('\n\n'):
            block = block.strip()
            if block.startswith('$'):
                addr, rest = block.split(None, 1)
                text[addr] = ' | '.join(l.strip() for l in rest.splitlines())
    return text


def play_recorded(build_dir, files_dir, script, more=None, boot=False):
    """Play one script while recording; returns (machine, stop reason, executed addresses,
    addresses of the rules whose actions ran). more(machine, symbols), if given, can add hooks;
    boot starts at the loader (play.py --boot)."""
    syms = symbols(os.path.join(build_dir, 'adventure.syms.csv'))
    executed, ran = set(), set()

    def setup(m):
        m.executed = executed
        m.hooks[syms['run_actions']] = lambda mach: ran.add(mach.rw(syms['rule_ptr']))
        if more:
            more(m, syms)

    m, reason = play.play(files_dir, play.read_commands(script), setup=setup, boot=boot)
    return m, reason, executed, ran


def measure(build_dir, files_dir, scripts):
    """Play each script; returns (executed addresses, addresses of the rules that ran)."""
    executed, ran = set(), set()
    for s in scripts:
        _, _, e, r = play_recorded(build_dir, files_dir, s, boot=os.path.basename(s) == 'intro.txt')
        executed |= e
        ran |= r
    return executed, ran


def report(build_dir, executed, ran, rules_txt=None, detail=False):
    syms = symbols(os.path.join(build_dir, 'adventure.syms.csv'))
    code = instructions(os.path.join(build_dir, 'adventure.lst'))
    hit = code & executed
    rules = {a: n for n, a in syms.items() if RULE.match(n)}
    turn_start, command_start = syms['turn_rules'], syms['command_rules']
    turn = {a for a in rules if turn_start <= a < command_start}
    command = set(rules) - turn
    out = ['instructions: %d of %d executed (%.1f%%)' % (len(hit), len(code), 100.0 * len(hit) / len(code)),
           'command rules: %d of %d ran' % (len(command & ran), len(command)),
           'turn rules: %d of %d ran' % (len(turn & ran), len(turn))]

    # routines: top-level code labels, each running to the next top-level label
    tops = sorted((a, n) for n, a in syms.items() if '__' not in n and not RULE.match(n))
    never, partly = [], []
    for i, (a, n) in enumerate(tops):
        end = tops[i + 1][0] if i + 1 < len(tops) else 0x10000
        if end == a:
            continue
        mine = {x for x in code if a <= x < end}
        if not mine:
            continue
        done = len(mine & executed)
        if done == 0:
            never.append('  %s (%d instructions)' % (n, len(mine)))
        elif done < len(mine):
            partly.append('  %s: %d of %d' % (n, done, len(mine)))
    out += ['', 'routines never entered: %d' % len(never)] + never
    if detail:
        out += ['', 'routines partly run: %d' % len(partly)] + partly

    text = rule_text(rules_txt)
    missed = sorted(a for a in rules if a not in ran)
    out += ['', 'rules that never ran: %d' % len(missed)]
    for a in missed:
        n = rules[a]
        desc = text.get('$' + n[5:], '')
        out.append(('  %s  %s' % (n, desc)).rstrip())
    return '\n'.join(out) + '\n'


def main():
    args = sys.argv[1:]
    rules_txt = None
    if '--rules' in args:
        i = args.index('--rules')
        rules_txt = args[i + 1]
        del args[i:i + 2]
    detail = '--detail' in args
    if detail:
        args.remove('--detail')
    if len(args) < 3:
        sys.exit(__doc__)
    build_dir, files_dir, scripts = args[0], args[1], args[2:]
    executed, ran = measure(build_dir, files_dir, scripts)
    sys.stdout.write(report(build_dir, executed, ran, rules_txt, detail))


if __name__ == '__main__':
    main()

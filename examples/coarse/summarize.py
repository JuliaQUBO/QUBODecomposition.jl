# SPDX-License-Identifier: MPL-2.0
"""Audit the one finite coarse campaign; never rerun or replace attempts."""
import hashlib
import json
from pathlib import Path
from statistics import median
import sys
import tomllib

folder = Path(sys.argv[1])
repo = Path(sys.argv[2])
plan = tomllib.loads((folder / 'plan.toml').read_text())
totals = tomllib.loads((folder / 'totals.toml').read_text())
rows = [tomllib.loads(path.read_text()) for path in sorted(folder.glob('attempt-[0-9][0-9].toml'))]
assert len(rows) == totals['arm_attempts'] == 18
assert [r['attempt'] for r in rows] == list(range(1, 19))
assert sum(r['child_assignments'] for r in rows) == totals['child_assignments'] <= 9216
assert totals['parent_invocations'] <= 36
assert totals['scalar_audit_assignments'] <= 512
for path, digest in plan['source_sha256'].items():
    assert hashlib.sha256((repo / path).read_bytes()).hexdigest() == digest, path
for name, files in plan['dependency_sha256'].items():
    dependency = Path(plan['dependency_roots'][name])
    for path, digest in files.items():
        assert hashlib.sha256((dependency / path).read_bytes()).hexdigest() == digest, (name, path)
for r in rows:
    assert r['child_assignments'] <= 512
    assert all(1 <= n <= 4 for n in r['child_dimensions'])
    assert sum(1 << n for n in r['child_dimensions']) == r['child_assignments']
    assert len(r['stages']) <= 2
    assert sum(s['calls'] for s in r['stages']) <= 64
    assert sum(s['candidate_evaluations'] for s in r['stages']) <= 1024
    if r['outcome'] == 'ok':
        assert len(r['stages']) == 2
        assert r['calls'] == sum(s['calls'] for s in r['stages'])
        assert r['candidate_evaluations'] == sum(s['candidate_evaluations'] for s in r['stages'])
        assert r['energy'] >= r['oracle_optimum']
        assert all(status == 'OPTIMAL' for stage in r['stages'] for status in stage['child_statuses'])

report = {'source_head': plan['source_head'], 'base': plan['base'], 'totals': totals,
          'prior_scalar_audit_assignments': plan['prior_scalar_audit_assignments'],
          'failed_attempts': [r for r in rows if r['outcome'] != 'ok'], 'fixtures': []}
for f in plan['fixtures']:
    selected = [r for r in rows if r['fixture'] == f['name'] and not r['warmup']]
    entry = {'fixture': f['name'], 'measured_attempts': [r['attempt'] for r in selected], 'modes': {}}
    for mode in ('partition', 'coarse'):
        arm = [r for r in selected if r['mode'] == mode]
        entry['modes'][mode] = {'outcomes': [r['outcome'] for r in arm]}
        if len(arm) == 2 and all(r['outcome'] == 'ok' for r in arm):
            entry['modes'][mode].update({key: [r[key] for r in arm] for key in (
                'energy', 'oracle_suboptimality', 'calls', 'candidate_evaluations',
                'child_assignments', 'wall_sec')})
            entry['modes'][mode]['median_wall_sec'] = median(r['wall_sec'] for r in arm)
            entry['modes'][mode]['phase_sec'] = {phase: [sum(s['phase_sec'][phase] for s in r['stages']) for r in arm]
                for phase in arm[0]['stages'][0]['phase_sec']}
    paired = []
    for repetition in (1, 2):
        pair = {r['mode']: r for r in selected if r['repetition'] == repetition}
        if set(pair) == {'partition', 'coarse'} and all(r['outcome'] == 'ok' for r in pair.values()):
            paired.append({key: pair['coarse'][key] - pair['partition'][key] for key in (
                'energy', 'oracle_suboptimality', 'calls', 'candidate_evaluations', 'child_assignments', 'wall_sec')})
    entry['paired_coarse_minus_partition'] = paired
    if paired:
        entry['median_paired_wall_sec'] = median(p['wall_sec'] for p in paired)
    report['fixtures'].append(entry)

print(json.dumps(report, indent=2))

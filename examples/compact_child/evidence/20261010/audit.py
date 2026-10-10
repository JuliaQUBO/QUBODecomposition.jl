# SPDX-License-Identifier: MPL-2.0
# Python 3.11+ standard-library audit; no solver execution or third-party packages.
import tomllib,statistics,hashlib,pathlib,json,sys,gzip
p=pathlib.Path(sys.argv[1])
raw=(p/'results.toml').read_bytes() if (p/'results.toml').is_file() else gzip.decompress((p/'results.toml.gz').read_bytes())
d=tomllib.loads(raw.decode())
assert len(d['attempts'])==24
assert d['environment']['julia_threads']==d['environment']['blas_threads']==1
assert all(not r['failed'] for r in d['attempts'])
assert sum(r['reserved_assignments'] for r in d['attempts'])==sum(r['actual_assignments'] for r in d['attempts'])==7680
assert d['preflight']['parent_bound']==7800
expected={'path15':(512,4,517,9,-60.),'star33':(128,64,133,69,-141.)}
for r in d['attempts']:
 assignments,calls,allparent,compactparent,energy=expected[r['fixture']]
 assert r['actual_assignments']==r['reserved_assignments']==assignments
 assert len(r['child_calls'])==calls
 assert r['rows_emitted']==(assignments if r['mode']=='all' else calls)
 assert r['parent_evaluations']==(allparent if r['mode']=='all' else compactparent)
 assert r['status']=='OPTIMAL' and r['proof_complete']
 assert r['energy']==r['original_energy']==r['reference']==energy
 assert all(x==1 for x in r['state'])
 proof=r['decomposition']['separator']
 assert proof['required_branches']==proof['started_branches']==proof['completed_branches']==proof['certified_branches']==2
 assert all(c['certificate_checked'] and not c['failed'] and c['actual_assignments']==c['reserved_assignments']<=256 and c['variables']<=8 for c in r['child_calls'])
 assert sum(c['valid_results'] for c in r['decomposition']['calls'])==r['rows_emitted']
 assert all(c['invalid_results']==0 and c['exact'] for c in r['decomposition']['calls'])
 assert sum(r['decomposition']['phase_sec'].values())<=r['elapsed_sec']+1e-9
 assert sum(c['certificate_selection_sec']+c['result_build_sec'] for c in r['child_calls'])<=r['decomposition']['phase_sec']['execution']
for trial_round in range(6):
 for name in expected:
  modes=[r['mode'] for r in d['attempts'] if r['round']==trial_round and r['fixture']==name]
  assert modes==(['all','compact'] if trial_round%2 else ['compact','all'])
for name,s in d['summary'].items():
 print(name)
 for mode in ['all','compact']:
  rs=[r for r in d['attempts'] if r['fixture']==name and r['mode']==mode and not r['warmup']]
  for key in ['elapsed_sec','allocation_bytes','gc_sec']:
   assert s[mode][key]['median']==statistics.median(r[key] for r in rs)
  print(mode,'time ms', {k:round(v*1000,6) for k,v in s[mode]['elapsed_sec'].items()},'alloc KiB median',s[mode]['allocation_bytes']['median']/1024)
 for pair in s['paired_compact_minus_all']['pairs']:
  rs={r['mode']:r for r in d['attempts'] if r['fixture']==name and r['round']==pair['round']}
  assert abs(pair['elapsed_sec']-(rs['compact']['elapsed_sec']-rs['all']['elapsed_sec']))<1e-12
 print('paired time ms',{k: v*1000 for k,v in s['paired_compact_minus_all']['elapsed_sec'].items()})
 for phase in ['execution','copying','validation_reconstruction','full_energy']:
  print(phase, {m:statistics.median(r['decomposition']['phase_sec'][phase] for r in d['attempts'] if r['fixture']==name and r['mode']==m and not r['warmup'])*1000 for m in ['all','compact']})
print('Validated attempts, paired order, work, proof, original scalar energy, timing containment and summaries.')
print('actual parent work',sum(r['parent_evaluations'] for r in d['attempts']))

# Audit paired medians/quantiles independently from per-lane medians, including
# the published paired allocation value (which need not equal lane-median difference).
for name,s in d['summary'].items():
    pairs=s['paired_compact_minus_all']['pairs']
    for metric in ['elapsed_sec','allocation_bytes']:
        xs=sorted(p[metric] for p in pairs)
        dist=s['paired_compact_minus_all'][metric]
        assert len(xs)==5
        for key,value in zip(['min','q25','median','q75','max'],xs):
            assert abs(dist[key]-value)<1e-12
if len(sys.argv)>2:
    report=pathlib.Path(sys.argv[2]).read_text()
    for name,s in d['summary'].items():
        rows=[line for line in report.splitlines() if line.startswith('| '+name+' |')]
        assert len(rows)==1
        cells=[c.strip() for c in rows[0].split('|')[1:-1]]
        dist=s['paired_compact_minus_all']
        wanted=[f"{dist['elapsed_sec'][k]*1000:.3f}" for k in ['min','q25','median','q75','max']]
        wanted.append(f"{dist['allocation_bytes']['median']/1024:.1f}")
        assert [c.replace('−','-') for c in cells[1:]]==wanted,(name,cells,wanted)
    print('Published paired time/allocated-byte table agrees with raw summary.')

# Bounded selector comparison

Use Julia 1.10 or later and a clean, committed candidate checkout. Clone
`JuliaQUBO/QUBOBenchmarks.jl` separately and check out merged pilot revision
`7dbe623c30fb674cef5ede6bdc46b7b99e07736b`. From this package root, run:

```sh
julia --startup-file=no --threads=1 examples/selection/run.jl /path/to/QUBOBenchmarks.jl /tmp/selection-comparison-new
```

The output directory must be new. The runner creates an isolated temporary Julia
project, pins ToQUBO 0.7.1, QUBODrivers 0.6.5 and QUBOTools 0.16.2, and develops
**this checkout**. It verifies the imported package path, clean candidate SHA/tree
and clean pilot revision. It never invokes the pilot's fixed-baseline bootstrap.
An optional `JULIA_DEPOT_PATH=/tmp/selection-depot` isolates package caches as well.
Package setup requires network access; the comparison uses only local CPU work.

The pinned pilot supplies its guarded ExactSampler, independent scalar/oracle
checks, three fixtures (disconnected, strongly coupled and constrained ToQUBO),
and source feasibility reconstruction. Two additional fixtures expose linear-bias
selection and joint improvement without positive individual gains. This runner
does not change the cross-repository campaign/storage harness.

Both policies use identical zero starts, seed 41, child capacity two, a shared
64-assignment allowance, at most 16 calls, three sweeps, 257 parent evaluations
and one stagnant sweep. The child checks eight-variable/256-assignment hard caps
and reserves work before dispatch. Actual assignments, term-evaluation work,
parent evaluations and all calls are retained. Equal allowances permit different
consumption; equal child-call counts would not establish equal work. Additional
four-assignment refusal probes retain both failures and their valid incumbents.

After symmetric warm-up, three paired repetitions alternate policy order. Full
execution includes fresh construction/ToQUBO compilation, loading, selection,
conditioning, conversion, child solving, reconstruction and result attachment.
Installation/import/warm-up and separately timed exhaustive audits are excluded.
Raw timing and work remain paired within each repetition. These tiny deterministic
runs do not estimate success probability, timing uncertainty or general speedup.

`evidence.json` retains source revisions, fixture hashes/formulas, dependency
versions/trees, limits, work, failures, timings and original/source checks. The
output directory also snapshots the isolated Project/Manifest. The known coupled
six-variable trap keeps capacity two: both policies can stop at energy 0 while
the exact reference is -24. Neither exact children nor an observed zero gap gives
coupled sweeps a global optimality certificate.

Recommendation: **adopt as opt-in**, retaining the default selector. Broader
datasets, policy/seed grids and statistical comparison remain under
QUBOBenchmarks issue #27. This comparison does not register, tag or release either
package or change the source submitted to General.

## Recorded candidate result

The committed [evidence](evidence.json) was produced by clean candidate
`3ce23073fc6058dad5ecbc5533e2a1377e82324a` (tree
`a53a86ac1975d37c58ce3a94b4cf15c4d1f59396`) on Julia 1.10.11, one Julia/BLAS
thread. Each energy/work count was identical across three measured repetitions;
times below are medians of full execution, not child-only timings.

| Fixture | Control energy / assignments / ms | Gain energy / assignments / ms |
| --- | --- | --- |
| Disconnected | -13.5 / 12 / 0.553 | -13.5 / 12 / 0.539 |
| Strongly coupled | 0 / 24 / 0.872 | 0 / 12 / 0.637 |
| Constrained | 1 / 40 / 3.431 | 12 / 20 / 2.817 |
| Linear/state bias | -8.5 / 32 / 1.165 | -8.5 / 16 / 0.661 |
| Joint move | -1 / 24 / 0.812 | -1 / 12 / 0.601 |

All 30 regular attempts returned valid binary QUBO states. Source feasibility is
separate: the constrained gain result `(z,b)=(2,1)` violates `z+2b<=3` by 1,
whereas the control returns feasible `(3,0)` with source objective 1. Gain's
compiled energy 12 includes the penalty; its source objective 2 is **not a
feasible solution**. Both policies report only `LOCALLY_SOLVED` on coupled inputs.
Both measured four-assignment refusal probes failed before a second dispatch and
retained the initial valid incumbent and four completed assignments.

Fewer assignments and small elapsed times therefore do not justify adopting gain
selection as the default or assuming preserved source quality. Use it as an
explicit experimental choice, validate original constraints, and defer any default
promotion pending broader evidence. Three repetitions on these tiny fixtures do
not support a speedup claim or timing threshold.

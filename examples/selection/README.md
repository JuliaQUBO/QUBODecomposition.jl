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
and source feasibility reconstruction. Additional fixtures expose linear-bias
selection, joint improvement without positive individual gains, and a path where
BFS fills capacity four beyond one hop. This runner
does not change the cross-repository campaign/storage harness.

All four policies (`:strongest_edge`, `:single_flip_gain`, `:bfs`,
`:random_blocks`) use identical zero starts, seed 41, child capacity two (four
on the multi-hop path), a shared 64-assignment allowance, at most 16 calls, three sweeps, 257 parent evaluations
and one stagnant sweep. The child checks eight-variable/256-assignment hard caps
and reserves work before dispatch. Actual assignments, term-evaluation work,
parent evaluations and all calls are retained. Equal allowances permit different
consumption; equal child-call counts would not establish equal work. Additional
four-assignment refusal probes retain all failures and their valid incumbents.

After symmetric warm-up, three paired repetitions alternate policy order. Full
execution includes fresh construction/ToQUBO compilation, loading, selection,
conditioning, conversion, child solving, reconstruction and result attachment.
Installation/import/warm-up and separately timed exhaustive audits are excluded.
Raw timing and work remain paired within each repetition. `selection_sec` is a
measured subset of `phase_sec.preparation`; conditioning and validation/reconstruction
have their own disjoint phase durations. The raw data retain each of these costs. These tiny deterministic
runs do not estimate success probability, timing uncertainty or general speedup.

`evidence.json` retains source revisions, fixture hashes/formulas, dependency
versions/trees, limits, work, failures, timings and original/source checks. The
output directory also snapshots the isolated Project/Manifest. The known coupled
six-variable trap keeps capacity two: all four policies can stop at energy 0 while
the exact reference is -24. Neither exact children nor an observed zero gap gives
coupled sweeps a global optimality certificate.

Recommendation: **adopt as opt-in**, retaining the default selector. Broader
datasets, policy/seed grids and statistical comparison remain under
QUBOBenchmarks issue #27. This comparison does not register, tag or release either
package or change the source submitted to General.

## Recorded candidate result

The four-policy results below are generated from this feature's clean committed
candidate. The earlier two-policy evidence remains in [PR #19's recorded
comparison](https://github.com/JuliaQUBO/QUBODecomposition.jl/blob/7b891df244d0317eb9e9b825e21508ecd6cc19ed/examples/selection/README.md).

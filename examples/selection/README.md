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

The committed [evidence](evidence.json) uses candidate `873b2c602fe2bcc360f6ec8490215d9d8cc3aba1`
(tree `b0ea1415eca1353cddcf2e18cb1d5db1f803cdcf`), Julia 1.10.11, one Julia/BLAS
thread, and the released package versions/trees recorded in its environment.
The final evidence commit changes documentation/data only. All energy and work
counts were identical across the three measured repetitions. Cells below contain
**parent energy / completed child assignments / median full-execution ms**.

| Fixture | Strongest edge | Single-flip gain | BFS | Random blocks |
| --- | --- | --- | --- | --- |
| disconnected | -13.5 / 12 / 0.535 | -13.5 / 12 / 0.511 | -13.5 / 12 / 0.500 | -13.5 / 12 / 0.536 |
| strongly coupled | 0 / 24 / 0.928 | 0 / 12 / 0.566 | 0 / 24 / 0.872 | 0 / 12 / 0.545 |
| constrained | 1 / 40 / 3.318 | 12 / 20 / 2.722 | 1 / 40 / 3.372 | 1 / 30 / 3.444 |
| linear state | -8.5 / 32 / 1.176 | -8.5 / 16 / 0.644 | -8.5 / 32 / 1.053 | -8.5 / 16 / 0.635 |
| joint move | -1 / 24 / 0.839 | -1 / 12 / 0.660 | -1 / 24 / 0.765 | 0 / 6 / 0.356 |
| multi hop path | -4 / 60 / 1.662 | -4 / 40 / 0.798 | -3 / 64 / 1.217 | 0 / 20 / 0.494 |

All 72 regular attempts retained valid binary incumbents. Six attempts (three
repetitions each of strongest-edge and BFS on the path) ended in `OTHER_ERROR`:
the guarded child refused a dispatch that would exceed the shared 64-assignment
allowance. Strongest-edge had completed 60 assignments and reached energy -4;
BFS completed 64 and reached -3. Refusal is retained as failure, even when an
incumbent matches the independent optimum. Four additional four-assignment probes
(one per policy) also refused before a second dispatch and retained their valid
initial incumbents and four completed assignments.

Random blocks used only six assignments on the joint-move fixture but stagnated
at 0 instead of -1. On the path they stagnated at 0 instead of -4. All four
policies remain at 0 on the six-bit coupled trap versus the global reference -24.
These are quality/work tradeoffs, not evidence of general superiority.

For the constrained fixture, strongest-edge, BFS and random blocks return feasible
`(z,b)=(3,0)`, source objective 1. Random blocks stop at the three-sweep cap with
`ITERATION_LIMIT`. Gain returns `(2,1)`, residual 1, source objective 2 and compiled
energy 12: the source point is infeasible. A binary QUBO state and exact children
do not establish original constraint feasibility.

For the capacity-four path, measured overhead medians are:

| Policy | Selection (µs) | Conditioning (ms) | Validation/reconstruction (ms) |
| --- | --- | --- | --- |
| strongest_edge | 5.056 | 0.032 | 0.171 |
| single_flip_gain | 3.615 | 0.016 | 0.114 |
| bfs | 2.482 | 0.017 | 0.165 |
| random_blocks | 4.468 | 0.009 | 0.061 |

The raw evidence retains all phase costs for every fixture/repetition. These
separate medians need not sum to the median full runtime. Timing on tiny fixtures,
one seed and three repetitions does not establish a speedup, success probability
or acceptable timing threshold. Keep the default, use the new policies explicitly,
and continue broader comparisons under QUBOBenchmarks #27.

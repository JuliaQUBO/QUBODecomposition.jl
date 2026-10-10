# Compact certified child result experiment

This test/example-only adapter evaluates [issue #24](https://github.com/JuliaQUBO/QUBODecomposition.jl/issues/24),
following [QUBOBenchmarks PR #31](https://github.com/JuliaQUBO/QUBOBenchmarks.jl/pull/31).
Production algorithms and APIs are unchanged. Released ExactSampler still reports
its conservative `LOCALLY_SOLVED` public status. This adapter is not a new released solver.

Both modes perform the same guarded ExactSampler exhaustive solve and create the
full result. Both check source completion metadata, evaluation count, row count,
frame, variable ordering, every row's primal status/domain/objective, unit
multiplicities and complete distinct assignment coverage. The compact mode then
returns one optimal incumbent, breaking exact energy ties lexicographically in
original child-variable order. It does not enumerate all optima. Parent behavior
still preserves an equally good initial incumbent; equivalent solves need not
return the same state. No source row can escape checks by being discarded.

The adapter's public `OPTIMAL` is installed only after the full source contract
passes. It clears previous attachments before every solve and gives the internal
sampler a private model copy. Exceptions and failed source checks cannot leave a
previous certificate attached. The parent still validates every emitted row,
reconstructs and independently evaluates the original energy, and requires every
separator branch/component to finish before certifying the global optimum.

Run the comparison from a clean committed checkout with Julia 1.10+:

```sh
JULIA_NUM_PRECOMPILE_TASKS=1 julia --startup-file=no --threads=1 examples/compact_child/run.jl /tmp/compact-results-new /tmp/compact-cumulative.toml
```

The runner creates an isolated environment, develops this checkout and pins
QUBOTools 0.16.2/QUBODrivers 0.6.5. Network is needed for bootstrap; solves are offline.
The copied resolved Project/Manifest describes the actual environment. Its local
checkout path is provenance; the bootstrap command is the portable rerun route.
Choose a new output path and retain the **same cumulative ledger** across failed
attempts/reruns for this experiment. Concurrent writers are unsupported.

Only supplied-separator path15/cap7 and star33/cap1 run. The fixtures match
[the pinned definitions](https://github.com/JuliaQUBO/QUBOBenchmarks.jl/blob/684a96b8e757b400964d062c4229aacc12a523e1/examples/decomposition/exact-scaling/scaling.jl):
`E(x)=1.5*(3-sum(x)-2*sum(x[i]*x[j] for edges))`, binary/min,
path edges `(i,i+1)`, star edges `(1,j)`. Separators are respectively `[8]` and `[1]`.
Every negative monomial reaches its lower bound at all ones, supplying an
independent attainable global bound. Tiny eight-variable family members are
cross-checked by a separate guarded scalar exhaustive oracle. These are easy
structured examples, not representative hard-instance optimization benchmarks.

One warmup and five measured repetitions per fixture/mode give **24 attempts**.
Paired mode order alternates by round. One Julia and one BLAS thread are required.
All modes retain identical equations, search work, plans, starts and child/parent
caps. Child work is separate from the production candidate budget. The latter
continues to count actual parent full-state evaluations, so compaction can change
when a tight parent budget suffices; it never changes that budget's semantics.

Preflight reserves 7,680 child assignments, a conservative 7,800 parent evaluation
bound (same all-row bound for both modes), and 512 independent oracle assignments
before running any part of the batch. Every child also reserves its own exhaustive
work before dispatch, including failures. Hard child/oracle caps are eight
variables and 256 assignments; per solve: 1,024 assignments, 128 calls and 2,049
parent evaluations. At most one full rerun fits cumulative ceilings of 48 attempts,
15,360 child assignments, 15,600 parent evaluations and 1,024 oracle assignments.
Failed attempts spend the reservation. A killed process leaves an incomplete
reserved batch, never a successful zero-cost solve. Time bounds are ten seconds
per solve and 300 seconds per batch, with cooperative parent cancellation;
JIT/opaque child calls, audits and filesystem work can overrun them. Work guards
bound exhaustive calls independently. Use a finite outer process timeout as well.

Complete `@timed` execution includes fresh fixture and parent construction,
loading, conditioning, conversion/copy, exhaustive search/full-result creation,
source certificate checking/selection, compaction/result construction, parent
validation/reconstruction and result attachment. **This does not measure a native
best-only solver that avoids full result creation.** Both modes pay identical
certificate checking/selection; their result construction and emitted-row
processing differ. Adapter nested timers stay inside parent child execution.
Production phase diagnostics are disjoint subsets, not a decomposition of all
complete time. Child-execution and parent-processing aliases must not be added
to phase sums. Allocation bytes are cumulative allocated bytes, not peak memory.

Independent scalar audits, bootstrap/import/JIT warmups, checkpoint serialization
and statistical summaries are outside per-solve timing. Warmup attempts are
retained and excluded from distributions. No profiler runs or timing assertions
are added to CI. The existing package suite includes focused deterministic
certificate/domain/mapping/budget/interruption/repeated-solve tests.

`results.toml` retains all attempts, failures, work, proof/completion diagnostics,
original states/energies, fixture equations, source SHA/hashes, environment, locks,
limits and paired distributions. Diagnostic `nothing` values serialize as the
literal string `__nothing__`; MOI enums and mapping keys serialize as strings.
Checkpoints serialize/write/close before atomic replacement. Historical benchmark
artifacts remain untouched. See [REPORT.md](REPORT.md) for the measured decision.

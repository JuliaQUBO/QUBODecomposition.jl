# PR 45 review correction evidence

The blocking review finding `coarse-contradictory-optimal-child` is corrected by
`f3affd3429e8e5d0dd2ff03b3ede08e55640f590`. An `OPTIMAL` coarse child must now
be consistent with its feasible no-flip macro point before staged results are
committed or marked complete/exact. The guard sums the actual exported,
coefficient-wise scaled Float64 polynomial as exact rationals and applies the
existing absolute/relative tolerance of `1e-12`. Original-objective improvement
acceptance stays independent. Added arithmetic is timed and checks the deadline.

The retained reviewer probe demonstrates the pre-fix failure with three scripted
calls and no enumeration. It was reused, not rerun. The new regression cohort
covers both senses and domains, negative scales, construction/scaling rounding,
absolute/relative tolerance, limited/interrupted statuses and guard deadlines.
Both driver contracts passed 824 focused assertions; the candidate-driver full
CPU suite passed 60,537 assertions, including public JuMP/MOI and ToQUBO checks.
The standalone example and source Markdown link checker also passed. The first
focused attempt had a test parse error after its existing 716 assertions passed;
its unmodified log is retained alongside the successful attempt.

`verification.json` binds exact source, environment and counts. The new/old
Project and Manifest snapshots describe candidate 0.6.6 and General 0.6.5.
The wrapper command used `prlimit --as=8589934592:8589934592 timeout 600`, Julia,
precompile and OpenBLAS threads all one, offline package mode, and an isolated
writable depot layered over read caches. Full CPU process tests used approved
local sockets. These limits do not establish aggregate RSS/no-swap control.
Commands were `focused.jl` (the retained focused include script),
`Pkg.test("QUBODecomposition"; allow_reresolve=false)`,
`examples/coarse/offline.jl`, and `docs/check.jl` in the respective environments.
The intentional worker-loss fixture emits an EOF trace in the successful full
log; its worker exits by design. Unchanged old full/floor and Documenter evidence
is retained under the original evidence directory and was not repeated.

The original comparison directory remains byte-for-byte frozen. No arm, solver
call or scalar campaign audit was repeated for this correction. Its 360/512
scalar audit ledger includes the independent root check. Old campaign timings
predate the additional guard and do not measure the final implementation.
Formal review verification and exact-head remote CI remain publication gates.

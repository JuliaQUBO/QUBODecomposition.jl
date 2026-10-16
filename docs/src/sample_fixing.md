# Sample-guided variable fixing

`strategy=:sample_fixing` accepts a caller-supplied pool of complete original-domain
assignments and fixes one high-consensus variable at a time until the residual
fits `max_variables`. It is a separately opt-in heuristic. The package does not
run a hidden solver to generate its pool, and never sends an oversized residual
to the child. Install the exact development commit until this feature is released.

```julia
pool = (labels=[:a, :b, :c], domain=:bool,
        assignments=[[1, 0, 0], [1, 1, 0], [1, 0, 1]],
        provenance="caller supplied CPU candidates", generation_sec=nothing)
optimizer = QUBODecomposition.Optimizer(
    strategy=:sample_fixing, sample_pool=pool, fixing_threshold=1.0,
    max_variables=2, child_optimizer=() -> QUBODrivers.ExactSampler.Optimizer())
```

Pool labels must uniquely cover `decomposition.labels`, the current original free
variables after any MOI-fixed variables are removed. Their order may differ:
`original_to_pool` records the reorder. `domain` must explicitly be `:bool` or
`:spin` and match the original model. Assignments must be complete finite binary
or spin vectors. `provenance` is caller attribution, not proof of execution or
hardware sampling. Optional `generation_sec` is reported finite nonnegative
external cost; its default `nothing` means unknown, while an explicitly reported
zero means zero. Parent timings cannot measure work done before `optimize!`.
External generators must carry their own shared ledger when claiming total cost.

The hard input limits are 256 rows, 65,536 assignment cells, 65,536 labels and
1,024 provenance bytes, checked before package-owned copies. `max_pool_size`
(default 256, range 1:256) may lower the row cap. Setters, getters and retained
configuration snapshots own copies. Every supplied row, including duplicates,
is independently scored against the full original objective under the parent
candidate/time allowances. Only after the entire pool scan validates may its
best strict improvement commit. A malformed later row or incomplete scan discards
the staged pool improvement; later reduction failures retain a completed pool-best
commit. Equal-energy rows use lexicographic original-state order for proposals.

Each distinct state has one equal vote. Duplicate rows are charged before
being deduplicated, retaining their first source row ID. Child multiplicities
are not physical shots or probabilities. For each currently free index, count
the two values among the surviving distinct states. A choice needs a strict
majority and a fraction at least `fixing_threshold`, which defaults to 1.0 and
must lie in `(1/2,1]`. The comparison is exact against the stored Float64
threshold, including boundaries such as `nextfloat(2/3)`. Choose the highest
fraction, tie by original index, fix its majority value, filter incompatible
rows, then recompute support. Accepted choices cannot empty nonempty support.
Filtered candidates are selection-biased optimization evidence, not fresh samples.

Stop as soon as the residual fits, no variable qualifies, the pool is empty,
`max_fixings` (default 256, range 0:256) is reached, or parent work/time stops.
On abstention or an oversized residual at the fixing cap, return the best full
incumbent with a heuristic stop reason; there is no implicit fallback sweep.
Configuration and pool validation precede constant shortcuts. Only serial
execution and default selection are supported; component executors, explicit
partition/consensus/coarse plans, separators and pruning are rejected.

Every restriction rebuilds through public `QUBOTools.fix_variables` from the
original objective and accumulated original-index constants. The reduced offset
already includes the recorded `offset_delta`; do not add it twice. Public
`lift_state` restores each full assignment, which is independently scored in the
original sense, scale and offset. An algebraically exact restriction does not
prove that its chosen fixing preserves any optimum.

Keep the best global incumbent separate from the restriction. The best validated
surviving pool row supplies a compatible working incumbent; a better global
incumbent strengthens that witness when it also satisfies the fixings. This keeps
the existing child `OPTIMAL` consistency check active without comparing an
infeasible global state against the restricted child. A complete valid child scan
may publish only a strict global improvement. A normally returned `INTERRUPTED`
can publish that completed improvement and then stops truthfully; thrown,
malformed, incomplete or overdue work discards only its staged terminal proposal.
A defensive empty residual is directly evaluated without an empty child. Normal
positive capacity stops fixing before reaching an empty residual.

All nonconstant routes report heuristic completion, even with no fixing or an
`OPTIMAL` terminal child. `calls[].exact` describes only that child's public
certificate, while `original_proof=false` rejects global certificate transfer.
Original constant objectives retain their direct proof after pool validation.
There is no persistency, global bound, approximation or quantum-advantage claim.

`decomposition.sample_fixing` records provenance and reported generation cost,
validated/distinct/duplicate counts, source row IDs, invocation, completion and
stop reason, each ordered fixing's original/current identity, support fraction,
retained support, constants, original-to-reduced map and offset. It records the
compatible restricted start and whether the global incumbent satisfied the
restriction. Preparation, selection, conditioning, validation/reconstruction and
original scoring appear in the parent phase timers and share its counters and
cooperative deadline. Opaque child work can overrun; no new allowance restarts.

The [offline example](https://github.com/JuliaQUBO/QUBODecomposition.jl/blob/main/examples/sample_fixing/offline.jl)
uses an explicitly biased pool whose restriction excludes the true optimum, while
preserving a superior complete incumbent. The [tiny full-cost comparison](https://github.com/JuliaQUBO/QUBODecomposition.jl/blob/main/examples/sample_fixing/REPORT.md)
retains generation, abstention and biased outcomes without a general advantage
claim. This unary slice does not implement
pair relations, preprocessing, resampling, backtracking or provider callbacks.

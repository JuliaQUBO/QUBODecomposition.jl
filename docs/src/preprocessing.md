# Certified root preprocessing

This is an **unreleased integration candidate** for
[issue #16](https://github.com/JuliaQUBO/QUBODecomposition.jl/issues/16).
The published QUBODecomposition 0.1.4 does not contain it. Development uses the
explicit QUBOPreprocessing source pin below; production merge requires its actual
published 0.1.0 dependency to resolve normally. The benchmark and release-resolution
criteria remain separate gates. Preprocessing defaults to `:off`.

```julia
using QUBODecomposition, QUBODrivers
optimizer = QUBODecomposition.Optimizer(
    child_optimizer=QUBODrivers.ExactSampler.Optimizer,
    max_variables=8, preprocessing=:dominance)
```

The first scope supports serial `:whole_model`, `:components` and
`:components_then_sweeps` with `:strongest_edge`, `:bfs`, `:random_blocks` or
`:single_flip_gain` selection. It rejects combinations with explicit partition,
separator, coarse, consensus or sample-pool plans, advanced strategies and component
executors. These interfaces use original indices or different proof/work contracts;
they are not silently interpreted as residual indices. Automatic preprocessing of
every neighborhood is also outside this root-only integration.

## Objective, scope and completion

Each solve establishes an original incumbent and constructs a fresh
QUBOPreprocessing workspace for the accepted stored Float64 objective. Strict
dominance is propagated before graph construction. The owned residual export and
its ordered root-global fixing proof are independently verified. Components are
rediscovered on the actual free residual; child capacity counts those free logical
variables. An all-fixed residual is evaluated locally without dispatch.

The original and residual incumbents remain in separate contexts. The original
snapshot and complete fallback survive malformed rows, failed/partial children,
work stops and interruption. A funded complete residual incumbent can be lifted
and audited before returning a limit status; an expired deadline retains the last
already validated original incumbent. Child rows themselves must be complete:
missing free values are never filled from a reference optimum or a prior solve.
The residual's initial incumbent is explicitly the accepted original start
restricted to free indices, with certified choices restored only at lifting.

Every returned candidate restores all original accepted QUBO variables, then the
existing MOI storage restores its separately fixed variables before JuMP/ToQUBO
decoding. The stored original polynomial is evaluated independently, including
scale and offset; conditional constants are never added twice. Exact original
arithmetic determines incumbent comparison on this path. Reported energies remain
finite Float64 values, which can hide tiny exact differences.

`OPTIMAL` requires the complete root proof/export, an exact residual procedure,
faithful child objectives and a completed original reconstruction. The adapter
checks the actual variable-dependent Float64 coefficients dispatched after
conditioning and scaling against the exact retained residual restriction.
An uncertified numerical transformation can produce a feasible candidate but
cannot transfer its child's optimality. Assignment-independent constant differences
do not change argmin/argmax. These checks certify the accepted stored QUBO; external
compiler/parser arithmetic and the supplied child's public solver claims retain
their own contracts.

Exact fitting residual components can provide a global proof. Exact coupled
neighborhood children remain heuristic. An `INTERRUPTED`/`TIME_LIMIT` child can
provide a validated improvement, but no global certificate. Generic ExactSampler
inherits its public version contract: 0.6.5 is conservative, while completed
0.6.6 solves expose `OPTIMAL`. Preprocessing does not upgrade that public status.

Root workspaces contain no external caller assumptions. If the composite is a
child of a caller-conditioned QUBOPreprocessing solve, it certifies only that
accepted residual; the outer consumer retains `scope=:assumptions` and does not
promote it to the unconditioned original optimum. MOI fixed constraints belong
to the submitted optimization problem and use their separate existing map.

## Limits and explicit costs

Existing child-call, candidate-evaluation and time caps remain distinct.
`max_work=typemax(Int)` is the default. A finite `max_work` activates one shared
structural ledger even when preprocessing is off, for the same supported serial
routes. It reserves storage/term passes before source copying, workspace creation,
propagation/exact cache work, proof/export, residual snapshots, graph/selection,
conditioning, child copying/reservation, candidate auditing and original lifting.
Dense storage positions count even when their coefficients are zero. Sorting,
arithmetic bit complexity, custom-label/hash work and caller callbacks are additional
to structural units; this is not an instruction count or a hard CPU-time bound.

The ledger charges conservative pass reservations (typically eight units per
storage position at copying boundaries), plus producer-reported work. Propagation
reserves up to four units per candidate/adjacency allowance and refunds unused
reservation on normal completion. Failed child reservations remain charged. Final
original lifting/auditing work and one candidate-evaluation slot are held before
residual dispatch, so residual work cannot consume the only reconstruction budget.
An insufficient initial allowance may return no incumbent; an unevaluated start
is never advertised as a validated result.

Other controls are `preprocessing_max_work` (candidate/edge allowance),
`preprocessing_max_deductions` and `preprocessing_max_exact_work`. A sound stopped
prefix can proceed to explicit materialization and solving only if the shared
allowance remains. Unsafe Float64 export abstains: the original objective path is
used only with its remaining budget and its own child-objective checks. The already
validated original incumbent survives an unfunded fallback. No oversized residual
is dispatched because inference stopped early.

Known built-in ExactSampler work reserves conversion and exhaustive state/term
passes and refuses more than 20 child variables **before exponentiation or
dispatch**. A different child under finite `max_work` needs
`child_work_bound(child, problem, remaining_work, deadline_seconds) -> nonnegative Int`.
It receives an owned immutable numerical description (`n`, domain/sense, linear and
quadratic term tuples, scale/offset), can configure its fresh child, and must return
a conservative reservation its backend honors. The callback does not receive mutable
workspace/snapshot storage. Without this contract finite-work dispatch abstains.
Unbounded unknown-child work is not claimed to have been measured.

Parent deadlines use the injectable seconds clock. Remaining time is conservatively
translated to QUBOPreprocessing's absolute monotonic UInt64 deadline. Parent checks
remain at all transaction boundaries, after original lifting and after the package
constructs its public result container. Children receive the remaining time through
their public setter; unsupported setters abstain on this bounded path. Limits are
combined with any readable shorter factory-configured limit, including samplers
whose public getter/setter works despite a conservative support query. They remain
cooperative, without hard real-time or process-preemption guarantees. User analysis
and QUBODrivers post-sample callback work retain their separate framework contract.

## Evidence, diagnostics and reuse

`MOI.RawOptimizerAttribute("preprocessing_result")` returns the current owned
workspace/export/verifier evidence and invocation identity, or `nothing` before
preparation. Input/configuration invalidation clears it. Every subsequent solve
constructs a new generation, including changes to coefficients, topology, labels,
domain/sense, scale/offset or ToQUBO penalties. Historical exports remain owned
records; they are never reused for a new model. Direct workspace callers can use
the upstream checkpoint/rollback API for cheap repeated local updates; this root
integration performs one initialization per solve.

Serializable `decomposition["preprocessing"]` diagnostics describe original/residual
dimensions, the original-to-residual map (zero means certified fixed), propagation
work/stop/pending counts, proof acceptance, fallback, generation and residual solve
diagnostics. Top-level call selections/components refer to original accepted free
indices; calls additionally retain residual indices and preprocessing-fixed counts.
Nested residual diagnostics use their own residual labels/dimension. Top-level phase
times aggregate residual work once; nested residual times are a breakdown and must
not be added again. Preprocessing subphase times similarly break down the single
top-level preprocessing duration. `work` reports reservations by phase and remaining
allowance; read counts remain logical candidate evaluations, not physical samples.

The deterministic tests cover both domains/senses and signed/zero scales, sparse
capacity splitting, exact original oracles, unsafe export/scaling, limits and
interrupted improvements, caller rollback scopes, changed generations, public driver
conformance, MOI-fixed composition and ToQUBO refinement/source feasibility. The
cross-package operating-envelope study belongs to
[QUBOBenchmarks #30](https://github.com/JuliaQUBO/QUBOBenchmarks.jl/issues/30).
A smaller residual alone is not a performance benefit; initialization, verification
and export costs are explicit. Default-off adoption remains unchanged.

For an isolated local development checkout while the dependency is unregistered:

```julia
using Pkg
Pkg.activate(mktempdir())
Pkg.add(PackageSpec(url="https://github.com/JuliaQUBO/QUBOPreprocessing.jl.git",
    rev="3aa2923a4b5fe6cda21fbb4e331e9198b603029f"))
Pkg.develop(path="/path/to/QUBODecomposition.jl")
```

The temporary CI bootstrap uses this same exact candidate in every active test/docs
environment. Remove it and verify normal published-floor resolution before production
merge; a green source-pinned run is not registration evidence.

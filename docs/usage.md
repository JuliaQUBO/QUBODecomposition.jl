# Serial-decomposition runtime contract

`QUBODecomposition.Optimizer` uses Float64 coefficients. Runtime dependencies are QUBOTools 0.16.2,
QUBODrivers 0.6.5 and MathOptInterface 1. Julia 1.10 is supported. JuMP and ToQUBO >=0.7.0 on the 0.7 compatibility line are test/example dependencies.
The exact resolved test versions are recorded in PR verification evidence and CI.
The MOI 1.0.0 floor lane runs the entire runtime suite and every driver conformance group.
JuMP 1 requires MOI >= 1.1.1, so its integration tests run through `Pkg.test()` in the other lanes.

## Construction and configuration

`Optimizer()` is loadable without a child. Before solving, set `child_optimizer` and `max_variables`,
using constructor keywords or `MOI.RawOptimizerAttribute` with the same names.
The child factory must return a fresh empty `MOI.AbstractOptimizer` for every call, supporting the
original homogeneous binary/spin domain, objective sense and Float64 quadratic objective.
A factory may configure solver-specific attributes; the parent overrides only the per-call seed
and the minimum applicable time limit. It rejects reused live optimizer instances.

| Option | Default and validation |
| --- | --- |
| `child_optimizer` | `nothing`; required zero-argument factory before solving |
| `max_variables` | `nothing`; required positive Int-sized integer, excludes Bool, including for empty models |
| `strategy` | `:components_then_sweeps`; also `:components` and `:whole_model` |
| `max_child_calls` | 1000; nonnegative Int-sized integer excluding Bool; across all component and neighborhood calls |
| `max_candidate_evaluations` | 100000; nonnegative Int-sized integer excluding Bool; cumulative across initial evaluation and every row of every child call |
| `max_sweeps` | 20; nonnegative Int-sized integer excluding Bool; whole-invocation sweep cap |
| `stagnation_sweeps` | 2; positive Int-sized integer excluding Bool; stop after this many complete sweeps without improvement |
| `child_time_limit_sec` | `nothing` or finite nonnegative seconds, excludes Bool |
| `seed` | `nothing` or integer in 0:2^31-2, excludes Bool |

Unknown options fail explicitly. The released driver's conformance contract also exercises the
legacy raw `fixed_variables` and `moi_variables` metadata slots; these are accepted as opaque
user data and never alter the actual MOI copying/reconstruction state. Invalid setters clear old results and throw. Missing configuration
returns `INVALID_OPTION` with no result. The required capacity counts every free logical variable,
including isolates. MOI-fixed variables are reduced by the public driver copy hook and reconstructed
through its public VariablePrimal interface. Arbitrary QUBOTools labels are preserved via
`QUBODrivers.set_model!` and `QUBOTools.backend`, `variable`, `index`, `state` and `solution`.
MOI variable queries apply to MOI-copied models; direct non-MOI labels use QUBOTools queries.

## Results

Each invocation clears old results and copies coefficient terms, labels, frame and starts into a fresh
snapshot. Specified starts must be valid; unspecified binary starts are 0 and spin starts are -1.
The initial incumbent is independently evaluated. Scale, including finite negative/zero scale, offset,
sense and domain are retained. Empty and identically constant objectives return a complete assignment
and `OPTIMAL` without a child, subject to the initial evaluation/time caps.

A fitting nonconstant model makes one child call. All variables are created explicitly, including
isolates, and the MOI copy index map controls every primal read. All returned rows must have feasible
public primal status, complete finite values in the original domain and finite reported objective
values. Finite reported energies are diagnostic only; the parent independently evaluates its scalar
objective. The best child candidate is selected in original sense; equal child energies use
lexicographic original index order. Only a strict improvement replaces the initial incumbent.
An `OPTIMAL` child worse than the known incumbent beyond `atol=1e-12, rtol=1e-12`
is rejected as inconsistent. This tolerance applies only to the certificate consistency check;
incumbent replacement still requires strict improvement.

The child scan is a transaction: no child candidate is committed until all rows are validated.
Malformed, truncated or interrupted scans retain the latest committed validated incumbent. This avoids
attaching partial work and incomplete certificates. This policy also applies to parent limits:
validated rows from an incomplete child scan are not committed. ExactSampler enumerates 2^n rows;
complete processing needs a candidate cap of at least 1 + 2^n (including the initial evaluation).
At n >= 17, the default 100000 cap therefore returns `ITERATION_LIMIT` with the initial incumbent.
Raise the cap for a complete enumeration, or use a child that returns fewer complete candidates.
For serial ExactSampler calls this requirement is cumulative: budget at least
`1 + sum(2^length(U_k))` for the calls you intend to process, including repeated overlapping
neighborhoods. At B=8 a full-size neighborhood uses 256 evaluations; the default 100000 cap
can process 390 such calls completely, then truncates the next scan. Direct-neighbor selection
can make neighborhoods smaller (for example, a chain uses at most three variables). A child may
finish its enumeration even when the remaining parent allowance cannot process every returned row;
that incomplete scan is discarded transactionally. Size the cap for the full intended serial work.
A completed call preserves its valid public
status, including `TIME_LIMIT` or `LOCALLY_SOLVED`. Existing ExactSampler publicly returns
`LOCALLY_SOLVED`; its metadata does not become a public `OPTIMAL` certificate.

Failure-class child statuses, thrown execution errors, empty results, malformed assignments,
non-finite data/energies and inconsistent maps return `OTHER_ERROR` with a diagnostic and any
validated incumbent. Unsupported child contracts or oversize in strict `:components` / `:whole_model` mode return
`INVALID_OPTION`. An interruption exception or public child `INTERRUPTED` retains the last committed
incumbent and stops with `INTERRUPTED`. A detected failure takes precedence over a parent limit.

There is one emitted full assignment with multiplicity one, or zero results if no incumbent was
validated. Public primal status is `FEASIBLE_POINT` for that unconstrained compiled problem;
dual status is `NO_SOLUTION`. No certified bound/gap is supplied. ToQUBO checks decoded source constraints as described in the
[integration contract](#toqubo-source-decoding-and-refinement). PostSampleCallback uses the framework's public contract;
metadata-only callbacks are supported. If callback processing throws or rejects changed samples,
no result is attached and `TerminationStatus` remains `OPTIMIZE_NOT_CALLED`. `PostSampleTransform=true` is rejected in this slice;
transforming samples and repair are deferred and cannot retain an optimality proof.

## Limits, timing and seeds

The initial evaluation counts toward `max_candidate_evaluations`; zero permits no result.
A zero child-call cap returns `ITERATION_LIMIT` and the validated incumbent. A call is reserved before
factory construction, so failed creation/copy/configuration consumes an attempt. A candidate cap
that truncates scanning returns `ITERATION_LIMIT`, never an incomplete proof. `max_sweeps` does not
limit the whole-model or fitting-component path; it caps complete/started neighborhood sweeps.

`MOI.TimeLimitSec` is finite nonnegative seconds or `nothing`, scoped to one parent invocation.
Zero returns `TIME_LIMIT` without a result. Parent preparation, validation and reconstruction count
against this deadline. Before child execution its supported time attribute receives the minimum of
factory limit, per-child limit and remaining parent time. Unsupported/unverified enforcement is
recorded. The parent cannot forcibly cancel an opaque synchronous child; it checks on return,
records overrun, and performs no later work. `enforces_time_limit` is conservatively false.
Per-child early-stop statuses remain valid when the parent has time left.

`MOI.SolveTimeSec() == QUBODrivers.effective_time(optimizer)` includes parent preparation, copying,
child execution and validation/reconstruction. The framework measures enclosing `time.total`,
including its callback. Child-execution sum and other parent processing are separate diagnostics. `decomposition.phase_sec`
records disjoint preparation, conditioning, copying/configuration, execution, validation/reconstruction
and independent full-energy evaluation durations. Per-call `phase_sec` uses the same keys; parent
preparation and the initial energy are additional invocation work. Their sum is at most effective
time; unclassified orchestration and final attachment preparation remain in effective time.
`child_execution_sec` is the execution phase, not an extra additive duration.
The deadline clock and interruption checkpoints are internal test instruments; tests advance
scripted clocks/counters without sleeping. Reported effective/total times use real elapsed seconds.

Call attempt k receives `(seed+k-1) mod (2^31-1)` in exact integer arithmetic through the public
`QUBODrivers.RandomSeed` attribute when supported. The call index resets each invocation, including after changed input.
No seed is imposed for `nothing`. Unsupported seeding is recorded. Repeatability also depends on
identical ordered input, package/child versions, effective work and deterministic child execution;
wall-clock limits and arbitrary factories do not promise deterministic results.

Metadata includes the required origin/algorithm/backend/status/reads/seeds/time dictionaries and
`decomposition` schema version 1: labels and maps, input frame, caps and consumed work, attempted/
completed calls, scan completeness, diagnostics, seed/limit support, exactness, and timing.
`reads.number_of_reads` counts independently evaluated full candidates including the initial state;
`reads.final_number_of_reads` and emitted multiplicity are 1 (or 0). Child-reported row multiplicities
are kept separately. Unknown physical reads stay `nothing`; exhaustive enumeration is not hardware
reads. `FinalNumberOfReads` is accepted by the public framework but not honored by this composite.

Automatic ToQUBO refinement has no shared wall-clock deadline; see the
[integration contract](#toqubo-source-decoding-and-refinement) and caller-owned deadline example.

## Components and conditioned sweeps

For a larger nonconstant model, adjacency uses public nonzero quadratic terms over every declared
free index, including isolates. Components are ordered by minimum original index. Each fitting
component gets exactly one call; disjoint components are not packed. Thus four nonconstant isolates
with B=2 and call cap 3 produce three singleton calls, a complete partial incumbent and
`ITERATION_LIMIT`, without a separable proof.

`:components` preflights all sizes before dispatch; an oversized component returns `INVALID_OPTION`
with its size and B and retains the initial incumbent. `:whole_model` similarly rejects n>B.
The default `:components_then_sweeps` processes fitting components once, then sweeps oversized
components in their component order, visiting anchors in ascending index. Each neighborhood contains
the anchor and at most B-1 distinct adjacent indices, ranked by descending absolute interaction
coefficient then ascending index. B=1 selects exactly the anchor. No unrelated variables are added.

Each call fixes the complement to the latest committed incumbent with released `fix_variables`,
validates its original-index to reduced-index map, copies the reduced objective to a fresh child,
validates all results, and uses released `lift_state` to reconstruct every original free index.
The conditioned form already includes its offset delta; it is not added again. Independent original
scalar evaluation is the acceptance authority. Only a strictly better complete scan commits a state;
equal energy preserves the incumbent. Constants from conditioned child objectives are never summed.

`component_exact` records only complete valid public OPTIMAL certificates. `separable_proof` becomes
true only after every independent component fits and is certified. Exact neighborhood solves cannot
certify the coupled model. Heuristic completion/stagnation reports `LOCALLY_SOLVED`, without a
certified global bound or a certified local minimum. Valid child early-stop statuses are recorded
and decomposition continues while parent allowances remain. Whole-model dispatch preserves them.

A sweep visits all queued anchors once; interruptions/failures/caps leave it started but incomplete.
`stagnation` counts consecutive complete sweeps with no strict improvements. Parent call/candidate/
sweep caps produce `ITERATION_LIMIT`; a reached parent cap or deadline precedes heuristic completion.
Exactly equaling a parent cap counts as reaching it, including after every heuristic component
is processed or when the last allowed sweep also satisfies stagnation. Those cases return
`ITERATION_LIMIT` and name the reached counter; completed-call/sweep metadata still records the
complete work. A fully assembled separable proof survives a later work check. Failures detected on child return
precede parent limits, and interruption discards in-flight results. Prior validated calls remain
committed. `incumbent_energy_trace` contains the initial energy and energy after each completed call.
Per-call diagnostics retain the original/reduced/child maps, `fixed_variable_count`,
`boundary_fixed_variables` (only fixed neighbors coupled to the selected set), and
`conditioning_incumbent_version` (the number of strict commits before conditioning).
The full complement exists only during the live fixing/lifting transaction; unrelated fixed
variables are not duplicated into every call log. All graph, plans, maps, counters, incumbent
and proof state rebuild on every invocation.

See [the runnable larger-than-budget example](../examples/serial_sweeps.jl) for full MOI primal
reconstruction including a fixed variable and truthful coupled heuristic status.

The implementation was written from the accepted contract, without adapting upstream source.
The pinned [QSplit neighborhood reference](https://github.com/alpha-unito/QSplit/blob/4da64b072e702953038addd51cdf54f97f0f9516/qsplit/splitting/split_k_interactions.py)
uses a NumPy negative slice that selects everything for zero neighbors and may select unrelated zero
interactions; this implementation explicitly handles B=1 and adjacency. The pinned
[D-Wave conditioning reference](https://github.com/dwavesystems/dwave-hybrid/blob/ec17a700b0250123da9909ec82db4ecb2516993d/hybrid/utils.py)
sets the induced model offset to zero. Here fixing preserves the offset, and full original energy
is independently recomputed. These are references only; no Python runtime dependency is added.

## ToQUBO source decoding and refinement

See the [offline public construction examples and environment](../examples/toqubo/README.md).
ToQUBO compiles source constraints and encodings into the composite's unconstrained objective.
Every encoded, slack and quadratization bit counts toward child capacity. The composite's
FEASIBLE_POINT describes a complete compiled assignment. By default ToQUBO 0.7 checks decoded
source constraints and reports INFEASIBLE_POINT when those constraints fail. Its
PrimalFeasibilityCheck opt-out forwards compiled primal status without making the source feasible.
Use `ToQUBO.violations` to inspect residuals and `ToQUBO.source_objective_value` for the decoded
source objective. `MOI.ObjectiveValue` is the penalized compiled objective.

Automatic refinement recompiles after updating penalties. MaxPenaltyUpdates bounds additional
composite solves; feasibility, empty results or an updater without an applicable penalty can stop
it earlier. Each invocation receives fresh composite counters, seed sequence and time deadline.
The limit is not shared across the enclosing refinement process. The explicit deadline example
disables automatic updates, compiles and copies before dispatching with the remaining absolute
allowance, and deducts source checking before the next round. Cooperative checks cannot preempt an
opaque synchronous child. Composite effective time and ToQUBO CompilationTime are last-invocation
and last-compilation measurements, respectively, not cumulative enclosing times.

Ordinary ToQUBO 0.7.0 repeated compilation retains encodings and can append stale slack bits.
Until upstream #244 is addressed, the examples and successful recompilation tests explicitly call
the public `MOI.Utilities.reset_optimizer(model)` before re-solving the cached JuMP source. Automatic
refinement already resets its own intermediate compiles. Refined penalty attributes persist on the
compiler; cached attributes can replace them during source recopy, so explicitly set the intended
hint when restarting. The acceptance matrix records the unreset regression as remaining work.

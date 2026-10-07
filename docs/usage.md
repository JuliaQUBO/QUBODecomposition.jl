# Whole-model runtime contract

`QUBODecomposition.Optimizer` uses Float64 coefficients. Runtime dependencies are QUBOTools 0.16.2,
QUBODrivers 0.6.5 and MathOptInterface 1. Julia 1.10 is supported. JuMP is a test/example dependency.
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
| `strategy` | `:whole_model`; other strategies are explicitly unsupported in this slice |
| `max_child_calls` | 1000; nonnegative Int-sized integer excluding Bool; at most one is used here |
| `max_candidate_evaluations` | 100000; nonnegative Int-sized integer excluding Bool |
| `max_sweeps` | 20; nonnegative Int-sized integer excluding Bool; reserved, no sweeps run |
| `stagnation_sweeps` | 2; positive Int-sized integer excluding Bool; reserved, no sweeps run |
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
An `OPTIMAL` child worse than the known incumbent is rejected as inconsistent.

The child scan is a transaction: no child candidate is committed until all rows are validated.
Malformed, truncated or interrupted scans retain the initial validated incumbent. This avoids
attaching partial work and incomplete certificates. A completed call preserves its valid public
status, including `TIME_LIMIT` or `LOCALLY_SOLVED`. Existing ExactSampler publicly returns
`LOCALLY_SOLVED`; its metadata does not become a public `OPTIMAL` certificate.

Failure-class child statuses, thrown execution errors, empty results, malformed assignments,
non-finite data/energies and inconsistent maps return `OTHER_ERROR` with a diagnostic and any
validated incumbent. Unsupported child contracts or oversized nonconstant inputs return
`INVALID_OPTION`. An interruption exception or public child `INTERRUPTED` retains the last committed
incumbent and stops with `INTERRUPTED`. A detected failure takes precedence over a parent limit.

There is one emitted full assignment with multiplicity one, or zero results if no incumbent was
validated. Public primal status is `FEASIBLE_POINT` for that unconstrained compiled problem;
dual status is `NO_SOLUTION`. No certified bound/gap is supplied. No source-constraint feasibility
is asserted for a future ToQUBO caller. PostSampleCallback uses the framework's public contract;
metadata-only callbacks are supported. `PostSampleTransform=true` is rejected in this slice;
transforming samples and repair are deferred and cannot retain an optimality proof.

## Limits, timing and seeds

The initial evaluation counts toward `max_candidate_evaluations`; zero permits no result.
A zero child-call cap returns `ITERATION_LIMIT` and the validated incumbent. A call is reserved before
factory construction, so failed creation/copy/configuration consumes an attempt. A candidate cap
that truncates scanning returns `ITERATION_LIMIT`, never an incomplete proof. `max_sweeps` does not
limit the whole-model path: it is reserved for the next slice.

`MOI.TimeLimitSec` is finite nonnegative seconds or `nothing`, scoped to one parent invocation.
Zero returns `TIME_LIMIT` without a result. Parent preparation, validation and reconstruction count
against this deadline. Before child execution its supported time attribute receives the minimum of
factory limit, per-child limit and remaining parent time. Unsupported/unverified enforcement is
recorded. The parent cannot forcibly cancel an opaque synchronous child; it checks on return,
records overrun, and performs no later work. `enforces_time_limit` is conservatively false.
Per-child early-stop statuses remain valid when the parent has time left.

`MOI.SolveTimeSec() == QUBODrivers.effective_time(optimizer)` includes parent preparation, copying,
child execution and validation/reconstruction. The framework measures enclosing `time.total`,
including its callback. Child-execution sum and other parent processing are separate diagnostics.
The deadline clock and interruption checkpoints are internal test instruments; tests advance
scripted clocks/counters without sleeping. Reported effective/total times use real elapsed seconds.

Call attempt k receives `(seed+k-1) mod (2^31-1)` in exact integer arithmetic through the public
`QUBODrivers.RandomSeed` attribute when supported. This slice uses k=1 and resets it each invocation.
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

Components, conditioning/lifting across neighborhoods, sweeps, ToQUBO refinement and shared outer
budgets are pending. The newer ToQUBO refinement/primal-status APIs require a verified installable
release before the later full integration matrix; they are not prerequisites for this slice.

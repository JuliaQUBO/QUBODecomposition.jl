# Limits, timing and seeds

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
[integration contract](integration.md) and caller-owned deadline example.

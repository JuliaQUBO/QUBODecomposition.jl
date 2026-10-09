# Budgets, timing, seeds and reads

The initial evaluation counts toward `max_candidate_evaluations`; zero permits no result.
On routes requiring a child, a zero child-call cap returns `ITERATION_LIMIT` and the validated incumbent. A call is reserved before
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
records disjoint preparation (including neighborhood selection and gain recomputation), conditioning, copying/configuration, execution, validation/reconstruction
and independent full-energy evaluation durations. Per-call `phase_sec` uses the same keys; parent
preparation and the initial energy are additional invocation work. Their sum is at most effective
time; unclassified orchestration and final attachment preparation remain in effective time.
`child_execution_sec` is the execution phase, not an extra additive duration.
`selection_sec` measures the subset of preparation spent in selector setup and
block selection (including gain recomputation, sorted BFS adjacency and random
permutations). It must not be added to `phase_sec` or total time again.
The deadline clock and interruption checkpoints are internal test instruments; tests advance
scripted clocks/counters without sleeping. Reported effective/total times use real elapsed seconds.

Call attempt k receives `(seed+k-1) mod (2^31-1)` in exact integer arithmetic through the public
`QUBODrivers.RandomSeed` attribute when supported. The call index resets each invocation, including after changed input.
No seed is imposed for `nothing`. Unsupported seeding is recorded. Repeatability also depends on
identical ordered input, package/child versions, effective work and deterministic child execution;
wall-clock limits and arbitrary factories do not promise deterministic results.

`:random_blocks` initializes a private `Random.Xoshiro` on each invocation that
enters oversized-component sweeps, using the parent seed when supplied. Otherwise
it obtains a seed from `Random.RandomDevice`; selection is then nondeterministic.
Neither path reads or advances Julia's task/global RNG. Child RNG behavior is the
child's responsibility. Selection draws never advance the child-seed sequence
above; fitting-component calls still count toward that sequence.

`decomposition.selection_seed` and `selection_rng` record the actual selection
RNG input and algorithm, or `nothing` when unused. Each attempted call's
`selected_indices`, `component` and `sweep` record the actual block, including a
failed child attempt. Indices are in ascending original order and `labels` maps
them back to input variables. These ordered block records allow replay of the
attempted selections without relying on an RNG implementation, including unseeded
runs. A call stopped before factory reservation is not an attempted child call;
unattempted blocks are not logged. Reproducing the complete search also requires
the same model, start, child behavior and work limits. RNG bitstreams are not
promised stable across Julia versions; retain blocks and environment for replay.

Metadata includes the required origin/algorithm/backend/status/reads/seeds/time dictionaries and
`decomposition` schema version 1: labels and maps, input frame, caps and consumed work, attempted/
completed calls, scan completeness, diagnostics, seed/limit support, exactness, and timing.
`reads.number_of_reads` counts independently evaluated full candidates including the initial state;
`reads.final_number_of_reads` and emitted multiplicity are 1 (or 0). Child-reported row multiplicities
are kept separately. Unknown physical reads stay `nothing`; exhaustive enumeration is not hardware
reads. `FinalNumberOfReads` is accepted by the public framework but not honored by this composite.

Automatic ToQUBO refinement has no shared wall-clock deadline; see the
[integration contract](integration.md) and caller-owned deadline example.


Separator branches share one invocation budget; none of the allowances resets at
a branch or component. With `r=2^length(S)` complete branches, candidate usage is
`1 + 2r + sum(returned_child_rows) + number_of_constant_residuals`: one original
initial evaluation, a branch-start and final original evaluation per branch,
every child row, and one direct evaluation per constant residual component.
Empty/full-separator plans can complete with `max_child_calls=0`. Evaluation and
time limits still apply. `max_sweeps` and `stagnation_sweeps` do not limit enumeration.
Certificate completion exactly at a call or evaluation cap returns `OPTIMAL`;
incomplete proof or heuristic completion retains existing limit precedence.

Work grows exponentially in separator size, plus residual child cost. A cap check
precedes shifting or allocation, with an absolute 16-variable separator ceiling.
Enumeration storage is linear in the model and plan, apart from retained child
call diagnostics bounded by `max_child_calls`; branch states are not retained.
Planning, public conditioning (which still scans/copies a form per component),
conversion, reconstruction and original evaluation are all included in total time.
The cap does not bound an arbitrary child's internal memory/search: configure that
child appropriately. The comparison runner adds independent exhaustive work guards.

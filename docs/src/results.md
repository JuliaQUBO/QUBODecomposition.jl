# Results and statuses

The [global-guarantee design decision](guarantees.md) separates a method's
conditional guarantee from a completed invocation's certificate. In particular,
an exact conditional child does not certify its coupled parent problem.

Each invocation clears old results and copies coefficient terms, labels, frame and starts into a fresh
snapshot. Specified starts must be valid; unspecified binary starts are 0 and spin starts are -1.
The initial incumbent is independently evaluated. Scale, including finite negative/zero scale, offset,
sense and domain are retained. Outside separator mode, empty and identically constant objectives return a complete assignment
and `OPTIMAL` without a child, subject to the initial evaluation/time caps.

Outside separator mode, a fitting nonconstant model makes one child call. All variables are created explicitly, including
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
validated incumbent. Unsupported child contracts or oversize in strict `:components` / `:whole_model` mode, or an invalid/oversized
separator plan, return `INVALID_OPTION`. An interruption exception or public child `INTERRUPTED` retains the last committed
incumbent and stops with `INTERRUPTED`. A detected failure takes precedence over a parent limit.

There is one emitted full assignment with multiplicity one, or zero results if no incumbent was
validated. Public primal status is `FEASIBLE_POINT` for that unconstrained compiled problem;
dual status is `NO_SOLUTION`. No certified bound/gap is supplied. ToQUBO checks decoded source constraints as described in the
[integration contract](integration.md). PostSampleCallback uses the framework's public contract;
metadata-only callbacks are supported. If callback processing throws or rejects changed samples,
no result is attached and `TerminationStatus` remains `OPTIMIZE_NOT_CALLED`. `PostSampleTransform=true` is rejected in this slice;
transforming samples and repair are deferred and cannot retain an optimality proof.


In `:separator` mode, `OPTIMAL` requires every separator assignment to complete,
all nonconstant residual child scans to validate public `OPTIMAL` certificates,
and complete reconstruction and original evaluation. Constant residuals and empty
residuals use direct evaluation under the same budgets. Released ExactSampler
results remain uncertified `LOCALLY_SOLVED`, even when their energy matches the
exhaustive oracle. Completed uncertified enumeration reports `LOCALLY_SOLVED`
unless a reached parent cap or deadline takes precedence. Invalid/missing child
results report the existing failure status and retain only completed incumbents.
A fully completed proof survives exactly consumed work allowances; an interrupted
final evaluation or commit has not completed proof.

`decomposition.separator` is `nothing` for other strategies, and when separator mode
stops before planning (for example, on a zero initial evaluation/time allowance).
Once separator planning begins it
records `indices`, `residual_components`, `required_branches`, `started_branches`,
`completed_branches`, `certified_branches`, `proof_complete` and `incomplete_reason`.
The required count is `nothing` if preflight did not finish. `component_certificates`
and `constant_components` count validated child certificates and direct constant
evaluations by residual component, including work in an unfinished branch; these
counts alone never certify a branch. `current_branch` is the one-based mask ordinal,
and `completed_components` is progress in that branch. Only completed certified
branches contribute to `certified_branches`. Incomplete enumeration uses the parent `stop_reason`; fully completed
uncertified work names `uncertified_components`, even when a reached parent cap
takes precedence in the public termination status.

Child call records use `kind="separator_component"` and `branch` to locate their
certificates. `committed_energy` and `conditioning_incumbent_version` describe
branch working state for these calls. The global `incumbent_energy_trace` contains
only the initial incumbent and completed branch commits. No branch assignment
array is retained; indices, mask order and call maps preserve reconstruction
provenance. `separable_proof` keeps its independent-component meaning.


`separator.discovery` is `nothing` for supplied plans. Automatic mode records a
compact dictionary: `mode`, `complete`, `reason`, `elapsed_sec`, `component_count`,
`largest_initial_component`, `visited_vertices`, `examined_adjacencies`,
`articulation_vertices`, `qualifying_vertices` and `selected_largest_residual`.
The counters describe completed discovery work, not child work or certificates;
there is no per-candidate trace. Already-fitting and zero-cap refusals do not run
DFS, so DFS counters are zero. `complete=true` means discovery finished (possibly
with refusal), not enumeration or proof completion. During interrupted discovery,
`complete=false`, `reason` names the parent stop, and counters retain partial work.
Discovery can finish before interruption in subsequent plan validation; then the
chosen score is retained but `indices` remains empty and `required_branches` stays
`nothing` until full plan validation completes. Rejected/unfinished plans have no
child dispatch. Timing always records real elapsed work, including a failed or
interrupted discovery attempt.

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
Scans that are malformed, truncated or interrupted before completion retain the
latest committed validated incumbent. This avoids
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
status, including `TIME_LIMIT` or `LOCALLY_SOLVED`, on the existing serial routes.
On the frozen-batch proposal/repair route, an accepted child limit status
(including `TIME_LIMIT`, `ITERATION_LIMIT`, `OBJECTIVE_LIMIT` or `SLOW_PROGRESS`)
ends the batch with that same parent `TerminationStatus` and
`stop_reason="batch_child_unfinished"`. Retain the previously committed assignment
and mark the batch incomplete. This reason distinguishes a child limit from
the parent's own `max_child_calls`/`max_candidate_evaluations` cap. Existing ExactSampler publicly returns
`LOCALLY_SOLVED`; its metadata does not become a public `OPTIMAL` certificate.

When `optimize!` returns normally with public `INTERRUPTED`, the parent scans all
available rows under the same validation and budgets. Whole-model and ordinary
serial/component calls can commit the best strict improvement after the entire
scan, then stop with `INTERRUPTED` and `stop_reason="child_interrupted"`, without
dispatching another child or claiming route completion. Zero returned rows are
legitimate only for this status and preserve the previous incumbent, as do equal
or worse valid results. A fully validated interrupted call counts in
`completed_calls` and is not an `incomplete_scan`; this records result processing,
not solver or strategy completion. Its `exact` flag is always false.

Separator branches and frozen voting/repair batches retain their larger transaction
boundaries: interrupted children are validated but their scratch candidates are
not committed, and the enclosing unfinished transaction is discarded. Previously
completed global commits and certificates remain recorded. These discarded scans
still consume shared time and candidate evaluations: validation failures and parent
limits have the same precedence as on ordinary calls, without extra allowance.

Failure-class child statuses, thrown execution errors, empty results outside the
interrupted-status exception, malformed assignments,
non-finite data/energies and inconsistent maps return `OTHER_ERROR` with a diagnostic and any
validated incumbent. Unsupported child contracts or oversize in strict `:components` / `:whole_model` mode, or an invalid/oversized
separator plan, return `INVALID_OPTION`. A thrown `InterruptException` stops with
`INTERRUPTED` and `stop_reason="interrupt_exception"`; a failed invocation is not
inspected for salvage and cannot contribute a candidate. A detected validation
failure takes precedence over a parent limit; otherwise parent limits that prevent
the complete scan or commit take precedence over the observed child interruption.
The call's `public_status` retains the normally returned child status even when
the parent reports a limit or validation failure.

There is one emitted full assignment with multiplicity one, or zero results if no incumbent was
validated. Public primal status is `FEASIBLE_POINT` for that unconstrained compiled problem;
dual status is `NO_SOLUTION`. No certified bound/gap is supplied. ToQUBO checks decoded source constraints as described in the
[integration contract](integration.md). PostSampleCallback uses the framework's public contract;
metadata-only callbacks are supported. If callback processing throws or rejects changed samples,
no result is attached and `TerminationStatus` remains `OPTIMIZE_NOT_CALLED`. `PostSampleTransform=true` is rejected in this slice;
post-sample transformations remain deferred. Internal frozen-batch disagreement
repair uses its own transaction and cannot establish an original global proof.


In `:separator` mode, `OPTIMAL` requires every separator assignment to be solved
and certified or safely excluded by opt-in certified pruning,
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

With `separator_pruning=true`, bounded scalar diagnostics add `attempted_branches`
(an alias of `started_branches`), `solved_branches` (an alias of
`completed_branches`), `certified_pruned_branches`, and `unfinished_branches`
(required minus solved minus excluded, including not-yet-started branches).
`certified_branches` counts certified solved branches only. A pruned branch has
no child call, result, or incumbent trace entry. An interrupted bound or branch
has no completion certificate. `pruning_enabled`, `bound_method`
(`exact_rational_original_termwise_v1` when available), `bound_unavailable`,
`bound_sec`, and `arithmetic_uncertified_branches` describe provenance, total bound
work and failed coefficient-transfer checks. Counts and timers reset every solve;
no per-branch bound history is retained. `bound_sec` includes preparation,
incumbent comparisons, termwise bounds and coefficient-transfer checks and equals
`phase_sec["bound"]`. That phase is absent when pruning is off.

For `strategy=:consensus`, completion remains heuristic and certified normalized
lower bounds live separately in [consensus metadata](consensus.md). Its evaluation
counter includes scanned surrogate rows as well as complete original candidates.


For [coarse proposals](coarse.md), child `OPTIMAL` does not imply original
optimality. Every nonconstant successful proposal reports `LOCALLY_SOLVED`;
child limits and returned interruption remain truthful. Macro maps and their
frozen incumbent live in `decomposition.coarse`, separately from ordinary
selected-original-index restrictions. All rows validate before one strict commit.

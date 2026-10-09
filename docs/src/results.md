# Results and statuses

The [global-guarantee design decision](guarantees.md) separates a method's
conditional guarantee from a completed invocation's certificate. In particular,
an exact conditional child does not certify its coupled parent problem.

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
[integration contract](integration.md). PostSampleCallback uses the framework's public contract;
metadata-only callbacks are supported. If callback processing throws or rejects changed samples,
no result is attached and `TerminationStatus` remains `OPTIMIZE_NOT_CALLED`. `PostSampleTransform=true` is rejected in this slice;
transforming samples and repair are deferred and cannot retain an optimality proof.

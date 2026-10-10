# Compact certified child results: bounded comparison

**Decision: investigate further; defer a production optimization.** Safe compact
certified results already integrate through the existing exact parent routes.
This experiment reduced complete cost on the exercised path and observed a smaller
star reduction, with a material GC outlier. It supports broader certified-child
integration measurements, not a general speedup or a production rewrite.

Ordinary producing commit: `27f2416cbbda594c2e0e050a866a2f1049cd591f`,
tree `231152c734b671767e0fef1bb3a73768e3710555`.
Production source remains identical to measured base
`5ac0f5439d39abf2ed8e8d21646008bf160d7eaf`.
[Raw ordinary evidence](evidence/20261010/ordinary/results.toml.gz),
[locks, logs and cumulative allowance](evidence/20261010/README.md),
[rerun/measurement contract](README.md).
The report/evidence were committed subsequently; frozen measurements are attributed
to their producing source, not relabeled as later documentation commits.

## Certificate preservation and correctness

Both adapter modes solve the identical bounded exhaustive problem with released
ExactSampler and create its complete result. Both establish exhaustive completion,
expected work, distinct complete assignment coverage and every source row's
primal status, domain, mapping and objective before any row is discarded.
Compact mode emits one exact-energy optimum with lexicographic tie choice in
original child order. It does not claim all optima. Source state/order/frame and
unit-multiplicity checks are independent of the parent's validation. The adapter
clears prior results and isolates internal result attachment; failed checks cannot
expose a stale source/adapter certificate. Released ExactSampler's public
`LOCALLY_SOLVED` is tested and unchanged.

Whole-model, independent components and supplied separators retain their existing
conditional exact guarantees: a valid optimal child incumbent suffices; the parent
still validates **every emitted row**, reconstructs the original assignment and
checks original energy. Separator optimality also requires every required branch
and residual component to complete with valid certificates. Interrupted children,
missing/inconsistent certificates, incomplete branches, exhausted child/parent
budgets and repeated solves receive no global proof through compaction.

Independent scalar oracles cover binary/spin domains, both senses, positive and
negative nonunit scales, offsets, labels, fixed variables and shifted MOI indices.
Malformed later source rows (including bad energies, duplicates, domain values,
multiplicities and incomplete results) fail in both modes. A source primal-status
proxy and changed mapping test the corresponding certificate premises explicitly.
Existing malformed-child/result/budget/separator regressions remain in the suite.

The supplied path15 and star33 equations, variables, domains, senses, scales,
offsets, separators and independent optimum references were compared with pinned
QUBOBenchmarks `684a96b8e757b400964d062c4229aacc12a523e1` definitions.
Their historical canonical fixture hashes are respectively
`17012b4b1c0a53a099e049e741f219a86446dbc8fe7e06505d681f35eb619a80` and
`c1805337cc3b27ec13a74921c96a215ddc7ec46624f17d4b5fb84d000326d74d`.
[Identity check evidence](evidence/20261010/pinned-fixture-check.log).
All ones attains the negative-monomial lower bounds −60 and −141. A separate
scalar exhaustive check on eight-variable family members confirms the bound.
These easy landscapes measure integration cost, not hard-instance solver quality.

## Complete costs and retained attempts

Julia 1.10.11, Sapphire Rapids, one Julia thread and one BLAS thread;
QUBOTools 0.16.2 and QUBODrivers 0.6.5. Package trees, exact resolved environment,
source hashes and original fixture equations accompany every cohort.
Background host activity is uncontrolled. No package-test process overlapped the
ordinary rerun. Each fixture/mode has one retained warmup and five measured
repetitions; paired mode order alternates by round. No profiling was performed.

Complete execution includes fresh fixture/parent construction, loading through
result attachment, full exhaustive result creation, source certificate
checking/selection, result copying/compaction and parent processing. This **does
not measure a native best-only solver that avoids full result creation**.
Independent audits, bootstrap/imports, checkpoint/storage and summaries are
outside solve timing. Warmup/JIT attempts are separate from distributions.
Allocation is cumulative allocated bytes, not peak resident memory.

| Fixture / mode | Median complete ms | Observed min–max ms | Median allocated KiB | Search assignments | Emitted rows | Parent evaluations |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| path15 / all | 4.512 | 4.280–4.673 | 3310.9 | 512 | 512 | 517 |
| path15 / compact | 2.083 | 1.687–2.854 | 1050.4 | 512 | 4 | 9 |
| star33 / all | 9.730 | 8.975–67.126 | 6327.8 | 128 | 128 | 133 |
| star33 / compact | 8.813 | 8.535–9.480 | 5990.6 | 128 | 64 | 69 |

Per-fixture **paired compact-minus-all** complete-time distributions:

| Fixture | Minimum ms | Q25 ms | Median ms | Q75 ms | Maximum ms | Paired median allocation change KiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| path15 | −2.592 | −2.573 | −2.572 | −2.314 | −1.659 | −2260.4 |
| star33 | −58.592 | −1.736 | −0.794 | −0.225 | −0.162 | −338.2 |

These are medians of paired differences, not differences of lane medians. The
star all-row first measured repetition had 51.254 ms GC within its 67.126 ms
complete duration; it remains in all ordinary distributions. All other measured
GC times were zero; both modes' median GC is zero. Do not attribute that large
paired difference entirely to compaction. No explicit GC ran between attempts;
garbage from previous solves/warmups can carry into the next timed attempt. In
particular, the first compact warmup allocated about 441 MiB. The measured order
has all-first three times and compact-first twice; five pairs cannot balance order
exactly. A future separately authorized campaign should manage GC outside timing
and counterbalance order; this frozen evidence is not rerun. Five pairs on a shared host do not
establish stable general performance. All warmups and failures are retained.

Available phase diagnostics explain the narrower integration observation:

| Median diagnostic ms | Path all | Path compact | Star all | Star compact |
| --- | ---: | ---: | ---: | ---: |
| Child execution, including full search/checking/result construction | 1.269 | 1.157 | 4.927 | 4.592 |
| Copying, including parent factory/conversion/copy/checks | 0.383 | 0.331 | 2.021 | 1.828 |
| Parent validation/reconstruction | 1.614 | 0.067 | 0.659 | 0.415 |
| Parent original-energy evaluations | 0.049 | 0.003 | 0.025 | 0.016 |
| Nested source certificate checking/selection | 0.324 | 0.336 | 0.148 | 0.134 |
| Nested result copying/compaction construction | 0.195 | 0.132 | 1.442 | 1.327 |

The last two rows are **inside child execution**, not additional phases.
Medians do not add; production phases omit some construction/loading/attachment
and control flow. Differences in copying or source-check medians are not isolated
causal effects of compaction. The path's emitted-row processing falls substantially;
the star still has 64 child calls and substantial complete overhead.

## Work, failures and cumulative limits

All 24 ordinary attempts finished OPTIMAL with independently checked original
energies, four/64 certified child calls per path/star solve, and two completed,
certified separator branches. Reserved and actual **search assignments** both
sum to 7,680. Parent actual candidate evaluations sum to 4,368, below the
conservative reserved bound of 7,800. Independent family-oracle work is 512
assignments, outside solve timing.

`actual_assignments` counts the underlying exhaustive search loop; it excludes
source validation and parent candidate work. The adapter additionally recomputes
one child objective per source row: **7,680 source objective checks per complete
cohort**, derived from its successful checked full-coverage loops, not a separately
instrumented optimizer counter. These checks and deterministic selection are paid
inside child/complete time. They are separately bounded by the same source-row
count (at most 256 per child). One compact emitted row does not mean one search
assignment, and neither result multiplicity nor any counter here is physical reads.

An [initial bootstrap failure](evidence/20261010/setup-failure/README.md) at
`ab366ade653b11214d3b52a9b55d470f02ad4259` omitted a direct MOI dependency and
failed before any reservation/solve/oracle. It spent zero solve work. The corrected
runner at `bde28e874a809f00f155e326551439541751ee27` completed a first 24-attempt
batch, but a package-test process overlapped its timing. That
[confounded cohort](evidence/20261010/confounded/README.md) is preserved separately
and excluded from this decision. The ordinary rerun followed after those processes
finished. A test-environment declaration fix between producers changes test-only
standard-library extras, not measured algorithms, fixture equations or run limits.

Both solve cohorts count against the predeclared cumulative allowance: **48
attempts, 15,360 reserved/actual search assignments, 15,600 reserved parent bound,
8,736 actual parent evaluations, and 1,024 oracle assignments**. Source validation
adds 15,360 child objective checks across them. No solve failure occurred; no
third cohort fits the allowance. Entire batches are reserved atomically before
any audits/dispatch; failed/interrupted attempts cannot refund that work.
Per-child eight-variable/256-assignment guards, finite parent deadlines and an
outer 360-second process timeout remained in force. Both complete batches took
about 6.5–6.7 seconds including warmups/audits/checkpoints, excluding bootstrap.

## Validation and next decision

Repository `julia --project=. -e 'using Pkg; Pkg.test()'` passed **53,444
assertions**, including **600** new focused acceptance/preflight/fixture checks.
The public whole-model/serial examples and documentation-link checks passed.
Raw-attempt audits verified work, paired scheduling, original energy/bounds,
proof counters, phase containment and summary arithmetic. SHA256SUMS preserves
archive integrity. Timing thresholds and profiling campaigns are excluded from CI.
The independent review's eight nonblocking findings are addressed with corrected
paired allocation arithmetic, retained reproducible audit/identity scripts, exact
invocations, spent-ledger/GC/order disclosure, stdlib test compatibility bounds,
and frame/parent-tie/partial-write guards. Post-fix `Pkg.test()` passed **53,482
assertions**, including **638** focused checks. Adapter/production solve code and
`execute` timing boundaries remain unchanged; checkpoint injection is outside
solve timing and the updated rerun string is metadata only. Historical timing
and logs remain at their producers. Corrected audits verify both raw cohorts and
the paired report table, including the star allocation median.

Independent review, fixes, verification and current-head CI are recorded in
PR history; none of those is human approval.

Investigate certified compact-result integration on a broader bounded set and,
separately authorized later, a genuinely native best-only child. Preserve the
full source/certificate premises when translating this test adapter into a real
solver contract. This evidence does not justify skipping returned-row validation,
a conditioner rewrite, conversion/copy or metadata caching changes, new separator
algorithms, heuristics or preprocessing. QUBOBenchmarks #27 retains its broader
scope. Registration, release and deployment work remain separate.

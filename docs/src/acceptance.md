# Acceptance coverage

Design acceptance matrix for the serial runtime and ToQUBO integration.

The [pinned matrix](https://github.com/JuliaQUBO/QUBO.jl/blob/7c3391f9e4ccf369027da858866f6d4b74790313/docs/src/design.md#offline-acceptance-matrix)
contains the full MVP requirements. The table maps every row in its original order.
Delivered means coverage of the local serial sampler contract; compiler integration and release
remain separate. Numerical expectations use original scalar coefficients independently of the child.

| Row | Delivered evidence | Remaining coverage |
| --- | --- | --- |
| 1: domains/senses/forms/scales/offset | `test/unit/whole_model.jl`, `test/unit/serial.jl`: binary/spin, Min/Max, sparse/dense/dict, positive/negative/zero scale, nonzero offset; independent enumeration of conditioned/lifted energies | delivered local sampler |
| 2: labels, reordering, isolates | arbitrary/reordered labels, internal/trailing isolates, original/reduced/child maps and full lift round trips in serial tests | delivered local sampler |
| 3: empty/constant/one/all fixed | whole-model and JuMP/MOI edge tests, serial fixed-variable primals | delivered local sampler |
| 4: budget one/capacity/invalid | singleton neighborhoods, duplicate edges, deterministic ranked neighbors without padding, strict oversized-component preflight, explicit whole-model rejection/pass-through | delivered local sampler |
| 5: disjoint components | exhaustive scalar global extrema across frames/storage; one call per component, complete public OPTIMAL certificates; explicit ExactSampler 0.6.5/0.6.6 status contract | delivered local sampler |
| 6: four linear isolates, partial cap | B=2, cap=3: three singleton calls, complete partial incumbent, ITERATION_LIMIT and incomplete component proof; exact final-cap proof test | delivered local sampler |
| 7: coupled sweeps | enumerated scalar global reference, monotone energy traces/strict commits, latest-incumbent conditioning, bounded caps/stagnation, no coupled global proof | delivered local sampler |
| 8: failed/malformed children | `test/unit/results.jl`, serial failure/empty/malformed/partial-scan tests retain prior committed calls | delivered local sampler |
| 9: duplicates/multiplicities | duplicate rows counted as evaluations, emitted multiplicity one; serial sampler multiplicities 3/7 retained per call with emitted 1 (never 21); serial ExactSampler counts; unknown physical reads separate | delivered local sampler |
| 10: caps/time/cancellation | `test/unit/budgets.jl`, serial call/candidate/sweep/stagnation checks and scripted clocks/checkpoints; disjoint invocation/per-call phase durations and effective/total consistency | delivered local sampler |
| 11: child limits versus parent | valid child early stops continue serial processing; scripted remaining-parent limits/overrun, supported factory/per-child limits | delivered local sampler |
| 12: interruption | `test/unit/interrupted_results.jl`: returned INTERRUPTED improvements, empty/multiple/malformed rows, limits and strategy rollback; child exceptions and injected before-factory/reconstruction/commit interruption after prior successful calls; checkpoint interruption inside a started sweep retains prior committed state | delivered local sampler |
| 13: seed/support | exact k>1 modular sequence, overflow boundary, unsupported children, reset on repeated invocation | delivered local sampler |
| 14: repeated solves/data | same-size reordered labels, changed domain/sense/scale/offset/coefficients/graph; fresh maps, plans, counters and proof; preserved whole-model regressions | delivered local sampler |
| 15: driver conformance | `test/conformance.jl`: every default group, controlled public exact child and released ExactSampler, both fitting and serial budgets | delivered local sampler |
| 16: direct JuMP | `test/integration/jump.jl`: binary/spin, Min/Max, diagonal convention, constants/fixed variables, separable and coupled larger-than-budget solves, complete original primals | delivered local sampler |
| 17: ToQUBO binary/refinement | `test/integration/toqubo.jl`: four source assignments (feasible optimum 8), all eight compiled assignments; weak penalty gives source 11/compiled 10.9 and default INFEASIBLE_POINT; opt-out and -0.1 → -1 → -10 automatic refinement; captured compiler/composite and child coefficients; fitting exact and B=2 heuristic runs | delivered with ordinary reused solves and live refined-hint persistence |
| 18: ToQUBO integer/auxiliary/slack/cubic | `test/integration/toqubo.jl`: source extrema 7/13 in both senses; assert actual integer/slack bits, enumerate every compiled bit and minimize/maximize over slack; lifted binary cubic extrema 3/8 with separately identified quadratization bits and exhaustive auxiliary envelope | delivered via quadratic MOI product lift; direct nonlinear cubic source input is unsupported in ToQUBO 0.7 |
| 19: recompile/refinement mapping | `test/integration/repeated_refinement.jl`: same compiler/composite reused with changed coefficients, penalties, source index ownership and Binary/Unary encoding; four ordinary ExactSampler solves keep three bits and match fresh coefficients, ownership, complete assignments and independently evaluated energies; failed/missing/limited results, committed-incumbent and feasibility-cache checks; explicit reset | delivered against released ToQUBO 0.7.1 |
| 20: outer refinement budgets | `test/integration/repeated_refinement.jl`: at most 1+updates invocations, feasible/empty/unreachable early stops; per-call limit minima, new invocation clocks/counters/seeds, ExactSampler complete-scan cap 9 vs truncated 8; explicit absolute-deadline example checks compilation/copy/check work and opaque-child overrun with injected clocks | delivered cooperative deadline example; automatic refinement has no shared wall-clock deadline |
| 21: fresh install/tutorial | `scripts/install_smoke.jl` locates installed distribution examples, checks identity/version/revision, rejects dev overrides and exercises fitting/serial scalar/status/reconstruction assertions; separate installed JuMP/ToQUBO environment | per-release exact-source installation, unqualified General install and registry-canary checks; see RELEASE.md |

The local runtime suite and every default driver-conformance group run with pinned QUBOTools 0.16.2,
QUBODrivers 0.6.5 and MOI 1.0.0 in the dependency-floor lane. Full package lanes also test direct
JuMP (JuMP 1 needs MOI >=1.1.1). CI preserves Julia 1.10/current on Linux and current Julia on
Windows. Existing examples and documentation links run in every lane; ToQUBO examples run in compatible lanes. An additional Julia 1.10 Linux lane explicitly resolves and pins released ToQUBO 0.7.1 in both the test and example environments, with resolved-version assertions, while normal package lanes resolve the supported 0.7 patch line from 0.7.1.

The ToQUBO test/example dependency is `0.7.1` (fixed minimum, supported 0.7 patch line), with no production dependency
or upstream development override. The [runnable environment and examples](https://github.com/JuliaQUBO/QUBODecomposition.jl/blob/main/examples/toqubo/README.md)
cover fitting and larger-than-budget public ExactSampler composition plus caller-owned outer deadlines.
Rows 17–20 separate compiled energy from independently evaluated source objective and residuals.
An exact whole-model oracle establishes extrema; serial tests check full assignments, monotone
incumbents, source feasibility for the chosen fixtures and truthful heuristic statuses.

Row 19 is delivered with ordinary recompilation on released ToQUBO 0.7.1. Four
unchanged solves retain three compiled bits, complete valid assignments and source
values [1,1], source objective 11, penalized objective 10.9 and INFEASIBLE_POINT.
With QUBODrivers 0.6.5 the actual ExactSampler returns LOCALLY_SOLVED; corrected
0.6.6 reports logical OPTIMAL after complete scans. Source feasibility remains
separately checked and can still be INFEASIBLE_POINT with weak penalties.
Fresh-instance comparisons cover
coefficients, complete mapping/ownership, states and independent scalar energies;
changed penalties, coefficients, Binary/Unary encodings and same-size source ownership
are also exercised without caller resets. Successful, malformed, failed, limited and
empty solves check result/proof/feasibility invalidation. Explicit reset remains tested.
Refined compiler hints persist across ordinary solves; tests read live backend
attributes separately from JuMP's cached inputs. Explicit reset tests disable automatic
refinement and check that the next JuMP source copy restores cached inputs, then
explicitly carry the desired refined hint through reset without additional updates.
Original penalty inputs are explicitly restored when needed.

Historically, ToQUBO 0.7.0 appended stale slack bits on ordinary repeated compilation.
The original downstream tripwire failed as expected on 0.7.1 (unexpected broken-test
pass and obsolete four-bit assertions), then was replaced by strict fresh-compilation
coverage. See the [original reproduction](https://github.com/JuliaQUBO/ToQUBO.jl/issues/244#issuecomment-6065898553),
[upstream fix #252](https://github.com/JuliaQUBO/ToQUBO.jl/pull/252) and
[released install evidence](https://github.com/JuliaQUBO/ToQUBO.jl/issues/244#issuecomment-6068818544).
The public reset workaround is no longer required.

The [development manual](https://juliaqubo.github.io/QUBODecomposition.jl/dev/) is published;
[publication evidence and remaining ecosystem handoffs](deployment.md) are recorded separately.
Row 21 is verified for each release through the [release procedure](https://github.com/JuliaQUBO/QUBODecomposition.jl/blob/main/RELEASE.md). Exact tested SHA/tree evidence belongs in the release PR and issue records. Candidate installation, normal General installation, tag/release verification and subsequent registry-canary adoption are distinct checks.
Tracker #1, QUBODrivers#87, ToQUBO#244, QUBO#73 and roadmap QUBO#76 own their respective delivery assessments.

Production uses public hooks, released `fix_variables`/`lift_state`, and independently recomputed
original energies. No QSplit/D-Wave source is adapted; their pinned selection/offset limitations are
explained in [strategies](strategies.md). No Python runtime is needed. Component packing, custom fast
conditioning, hierarchical/multilevel partition planning, coupled parallel children,
advanced preprocessing composition and coupled external execution remain separate work. Supplied/callback
partition sweeps are implemented and tested below.

[Certified root preprocessing](preprocessing.md) combines an independently verified
reduction with original-state lifting and conservative child-status transfer.
Its tests cover exact/scoped oracles, numeric transport, bounded-work and deadline
refusals, stale proof rejection, public conformance and ToQUBO source feasibility.
The published QUBOPreprocessing operating envelope records the cross-package
cost evidence; default-off adoption keeps those workload limits explicit.

## BFS and random-block selection (#12)

`test/unit/bfs_random.jl` checks multi-hop discovery on paths, cycles, stars, dense
graphs and isolates, arbitrary original labels, capacity boundaries, random
per-component coverage, seed replay/global RNG isolation, changed-input rebuilds,
and independent exhaustive conditioned/lifted energies in both domains/senses
with signed scales and offsets. Caps, child failures, interruption, monotone
acceptance and the six-bit exact-child trap retain the existing transaction and
heuristic-status contracts. `test/conformance.jl` runs every default driver group
for both new policies with controlled exact and released ExactSampler children.

The [four-policy comparison](https://github.com/JuliaQUBO/QUBODecomposition.jl/blob/main/examples/selection/README.md)
records actual tested revisions, guarded total work, phase costs and source
feasibility. This package-local slice does not deliver QUBOPreprocessing or
change the independent release/registration and ecosystem publication gates.


## Separator conditioning (#14)

`test/unit/separator.jl` uses independent scalar/exhaustive oracles on paths,
stars and articulation-linked clusters. It covers empty/full separators,
constant residuals, isolates, ties, arbitrary labels, both domains/senses,
signed scales, offsets and boundary/separator-only terms. A public MOI fixture
fixes a variable before selecting the separator by free-variable position and
checks complete source primal reconstruction. Configuration ownership and plan
rejection are checked before child dispatch.

Controlled exhaustive children supply public `OPTIMAL` in positive certificate
tests; controlled heuristic children preserve the uncertified control. Actual
ExactSampler tests cover the explicit 0.6.5/0.6.6 contract. Failed/malformed
results, branch/call interruption, shared allowances, exact budget boundaries,
missing-certificate reasons and changed/repeated solves retain validated global
incumbents without leaking unfinished branches or proof. All default CPU driver
conformance groups also run in separator mode with both child paths.

The [guarded comparison](https://github.com/JuliaQUBO/QUBODecomposition.jl/blob/main/examples/separator/README.md)
records revision-pinned direct/sweep/separator quality, certificate sources and
complete costs, including unfavorable timings. The feature is opt-in and adds
no preprocessing, partition dependency or release/registration change.


## Automatic articulation discovery (#22)

`test/unit/articulation.jl` independently deletes vertices and recomputes
connectivity for every simple graph through five vertices, sampled larger graphs,
paths, stars, linked dense clusters, cycles, isolates and disconnected inputs.
It covers whole-model capacity, minimal residual scores/ties, zero separator caps,
no-articulation refusal versus a valid supplied plan, tiny nonzero coefficients,
raw option ownership/invalidation and changed/repeated solves. A 30,000-vertex
path checks iterative planning and linear traversal counters without child dispatch.
Scripted deadlines/interruptions inside discovery and validation retain partial
metadata and make zero child calls. Independent tiny original-energy enumeration
compares identical automatic/manual plans across domains/senses/scales/offsets,
public certified/uncertified children and interrupted branches. The MOI fixing
fixture exercises both separator modes; full CPU conformance includes automatic
mode with both child paths. Exhaustive work remains restricted to tiny cases.

Graph-partition coverage lives in `test/unit/partition.jl`: invalid plans before dispatch, isolates and capacity one, callback ownership/failures, repeated model changes, independent conditioned energies and mapped lifting, bridge-discard counterexample, exact-child heuristic trap, shared caps and interrupted transactions.


Frozen-batch coverage lives in `test/unit/voting.jl`: independent bit/spin vote
counts, conflicts/ties/uncovered indices, duplicate rows and multiplicities,
incomparable child energies, identical frozen boundaries, worsening consensus,
conditional repair boundary coefficients and oversized disagreement blocks,
transaction aborts and shared budgets, min/max signed scales/offsets/labels,
repeated solves and exact special cases, and an exact-child global counterexample.
The finite matched-allowance three-mode comparison is retained in
[examples/voting](https://github.com/JuliaQUBO/QUBODecomposition.jl/blob/main/examples/voting/README.md).


## Component executors and absolute deadlines (0.1.2)

`test/unit/components.jl`, `test/integration/process_components.jl` and
`test/unit/absolute_deadline.jl` cover owned frozen jobs, sequential/process
agreement, deterministic commit, shared caps, failure/interruption/draining,
proof refusal, repeated solves, caller worker ownership and the earlier of
absolute and invocation-relative deadlines. The process test uses two actual
local workers and synchronization barriers rather than timing thresholds.
`scripts/install_smoke.jl` also runs the installed three-variable process example:
each worker checks its package source/version and active project against the
coordinator, the caller reuses the pool and cleans it up, and an expired absolute
deadline prevents child dispatch. These APIs require **0.1.2 or later**; candidate
installation evidence remains separate from General and hosted publication.


## Block-orientation coarse proposals (#17)

`test/unit/coarse.jl` independently checks the full substitution identity across
both domains/senses, signed/zero scale, offsets, nonzero linears, within-group,
cross-group and fixed-boundary terms, arbitrary labels, starts and isolates.
It covers the joint partition barrier, macro capacity, subset and singleton maps,
invalid/owned plans before shortcuts, fixed-variable primal reconstruction,
repeated-solve invalidation, transactional malformed/interrupted scans and shared
caps/deadlines. Enumeration reserves bounded work before dispatch/allocation.
The [comparison](https://github.com/JuliaQUBO/QUBODecomposition.jl/blob/main/examples/coarse/README.md)
tracks finite CPU evidence separately from these mathematical and lifecycle checks.

## Sample-guided unary fixing (#18)

`test/unit/sample_fixing.jl` independently checks every prefix restriction and
full lifted energy across both domains/senses, signed/zero scale, offsets and
reordered labels. It covers owned pools, all-row validation and charging before
deduplication, exact threshold boundaries, changing support, abstention, biased
fixings that exclude an optimum, separate global/restricted incumbents, child
OPTIMAL consistency, interruption transactions, shared caps/deadlines and repeated
input invalidation. Enumeration is guarded before allocation or dispatch.
The [finite comparison](https://github.com/JuliaQUBO/QUBODecomposition.jl/blob/main/examples/sample_fixing/REPORT.md)
retains generation cost, no-consensus and biased outcomes with no general
advantage claim. Coarse/sample-fixing APIs require **0.1.4 or later**. The installed
distribution smoke independently scores both complete example states and checks
heuristic status, actual capacity and reconstruction/provenance diagnostics.

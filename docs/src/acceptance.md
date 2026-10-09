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
| 5: disjoint components | exhaustive scalar global extrema across frames/storage; one call per component, complete public OPTIMAL certificates; conservative ExactSampler status | delivered local sampler |
| 6: four linear isolates, partial cap | B=2, cap=3: three singleton calls, complete partial incumbent, ITERATION_LIMIT and incomplete component proof; exact final-cap proof test | delivered local sampler |
| 7: coupled sweeps | enumerated scalar global reference, monotone energy traces/strict commits, latest-incumbent conditioning, bounded caps/stagnation, no coupled global proof | delivered local sampler |
| 8: failed/malformed children | `test/unit/results.jl`, serial failure/empty/malformed/partial-scan tests retain prior committed calls | delivered local sampler |
| 9: duplicates/multiplicities | duplicate rows counted as evaluations, emitted multiplicity one; serial sampler multiplicities 3/7 retained per call with emitted 1 (never 21); serial ExactSampler counts; unknown physical reads separate | delivered local sampler |
| 10: caps/time/cancellation | `test/unit/budgets.jl`, serial call/candidate/sweep/stagnation checks and scripted clocks/checkpoints; disjoint invocation/per-call phase durations and effective/total consistency | delivered local sampler |
| 11: child limits versus parent | valid child early stops continue serial processing; scripted remaining-parent limits/overrun, supported factory/per-child limits | delivered local sampler |
| 12: interruption | child INTERRUPTED/exception and injected before-factory/reconstruction/commit interruption after prior successful calls; checkpoint interruption inside a started sweep retains prior committed state | delivered local sampler |
| 13: seed/support | exact k>1 modular sequence, overflow boundary, unsupported children, reset on repeated invocation | delivered local sampler |
| 14: repeated solves/data | same-size reordered labels, changed domain/sense/scale/offset/coefficients/graph; fresh maps, plans, counters and proof; preserved whole-model regressions | delivered local sampler |
| 15: driver conformance | `test/conformance.jl`: every default group, controlled public exact child and released ExactSampler, both fitting and serial budgets | delivered local sampler |
| 16: direct JuMP | `test/integration/jump.jl`: binary/spin, Min/Max, diagonal convention, constants/fixed variables, separable and coupled larger-than-budget solves, complete original primals | delivered local sampler |
| 17: ToQUBO binary/refinement | `test/integration/toqubo.jl`: four source assignments (feasible optimum 8), all eight compiled assignments; weak penalty gives source 11/compiled 10.9 and default INFEASIBLE_POINT; opt-out and -0.1 → -1 → -10 automatic refinement; captured compiler/composite and child coefficients; fitting exact and B=2 heuristic runs | delivered with ordinary reused solves and live refined-hint persistence |
| 18: ToQUBO integer/auxiliary/slack/cubic | `test/integration/toqubo.jl`: source extrema 7/13 in both senses; assert actual integer/slack bits, enumerate every compiled bit and minimize/maximize over slack; lifted binary cubic extrema 3/8 with separately identified quadratization bits and exhaustive auxiliary envelope | delivered via quadratic MOI product lift; direct nonlinear cubic source input is unsupported in ToQUBO 0.7 |
| 19: recompile/refinement mapping | `test/integration/repeated_refinement.jl`: same compiler/composite reused with changed coefficients, penalties, source index ownership and Binary/Unary encoding; four ordinary ExactSampler solves keep three bits and match fresh coefficients, ownership, complete assignments and independently evaluated energies; failed/missing/limited results, committed-incumbent and feasibility-cache checks; explicit reset | delivered against released ToQUBO 0.7.1 |
| 20: outer refinement budgets | `test/integration/repeated_refinement.jl`: at most 1+updates invocations, feasible/empty/unreachable early stops; per-call limit minima, new invocation clocks/counters/seeds, ExactSampler complete-scan cap 9 vs truncated 8; explicit absolute-deadline example checks compilation/copy/check work and opaque-child overrun with injected clocks | delivered cooperative deadline example; automatic refinement has no shared wall-clock deadline |
| 21: fresh install/tutorial | package import, whole-model example and `examples/serial_sweeps.jl`: larger-than-budget heuristic status, isolate/fixed-variable reconstruction | release/tag/registry fresh-install verification |

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
Released ExactSampler remains LOCALLY_SOLVED. Fresh-instance comparisons cover
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
Release/fresh-install row 21 and ecosystem adoption remain subsequent milestones.
Tracker #1, QUBODrivers#87, ToQUBO#244, QUBO#73 and roadmap QUBO#76 remain open.

Production uses public hooks, released `fix_variables`/`lift_state`, and independently recomputed
original energies. No QSplit/D-Wave source is adapted; their pinned selection/offset limitations are
explained in [strategies](strategies.md). No Python runtime is needed. Component packing, custom fast
conditioning, advanced partitions, voting/repair, parallel children and external execution remain
later work.

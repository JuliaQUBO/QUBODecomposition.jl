# Design acceptance matrix: serial runtime slice

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
| 17: ToQUBO binary/refinement | pending | full downstream integration |
| 18: ToQUBO integer/auxiliary/slack/cubic | pending | full downstream integration |
| 19: recompile/refinement mapping | pending | full downstream integration |
| 20: outer refinement budgets | pending | installable newer ToQUBO APIs and full integration |
| 21: fresh install/tutorial | package import, whole-model example and `examples/serial_sweeps.jl`: larger-than-budget heuristic status, isolate/fixed-variable reconstruction | release/tag/registry fresh-install verification |

The local runtime suite and every default driver-conformance group run with pinned QUBOTools 0.16.2,
QUBODrivers 0.6.5 and MOI 1.0.0 in the dependency-floor lane. Full package lanes also test direct
JuMP (JuMP 1 needs MOI >=1.1.1). CI preserves Julia 1.10/current on Linux and current Julia on
Windows; both runnable examples and documentation links run in every lane.

Full ToQUBO auxiliary/slack/feasibility/refinement integration is the next slice, using an installable
release containing its newer MaxPenaltyUpdates and PrimalFeasibilityCheck interfaces. This work
neither adds a production ToQUBO dependency nor claims rows 17–20 passed. Subsequent release/fresh
installation and ecosystem adoption follow the design sequence. Tracker #1, QUBODrivers#87,
ToQUBO#244, QUBO#73 and roadmap QUBO#76 remain open for that handoff.

Production uses public hooks, released `fix_variables`/`lift_state`, and independently recomputed
original energies. No QSplit/D-Wave source is adapted; their pinned selection/offset limitations are
explained in [usage](usage.md). No Python runtime is needed. Component packing, custom fast
conditioning, advanced partitions, voting/repair, parallel children and external execution remain
later work.

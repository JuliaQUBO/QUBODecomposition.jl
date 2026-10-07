# Design acceptance matrix: first runtime slice

The [pinned matrix](https://github.com/JuliaQUBO/QUBO.jl/blob/7c3391f9e4ccf369027da858866f6d4b74790313/docs/src/design.md#offline-acceptance-matrix)
contains the full MVP requirements. The table below maps every row in its original order.
Partial means the whole-model portion is tested; no conditioned/components/sweep coverage is claimed.

| Row | First-slice evidence | Remaining coverage |
| --- | --- | --- |
| 1: domains/senses/forms/scales/offset | `test/unit/whole_model.jl`, independent scalar enumeration | conditioned and lifted energies |
| 2: labels, reordering, isolates | whole-model oracle and copied index fixture | conditional label/lift round trips |
| 3: empty/constant/one/all fixed | whole-model and JuMP/MOI edge tests | delivered for this path |
| 4: budget one/capacity/invalid | singleton, oversized input diagnostic, config tests | neighbor selection, oversized-component policies |
| 5: disjoint components | pending | all component certificates/global assembly |
| 6: four linear isolates, partial cap | pending | serial singleton calls and partial proof |
| 7: coupled sweeps | pending | monotonicity and no global proof |
| 8: failed/malformed children | `test/unit/results.jl` | same failures across conditioned calls |
| 9: duplicates/multiplicities | whole-model candidate/output accounting, ExactSampler reads | component combination (no invented joint reads) |
| 10: caps/time/cancellation | `test/unit/budgets.jl`, scripted clock/checkpoints | sweeps, stagnation and serial continuation |
| 11: child limits versus parent | one-call status preservation and parent overrun | later-neighborhood continuation |
| 12: interruption | before factory, reconstruction and child interruption | conditioned serial paths |
| 13: seed/support | deterministic repeat, first-call modular forwarding | k>1 serial sequence |
| 14: repeated solves/data | `test/unit/repeated_solves.jl`, MOI copying | graph/conditioned-plan invalidation when introduced |
| 15: driver conformance | `test/conformance.jl`, all defaults enabled, both controlled child and ExactSampler | broader serial optimizer conformance |
| 16: direct JuMP | binary/spin, Min/Max, diagonal convention, constants/fixed variables | broader serial cases |
| 17: ToQUBO binary/refinement | pending | full downstream integration |
| 18: ToQUBO integer/auxiliary/slack/cubic | pending | full downstream integration |
| 19: recompile/refinement mapping | pending | full downstream integration |
| 20: outer refinement budgets | pending | installable newer ToQUBO APIs and full integration |
| 21: fresh install/tutorial | package import and supported public whole-model example | release/tag/registry install, larger-than-budget heuristic tutorial |

No claim is made that the full serial-decomposition or ToQUBO matrix passes.
Next slice: fitting components, oversized-component policy and conditioned sweeps using released
`fix_variables`/`lift_state`, with independent full-energy acceptance and serial limit/seed tests.
Then full compiler integration, installation/release checks and adoption follow the design sequence.
Coordination remains open in QUBODrivers#87, ToQUBO#244, QUBO#73 and roadmap QUBO#76.

Production uses public hooks, not copied private driver/compiler helpers. The pinned QUBOTools and
QUBODrivers sources are references. No QSplit/D-Wave source is adapted and no Python runtime is needed.

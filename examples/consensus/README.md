# Offline overlapping-block consensus

Run `julia --project=. examples/consensus/offline.jl` for a guarded example.
It uses a dedicated exact rational MOI child that enumerates at most four
variables and reserves at most 1,024 assignments across a parent solve. It does
not change released ExactSampler's public status.

The bounded comparison is `JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 timeout 600
julia --project=. examples/consensus/compare.jl NEW_OUTPUT_DIRECTORY`.
Run it only within an explicitly authorized experiment budget. The new output
directory must not exist. The script freezes all fixtures, starts, overlapping
plans, separate disjoint partition plans, settings and source hashes before
measurement and retains each started attempt, including failures. There are
three fixtures, one warmup and two measured pairs per fixture: 18 top-level solves
and no retries. Both methods share the child, starts, 64-call and 2,000-parent-
evaluation ceilings, 10-second cooperative parent deadline, and 1,024 enumerated
child-assignment guard. Consensus has at most 16 iterations and four blocks per
plan; partition has at most 16 sweeps. All children have at most four variables.
No workers or external annealers run. Use an OS memory limit as appropriate for
the host as well as the ten-minute hard process timeout.

`wall_sec` includes model/optimizer construction and the complete parent solve,
including coordination, reconciliation and original evaluation. Child execution
and parent phase times are reported separately. Oracle evaluation and file writes
are outside this timing. Warmups are retained and excluded from measured pairs;
JIT can still affect later fixtures. Compare paired repetitions and report their
actual work alongside quality and bounds, rather than assuming equal work from
equal ceilings. Consensus's parent evaluation count includes surrogate rows;
partition's counts complete original candidates. Child-assignment counts make
the different enumeration work explicit. Baseline partition completion has no
reported global bound. A gap in the original-oracle comparison is observed
quality, distinct from consensus's certified normalized bound gap.

Results and the adopt/revise/defer conclusion will be recorded with the retained
measurement evidence. No general performance claim follows from these fixtures.

## Retained first-slice comparison

**Conclusion: revise before wider adoption.** Keep the prototype opt-in for human
review. Reference-copy reconciliation misses a better chain candidate, while
escaping a joint-move barrier; the frustrated triangle retains a duality gap.
Improved reconciliation or optional bounded repair is a follow-up, not an
unmeasured claim for this PR. No general superiority or speedup is established.

The [frozen plan](evidence/plan.toml), [source hashes](evidence/source-sha256.toml),
18 raw attempts, Project and Manifest are retained in `evidence/`. All attempts
completed without retries: 18/32 authorized comparison solves consumed, leaving
14 for necessary post-review validation. Total reserved/completed child work was
2,406 assignments; no solve exceeded 192, below its 1,024 ceiling. Summed complete
solve wall time including warmups was 9.940504 seconds. Every solve stayed below
its ten-second parent deadline; the process ran under `timeout 600`, one Julia
thread, one BLAS thread and a 10,000,000 KiB virtual-memory ceiling. It used Julia
1.10.11, QUBOTools 0.16.2, QUBODrivers 0.6.5 and MOI 1.54.0. These measurements
belong to the executable source hashes, not published version 0.1.2. Measurement
ran before the implementation commit: `source_head` records the base checkout;
the hashes identify the measured implementation. Later revisions require a hash
comparison before treating these timings as current implementation evidence.

Both measured repetitions gave the following quality and work. Calls, assignments
and parent evaluations are shown as partition/consensus. Bounds are normalized
minimization lower bounds; the partition baseline reports none.

| Fixture | Original optimum | Candidate energies P/C | Consensus bound | Calls P/C | Child assignments P/C | Parent evaluations P/C |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Chain and isolate | 0.25 | 0.25 / 1.25 | 0.25 | 33 / 48 | 130 / 160 | 34 / 65 |
| Joint barrier | -8 | 0 / -8 | -8 | 32 / 12 | 128 / 96 | 33 / 16 |
| Frustrated triangle | 1 | 1 / 1 | -1 | 32 / 48 | 96 / 192 | 33 / 65 |

Consensus finished with `LOCALLY_SOLVED` throughout. Baseline sweeps reached their
16-sweep `ITERATION_LIMIT`, retaining valid candidates. The chain's certified gap
is 1; the barrier's is zero without status promotion; the triangle's is 2. Warmup
attempts are retained and excluded from the two measured pairs. Paired complete
wall differences (consensus minus partition, milliseconds) were `[-0.261,+0.731]`,
`[+1.164,-0.255]`, and `[+1.621,+0.686]`, respectively; their medians were +0.235,
+0.454 and +1.154 ms. Two repetitions at millisecond scale are insufficient for
performance conclusions. Construction, coordination and reconstruction are inside
the complete wall boundary; raw phase times distinguish parent and child work.

Run `python3 examples/consensus/summarize.py` (Python 3.11+) to audit all attempts
and reproduce the paired summaries without invoking any solver. This allowance
does not rerun earlier separator-pruning or native-annealer experiments.

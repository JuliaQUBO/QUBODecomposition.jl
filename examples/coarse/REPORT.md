# Bounded coarse-proposal comparison

**Outcome: adopt as an opt-in bounded proposal.** On the joint barrier, one coarse
move supplies an improvement that another exact partition sweep misses. The two
control fixtures match the partition result. Timings are mixed and noisy across
only two measured pairs; these data establish no general runtime or quality advantage.

The producing source is `750c350f112526617177801ad5d8ad3101436b74`, based on merged
transition `4bc2ff497da5cf911826d08c400a9edcec1bb24d`. The public ExactSampler is
immutable **candidate** `7ad2e929af65d0169f0dcb443ec4f99824aa3b67` (version 0.6.6),
not a claim that 0.6.6 was registered. Julia 1.10.11, QUBOTools 0.16.2 and MOI 1.54.0
were used. [The plan](evidence/20261016/plan.toml) binds fixture coefficients,
starts, groups, options, environment Manifest and actual driver/conversion/MOI
source hashes. No upstream reference implementation was adapted.

## Design and complete costs

Each arm starts from the same fixture state and performs at most three partition
sweeps. Stage two is one further partition sweep or one coarse proposal. Both
stages use the same public child and share one absolute 10-second deadline, 64
calls, 1,024 original candidate evaluations and 512 reserved child assignments.
Remaining calls/evaluations and the deterministic attempt seed stream carry into
stage two. The guard reserves enumeration work before dispatch; every child has
at most four variables. Actual children here have one or two variables.

Three fixtures, one warmup pair and two measured pairs each produced **18 arms,
36 parent invocations and 726 child assignments**, with no failed arms or
measured-arm retries. Pair order alternates. The total child ceiling was 9,216.
The process used one Julia/precompile/BLAS thread, a 600-second timeout and a hard
8 GiB virtual-address cap; this is not an aggregate RSS/no-swap limit. Logs have
an OS file-size cap of 32 MiB. Retained evidence is about 128 KiB, below 100 MiB.

Wall time begins before the first source/optimizer/group construction and ends
immediately after the second result attaches. It includes both constructions,
selection/conditioning or coarse construction, copying, child execution, full
original evaluations, lifting, attachment and intervening harness bookkeeping.
Imports, independent scalar audits and artifact writes are outside that timer.
The phase fields below cover parent callbacks and do not include every operation
inside the broader wall timer.

## Measured pairs

Work columns are per whole arm and are identical between the two measured
repetitions. Energies are independently checked original minimization objectives.
Wall columns list repetition 1 / repetition 2 in milliseconds, rather than selecting
a favorable repetition. Full precision and paired differences are retained in
[summary.json](evidence/20261016/summary.json).

| Fixture | Stage-two arm | Energy | Calls | Original evaluations | Child assignments | Wall ms, pair 1 / 2 |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Joint barrier | Partition | 0 | 8 | 34 | 32 | 1.327 / 1.142 |
| Joint barrier | Coarse | -4 | 7 | 30 | 28 | 31.971 / 2.008 |
| Boundary/internal terms | Partition | -48.75 | 18 | 54 | 52 | 3.669 / 3.532 |
| Boundary/internal terms | Coarse | -48.75 | 14 | 44 | 42 | 2.063 / 2.207 |
| Easy attractive chain | Partition | -9 | 12 | 50 | 48 | 2.115 / 2.719 |
| Easy attractive chain | Coarse | -9 | 10 | 42 | 40 | 2.040 / 2.422 |

The scalar global optima are respectively -4, -48.75 and -9. The barrier has
nonzero linear terms: `sum(x)-2*(x1+x2)*(x3+x4)`. From zero, either original block
change costs +2, while both orientations together give -4. Exactness of the child
still supplies no original-problem certificate for a non-surjective coarse map.
Both arms remain heuristic outer searches. The other fixtures show no extra
quality benefit. Equal ceilings produced unequal actual work; fewer child states
do not by themselves imply a faster complete solve.

The next table reports the median of the two measured whole-arm phase sums, in
milliseconds. Build/copy combines preparation, conditioning and copying.
Validation/lift includes row validation and reconstruction; it does not isolate
lifting alone. Child execution includes the public child optimizer invocation.
These callback phases are disjoint, but need not sum to the broader wall time.

| Fixture | Arm | Build/copy | Validation/lift | Child execution | Original evaluation |
| --- | --- | ---: | ---: | ---: | ---: |
| Joint barrier | Partition | 0.2657 | 0.0961 | 0.2986 | 0.0034 |
| Joint barrier | Coarse | 0.5787 | 0.1618 | 15.3085 | 0.0050 |
| Boundary/internal terms | Partition | 0.9852 | 0.2833 | 1.0799 | 0.0090 |
| Boundary/internal terms | Coarse | 0.5274 | 0.1642 | 0.6006 | 0.0054 |
| Easy chain | Partition | 0.6060 | 0.2106 | 0.6234 | 0.0068 |
| Easy chain | Coarse | 0.5384 | 0.2169 | 0.6132 | 0.0062 |

The coarse barrier arm is slower in both measured pairs despite doing fewer
child assignments. This report makes no causal attribution for the timing spread.
The other two fixtures favor coarse in these tiny measurements. Two pairs and
these deliberately small controls support an opt-in implementation decision only.

## Audit accounting and retained failures

A provenance preflight at source `35a81a01467d84f0362c6f29ae8b1d533cd4cb60`
failed on an unquoted Julia command revision expression. It created an empty
output directory and ran **144 scalar fixture-oracle assignments**, then failed
before writing a plan or starting any arm. It made zero parent or child calls.
An initial status message understated that audit work; filesystem and control-flow
inspection corrected the record before continuing. The
[failed log](evidence/20261016/preflight-failure.log) and
[accounting record](evidence/20261016/preflight-accounting.toml) are retained.
No measured arm was replaced or repeated.

The original 512 scalar-audit allowance includes those 144 spent assignments,
144 fixture-oracle assignments in the successful producing run, and 36 independent
scalar checks of its attached stage states: **324 total**, not 180. The
[immutable producer totals](evidence/20261016/totals.toml) record that count.
A separate independent review of the 36 retained stage energies can fit in the
remaining allowance; it is not represented here as already performed.

The campaign computed original scalar energies outside timing and compared them
with every attached stage energy. [summarize.py](summarize.py) separately verifies
the recorded outcomes, statuses, work ledgers, ceilings, producing-source hashes
and dependency-source hashes. That verifier does not independently recompute the
stage energies. The retained raw states and fixture coefficients permit such an
audit without another solver invocation or enumeration. All child public statuses
in the successful campaign were `OPTIMAL`; coarse parent statuses remain heuristic.

## Correctness checks and reproduction

The [verification record](evidence/20261016/verification.json) and logs retain:

- Candidate-driver full package/conformance/JuMP/ToQUBO suite: 60,366 assertions
  at `73ef53ea85c2d6a6c9353b61c3ac7dcb2dfd21f2`, before 63 additional public-adapter
  assertions. Production runtime is unchanged afterward.
- Final candidate focused cohort: 716 assertions, 228 oracle/macro assignments
  and 220 child assignments, covering the additional actual public-child adapter.
- Released General 0.6.5 full suite: 60,427 assertions; MOI 1.0.0 runtime-floor
  suite: 57,888. Both include the final public-child cases and conservative status.
- Candidate nondeploying manual/doctests/executable examples and 32 Markdown file
  checks passed. The first sandbox attempt could not open local worker sockets;
  the identical build passed with local socket permission. No source fix was needed.
  A final file-link check after adding this report passed all 33 Markdown files.
- Final harness macro expansion passed before the producing run. The initial
  syntax-only parse did not catch the command-literal macro error.

Use a fresh isolated environment with this package and the fixed public candidate
(or a subsequently verified release), checking source identity against the retained
hashes. From the repository root, a fresh campaign is:

```sh
julia --project=/absolute/isolated/environment examples/coarse/compare.jl NEW_OUTPUT_DIRECTORY
python3 examples/coarse/summarize.py NEW_OUTPUT_DIRECTORY /absolute/repository
```

Apply the same process/thread/memory/file-size limits as the recorded plan. The
recorded continuation supplied the optional `144` audit carry argument because it
belonged to the same already-started audit campaign. A new reproduction omits
that argument and records its own work; it must not import historical spent work
as new observations. Never overwrite prior output or retry a measured arm.
Registration, hosted publication, independent review and merge checks remain their
separate authorized workflows.

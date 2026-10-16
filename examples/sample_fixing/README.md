# Bounded sample-guided fixing examples

`offline.jl` supplies a biased explicit pool, fixes a residual within child
capacity two, and preserves a better full-space incumbent excluded by the
restriction. `SampleFixingExample.run()` returns the optimizer, state, energy,
status, metadata and guarded child-work diagnostics. It uses no credentials,
external pool generator or new dependency. Its parent has a ten-second limit,
four-call and 32-candidate ceilings; its public exact child guards dimension and
assignment count before enumeration. The result remains heuristic with either
released ExactSampler 0.6.5 or the corrected 0.6.6 public status contract.

After developing this checkout into the docs environment, run the standalone
example with `julia --project=docs examples/sample_fixing/offline.jl`. Call
`include("examples/sample_fixing/offline.jl"); SampleFixingExample.run()` to
inspect its returned public optimizer and metadata.

## Finite comparison design

`compare.jl --preflight` checks fixture dimensions, partitions, source/environment
identity and the finite work plan without enumeration, optimization or output
artifacts. The measurement path accepts one **new** output directory. A completed
campaign must never be rerun into that directory, replace an arm or select only
favorable results. The [completed report](REPORT.md) retains the one campaign, every pair and its
source/environment evidence.

There are three fixed connected binary fixtures: six variables with four stable
unanimous coordinates and a fitting two-variable residual; four variables whose
initial and generated states disagree everywhere, yielding no consensus; and the
four-variable joint barrier whose unanimous zero pool excludes the true optimum.
No fixture is selected or changed after observing campaign outcomes.

Each arm starts from its fixture input and uses the same public bounded CPU
ExactSampler, with capacity two. Its first parent runs the existing component/
partition policy for at most three sweeps. Capture exactly two attributed full
rows: the caller's complete initial state and the generation parent's public
complete final incumbent. Both were independently scored by that parent; copying,
source construction, optimization, result extraction and pool construction are
inside the arm timer. There are no private intermediate-state hooks, extra parent
calls or hidden oversized pool solver. Duplicate rows remain supplied and charged
before distinct-state voting. With two distinct rows and threshold greater than
one half, only unanimous coordinates can qualify. This is optimization input,
not an annealer sample distribution.

Stage two compares one further partition sweep with one sample-fixing proposal
at threshold 1.0. Both arms construct the same explicit pool; sample fixing also
pays its required row-validation/deduplication cost. The same absolute ten-second
deadline, 64 calls, 1,024 original candidate evaluations and 512 reserved child
assignments carry across both parents. Generation calls and original evaluations
are included, and every supplied pool row is additionally charged by treatment.
Shared ceilings do not imply equal consumed work or cost. Every child is checked
before exponentiation/dispatch, with a hard four-variable bound. No native,
hardware, Python or paid solver is used.

Three fixtures times one warmup pair and two measured pairs allow exactly 18 arm
attempts and at most 36 parent invocations. Pair order alternates. Aggregate child
work is at most 9,216 assignments. Independent fixture oracles use 96 assignments;
checking the two stage states and two pool rows per arm uses 72 more, for a planned
168 of 512 scalar audits. These audits are verification outside the arm timer,
separate from the optimization candidate ledger. All successful, failed, limited
and warmup attempts are retained; no retries are permitted once an arm starts.
If a failed solve prevents a stage record, parent counters are explicitly marked
partial/unknown and recorded values are only lower bounds. Compatibility is
reported only when a terminal restriction was actually considered.

Wall time ends at stage-two result attachment and includes generation and both
optimizer/source constructions, explicit pool copies, validation, selection,
conditioning, residual work, lifting and attachment. Pool generation time ends
after generation result extraction and copying the public final state; remaining
pool option construction is included in overall wall time. Imports, independent
scalar audits and artifact writes are outside the timer. Phase times supplement
the broad wall measurement and do not partition all harness operations.

Run only in a frozen exact-source environment with one heavy process, Julia,
precompile and BLAS thread, `prlimit --as=8589934592:8589934592`, and an outer
`timeout 600`. The address limit is per process, not aggregate RSS/no-swap control.
The harness caps serialized artifacts at 64 MiB, logs must be capped at 32 MiB,
and environment/provenance at 4 MiB, within 100 MiB retained total. Record all
failed preflights and consumed scalar work; never reset a spent allowance.

`summarize.py NEW_OUTPUT_DIRECTORY REPO` verifies recorded outcomes, status and
work ledgers and source/dependency hashes, then reports both measured repetitions
and within-pair differences. The producer performs the independent scalar audits;
the summarizer does not independently recompute energies. The final report must
retain no-consensus and biased outcomes, distinguish costs actually consumed,
and make no general quality, runtime or quantum-advantage claim.

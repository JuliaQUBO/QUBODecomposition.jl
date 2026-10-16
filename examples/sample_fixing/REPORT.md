# Tiny full-cost sample-fixing comparison

**Outcome: adopt only as an opt-in bounded heuristic.** On these three fixed CPU
fixtures, sample fixing and another partition sweep return the same energies.
Treatment consumes fewer calls/evaluations/child assignments under the common
ceilings, but measured timing differences change sign on two fixtures. These data
establish no general runtime or quality advantage. The biased pool explicitly
misses the true optimum, while the no-consensus pool abstains honestly.

The producer is `8066c8a0fe974714f72c57f51f4ed4b15db2dcb1`, based on merged main
`843fc6d7d05463ecff5bc556a322b2cbd945e5e9`. Public ExactSampler is immutable
**candidate** `7ad2e929af65d0169f0dcb443ec4f99824aa3b67` (version 0.6.6), not a
claim of General registration. Julia 1.10.11, QUBOTools 0.16.2 and MOI 1.54.0 were
used. [The frozen plan](evidence/20261016/plan.toml) binds all fixtures, source,
conversion/driver/MOI content hashes, settings and the actual environment Manifest.
No external reference implementation was adapted.

## What the cost includes

Both arms begin with the same bounded partition generation stage, at most three
sweeps and capacity two. The explicit two-row pool contains the caller's complete
initial state and the generation parent's public complete final incumbent. Both
were evaluated by that parent. Copying, source/optimizer construction, generation,
result extraction and pool construction lie inside the arm timer. No private
intermediate-state hook, extra generation parent or oversized full-model solver
is used. Duplicates remain supplied and charged before distinct equal voting.
With two distinct rows and a threshold greater than half, only unanimous
coordinates qualify; this is not an annealer sample distribution.

Stage two is one further partition sweep or one sample-fixing proposal. Calls,
original evaluations, reserved child assignments and the absolute deadline carry
across both parents. Treatment also pays its required pool validation/deduplication
cost. The shared ceilings are 64 calls, 1,024 original evaluations, 512 child
assignments and ten seconds per arm; they do not mean equal consumed work or cost.
Each actual child has two variables, guarded before exponentiation and dispatch;
the hard permitted ceiling is four.

Wall time ends at stage-two result attachment. It includes both source/optimizer
constructions, pool copies, validation, selection, conditioning, residual work,
lifting and attachment. Pool generation time ends after generation result
extraction and copying its public final state. Imports, independent scalar audits
and artifact writes are outside the arm timer. Raw phase timers for selection,
conditioning, child execution, validation/reconstruction and original scoring are
retained alongside the broad wall time; they do not partition all harness work.

## All measured pairs

The numbers below include generation and terminal stages. Repetitions 1 / 2 are
shown separately; work and energies are identical across those repetitions.
Warmup pairs and every started/result marker are also retained.

| Fixture | Terminal policy | Energy | Calls | Original evaluations | Child assignments | Wall ms 1 / 2 | Generation ms 1 / 2 |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Capacity fit | Partition | -2 | 12 | 50 | 48 | 2.224 / 1.807 | 1.474 / 1.180 |
| Capacity fit | Sample fixing | -2 | 10 | 44 | 40 | 2.468 / 1.742 | 1.834 / 1.164 |
| No consensus | Partition | -8 | 8 | 34 | 32 | 1.821 / 1.472 | 1.223 / 0.973 |
| No consensus | Sample fixing | -8 | 6 | 28 | 24 | 1.277 / 1.100 | 0.991 / 0.891 |
| Biased barrier | Partition | 0 | 8 | 34 | 32 | 2.155 / 1.336 | 1.603 / 0.896 |
| Biased barrier | Sample fixing | 0 | 7 | 32 | 28 | 1.441 / 1.594 | 0.967 / 0.988 |

Capacity fit retains four unanimous zero coordinates and solves a two-variable
residual; both arms attain its independently enumerated optimum -2. No consensus
has two opposite distinct rows and dispatches no terminal child; generation
already attained its optimum -8, so abstention saves work here. The biased barrier
has two supplied duplicate zero states, one distinct vote, and fixes away the
all-one optimum -4; both arms remain at 0. Sample agreement is not persistency.
A separate regression and callable offline example demonstrate that a superior
previously known full incumbent survives an incompatible biased restriction.

Full-precision within-pair differences and all phase fields are in
[campaign-summary.json](evidence/20261016/campaign-summary.json). Capacity-fit's
sample-minus-partition wall differences are +0.245 / -0.065 ms; biased barrier's
are -0.714 / +0.258 ms. Two measured pairs per fixture support no timing
extrapolation or speculative explanation of those differences.

## Work, audits and verification

The one campaign completed **18 arms and 36 parent invocations**, using **612
child assignments**, with zero failed arms or retries. The aggregate allowance
was 9,216 child assignments. The producer performed 96 independently guarded
fixture-oracle assignments plus 36 stage and 36 pool-row scalar checks: **168**
audits. Zero-work preflight and whole-script parse/macro expansion consumed no
assignments or solver calls. The summarizer verifies recorded statuses, ledgers
and source/dependency hashes; it does not independently rescore energies.

The additive [independent pointwise audit](evidence/20261016/root-pointwise-audit.json)
recomputed all 36 retained stage energies with a Fraction-based scalar polynomial,
without production scoring helpers, enumeration or optimizer calls. All passed;
its inputs are SHA256-bound. The complete scalar ledger is **204/512**, leaving
308. Raw producer `totals.toml` remains unchanged at 168; no stage was re-solved
or campaign arm replaced.

The process used a hard 8 GiB per-process virtual-address cap, timeout 600,
one Julia/precompile/BLAS thread, an isolated writable depot over read caches,
and a 32 MiB file-size cap. This does not establish aggregate RSS/no-swap control.
The [environment and check record](evidence/20261016/verification.json) retains
both dependency contracts: the candidate full CPU/JuMP/ToQUBO suite passed 61,550
assertions, released 0.6.5 passed 61,548, the MOI 1.0.0 floor passed 59,009, and
the focused new cohort passed 1,013 (488 guarded oracle / 126 child assignments).
The nondeploying manual build passed doctests, executable examples and source
link checks. These checks cover final runtime/test content; later additions only
retain this report and evidence. The intentional worker-loss fixture's EOF trace
is retained in otherwise successful full/floor logs.

This establishes the bounded unary interface and its limitations on these tiny
fixtures. It does not establish optimum-preserving fixings, a stronger global
certificate, a general benefit, hardware behavior or a quantum advantage.

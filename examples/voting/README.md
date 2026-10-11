# Bounded frozen-batch comparison

Use Julia 1.10 or a current supported runtime, one Julia/BLAS thread, QUBODrivers
0.6.5 and QUBOTools 0.16.2. Develop this checkout in an isolated environment with
MathOptInterface. Commit the candidate before running from the package root:

```sh
julia --startup-file=no --threads=1 --project=/path/to/environment examples/voting/compare.jl /tmp/voting-comparison-new
```

The output path must be new. Apply an OS resident-memory cap of 4 GiB with swap
disabled and a 180-second process timeout. The runner has a 120-second campaign
cap. It verifies the imported source and clean candidate revision, records raw
TOML outcomes and environment manifests, and guards enumeration before allocation.

Declared limits: three fixed fixtures, three modes (serial strongest-edge,
frozen voting alone, frozen voting with repair), one symmetric warmup and one
measured repetition per fixture/mode, plus three refusal probes: **30-attempt ceiling**,
including failures. A fresh runner starts at zero: nine warmups, nine measured
runs and three refusal probes charge 21 attempts. The historical preflight failure
belongs only to the retained campaign below, whose measured repetition count
was reduced from two to one within the original allowance. Each attempt has at most 24 child calls, capacity three (two
for the trap), 256 cumulative child assignments, 64 parent evaluations, three
sweeps, one stagnant sweep, seed 41, identical starts and five parent seconds.
Campaign child assignments are capped at 7680, and parent evaluations at 1920.
Independent oracles have maximum dimension seven and a separately reserved
256-assignment cumulative limit. Counts distinguish reservations, actually visited
assignments and derived objective term-work. Refusals consume attempts but no
unreserved assignments. No broader campaign or CI timing threshold is introduced.

Complete execution timing begins before optimizer construction/model loading and
includes graph/selector work, conditioning, child construction/copy/solve,
aggregation, repair, validation, reconstruction, original energy and attachment.
Imports, symmetric warmup attempts and the independent oracle audit are recorded
separately from measured execution. Each raw attempt retains source/environment,
quality, status/failure, costs, boundaries, batch diagnostics and consumed work.
Paired differences are computed before aggregation. Identical allowances do not
imply identical consumed work or globally optimal results.

## Recorded result and decision

The retained [raw evidence](evidence/20261010/evidence.toml) and
[paired differences](evidence/20261010/paired.toml) come from clean candidate
`5cc5fe31bd306668d18b683afb49567d924f5d55`, tree
`9fed0cc1f41ce1993cc80a62ddcefae58de02bfe`, Julia 1.10.11, one Julia/BLAS
thread, MOI 1.54.0, QUBODrivers 0.6.5, QUBOTools 0.16.2 and ToQUBO 0.7.1.
The environment Project/Manifest and script SHA256 accompany raw records.
One [preflight parsing failure](evidence/20261010/preflight-failure.log) occurred
before enumeration; it is retained and charged, with unmeasured duration.
No previous comparison's artifacts or spent allowance was changed.

Cells show **energy / completed child assignments / full execution ms** for the
single measured repetition. Costs include construction through attachment.

| Fixture | Serial neighborhoods | Voting alone | Voting + repair | Global oracle |
| --- | --- | --- | --- | --- |
| Clusters + bridge + isolate | 3.75 / 98 / 5.204 | 3.75 / 98 / 1.377 | 3.75 / 102 / 1.541 | 3.75 |
| Coupled trap | 0 / 24 / 0.828 | 0 / 24 / 0.893 | 0 / 24 / 0.878 | -24 |
| Frustrated four bits | -5 / 32 / 0.920 | -5 / 32 / 1.031 | -5 / 32 / 1.126 | -5 |

The 21 executed attempts plus the preflight failure charge 22 of the original
30-attempt ceiling. Cumulative reserved and independently counted completed
child assignments both equal 944 of 7680, and parent evaluations total 268 of
1920. Independent oracle reservations and actual visits both equal 208 of 256
(`2^7 + 2^6 + 2^4`). The three refusal probes reserve/complete four assignments,
then reject the next enumeration before reservation. Each retains a valid zero
incumbent and reports `OTHER_ERROR`; the frozen modes discard the unfinished batch.
All regular attempts complete with heuristic `LOCALLY_SOLVED` status.

Conclusion: **adopt as opt-in**, preserving serial as the default. These fixtures
show equal observed quality with mixed costs; repair adds work on the cluster
fixture and does not escape the trap. The independently tested worsening-consensus
fixture demonstrates useful conditional repair behavior, but the comparison does
not establish a quality advantage. One measured repetition, one seed, small
fixtures, serial-first order and timing variation cannot establish a general
speedup, timing uncertainty or success probability. No timing threshold enters CI.

The reusable runner now records only failures that occur during the new run; it
does not inject the retained campaign's inherited preflight charge. Its source
has since changed to make that distinction explicit. The frozen 22-attempt
evidence above remains tied to its recorded candidate and script hash and was
not rerun or rewritten.

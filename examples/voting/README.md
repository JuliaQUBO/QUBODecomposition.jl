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
including failures. One pre-child parsing failure is charged; the measured
repetition count was reduced from two to one within the original allowance.
Nine warmups, nine measured runs and three refusal probes plus that failure
charge 22 attempts. Each attempt has at most 24 child calls, capacity three (two
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

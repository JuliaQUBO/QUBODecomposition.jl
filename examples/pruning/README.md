# Certified separator pruning

Run the offline example with `julia --project=. examples/separator_pruning.jl`.
Its original-domain exhaustive children are guarded by the parent capacity of
one variable, with an eight-variable ceiling. Useful pruning removes the second
branch's dispatches. On QUBODrivers 0.6.5 the solved branch has public
`LOCALLY_SOLVED`, so the invocation has no global certificate. With the corrected
0.6.6 contract, once that version is available, complete certified coverage
returns `OPTIMAL`. The historical paired measurements below remain tied to
their producing revision and dependency versions.

The paired comparison is deliberately small: three fixed three-variable binary
fixtures (useful pruning, a weak bound, ties), separator `[1]`, one warmup pair
and two measured pairs each, 18 top-level solves including warmups, no retries.
No worker processes, annealers, native services or hardware are used. The runner
writes its fixtures, settings and executable source hashes before the first
solve and retains each attempt in its own TOML file, including started/failed
attempts. Parent construction, model loading and bound preparation are inside
complete wall time; imports/JIT compilation before entry are outside it.
Each parent has a 10-second deadline, at most 64 child calls and 2000 full parent
candidate evaluations. Guarding each exhaustive child at eight variables bounds
its total internal evaluations by 16384, so combined work is below 20000.

Run only with a fresh allowance and new output directory, under a 600-second OS
timeout and an OS memory cap, one Julia thread and one BLAS thread:

```sh
OPENBLAS_NUM_THREADS=1 JULIA_NUM_THREADS=1 timeout 600 julia --project=. examples/pruning/compare.jl NEW_OUTPUT_DIRECTORY
```

Use paired differences before aggregating measured repetitions. This tiny ordered
sample measures JIT/GC and host noise as well as useful work; fewer child calls
alone do not establish a speedup. See the retained evidence and measured results
in this directory for the authorized run.

The authorized run retained all 18 successful attempts in `evidence/`. Numerical
source and runner hashes bind the measured implementation at
`314feb10c77f6299eea657026c5a43b05aa55e14` (the base SHA in the plan predates its
uncommitted implementation). The subsequent review fix gates an original-objective
consistency check on faithful coefficient transfer; it has not been remeasured.
All comparison fixtures preserve their coefficients, but these timings describe
the measured revision, not a new-head performance result. Julia 1.10.11, QUBOTools 0.16.2 and
QUBODrivers 0.6.5 were resolved; the exact environment is retained. Recompute the
table with `python3 examples/pruning/summarize.py` from the repository root.

| Fixture | Calls off/on | Median complete wall off/on (ms) | Median paired on−off (ms) | Median bound work on (ms) |
|---|---:|---:|---:|---:|
| useful | 3/2 | 1.006/0.778 | -0.229 | 0.202 |
| weak | 2/2 | 0.768/1.122 | +0.353 | 0.288 |
| ties | 0/0 | 0.281/0.247 | -0.033 | 0.026 |

These are two measured pairs per fixture after one symmetric warmup pair. Each
wall sample covers construction, loading and the complete optimize call; bound
work includes preparation, original-incumbent comparisons and transfer checks.
The first warmups include substantial JIT cost and are retained, excluded from
the table. Measurement order is always off then on. Other bounded validation
processes shared the host, and these sub-millisecond samples have GC and timing
noise. The weak fixture costs more with pruning. This is bounded correctness and
dispatch evidence, not a general speedup claim or a benchmark campaign.

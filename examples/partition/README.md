# Bounded graph-partition comparison

Use Julia 1.10, one Julia/BLAS thread, QUBODrivers 0.6.5 and QUBOTools 0.16.2.
Develop this checkout in an isolated environment with MathOptInterface. Commit
the candidate first, then run from the package root:

```sh
julia --startup-file=no --threads=1 --project=/path/to/environment examples/partition/compare.jl /tmp/partition-comparison-new
```

The output path must be new. The script verifies the imported source and clean
candidate revision, retains raw outcomes in `evidence.toml`, and snapshots the
Project/Manifest. Use an OS memory cap and a 180-second process timeout; the
in-script comparison has a 120-second campaign cap. Installation/import/JIT before
the comparison and independent global-oracle audit are excluded from solve time.

Declared finite limits: three fixtures (two dense clusters with a bridge and
isolate, a coupled six-bit trap, and a path), two methods, one warmup per
fixture/method, two paired measured repetitions with alternating method order,
and two refusal probes: **20 attempts total**, failures included. Child dimension
is checked against three before exponentiation/enumeration. Each regular attempt
shares 128 exhaustive assignments across all children, at most 16 calls, 129
parent candidate evaluations, three sweeps, one stagnant sweep and five parent
seconds. The campaign reserves at most 2560 child assignments; the independent
oracle separately enumerates at most 256 assignments over dimensions at most
seven. Refusal probes give each method four assignments. No timing threshold
enters CI, and this is not a broader optimization or policy/seed campaign.

The unchanged strongest-edge control and graph-region-growing partitions use the
same exact public-MOI child, zero starts, seed 41, child capacity (three except
two for the trap) and total allowances. Assignment work is reserved before each
child enumeration, including attempts that could subsequently fail. Raw records
retain actual assignments, child term-evaluation work, parent evaluations, seeds,
statuses, boundaries, mappings, cut statistics and phase durations. Complete
timing starts before optimizer construction/loading and includes partitioning,
conditioning, child copying/solving, validation, reconstruction, original-energy
evaluation and result attachment. These costs are reported separately from
quality: equal allowances do not imply equal consumed work or optimality.

The callback in [region_growing.jl](region_growing.jl) is flat and deterministic,
with no recursion, mandatory partitioner or upstream code adaptation. Run
[sweeps.jl](sweeps.jl) for a small public ExactSampler example. Design and
guarantee details are in [strategies](../../docs/src/strategies.md#graph-partition-sweeps).

Recorded results and an adopt/revise/defer decision follow after the bounded run.

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
fixture/method, one paired measured repetition (control first),
and two refusal probes: **20-attempt ceiling**, failures included. Three pre-child harness failures were
charged to that ceiling; six warmups, six measured runs and two refusal probes
use 14 further attempts (17 total). The originally planned second repetition
was removed to stay within the original budget; the comparison was not expanded. Child dimension
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

## Recorded result and decision

The retained [raw evidence](evidence/20261010/evidence.toml) was produced by clean
candidate `2cfd8bcf7a57bf4f3ebd1e3f26a4e9a4de1b6d3d`, tree
`62e5273637d7e338418fa1d8691f8f01abd2402f`, Julia 1.10.11, one Julia/BLAS
thread, MOI 1.54.0, QUBODrivers 0.6.5 and QUBOTools 0.16.2.
Project/Manifest retain dependency versions/trees; the fixture-script SHA256,
source identity, exact limits and every warmup/measured/refusal record are in the
raw data. The three pre-child harness failures are also retained beside it;
they consumed no assignments and are charged in `charged_attempts=17`.
Their wall durations were not measured and are not included in `campaign_sec`.
The final evidence commit changes only documentation and data.

Cells show **energy / child assignments / full execution ms** from the single
measured repetition, with independent reference energies in the last column.

| Fixture | Strongest edge | Partition | Global reference |
| --- | --- | --- | --- |
| Dense clusters + bridge + isolate | 3.75 / 98 / 0.867 | 3.75 / 38 / 0.500 | 3.75 |
| Coupled six-bit trap | 0 / 24 / 0.398 | 0 / 12 / 0.239 | -24 |
| Path | -4 / 80 / 0.644 | -4 / 32 / 0.395 | -4 |

All regular attempts returned valid incumbents with `LOCALLY_SOLVED`. Both
four-assignment probes completed one child, refused the next dispatch before
exceeding their shared assignment allowance, returned `OTHER_ERROR`, and retained
the valid all-zero incumbent at energy 0. Failures are recorded even when a valid
incumbent survives. Total reserved/completed child work was 576 assignments over
14 actual runs, within the 2560-assignment campaign cap. The independent oracle
used exactly 256 separately bounded assignments.

The measured partition planning costs were 17.242, 18.690 and 12.432 microseconds
for clusters, trap and path. Conditioning costs (control / partition) were
39.144 / 22.050, 19.790 / 10.576 and 31.068 / 13.684 microseconds.
Raw phase records retain copying, execution, validation/reconstruction and full
energy costs. Planning is included in preparation; these phase figures do not
include constructor/attachment overhead already included in full execution.

Conclusion: **adopt as opt-in**, keeping strongest-edge as the default. On these
three fixtures the partition used fewer assignments for the same observed
quality, including the same failure to escape the exact-child trap. The
single measured pair per fixture, one seed, tiny finite fixtures, symmetric
warmups and control-first order cannot establish timing uncertainty, success
probability or a general speedup. No broad benchmark or production optimization
campaign was run, and no CI timing threshold is introduced.

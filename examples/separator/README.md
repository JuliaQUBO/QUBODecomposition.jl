# Bounded separator comparison

Use the same clean pinned QUBOBenchmarks pilot checkout as the
[selector comparison](../selection/README.md), revision
`7dbe623c30fb674cef5ede6bdc46b7b99e07736b`. From a clean committed candidate:

```sh
julia --startup-file=no --threads=1 examples/separator/run.jl /path/to/QUBOBenchmarks.jl /tmp/separator-comparison-new
```

The runner creates an isolated project and pins released QUBOTools 0.16.2,
QUBODrivers 0.6.5 and ToQUBO 0.7.1. The pilot supplies unchanged exhaustive
size/work guards and the `GuardedExact` adapter. That adapter exposes its validated
enumeration through public `OPTIMAL`; this is a different certificate source from
the released ExactSampler, whose public `LOCALLY_SOLVED` remains uncertified.
All six methods use the same adapter. Direct solving has the full problem's
capacity; composite methods share the fixture's smaller capacity and configuration.

The fixtures are a five-vertex path, a star where changing the center initially
worsens the zero incumbent, and two dense clusters joined through an articulation
vertex plus an isolate. Starts are all zero, composite seed 41, offset 3. The deterministic pilot
adapter does not support a child seed; its recorded forwarded seed is `nothing`. Composite capacity
is respectively 2, 1 and 3. One shared allowance permits 512 exhaustive assignments,
with hard caps of eight variables/256 assignments per child before dispatch;
parent caps are 64 calls, 1025 evaluations, three sweeps and one stagnant sweep.
No wall deadline is set. An independent scalar exhaustive oracle has the same
hard size guard. A refusal probe verifies no oversized work was dispatched.

After one symmetric warmup, three repetitions alternate method order. Timings
cover fresh construction/loading through result attachment, including planning,
public conditioning, conversion, child execution, reconstruction and parent
objective evaluation. Independent scalar audits are timed separately. The direct
baseline uses the child without the composite wrapper. Raw runs retain source
SHA/tree, dependencies, all phase/work counters, starts, seeds, limits and status.
There are no timing acceptance thresholds or claims about general speedup.

Enumeration costs `2^length(separator)` branches. Tiny favorable separators do
not imply favorable total runtime: the current public conditioner copies/scans
forms and the composite makes multiple child transactions and full evaluations.
These fixtures establish bounded behavior and observed quality, not statistical
performance. See the [runnable released-child example](../separator_conditioning.jl)
and the [guarantee argument](../../docs/src/guarantees.md).

## Recorded result

The [raw evidence](evidence.json) was generated from clean candidate
`b8bf8adb26b0b2a83b6a9037e65a7070eb837e6b` (tree
`725b88e14832ef71d51f4d20f9571dee26f07965`) on Julia 1.10.11,
with one Julia and BLAS thread. The subsequent evidence commit changes data and
documentation only. The isolated resolved Project/Manifest accompany the local
run artifact; dependency versions and trees are embedded in the JSON.

Each row selects the repetition with median complete execution time; its work and
status come from that same repetition. All energies and work counts were identical
across the three repetitions. Times are milliseconds, not child-only timings.

| Fixture | Method | Energy | Child assignments | Parent evaluations | Complete ms | Public status |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| path | direct | 0 | 32 | — | 0.078 | OPTIMAL |
| path | strongest_edge | 3 | 20 | 21 | 0.675 | LOCALLY_SOLVED |
| path | single_flip_gain | 3 | 10 | 11 | 0.477 | LOCALLY_SOLVED |
| path | bfs | 3 | 20 | 21 | 0.702 | LOCALLY_SOLVED |
| path | random_blocks | 3 | 10 | 11 | 0.501 | LOCALLY_SOLVED |
| path | separator | 0 | 16 | 21 | 0.550 | OPTIMAL |
| star_trap | direct | 1 | 32 | — | 0.079 | OPTIMAL |
| star_trap | strongest_edge | 3 | 10 | 11 | 0.665 | LOCALLY_SOLVED |
| star_trap | single_flip_gain | 3 | 10 | 11 | 0.571 | LOCALLY_SOLVED |
| star_trap | bfs | 3 | 10 | 11 | 0.621 | LOCALLY_SOLVED |
| star_trap | random_blocks | 3 | 10 | 11 | 0.606 | LOCALLY_SOLVED |
| star_trap | separator | 1 | 16 | 21 | 0.998 | OPTIMAL |
| clusters | direct | -6 | 128 | — | 0.147 | OPTIMAL |
| clusters | strongest_edge | -6 | 90 | 91 | 1.863 | LOCALLY_SOLVED |
| clusters | single_flip_gain | -6 | 34 | 35 | 0.854 | LOCALLY_SOLVED |
| clusters | bfs | -6 | 98 | 99 | 1.849 | LOCALLY_SOLVED |
| clusters | random_blocks | -6 | 50 | 51 | 1.186 | ITERATION_LIMIT |
| clusters | separator | -6 | 28 | 33 | 0.983 | OPTIMAL |

Separator conditioning reaches all three independent optima and transfers the
pilot adapter's public certificates. All sweep policies miss the path/star
optimum at the matched small capacity; they reach the cluster optimum without
a global certificate. Random blocks reaches its three-sweep cap on clusters.

**Unfavorable runtime result:** direct exhaustive solving is faster on every tiny
fixture, even though separator solving reserves fewer child assignments. Separator
execution is about 7.1×, 12.6× and 6.7× the direct median respectively. On the star,
separator is also slower than every sweep policy. Its median conditioning phases
are 0.013, 0.024 and 0.023 ms respectively; the raw records additionally separate
copying, child execution, validation/reconstruction and full-energy costs. These
measurements do not justify a custom conditioner or a general speedup claim.

Recommendation: **adopt as opt-in** for capacity-limited models with a small known
separator and a need for complete, certified outer search. Do not promote it as a
speed optimization. Separator size remains exponential; larger benchmarks and
statistical performance belong in the separate QUBOBenchmarks campaign. Group this
compatible feature into a later 0.1.x release after human review, keeping the pending
0.1.0 registration and the earlier selector release grouping independent.

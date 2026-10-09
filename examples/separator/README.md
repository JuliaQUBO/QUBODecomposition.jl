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
vertex plus an isolate. Starts are all zero, seed 41, offset 3. Composite capacity
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

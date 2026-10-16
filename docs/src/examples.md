# Executable examples

The code below is read from the repository scripts during the build, so there is
one executable source for each example. All children are public ExactSampler
instances and need no credentials. After dependency setup the scripts work offline.
The [ExactSampler version contract](results.md#ExactSampler-version-contract)
distinguishes the 0.6.5 public-status defect from corrected 0.6.6 completion.
Heuristic neighborhood solves do not certify
a coupled global optimum, even when a fixture reaches its known optimum.

For standalone ToQUBO setup and execution, see the
[example environment instructions](https://github.com/JuliaQUBO/QUBODecomposition.jl/blob/main/examples/toqubo/README.md).
The docs environment can also run all five scripts directly.

## Fitting whole model

```@eval
import Markdown
import QUBODecomposition
Markdown.parse("```julia\n" * read(joinpath(dirname(pathof(QUBODecomposition)), "..", "examples/whole_model.jl"), String) * "\n```")
```

```@example whole
import QUBODecomposition # hide
include(joinpath(dirname(pathof(QUBODecomposition)), "..", "examples/whole_model.jl")) # hide
(; objective=MOI.get(optimizer, MOI.ObjectiveValue()), status=MOI.get(optimizer, MOI.TerminationStatus()))
```

## Larger than child capacity

```@eval
import Markdown
import QUBODecomposition
Markdown.parse("```julia\n" * read(joinpath(dirname(pathof(QUBODecomposition)), "..", "examples/serial_sweeps.jl"), String) * "\n```")
```

```@example serial
import QUBODecomposition # hide
include(joinpath(dirname(pathof(QUBODecomposition)), "..", "examples/serial_sweeps.jl")) # hide
(; full_state, energy, status=MOI.get(optimizer, MOI.TerminationStatus()))
```

## ToQUBO refinement

The weak penalty gives decoded source objective **11**, compiled objective **10.9**
and `INFEASIBLE_POINT`. Refinement checks actual source residuals and reaches source
objective **8** for this fixture. Budget two uses sweeps; budget eight fits all three bits.

```@eval
import Markdown
import QUBODecomposition
Markdown.parse("```julia\n" * read(joinpath(dirname(pathof(QUBODecomposition)), "..", "examples/toqubo/refinement.jl"), String) * "\n```")
```

```@example refinement
import QUBODecomposition # hide
include(joinpath(dirname(pathof(QUBODecomposition)), "..", "examples/toqubo/refinement.jl")) # hide
small = RefinementExample.run(; budget=2)
fitting = RefinementExample.run(; budget=8)
@assert small.source_feasible && fitting.source_feasible
@assert small.source_objective == fitting.source_objective == 8
(; small, fitting)
```

## Caller-owned deadline

The outer loop charges compilation, copying, execution and source checks against
one absolute allowance. Cancellation remains cooperative for opaque children.

```@eval
import Markdown
import QUBODecomposition
Markdown.parse("```julia\n" * read(joinpath(dirname(pathof(QUBODecomposition)), "..", "examples/toqubo/deadline.jl"), String) * "\n```")
```

```@example deadline
import QUBODecomposition # hide
include(joinpath(dirname(pathof(QUBODecomposition)), "..", "examples/toqubo/deadline.jl")) # hide
result = DeadlineExample.run()
@assert result.reason == :feasible
@assert last(result.history).source_value == 8
(; reason=result.reason, final=last(result.history))
```


## Separator conditioning

With QUBODrivers 0.6.5, this example reaches its call cap after complete
uncertified work and reports `ITERATION_LIMIT`. With the corrected 0.6.6 public
certificate, the last call completes proof and returns `OPTIMAL` even at the exact
allowance. Both paths retain the optimum found; an incomplete scan cannot certify it.

```@eval
import Markdown
import QUBODecomposition
Markdown.parse("```julia\n" * read(joinpath(dirname(pathof(QUBODecomposition)), "..", "examples/separator_conditioning.jl"), String) * "\n```")
```

```@example separator
import QUBODecomposition # hide
include(joinpath(dirname(pathof(QUBODecomposition)), "..", "examples/separator_conditioning.jl")) # hide
result = SeparatorExample.compare()
(; result.automatic.state, result.automatic.energy, result.automatic.status,
   separator=result.automatic.proof["indices"], result.discovery_sec)
```

Automatic and supplied selection use the identical selected separator, child,
start and budgets. Discovery timing is a subset of preparation. A cycle refuses
automatic selection even though a supplied separator is supported:

```@example separator
SeparatorExample.refusal()
```

The [bounded comparison](https://github.com/JuliaQUBO/QUBODecomposition.jl/blob/main/examples/separator/README.md)
compares direct enumeration, all existing sweep selectors and automatic/supplied separator branches
using the same guarded child and independent scalar oracles.


## Graph-partition regions

```@eval
import Markdown
import QUBODecomposition
Markdown.parse("```julia\n" * read(joinpath(dirname(pathof(QUBODecomposition)), "..", "examples/partition/sweeps.jl"), String) * "\n```")
```

```@example partition
import QUBODecomposition # hide
include(joinpath(dirname(pathof(QUBODecomposition)), "..", "examples/partition/sweeps.jl")) # hide
(; full_state, energy, partition, status=MOI.get(optimizer, MOI.TerminationStatus()))
```

## Certified separator pruning

The [offline pruning example](https://github.com/JuliaQUBO/QUBODecomposition.jl/blob/main/examples/separator_pruning.jl)
uses `separator_pruning=true`, saves child dispatches, and keeps truthful public
child statuses. The [paired comparison](https://github.com/JuliaQUBO/QUBODecomposition.jl/blob/main/examples/pruning/README.md)
records complete wall time and bound preparation as well as dispatch counts.

```@example pruning
using QUBODecomposition # hide
include(joinpath(dirname(pathof(QUBODecomposition)), "..", "examples/separator_pruning.jl")) # hide
result = SeparatorPruningExample.run()
(calls=result.data["attempted_calls"],
 pruned=result.data["separator"]["certified_pruned_branches"],
 proof_complete=result.data["separator"]["proof_complete"])
```

The [consensus example](https://github.com/JuliaQUBO/QUBODecomposition.jl/blob/main/examples/consensus/offline.jl)
uses bounded exact children and exposes a persistent duality gap; see the
[consensus contract](consensus.md).


The [coarse offline example](https://github.com/JuliaQUBO/QUBODecomposition.jl/blob/main/examples/coarse/offline.jl)
coordinates two whole-group flips using two macrovariables for four originals.
The [coarse manual](coarse.md) records its conservative heuristic guarantee.

```@example coarse
import QUBODecomposition # hide
include(joinpath(dirname(pathof(QUBODecomposition)), "..", "examples/coarse/offline.jl")) # hide
(; state=x, energy=QUBOTools.value(optimizer,1), status=MOI.get(optimizer,MOI.TerminationStatus()))
```

## Sample-guided fixing with a biased pool

```@eval
import Markdown
import QUBODecomposition
Markdown.parse("```julia\n" * read(joinpath(dirname(pathof(QUBODecomposition)), "..", "examples/sample_fixing/offline.jl"), String) * "\n```")
```

```@example sample_fixing
import QUBODecomposition # hide
include(joinpath(dirname(pathof(QUBODecomposition)), "..", "examples/sample_fixing/offline.jl")) # hide
(; incumbent=x, status=MOI.get(optimizer,MOI.TerminationStatus()))
```

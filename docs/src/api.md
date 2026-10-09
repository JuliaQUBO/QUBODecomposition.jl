# Public API

```@docs
QUBODecomposition.Optimizer
```

## Released interface entry points

The composite implements the released interfaces below. Configuration and detailed
semantics have one authoritative source in this manual.

| Interface | Use | Contract |
| --- | --- | --- |
| `MOI.RawOptimizerAttribute(name)` | Read/set constructor options by their string names | [Configuration](configuration.md) |
| `MOI.copy_to`, `MOI.optimize!`, `MOI.empty!` | Copy a model, solve, clear it | [Results](results.md) |
| `MOI.TerminationStatus`, `MOI.PrimalStatus`, `MOI.ResultCount` | Read truthful completion and result availability | [Results](results.md) |
| `MOI.ObjectiveValue`, `MOI.VariablePrimal` | Read original compiled energy and copied-model primals | [Results](results.md) |
| `MOI.TimeLimitSec`, `MOI.SolveTimeSec` | Set invocation allowance; read effective elapsed time | [Budgets](budgets.md) |
| `QUBODrivers.set_model!`, `QUBOTools.backend`, `QUBOTools.state`, `QUBOTools.solution` | Direct labeled QUBOTools model/results | [Configuration](configuration.md) |
| `QUBODrivers.RandomSeed`, `FinalNumberOfReads`, `PostSampleCallback`, `PostSampleTransform` | Released sampler attributes (last three qualified by `QUBODrivers`) | [Results](results.md), [reads/seeds](budgets.md) |
| `QUBOTools.metadata(QUBOTools.solution(opt))` | Read `decomposition` schema version 1 and framework metadata | [Budgets](budgets.md) |

`ModelStorage` and internal clocks/checkpoints are implementation details.
The runtime exposes no additional global-optimality certificate for coupled sweeps.

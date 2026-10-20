# QUBODecomposition.jl

A local QUBO/Ising composite optimizer using released QUBODrivers and MathOptInterface
interfaces. The default `:components_then_sweeps` strategy dispatches fitting models
whole, solves fitting independent components, and uses conditioned sweeps for
oversized components. Exact neighborhoods do not prove a coupled global optimum.

[Installation and quick start](start.md) covers registered and development
installation and a runnable example. Runtime minimums remain Julia 1.10, QUBOTools 0.16.2,
QUBODrivers 0.6.5 and MathOptInterface 1.0.0. ToQUBO integration requires 0.7.1 on the 0.7 patch line.
Certified root preprocessing uses the registered QUBOPreprocessing 0.1.0 dependency
and stays off by default; the [root preprocessing guide](preprocessing.md) explains
when and how to enable it. This development integration is not in released
QUBODecomposition 0.1.4.

## Choose a workflow

- [Optimizer construction and configuration](configuration.md)
- [Design decision: global guarantees](guarantees.md)
- [Whole-model, components and conditioned sweeps](strategies.md)
- [Certified root preprocessing](preprocessing.md) (default off)
- [Experimental Lagrangian consensus](consensus.md) (0.1.3 or later)
- [Block-orientation coarse proposals](coarse.md) (0.1.4 or later)
- [Sample-guided variable fixing](sample_fixing.md) (0.1.4 or later)
- [Results, statuses and source feasibility](results.md)
- [Budgets, timing, seeds and reads](budgets.md)
- [Direct JuMP and ToQUBO composition](integration.md)
- [Executable examples](examples.md) and [public API](api.md)

Source: [JuliaQUBO/QUBODecomposition.jl](https://github.com/JuliaQUBO/QUBODecomposition.jl).

The QUBODrivers floor stays 0.6.5. See the [ExactSampler version contract](results.md#ExactSampler-version-contract) for the corrected 0.6.6 public certificate and unchanged heuristic/limit rules.

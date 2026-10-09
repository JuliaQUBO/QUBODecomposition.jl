# QUBODecomposition.jl

A local QUBO/Ising composite optimizer using released QUBODrivers and MathOptInterface
interfaces. The default `:components_then_sweeps` strategy dispatches fitting models
whole, solves fitting independent components, and uses conditioned sweeps for
oversized components. Exact neighborhoods do not prove a coupled global optimum.

A Project version alone does not establish registry availability. A versioned manual
is published only after the real General release and tag are verified.
[Installation and quick start](start.md) separates development installation from
post-publication registry commands, using released upstream dependencies. Runtime minimums remain Julia 1.10, QUBOTools 0.16.2, QUBODrivers 0.6.5
and MathOptInterface 1.0.0. ToQUBO integration requires 0.7.1 on the 0.7 patch line.

## Choose a workflow

- [Optimizer construction and configuration](configuration.md)
- [Whole-model, components and conditioned sweeps](strategies.md)
- [Results, statuses and source feasibility](results.md)
- [Budgets, timing, seeds and reads](budgets.md)
- [Direct JuMP and ToQUBO composition](integration.md)
- [Executable examples](examples.md) and [public API](api.md)
- [Acceptance coverage and pending release/adoption](acceptance.md)
- [Documentation publication and ecosystem handoff](deployment.md)

Repository and maintenance authority: [JuliaQUBO/QUBODecomposition.jl](https://github.com/JuliaQUBO/QUBODecomposition.jl),
[@bernalde](https://github.com/bernalde). Package documentation/publication belongs to
[#3](https://github.com/JuliaQUBO/QUBODecomposition.jl/issues/3); the MVP tracker is
[#1](https://github.com/JuliaQUBO/QUBODecomposition.jl/issues/1).

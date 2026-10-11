# QUBODecomposition.jl

[![CI](https://github.com/JuliaQUBO/QUBODecomposition.jl/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/JuliaQUBO/QUBODecomposition.jl/actions/workflows/ci.yml)
[![Documentation](https://github.com/JuliaQUBO/QUBODecomposition.jl/actions/workflows/documentation.yml/badge.svg?branch=main)](https://github.com/JuliaQUBO/QUBODecomposition.jl/actions/workflows/documentation.yml)
[![Manual](https://img.shields.io/badge/docs-dev-blue.svg)](https://juliaqubo.github.io/QUBODecomposition.jl/dev/)
[![Coverage](https://codecov.io/gh/JuliaQUBO/QUBODecomposition.jl/graph/badge.svg)](https://app.codecov.io/gh/JuliaQUBO/QUBODecomposition.jl)

A local QUBO/Ising composite optimizer using public QUBODrivers and MathOptInterface interfaces.
Fitting models use one whole-model child call. Larger models solve independent connected components
and use bounded conditioned neighborhood sweeps for oversized components. The default strategy is
`:components_then_sweeps`; `:components` rejects oversized components before dispatch.
Opt into bounded exact conditioning with `strategy=:separator, separator=[...]`
when removing a small supplied separator leaves capacity-fitting components.
Use `separator=:articulation` to discover a deterministic supported single-vertex
plan, or an empty separator when all components already fit.
Empty/constant objectives are solved locally. Coupled sweeps report heuristic completion.

The [global-guarantee design decision](docs/src/guarantees.md) distinguishes methods
that recover a global optimum with exact subproblem solves from heuristics that
do not. Whole-model and independent-component solves can transfer valid global
certificates; strongest-edge, single-flip-gain, BFS, random-block and graph-partition sweeps, and frozen-batch voting/repair on coupled components cannot.
Separator enumeration can certify complete runs with certified residual solves.
The decision also classifies implemented graph-partition and voting/repair strategies and planned preprocessing methods.

```julia
using QUBODecomposition, QUBODrivers
optimizer = QUBODecomposition.Optimizer(
    child_optimizer = () -> QUBODrivers.ExactSampler.Optimizer(),
    max_variables = 8,
    seed = 123,
)
```

Candidate caps apply to the whole invocation: an ExactSampler call on eight variables uses
256 candidate evaluations. Size the cap for all planned component/neighborhood calls.

Read the [hosted development manual](https://juliaqubo.github.io/QUBODecomposition.jl/dev/)
for [configuration](https://juliaqubo.github.io/QUBODecomposition.jl/dev/configuration/),
[executable examples](https://juliaqubo.github.io/QUBODecomposition.jl/dev/examples/) and
the [public API](https://juliaqubo.github.io/QUBODecomposition.jl/dev/api/).

Install development source into another project with Julia 1.10 or later:

```julia
using Pkg
Pkg.add(url="https://github.com/JuliaQUBO/QUBODecomposition.jl.git", rev="main")
Pkg.add("QUBODrivers")
```

For reproducible installations, use a full commit SHA instead of `main`.
See [installation and quick start](https://juliaqubo.github.io/QUBODecomposition.jl/dev/start/).

Development uses AI assistance. [@bernalde](https://github.com/bernalde) reviews
and certifies the work and takes responsibility for what is published.

See [CONTRIBUTING.md](CONTRIBUTING.md). Licensed under [MPL-2.0](LICENSE).

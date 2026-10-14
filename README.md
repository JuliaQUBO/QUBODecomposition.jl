# QUBODecomposition.jl

[![CI](https://github.com/JuliaQUBO/QUBODecomposition.jl/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/JuliaQUBO/QUBODecomposition.jl/actions/workflows/ci.yml)
[![Documentation](https://github.com/JuliaQUBO/QUBODecomposition.jl/actions/workflows/documentation.yml/badge.svg?branch=main)](https://github.com/JuliaQUBO/QUBODecomposition.jl/actions/workflows/documentation.yml)
[![Manual](https://img.shields.io/badge/docs-dev-blue.svg)](https://juliaqubo.github.io/QUBODecomposition.jl/dev/)
[![Coverage](https://codecov.io/gh/JuliaQUBO/QUBODecomposition.jl/graph/badge.svg)](https://app.codecov.io/gh/JuliaQUBO/QUBODecomposition.jl)

QUBODecomposition.jl splits QUBO and Ising models into smaller problems and solves
them with a solver you choose. You set how many variables that solver can handle
at once. Models that fit go directly to the solver; larger models use independent
components and local sweeps.

Requires Julia 1.10 or later. Install the registered release with:

```julia
using Pkg
Pkg.add("QUBODecomposition")
Pkg.add("QUBODrivers")
```

For development or a release candidate, use
`Pkg.add(url="https://github.com/JuliaQUBO/QUBODecomposition.jl.git", rev="FULL_COMMIT_SHA")`
with the exact full commit SHA. A candidate installation can contain fixes that
are not yet available in General. The linked development manual tracks `main`;
registered releases can lag it. See [CHANGELOG.md](CHANGELOG.md) for each version's
changes.

For example, this creates an optimizer using ExactSampler, with up to eight
variables per subproblem:

```julia
using QUBODecomposition, QUBODrivers
optimizer = QUBODecomposition.Optimizer(
    child_optimizer = () -> QUBODrivers.ExactSampler.Optimizer(),
    max_variables = 8,
    seed = 123,
)
```

An exact solver can establish a global optimum when it solves the whole model or
every independent component. Local sweeps are heuristic: solving each small
problem exactly does not prove that the full model is optimal.

The [manual](https://juliaqubo.github.io/QUBODecomposition.jl/dev/) has complete
[solve examples](https://juliaqubo.github.io/QUBODecomposition.jl/dev/examples/),
[configuration options](https://juliaqubo.github.io/QUBODecomposition.jl/dev/configuration/)
and the [guarantees and limitations](https://juliaqubo.github.io/QUBODecomposition.jl/dev/guarantees/)
of each strategy.

Maintained by [@bernalde](https://github.com/bernalde). I use AI to help with
development, but I review and certify the work myself and take responsibility
for what I publish.

See [CONTRIBUTING.md](CONTRIBUTING.md). Licensed under [MPL-2.0](LICENSE).

Opt into bounded independent-component execution with a caller-owned local
worker pool; see [component jobs, factories and lifecycle](docs/src/components.md)
and the [tiny offline process example](examples/process_components.jl). Serial
execution remains the default. This API requires the new reviewed revision and
is absent from registered 0.1.1.

# QUBODecomposition.jl

[![CI](https://github.com/JuliaQUBO/QUBODecomposition.jl/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/JuliaQUBO/QUBODecomposition.jl/actions/workflows/ci.yml)
[![Documentation](https://github.com/JuliaQUBO/QUBODecomposition.jl/actions/workflows/documentation.yml/badge.svg?branch=main)](https://github.com/JuliaQUBO/QUBODecomposition.jl/actions/workflows/documentation.yml)
[![Manual](https://img.shields.io/badge/docs-stable-blue.svg)](https://juliaqubo.github.io/QUBODecomposition.jl/stable/)
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

The [manual](https://juliaqubo.github.io/QUBODecomposition.jl/stable/) has complete
[solve examples](https://juliaqubo.github.io/QUBODecomposition.jl/stable/examples/),
[configuration options](https://juliaqubo.github.io/QUBODecomposition.jl/stable/configuration/)
and the [guarantees and limitations](https://juliaqubo.github.io/QUBODecomposition.jl/stable/guarantees/)
of each strategy.

See [CONTRIBUTING.md](CONTRIBUTING.md). Licensed under [MPL-2.0](LICENSE).

Opt into bounded independent-component execution with a caller-owned local
worker pool; see [component jobs, factories and lifecycle](docs/src/components.md)
and the [tiny offline process example](examples/process_components.jl). Serial
execution remains the default. The explicit component executors and
`absolute_deadline_sec` require QUBODecomposition **0.1.2 or later**. Deadlines are
cooperative; opaque children and draining can overrun, with no hard cancellation.

Certified `separator_pruning=true` and experimental `strategy=:consensus` require
QUBODecomposition **0.1.3 or later**. Pruning requires complete certified coverage
for global `OPTIMAL`;
consensus remains heuristic even with exact children, agreement or zero gap.
See [pruning guarantees](docs/src/guarantees.md#certified-separator-exclusions) and
[consensus](docs/src/consensus.md) for arithmetic, status and bound conventions.

For a coordinated whole-group move, opt into `strategy=:coarse` with explicit
`coarse_groups`; see [coarse proposals](docs/src/coarse.md). It uses one
macrovariable per group and remains heuristic for nonconstant original models.

For a bounded caller-supplied pool of complete candidates, opt into
`strategy=:sample_fixing`; see [sample-guided fixing](docs/src/sample_fixing.md).
Its deterministic unary restrictions remain heuristic and preserve the best
full-space incumbent separately. Pool generation is explicit external work.
Both strategies require **0.1.4 or later**.

[Certified root preprocessing](docs/src/preprocessing.md) adds opt-in
`preprocessing=:dominance` for supported serial routes, with shared work
accounting, verified lifting and conservative status transfer. Its QUBOPreprocessing
dependency resolves normally through General. The default remains off; use the
measured operating envelope to decide whether its full cost helps your workload.
Root preprocessing requires **QUBODecomposition 0.1.5 or later**.

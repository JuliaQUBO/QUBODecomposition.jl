# QUBODecomposition.jl

A local QUBO/Ising composite optimizer using public QUBODrivers and MathOptInterface interfaces.
The first runtime slice handles empty/constant models and one-call whole-model solves that fit a logical-variable budget.
Nonconstant models exceeding that budget return `INVALID_OPTION` without a child call.
Connected components and conditioned sweeps are pending.

```julia
using QUBODecomposition, QUBODrivers
optimizer = QUBODecomposition.Optimizer(
    child_optimizer = () -> QUBODrivers.ExactSampler.Optimizer(),
    max_variables = 8,
    seed = 123,
)
```

See [usage and contracts](docs/usage.md), the [runnable public example](examples/whole_model.jl),
and [acceptance coverage and pending work](docs/acceptance.md).
The package is under development; this PR is not the complete serial-decomposition MVP.
No tag, release or General registration is available. For development, check out the feature branch and run:

```julia
using Pkg
Pkg.activate(".")
Pkg.instantiate()
Pkg.test()
```

The package follows the [accepted design](https://github.com/JuliaQUBO/QUBO.jl/blob/7c3391f9e4ccf369027da858866f6d4b74790313/docs/src/design.md).
The implementation tracker is [#1](https://github.com/JuliaQUBO/QUBODecomposition.jl/issues/1).
Accepting maintainer and release authority: [@bernalde](https://github.com/bernalde).
The eventual first release is 0.1.0 through General, after the full MVP matrix and release checks pass.
The Project version reserves that intended identity and does not indicate a published release.

See [CONTRIBUTING.md](CONTRIBUTING.md). Licensed under [MPL-2.0](LICENSE).

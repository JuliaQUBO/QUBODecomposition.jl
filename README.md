# QUBODecomposition.jl

A local QUBO/Ising composite optimizer using public QUBODrivers and MathOptInterface interfaces.
Fitting models use one whole-model child call. Larger models solve independent connected components
and use bounded conditioned neighborhood sweeps for oversized components. The default strategy is
`:components_then_sweeps`; `:components` rejects oversized components before dispatch.
Empty/constant objectives are solved locally. Coupled sweeps report heuristic completion.

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

See [usage and contracts](docs/usage.md), the [runnable public example](examples/whole_model.jl),
the [larger-than-budget sweep example](examples/serial_sweeps.jl),
and [acceptance coverage and pending work](docs/acceptance.md).
The current runtime is a partial slice; see the acceptance coverage above for remaining MVP work.
No tag, release or General registration is available. For development, clone this repository,
enter its directory and run:

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

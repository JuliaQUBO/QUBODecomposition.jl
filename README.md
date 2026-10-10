# QUBODecomposition.jl

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
certificates; strongest-edge, single-flip-gain, BFS and random-block sweeps on coupled components cannot.
Separator enumeration can certify complete runs with certified residual solves.
The decision also classifies planned preprocessing, partition and aggregation methods.

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

Source references: [documentation overview](docs/src/index.md), [configuration](docs/src/configuration.md), the [runnable public example](examples/whole_model.jl),
the [larger-than-budget sweep example](examples/serial_sweeps.jl),
the [offline ToQUBO integration examples](examples/toqubo/README.md),
and [acceptance coverage and pending work](docs/src/acceptance.md).
ToQUBO test/example integration requires released 0.7.1 on the 0.7 patch line;
ordinary repeated solves rebuild generated state without caller resets.
Acceptance rows 1–20 are delivered, and the development manual is published.
Row 21 requires verified publication and registry installation, followed by ecosystem adoption.
See the acceptance coverage above.
The first version prepared for General is 0.1.0. A Project version alone does not
establish publication; verify the General record and GitHub release before using
registry or tag instructions. To install development source
into another project, use `Pkg.add(url="https://github.com/JuliaQUBO/QUBODecomposition.jl.git", rev="main")`;
pin a full commit SHA for reproducibility and add `QUBODrivers` to use the optimizer
construction example above. For development, clone this repository,
enter its directory and run:

```julia
using Pkg
Pkg.activate(".")
Pkg.instantiate()
Pkg.test()
```

To build the manual, see [documentation setup](docs/src/start.md) and the
[publication and ecosystem handoff](docs/src/deployment.md). The hosted manual
is development documentation. The [QUBO aggregate](https://juliaqubo.github.io/QUBO.jl/QUBODecomposition.jl/dev/)
and [QUBODrivers catalog](https://juliaqubo.github.io/QUBODrivers.jl/dev/manual/3-samplers/#QUBODecomposition)
are published. Registration/release verification and registry canary adoption
follow the maintained release procedure.
See the maintained [release procedure](RELEASE.md) and [planned notes](CHANGELOG.md).

The package follows the [accepted design](https://github.com/JuliaQUBO/QUBO.jl/blob/7c3391f9e4ccf369027da858866f6d4b74790313/docs/src/design.md).
The implementation tracker is [#1](https://github.com/JuliaQUBO/QUBODecomposition.jl/issues/1).
Accepting maintainer and release authority: [@bernalde](https://github.com/bernalde).
The first version prepared for General is 0.1.0. Publication requires the full MVP
matrix and release checks; the Project version alone does not indicate a published release.

See [CONTRIBUTING.md](CONTRIBUTING.md). Licensed under [MPL-2.0](LICENSE).

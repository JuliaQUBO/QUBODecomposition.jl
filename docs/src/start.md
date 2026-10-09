# Installation and quick start

Use Julia 1.10 or later. For an ordinary development installation in your own project:

```julia
using Pkg
Pkg.add(url="https://github.com/JuliaQUBO/QUBODecomposition.jl.git", rev="main")
Pkg.add("QUBODrivers") # imported directly by the construction example
```

Pin a full commit SHA instead of `main` when recording reproducible evidence.
After the first General publication is verified, `Pkg.add("QUBODecomposition")`
will be the supported registry command. A `rev="v0.1.0"` URL install requires the
real future tag. Neither command establishes publication during preparation;
see the [release procedure](https://github.com/JuliaQUBO/QUBODecomposition.jl/blob/main/RELEASE.md).

Before registration, clone the development package; use a registry
`Pkg.add("QUBODecomposition")` installation only after publication is verified.
From a terminal:

```sh
git clone https://github.com/JuliaQUBO/QUBODecomposition.jl.git
cd QUBODecomposition.jl
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. examples/whole_model.jl
julia --project=. examples/serial_sweeps.jl
```

The first example fits three free variables into one public ExactSampler call and
asserts objective 2 and public `LOCALLY_SOLVED`. The second handles five free
variables with child capacity two and reconstructs a fixed sixth variable.
[Executable examples](examples.md) renders these authoritative scripts.

To use this checkout from another Julia project, develop its absolute path:

```julia
using Pkg
Pkg.activate("my-project"; shared=false)
Pkg.develop(path="/absolute/path/to/QUBODecomposition.jl")
```

Only this unregistered package uses a development path. Upstream QUBOTools,
QUBODrivers, JuMP and ToQUBO resolve as released packages.

## Build this manual

From the repository root, develop the local checkout into the separate docs environment:

```sh
julia --project=docs -e 'using Pkg; Pkg.develop(path=pwd()); Pkg.instantiate(); Pkg.status()'
julia --project=docs docs/make.jl --skip-deploy
julia --project=docs docs/check.jl
```

The build runs doctests and all four existing offline scripts, including both ToQUBO
refinement capacities. No deployment credentials are required. Open `docs/build/index.html`
through a local HTTP server to follow pretty URLs, for example:

```sh
python3 -m http.server 8000 --directory docs/build
```

Visit `http://localhost:8000/`. For package tests, use
`julia --project=. -e 'using Pkg; Pkg.test()'`.

## Construct a sampler

```jldoctest
julia> using QUBODecomposition, QUBODrivers

julia> opt = QUBODecomposition.Optimizer(
           child_optimizer=() -> QUBODrivers.ExactSampler.Optimizer(),
           max_variables=8, seed=123,
       );

julia> import MathOptInterface as MOI

julia> MOI.get(opt, MOI.RawOptimizerAttribute("strategy"))
:components_then_sweeps
```

Eight ExactSampler variables produce 256 candidates per complete child call.
Include the initial evaluation and every planned call in the parent candidate cap;
see [budgets](budgets.md).

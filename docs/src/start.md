# Installation and quick start

Use Julia 1.10 or later. The development source installation path is:

```julia
using Pkg
Pkg.add(url="https://github.com/JuliaQUBO/QUBODecomposition.jl.git", rev="main")
Pkg.add(["QUBODrivers", "MathOptInterface"]) # imported directly below
```

Pin a full commit SHA instead of `main` when recording reproducible evidence.
For a registered release, use `Pkg.add("QUBODecomposition")` after checking its
General record. The source installation above also works for development and
release candidates; [the release procedure](https://github.com/JuliaQUBO/QUBODecomposition.jl/blob/main/RELEASE.md)
records the publication and installed-source verification gates.

For a checkout that runs the repository examples:

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
Pkg.add(["QUBODrivers", "MathOptInterface"])
```

Only the package checkout in this development example uses a development path.
Upstream QUBOTools,
QUBODrivers, JuMP and ToQUBO resolve as released packages.

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

# Installation and quick start

Use Julia 1.10 or later. Install the registered release with:

```julia
using Pkg
Pkg.add("QUBODecomposition")
Pkg.add(["QUBODrivers", "MathOptInterface"]) # imported directly below
```

Use `pkgversion(QUBODecomposition)` to check your installed version. Component
executors and `absolute_deadline_sec` require **0.1.2 or later**; certified
separator pruning and experimental consensus require **0.1.3 or later**; coarse
proposals and sample-guided fixing require **0.1.4 or later**. Opt-in
[root preprocessing](preprocessing.md) requires **0.1.5 or later**.
The [guarantees](guarantees.md) explain which combinations can certify a global
optimum and which remain heuristic.

For a checkout that runs the repository examples:

```sh
git clone https://github.com/JuliaQUBO/QUBODecomposition.jl.git
cd QUBODecomposition.jl
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. examples/whole_model.jl
julia --project=. examples/serial_sweeps.jl
```

The first example fits three free variables into one public ExactSampler call and
asserts objective 2 and the [version-dependent public status](results.md#ExactSampler-version-contract). The second handles five free
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

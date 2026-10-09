# Construction and configuration

`QUBODecomposition.Optimizer` uses Float64 coefficients. Runtime dependencies are QUBOTools 0.16.2,
QUBODrivers 0.6.5 and MathOptInterface 1. Julia 1.10 is supported. JuMP and ToQUBO >=0.7.1 on the 0.7 compatibility line are test/example dependencies.
The exact resolved test versions are recorded in PR verification evidence and CI.
The MOI 1.0.0 floor lane runs the entire runtime suite and every driver conformance group.
JuMP 1 requires MOI >= 1.1.1, so its integration tests run through `Pkg.test()` in the other lanes.


`Optimizer()` is loadable without a child. Before solving, set `child_optimizer` and `max_variables`,
using constructor keywords or `MOI.RawOptimizerAttribute` with the same names.
The child factory must return a fresh empty `MOI.AbstractOptimizer` for every call, supporting the
original homogeneous binary/spin domain, objective sense and Float64 quadratic objective.
A factory may configure solver-specific attributes; the parent overrides only the per-call seed
and the minimum applicable time limit. It rejects reused live optimizer instances.

| Option | Default and validation |
| --- | --- |
| `child_optimizer` | `nothing`; required zero-argument factory before solving |
| `max_variables` | `nothing`; required positive Int-sized integer, excludes Bool, including for empty models |
| `strategy` | `:components_then_sweeps`; also `:components`, `:whole_model` and `:separator` |
| `separator` | `Int[]`; unique positive Int-sized free-variable indices, excludes Bool; checked against the current model in separator mode; setter/getter copy the vector |
| `max_separator_size` | 8; integer in 0:16, excludes Bool; separator length checked before any exponentiation or branch allocation |
| `selection` | `:strongest_edge`; also `:single_flip_gain`, `:bfs` and `:random_blocks`; applies only to oversized-component sweeps |
| `max_child_calls` | 1000; nonnegative Int-sized integer excluding Bool; across all component, neighborhood and separator calls |
| `max_candidate_evaluations` | 100000; nonnegative Int-sized integer excluding Bool; cumulative across initial evaluation, every row of every child call and separator direct evaluations |
| `max_sweeps` | 20; nonnegative Int-sized integer excluding Bool; whole-invocation sweep cap |
| `stagnation_sweeps` | 2; positive Int-sized integer excluding Bool; stop after this many complete sweeps without improvement |
| `child_time_limit_sec` | `nothing` or finite nonnegative seconds, excludes Bool |
| `seed` | `nothing` or integer in 0:2^31-2, excludes Bool |

Unknown options fail explicitly. The released driver's conformance contract also exercises the
legacy raw `fixed_variables` and `moi_variables` metadata slots; these are accepted as opaque
user data and never alter the actual MOI copying/reconstruction state. Invalid setters clear old results and throw. Missing configuration
returns `INVALID_OPTION` with no result. The required capacity counts every free logical variable,
including isolates. MOI-fixed variables are reduced by the public driver copy hook and reconstructed
through its public VariablePrimal interface. Arbitrary QUBOTools labels are preserved via
`QUBODrivers.set_model!` and `QUBOTools.backend`, `variable`, `index`, `state` and `solution`.
MOI variable queries apply to MOI-copied models; direct non-MOI labels use QUBOTools queries.

# ToQUBO source decoding and refinement

See the [offline public construction examples and environment](https://github.com/JuliaQUBO/QUBODecomposition.jl/blob/main/examples/toqubo/README.md).
ToQUBO compiles source constraints and encodings into the composite's unconstrained objective.
Every encoded, slack and quadratization bit counts toward child capacity. The composite's
FEASIBLE_POINT describes a complete compiled assignment. By default ToQUBO 0.7 checks decoded
source constraints and reports INFEASIBLE_POINT when those constraints fail. Its
PrimalFeasibilityCheck opt-out forwards compiled primal status without making the source feasible.
Use `ToQUBO.violations` to inspect residuals and `ToQUBO.source_objective_value` for the decoded
source objective. `MOI.ObjectiveValue` is the penalized compiled objective.

Automatic refinement recompiles after updating penalties. MaxPenaltyUpdates bounds additional
composite solves; feasibility, empty results or an updater without an applicable penalty can stop
it earlier. Each invocation receives fresh composite counters, seed sequence and time deadline.
The limit is not shared across the enclosing refinement process. The explicit deadline example
disables automatic updates, compiles and copies before dispatching with the remaining absolute
allowance, and deducts source checking before the next round. Cooperative checks cannot preempt an
opaque synchronous child. Composite effective time and ToQUBO CompilationTime are last-invocation
and last-compilation measurements, respectively, not cumulative enclosing times.

ToQUBO 0.7.1 is the fixed minimum for ordinary repeated compilation. Re-solving the
same source rebuilds generated encodings, slack, coefficients and result state without a
caller reset. Refined penalty attributes persist across ordinary solves. Explicit
`MOI.Utilities.reset_optimizer(model)` remains supported: the compiler retains its
settings on reset, but JuMP recopies cached source attributes on the next solve.
To carry the refined hint through that recopy, set it explicitly on the JuMP constraint.
JuMP can retain the original cached user hint (for example -0.1) while the live
compiler hint is -10 during ordinary reuse; inspect
`MOI.get(compiler, ToQUBO.Attributes.ConstraintEncodingPenaltyHint(), JuMP.index(c))`
for the current value. Set the desired hint explicitly when restarting from original
penalty inputs or reusing source constraint indices. Acceptance row 19 covers ordinary
reuse, fresh-compilation parity and explicit reset against released dependencies.

## Direct JuMP use

An unconstrained homogeneous binary quadratic objective can use the composite directly:

```@example direct_jump
using JuMP, QUBODecomposition, QUBODrivers
import MathOptInterface as MOI
model = Model(() -> QUBODecomposition.Optimizer(
    child_optimizer=() -> QUBODrivers.ExactSampler.Optimizer(),
    max_variables=2, seed=123,
))
@variable(model, x[1:2], Bin)
@objective(model, Min, 5 - 3*x[1] + 2*x[2] + 4*x[1]*x[2])
optimize!(model)
@assert objective_value(model) == 2
@assert value.(x) == [1, 0]
@assert termination_status(model) == MOI.LOCALLY_SOLVED
(; objective=objective_value(model), status=termination_status(model))
```

For general source constraints or encodings, place `ToQUBO.Optimizer` outside the
composite as in [the executable refinement example](examples.md#ToQUBO-refinement).
Compiled capacity counts all encoded, slack and quadratization bits.

# SPDX-License-Identifier: MPL-2.0
using QUBODecomposition, QUBODrivers, QUBOTools
import MathOptInterface as MOI

optimizer = QUBODecomposition.Optimizer(
    child_optimizer = () -> QUBODrivers.ExactSampler.Optimizer(),
    max_variables = 3,
    strategy = :whole_model,
    seed = 123,
)
source = MOI.Utilities.Model{Float64}()
x = MOI.add_variables(source, 3) # x[3] is an isolate
for v in x
    MOI.add_constraint(source, v, MOI.ZeroOne())
end
f = MOI.ScalarQuadraticFunction(
    [MOI.ScalarQuadraticTerm(4.0, x[1], x[2])],
    [MOI.ScalarAffineTerm(-3.0, x[1]), MOI.ScalarAffineTerm(2.0, x[2])],
    5.0,
)
MOI.set(source, MOI.ObjectiveFunction{typeof(f)}(), f)
MOI.set(source, MOI.ObjectiveSense(), MOI.MIN_SENSE)
map = MOI.copy_to(optimizer, source)
MOI.optimize!(optimizer)
@assert MOI.get(optimizer, MOI.ObjectiveValue()) == 2.0
@assert MOI.get(optimizer, MOI.VariablePrimal(), map[x[1]]) == 1.0
@assert MOI.get(optimizer, MOI.VariablePrimal(), map[x[2]]) == 0.0
@assert MOI.get(optimizer, MOI.TerminationStatus()) == MOI.LOCALLY_SOLVED
@assert length(QUBOTools.state(optimizer, 1)) == 3

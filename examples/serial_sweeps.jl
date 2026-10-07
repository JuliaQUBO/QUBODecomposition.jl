# SPDX-License-Identifier: MPL-2.0
using QUBODecomposition, QUBODrivers, QUBOTools
import MathOptInterface as MOI

# Four coupled logical variables, one isolate, and a fixed sixth variable.
# Each child handles at most two free variables; ExactSampler's public status is
# conservative and neighborhood optima cannot establish a coupled global proof.
optimizer = QUBODecomposition.Optimizer(
    child_optimizer = () -> QUBODrivers.ExactSampler.Optimizer(),
    max_variables = 2,
    strategy = :components_then_sweeps,
    max_sweeps = 10,
    stagnation_sweeps = 2,
    seed = 123,
)
source = MOI.Utilities.UniversalFallback(MOI.Utilities.Model{Float64}())
x = MOI.add_variables(source, 6)
for v in x
    MOI.add_constraint(source, v, MOI.ZeroOne())
end
MOI.add_constraint(source, x[6], MOI.EqualTo(1.0))
f = MOI.ScalarQuadraticFunction(
    [MOI.ScalarQuadraticTerm(4.0, x[1], x[2]),
     MOI.ScalarQuadraticTerm(-2.0, x[2], x[3]),
     MOI.ScalarQuadraticTerm(1.0, x[3], x[4])],
    [MOI.ScalarAffineTerm(-3.0, x[1]), MOI.ScalarAffineTerm(2.0, x[2]),
     MOI.ScalarAffineTerm(-1.0, x[3]), MOI.ScalarAffineTerm(-2.0, x[5]),
     MOI.ScalarAffineTerm(3.0, x[6])],
    5.0,
)
MOI.set(source, MOI.ObjectiveFunction{typeof(f)}(), f)
MOI.set(source, MOI.ObjectiveSense(), MOI.MIN_SENSE)
map = MOI.copy_to(optimizer, source)
MOI.optimize!(optimizer)
full_state = [MOI.get(optimizer, MOI.VariablePrimal(), map[v]) for v in x]
energy = 5 - 3*full_state[1] + 2*full_state[2] - full_state[3] -
    2*full_state[5] + 3*full_state[6] + 4*full_state[1]*full_state[2] -
    2*full_state[2]*full_state[3] + full_state[3]*full_state[4]
@assert length(full_state) == 6 && full_state[6] == 1
@assert energy == MOI.get(optimizer, MOI.ObjectiveValue())
@assert MOI.get(optimizer, MOI.TerminationStatus()) == MOI.LOCALLY_SOLVED
@assert all(length(c["selected_indices"]) <= 2 for c in QUBOTools.metadata(QUBOTools.solution(optimizer))["decomposition"]["calls"])
println((; full_state, energy, status=MOI.get(optimizer, MOI.TerminationStatus())))

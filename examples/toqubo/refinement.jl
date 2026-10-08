# SPDX-License-Identifier: MPL-2.0
module RefinementExample
using JuMP, ToQUBO, QUBODecomposition, QUBODrivers, QUBOTools
import MathOptInterface as MOI

function run(; budget=2)
    composite=QUBODecomposition.Optimizer(
        child_optimizer=()->QUBODrivers.ExactSampler.Optimizer(),
        max_variables=budget,seed=123,max_child_calls=100,
        # Include the initial evaluation and every row of every child scan.
        max_candidate_evaluations=1+100*2^budget,
    )
    model=Model(()->ToQUBO.Optimizer(()->composite))
    @variable(model,x[1:2],Bin)
    @objective(model,Max,5+3*x[1]+3*x[2])
    c=@constraint(model,x[1]+x[2]<=1)
    set_attribute(c,ToQUBO.Attributes.ConstraintEncodingPenaltyHint(),-0.1)
    optimize!(model)
    @assert primal_status(model)==MOI.INFEASIBLE_POINT
    @assert ToQUBO.source_objective_value(model)==11
    @assert objective_value(model)≈10.9 # source objective minus the weak penalty
    set_attribute(model,ToQUBO.Attributes.MaxPenaltyUpdates(),5)
    # ToQUBO 0.7.0 requires an explicit public reset for a fresh encoding.
    MOI.Utilities.reset_optimizer(model)
    optimize!(model)
    state=value.(x)
    @assert state[1]+state[2]<=1
    @assert isempty(ToQUBO.violations(model))
    @assert ToQUBO.source_objective_value(model)==5+3*sum(state)
    @assert termination_status(model)==MOI.LOCALLY_SOLVED
    @assert length(QUBOTools.state(composite,1))==3
    # With B=2, three compiled bits exceed child capacity. Even exact child
    # neighborhoods have no coupled global certificate. ExactSampler itself
    # publicly reports LOCALLY_SOLVED on a fitting whole model, too.
    return (; state,source_objective=ToQUBO.source_objective_value(model),
        penalized_objective=objective_value(model),status=termination_status(model),
        source_feasible=ToQUBO.is_feasible(model),
        updates=get_attribute(model,ToQUBO.Attributes.PenaltyUpdateCount()))
end
end
if abspath(PROGRAM_FILE)==@__FILE__
    println(RefinementExample.run(;budget=2))
    println(RefinementExample.run(;budget=8))
end

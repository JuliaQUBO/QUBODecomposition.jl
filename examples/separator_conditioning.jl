# SPDX-License-Identifier: MPL-2.0
module SeparatorExample
using QUBODecomposition, QUBODrivers, QUBOTools
import MathOptInterface as MOI
function run()
    # The separator value 1 initially costs +2, but completed leaves give -4.
    model = QUBOTools.Model{Symbol,Float64,Int}([:center,:left,:right],
        [1,2,3],[2.,1.,1.],[1,1],[2,3],[-4.,-4.])
    optimizer = QUBODecomposition.Optimizer(
        child_optimizer=()->QUBODrivers.ExactSampler.Optimizer(),
        max_variables=1, strategy=:separator, separator=[1], max_separator_size=1,
        max_child_calls=4, max_candidate_evaluations=32, seed=41)
    QUBODrivers.set_model!(optimizer,model)
    MOI.optimize!(optimizer)
    @assert QUBOTools.state(optimizer,1)==[1,1,1]
    @assert QUBOTools.value(optimizer,1)==-4.
    # Released ExactSampler's public status is deliberately not a global proof.
    @assert MOI.get(optimizer,MOI.TerminationStatus())===MOI.ITERATION_LIMIT
    proof=QUBOTools.metadata(QUBOTools.solution(optimizer))["decomposition"]["separator"]
    @assert proof["completed_branches"]==2 && !proof["proof_complete"]
    @assert proof["incomplete_reason"]=="uncertified_components"
    return (;state=QUBOTools.state(optimizer,1), energy=QUBOTools.value(optimizer,1),
        status=MOI.get(optimizer,MOI.TerminationStatus()), proof)
end
end
SeparatorExample.run()

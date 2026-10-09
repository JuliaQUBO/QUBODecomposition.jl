# SPDX-License-Identifier: MPL-2.0
module SeparatorExample
using QUBODecomposition, QUBODrivers, QUBOTools
import MathOptInterface as MOI
function run(; separator=[1])
    # The separator value 1 initially costs +2, but completed leaves give -4.
    model = QUBOTools.Model{Symbol,Float64,Int}([:center,:left,:right],
        [1,2,3],[2.,1.,1.],[1,1],[2,3],[-4.,-4.])
    optimizer = QUBODecomposition.Optimizer(
        child_optimizer=()->QUBODrivers.ExactSampler.Optimizer(),
        max_variables=1, strategy=:separator, separator=separator, max_separator_size=1,
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

function compare()
    automatic = run(;separator=:articulation)
    manual = run(;separator=automatic.proof["indices"])
    @assert automatic.state == manual.state && automatic.energy == manual.energy
    @assert automatic.status == manual.status
    @assert automatic.proof["indices"] == [1]
    return (;automatic,manual,discovery_sec=automatic.proof["discovery"]["elapsed_sec"])
end

function refusal()
    # Removing any cycle vertex leaves a fitting path, but it is not articulation.
    model = QUBOTools.Model{Int,Float64,Int}(collect(1:4),collect(1:4),ones(4),
        [1,2,3,1],[2,3,4,4],fill(-2.,4))
    results = map((:articulation,[1])) do separator
        optimizer = QUBODecomposition.Optimizer(
            child_optimizer=()->QUBODrivers.ExactSampler.Optimizer(),
            max_variables=3,strategy=:separator,separator=separator,
            max_child_calls=4,max_candidate_evaluations=64)
        QUBODrivers.set_model!(optimizer,model); MOI.optimize!(optimizer)
        return optimizer
    end
    automatic,manual = results
    @assert MOI.get(automatic,MOI.TerminationStatus()) === MOI.INVALID_OPTION
    data=QUBOTools.metadata(QUBOTools.solution(automatic))["decomposition"]
    @assert data["attempted_calls"] == 0
    @assert data["separator"]["discovery"]["reason"] == "no_supported_articulation"
    @assert MOI.get(manual,MOI.TerminationStatus()) === MOI.LOCALLY_SOLVED
    return (;automatic_status=MOI.get(automatic,MOI.TerminationStatus()),
        manual_status=MOI.get(manual,MOI.TerminationStatus()),diagnostic=data["diagnostic"])
end
end
SeparatorExample.compare()
SeparatorExample.refusal()

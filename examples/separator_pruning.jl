# SPDX-License-Identifier: MPL-2.0
module SeparatorPruningExample
using QUBODecomposition, QUBODrivers, QUBOTools
import MathOptInterface as MOI

function run(; pruning=true)
    model = QUBOTools.Model(Dict(:center=>10., :left=>-2., :right=>-1.),
        Dict((:center,:left)=>1., (:center,:right)=>1.); offset=4.)
    # This example has three original variables and no compiler/encoding step.
    # Parent capacity checks guard each original-domain exhaustive dispatch.
    QUBOTools.dimension(model) <= 8 || error("exhaustive example limited to eight variables")
    capacity = 1
    capacity <= 8 || error("exhaustive child limited to eight variables")
    optimizer = QUBODecomposition.Optimizer(
        child_optimizer=()->QUBODrivers.ExactSampler.Optimizer(),
        max_variables=capacity, strategy=:separator, separator=[QUBOTools.index(model,:center)],
        separator_pruning=pruning, max_separator_size=3,
        max_child_calls=64, max_candidate_evaluations=2000)
    MOI.set(optimizer, MOI.TimeLimitSec(), 10.)
    QUBODrivers.set_model!(optimizer, model)
    MOI.optimize!(optimizer)
    @assert QUBOTools.state(optimizer,1)==[v===:center ? 0 : 1 for v in QUBOTools.variables(model)]
    @assert QUBOTools.value(optimizer,1)==1.
    data = QUBOTools.metadata(QUBOTools.solution(optimizer))["decomposition"]
    @assert data["separator"]["certified_pruned_branches"] == (pruning ? 1 : 0)
    # QUBODrivers 0.6.6 corrects ExactSampler's public exhaustive certificate.
    certified = pkgversion(QUBODrivers) >= v"0.6.6"
    @assert MOI.get(optimizer,MOI.TerminationStatus()) === (certified ? MOI.OPTIMAL : MOI.LOCALLY_SOLVED)
    @assert data["separator"]["proof_complete"] == certified
    return (; optimizer, data)
end
end
if abspath(PROGRAM_FILE) == @__FILE__
    result = SeparatorPruningExample.run()
    println((calls=result.data["attempted_calls"], proof=result.data["separator"]))
end

# SPDX-License-Identifier: MPL-2.0
module ConsensusExample
using QUBODecomposition, QUBODrivers, QUBOTools
import MathOptInterface as MOI
include("child.jl")
function run()
    model=QUBOTools.Model(Dict(:a=>0.,:b=>0.,:c=>0.),
        Dict((:a,:b)=>1.,(:b,:c)=>1.,(:a,:c)=>1.);domain=:spin,offset=2.)
    work=Ref(0)
    opt=QUBODecomposition.Optimizer(child_optimizer=()->BoundedExactChild(work),
        max_variables=2,strategy=:consensus,consensus_plan=[[1,2],[2,3],[1,3]],
        consensus_iterations=8,max_child_calls=64,max_candidate_evaluations=2000)
    MOI.set(opt,MOI.TimeLimitSec(),10.)
    QUBODrivers.set_model!(opt,model)
    MOI.optimize!(opt)
    data=QUBOTools.metadata(QUBOTools.solution(opt))["decomposition"]["consensus"]
    @assert MOI.get(opt,MOI.TerminationStatus())===MOI.LOCALLY_SOLVED
    @assert data["best_lower_bound"]<=1<=data["incumbent_normalized"]
    return (;state=QUBOTools.state(opt,1),energy=QUBOTools.value(opt,1),
        lower=data["best_lower_bound"],gap=data["absolute_gap"],child_assignments=work[])
end
end
if abspath(PROGRAM_FILE)==@__FILE__
    println(ConsensusExample.run())
end

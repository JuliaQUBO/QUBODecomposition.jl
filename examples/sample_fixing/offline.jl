# SPDX-License-Identifier: MPL-2.0
module SampleFixingExample
using QUBODecomposition, QUBODrivers, QUBOTools
import MathOptInterface as MOI
include("guarded_child.jl")
function run()
    labels=[:a,:b,:c,:isolate]
    model=QUBOTools.Model{Symbol,Float64,Int}(labels,[1,2,3],[4.,-2.,-1.],
        Int[],Int[],Float64[];start=Dict(zip(labels,[0,1,1,0])))
    pool=(;labels,domain=:bool,assignments=[[1,0,0,0],[1,1,0,0],[1,0,1,0]],
        provenance="explicit biased demonstration pool; not generated samples")
    work=Ref(0); dimensions=Int[]
    optimizer=QUBODecomposition.Optimizer(strategy=:sample_fixing,sample_pool=pool,
        max_variables=2,max_child_calls=4,max_candidate_evaluations=32,child_optimizer=()->SampleFixingExactChild(work,dimensions))
    MOI.set(optimizer,MOI.TimeLimitSec(),10.)
    QUBODrivers.set_model!(optimizer,model)
    MOI.optimize!(optimizer)
    data=QUBOTools.metadata(QUBOTools.solution(optimizer))["decomposition"]
    info=data["sample_fixing"]
    x=QUBOTools.state(optimizer,1)
    @assert x == [0,1,1,0] && QUBOTools.value(optimizer,1) == 4x[1]-2x[2]-x[3] == -3.
    @assert info["fixed_variables"] == Dict(1=>1,4=>0)
    @assert !info["global_incumbent_compatible"] && !info["original_proof"]
    @assert info["reported_generation_sec"] === nothing
    @assert dimensions == [2] && work[] == 4
    @assert MOI.get(optimizer,MOI.TerminationStatus()) === MOI.LOCALLY_SOLVED
    return (;optimizer,state=copy(x),energy=QUBOTools.value(optimizer,1),
        status=MOI.get(optimizer,MOI.TerminationStatus()),metadata=QUBOTools.metadata(QUBOTools.solution(optimizer)),
        child_assignments=work[],child_dimensions=copy(dimensions))
end
end
if abspath(PROGRAM_FILE) == @__FILE__
    result=SampleFixingExample.run()
    println((;state=result.state,energy=result.energy,status=result.status,child_assignments=result.child_assignments))
end

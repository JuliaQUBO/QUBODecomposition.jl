# SPDX-License-Identifier: MPL-2.0
# Execute only within an authorized campaign; never overwrite prior attempts.
using QUBODecomposition,QUBODrivers,QUBOTools,LinearAlgebra,TOML,SHA,Pkg
import MathOptInterface as MOI
include("child.jl")
length(ARGS)==1 || error("usage: compare.jl NEW_OUTPUT_DIRECTORY")
Threads.nthreads()==1 || error("one Julia thread required")
BLAS.set_num_threads(1)
root=normpath(joinpath(@__DIR__,"../.."))
output=abspath(only(ARGS))
ispath(output) && error("retain every attempt; output directory must be new")
mkdir(output)
fixtures=[
    Dict("name"=>"chain_isolate","linear"=>[-2.,3.,-1.,.5],"edges"=>[[1,2],[2,3]],
        "weights"=>[-4.,2.],"domain"=>"bool","offset"=>3.25,"capacity"=>2,
        "overlap"=>[[1,2],[2,3],[4]],"disjoint"=>[[1,2],[3,4]]),
    Dict("name"=>"joint_barrier","linear"=>ones(4),"edges"=>[[1,2],[1,3],[1,4],[2,3],[2,4],[3,4]],
        "weights"=>fill(-2.,6),"domain"=>"bool","offset"=>0.,"capacity"=>3,
        "overlap"=>[[1,2,3],[1,2,4],[1,3,4],[2,3,4]],"disjoint"=>[[1,2],[3,4]]),
    Dict("name"=>"frustrated_triangle","linear"=>zeros(3),"edges"=>[[1,2],[2,3],[1,3]],
        "weights"=>ones(3),"domain"=>"spin","offset"=>2.,"capacity"=>2,
        "overlap"=>[[1,2],[2,3],[1,3]],"disjoint"=>[[1,2],[3]])]
plan=Dict("fixtures"=>fixtures,"warmup_pairs"=>1,"measured_pairs"=>2,"total_solves"=>18,
    "max_consensus_iterations"=>16,"max_sweeps"=>16,"stagnation"=>16,
    "max_child_calls"=>64,"max_candidate_evaluations"=>2000,"parent_deadline_sec"=>10.,
    "max_child_variables"=>4,"max_child_assignments_per_solve"=>1024,
    "consensus_step"=>1.,"consensus_multiplier_limit"=>1e6,"history_limit"=>16,
    "start"=>"all zero Bool / all minus one Spin","sense"=>"min","scale"=>1.,
    "hard_process_limit_sec"=>600,"julia_threads"=>1,"blas_threads"=>1,
    "child"=>"BoundedExactChild: exact rational enumeration of dispatched Float64 coefficients",
    "julia_version"=>string(VERSION),"base"=>readchomp(`git -C $root rev-parse origin/main`),
    "source_head"=>readchomp(`git -C $root rev-parse HEAD`))
open(io->TOML.print(io,plan),joinpath(output,"plan.toml"),"w")
for file in ("Project.toml","Manifest.toml")
    cp(joinpath(root,file),joinpath(output,file))
end
paths=[joinpath("src",f) for f in readdir(joinpath(root,"src")) if endswith(f,".jl")]
append!(paths,["examples/consensus/child.jl","examples/consensus/compare.jl"])
open(io->TOML.print(io,Dict(p=>bytes2hex(sha256(read(joinpath(root,p)))) for p in paths)),
    joinpath(output,"source-sha256.toml"),"w")
for (fi,f) in enumerate(fixtures), repetition in 0:2, mode in ("partition","consensus")
    attempt=(fi-1)*6+repetition*2+(mode=="partition" ? 1 : 2)
    row=Dict{String,Any}("attempt"=>attempt,"fixture"=>f["name"],"repetition"=>repetition,
        "warmup"=>repetition==0,"mode"=>mode,"outcome"=>"started")
    path=joinpath(output,"attempt-$(lpad(attempt,2,'0')).toml")
    save()=open(io->TOML.print(io,row),path,"w")
    save()
    work=Ref(0)
    started=time_ns()
    try
        n=length(f["linear"])
        n<=8 && f["capacity"]<=4 && length(f["overlap"])<=4 &&
            length(f["disjoint"])<=4 || error("fixture size guard")
        model=QUBOTools.Model{Int,Float64,Int}(collect(1:n),collect(1:n),f["linear"],
            first.(f["edges"]),last.(f["edges"]),f["weights"];
            domain=Symbol(f["domain"]),offset=f["offset"])
        common=(;child_optimizer=()->BoundedExactChild(work),max_variables=f["capacity"],
            max_child_calls=64,max_candidate_evaluations=2000,max_sweeps=16,stagnation_sweeps=16)
        opt=mode=="consensus" ? QUBODecomposition.Optimizer(;common...,
            strategy=:consensus,consensus_plan=f["overlap"],consensus_iterations=16,
            consensus_stagnation=16,consensus_step=1.,consensus_multiplier_limit=1e6,
            consensus_history_limit=16) : QUBODecomposition.Optimizer(;common...,
            selection=:partition,partition_plan=f["disjoint"])
        MOI.set(opt,MOI.TimeLimitSec(),10.)
        QUBODrivers.set_model!(opt,model)
        MOI.optimize!(opt)
        row["wall_sec"]=(time_ns()-started)/1e9 # construction through full solve
        d=QUBOTools.metadata(QUBOTools.solution(opt))["decomposition"]
        row["parent_effective_sec"]=QUBOTools.metadata(QUBOTools.solution(opt))["time"]["effective"]
        row["calls"]=d["attempted_calls"]
        row["candidate_evaluations"]=d["candidate_evaluations"]
        row["child_assignments"]=work[]
        row["child_sec"]=d["child_execution_sec"]
        row["parent_sec"]=d["parent_processing_sec"]
        row["phase_sec"]=d["phase_sec"]
        row["status"]=string(MOI.get(opt,MOI.TerminationStatus()))
        row["stop_reason"]=d["stop_reason"]
        state=QUBOTools.state(opt,1)
        scalar(x)=f["offset"]+sum(f["linear"].*x)+
            sum(c*x[i]*x[j] for ((i,j),c) in zip(f["edges"],f["weights"]))
        domain=f["domain"]=="bool" ? (0,1) : (-1,1)
        optimum=minimum(scalar(x) for x in Iterators.product(fill(domain,n)...))
        @assert scalar(state)==QUBOTools.value(opt,1)
        row["state"]=state
        row["energy"]=scalar(state)
        row["oracle_optimum"]=optimum
        row["oracle_suboptimality"]=scalar(state)-optimum
        if mode=="consensus"
            c=d["consensus"]
            row["iterations"]=c["completed_iterations"]
            row["bound_available"]=c["best_lower_bound"]!==nothing
            if row["bound_available"]
                @assert c["best_lower_bound"]<=optimum<=c["incumbent_normalized"]
                row["certified_lower_exact"]=string(c["best_lower_bound"])
                row["certified_lower"]=Float64(c["best_lower_bound"])
                row["certified_gap_exact"]=string(c["absolute_gap"])
            end
        else
            row["bound_available"]=false
        end
        row["outcome"]="ok"
    catch err
        row["outcome"]="failed"
        row["error"]=sprint(showerror,err)
        row["wall_sec"]=(time_ns()-started)/1e9
        row["child_assignments"]=work[]
    finally
        save()
    end
end
println("Retained all 18 attempts in ",output)

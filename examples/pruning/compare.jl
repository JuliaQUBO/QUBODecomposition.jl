# SPDX-License-Identifier: MPL-2.0
# Run once per authorized comparison; NEW_OUTPUT_DIRECTORY must not exist.
using QUBODecomposition, QUBODrivers, QUBOTools, LinearAlgebra, TOML, SHA, Pkg
import MathOptInterface as MOI
length(ARGS)==1 || error("usage: compare.jl NEW_OUTPUT_DIRECTORY")
Threads.nthreads()==1 || error("one Julia thread required")
BLAS.set_num_threads(1)
root=normpath(joinpath(@__DIR__,"../.."))
output=abspath(only(ARGS))
ispath(output) && error("retain prior attempts; choose a new output directory")
mkdir(output)
# Freeze the full plan before the first solve, including warmups. No retries.
fixtures=[
    Dict("name"=>"useful", "linear"=>[10.,-2.,-1.], "edges"=>[[1,2],[1,3]], "weights"=>[1.,1.], "capacity"=>1),
    Dict("name"=>"weak", "linear"=>[-.25,-1.,-1.], "edges"=>[[1,2],[1,3],[2,3]], "weights"=>[.25,.25,4.], "capacity"=>2),
    Dict("name"=>"ties", "linear"=>[0.,0.,0.], "edges"=>[[1,2],[1,3]], "weights"=>[0.,0.], "capacity"=>1)]
plan=Dict("fixtures"=>fixtures,"separator"=>[1],"offset"=>4.,"domain"=>"bool","sense"=>"min","scale"=>1.,
    "warmup_pairs"=>1,"measured_pairs"=>2,"total_solves"=>18,"max_child_calls"=>64,
    "max_parent_candidate_evaluations"=>2000,"max_combined_candidate_evaluations"=>20000,
    "parent_deadline_sec"=>10.,"hard_process_limit_sec"=>600,"julia_threads"=>1,"blas_threads"=>1,
    "child"=>"released QUBODrivers.ExactSampler (public LOCALLY_SOLVED)",
    "julia_version"=>string(VERSION),"base"=>readchomp(`git -C $root rev-parse origin/main`),
    "source_head"=>readchomp(`git -C $root rev-parse HEAD`))
open(joinpath(output,"plan.toml"),"w") do io; TOML.print(io,plan); end
cp(joinpath(root,"Manifest.toml"),joinpath(output,"Manifest.toml"))
cp(joinpath(root,"Project.toml"),joinpath(output,"Project.toml"))
# Bind executable inputs even when recording on an uncommitted candidate tree.
open(joinpath(output,"source-sha256.toml"),"w") do io
    paths=[joinpath("src",f) for f in readdir(joinpath(root,"src")) if endswith(f,".jl")]
    push!(paths,"examples/pruning/compare.jl")
    TOML.print(io,Dict(path=>bytes2hex(sha256(read(joinpath(root,path)))) for path in paths))
end
for (fi, f) in enumerate(fixtures), repetition in 0:2, pruning in (false,true)
    attempt=(fi-1)*6+repetition*2+Int(pruning)+1
    row=Dict{String,Any}("attempt"=>attempt,"fixture"=>f["name"],"repetition"=>repetition,
        "warmup"=>repetition==0,"pruning"=>pruning,"outcome"=>"started")
    path=joinpath(output,"attempt-$(lpad(attempt,2,'0')).toml")
    save()=open(io->TOML.print(io,row),path,"w")
    save() # retain every started attempt, including a killed process
    start=time_ns()
    try
        n=length(f["linear"]);capacity=f["capacity"]
        n<=8 && capacity<=8 && length(plan["separator"])<=3 || error("size guard")
        # <=64*2^8 internal child evaluations + <=2000 parent evaluations
        # is <=18384, below the combined per-solve ceiling of 20000.
        model=QUBOTools.Model{Int,Float64,Int}(collect(1:n),collect(1:n),f["linear"],
            first.(f["edges"]),last.(f["edges"]),f["weights"];offset=4.)
        opt=QUBODecomposition.Optimizer(child_optimizer=()->QUBODrivers.ExactSampler.Optimizer(),
            max_variables=capacity,strategy=:separator,separator=[1],separator_pruning=pruning,
            max_separator_size=3,max_child_calls=64,max_candidate_evaluations=2000)
        MOI.set(opt,MOI.TimeLimitSec(),10.)
        QUBODrivers.set_model!(opt,model)
        MOI.optimize!(opt)
        row["wall_sec"]=(time_ns()-start)/1e9
        d=QUBOTools.metadata(QUBOTools.solution(opt))["decomposition"]
        row["calls"]=d["attempted_calls"]
        row["candidate_evaluations"]=d["candidate_evaluations"]
        row["bound_sec"]=d["separator"]["bound_sec"]
        row["pruned_branches"]=d["separator"]["certified_pruned_branches"]
        row["child_sec"]=d["child_execution_sec"]
        row["parent_sec"]=d["parent_processing_sec"]
        row["status"]=string(MOI.get(opt,MOI.TerminationStatus()))
        x=QUBOTools.state(opt,1)
        scalar(x)=4+sum(f["linear"].*x)+sum(c*x[i]*x[j] for ((i,j),c) in zip(f["edges"],f["weights"]))
        reference=minimum(scalar(x) for x in Iterators.product(fill((0,1),n)...))
        @assert scalar(x)==reference==QUBOTools.value(opt,1)
        row["state"]=x;row["energy"]=reference
        row["outcome"]="ok"
    catch err
        row["outcome"]="failed"
        row["error"]=sprint(showerror,err)
        row["wall_sec"]=(time_ns()-start)/1e9
    finally
        save()
    end
end
println("Retained all 18 attempts in ",output)

# SPDX-License-Identifier: MPL-2.0
# Run once within the documented finite campaign; no retries or old-file writes.
using QUBODecomposition, QUBODrivers, QUBOTools, LinearAlgebra, TOML, SHA, Pkg
import MathOptInterface as MOI
include("guarded_child.jl")
length(ARGS) == 1 || error("usage: compare.jl NEW_OUTPUT_DIRECTORY")
Threads.nthreads() == 1 || error("one Julia thread required")
BLAS.set_num_threads(1)
pkgversion(QUBODrivers) >= v"0.6.6" || error("fixed public ExactSampler >=0.6.6 is required")
root = normpath(joinpath(@__DIR__,"../.."))
realpath(pathof(QUBODecomposition)) == realpath(joinpath(root,"src/QUBODecomposition.jl")) || error("wrong decomposition source")
output = abspath(only(ARGS))
ispath(output) && error("output directory must be new; retain prior attempts")
mkdir(output)
fixtures = [
    Dict("name"=>"joint_barrier", "linear"=>ones(4), "edges"=>[[1,3],[1,4],[2,3],[2,4]],
        "weights"=>fill(-2.,4), "offset"=>0., "scale"=>1., "start"=>zeros(Int,4),
        "partition"=>[[1,2],[3,4]], "coarse"=>[[1,2],[3,4]]),
    Dict("name"=>"boundary_internal", "linear"=>[-3.,2.,-1.,4.,.5,0.],
        "edges"=>[[1,2],[3,4],[1,3],[2,4],[3,5],[4,5]],
        "weights"=>[3.,-1.,-2.,5.,-4.,1.], "offset"=>7., "scale"=>-2.5,
        "start"=>[0,1,0,1,1,0], "partition"=>[[1,2],[3,4],[5],[6]], "coarse"=>[[1,2],[3,4]]),
    Dict("name"=>"easy_chain", "linear"=>fill(-1.,6),
        "edges"=>[[1,2],[2,3],[3,4],[4,5],[5,6]], "weights"=>fill(-1.,5),
        "offset"=>2., "scale"=>1., "start"=>zeros(Int,6),
        "partition"=>[[1,2],[3,4],[5,6]], "coarse"=>[[1,2,3],[4,5,6]])]
retained_bytes = Ref(0)
function bounded_save(path, data, ceiling)
    bytes = take!(let io=IOBuffer(); TOML.print(io,data); io end)
    length(bytes) <= ceiling || error("individual serialized artifact ceiling")
    retained_bytes[] + length(bytes) <= 64*1024^2 || error("cumulative serialized evidence ceiling")
    ispath(path) && error("never overwrite an attempt artifact")
    write(path,bytes)
    retained_bytes[] += length(bytes)
end
source_paths = [joinpath("src",f) for f in readdir(joinpath(root,"src")) if endswith(f,".jl")]
append!(source_paths,["Project.toml","examples/coarse/compare.jl","examples/coarse/guarded_child.jl"])
hashes = Dict(p=>bytes2hex(sha256(read(joinpath(root,p)))) for p in source_paths)
# Audit allowances include fixture oracle states and both stage outputs per arm.
audit_work = Ref(0)
function scalar(f,x)
    audit_work[] < 512 || error("independent scalar audit allowance")
    audit_work[] += 1
    return f["scale"]*(f["offset"] + sum(f["linear"].*x) +
        sum(c*x[i]*x[j] for ((i,j),c) in zip(f["edges"],f["weights"])))
end
oracles = Dict{String,Float64}()
for f in fixtures
    n = length(f["linear"])
    n <= 8 || error("oracle dimension ceiling")
    audit_work[] + (1 << n) <= 512 || error("oracle aggregate allowance")
    # Scalar itself charges each assignment; the preflight precedes the iterator.
    oracles[f["name"]] = minimum(scalar(f,x) for x in Iterators.product(fill((0,1),n)...))
end
plan = Dict("fixtures"=>fixtures, "oracle_optima"=>oracles, "source_sha256"=>hashes,
    "warmup_pairs"=>1, "measured_pairs"=>2, "max_arm_attempts"=>18, "max_parent_invocations"=>36,
    "max_child_variables"=>4, "max_child_assignments_per_arm"=>512,
    "max_child_assignments_total"=>9216, "max_scalar_audit_assignments"=>512,
    "max_child_calls_per_arm"=>64, "max_candidate_evaluations_per_arm"=>1024,
    "deadline_sec_per_arm"=>10., "hard_process_timeout_sec"=>600,
    "virtual_address_limit_bytes"=>8*1024^3, "julia_threads"=>1, "blas_threads"=>1,
    "max_serialized_bytes_per_arm"=>2*1024^2, "max_serialized_bytes_total"=>64*1024^2,
    "max_logs_bytes"=>32*1024^2, "max_environment_bytes"=>4*1024^2,
    "first_stage"=>"partition, at most three sweeps", "control_second_stage"=>"one partition sweep",
    "treatment_second_stage"=>"one coarse proposal", "seed"=>41,
    "source_head"=>readchomp(`git -C $root rev-parse HEAD`),
    "base"=>"1484b8f291458f5312a21ed701a14626e9e1bf20", "julia_version"=>string(VERSION),
    "driver_version"=>string(pkgversion(QUBODrivers)), "driver_source"=>pathof(QUBODrivers),
    "decomposition_source"=>pathof(QUBODecomposition),
    "tools_version"=>string(pkgversion(QUBOTools)), "tools_source"=>pathof(QUBOTools),
    "manifest_sha256"=>bytes2hex(sha256(read(joinpath(dirname(Base.active_project()),"Manifest.toml")))))
bounded_save(joinpath(output,"plan.toml"),plan,4*1024^2)
for file in ("Project.toml","Manifest.toml")
    source = joinpath(dirname(Base.active_project()),file)
    isfile(source) || error("active environment must retain $file")
    filesize(source) <= 2*1024^2 || error("environment artifact ceiling")
    cp(source,joinpath(output,file))
end
function source_model(f,start)
    n = length(f["linear"])
    labels = [Symbol("v",i) for i in 1:n]
    QUBOTools.Model{Symbol,Float64,Int}(labels,collect(1:n),f["linear"],
        first.(f["edges"]),last.(f["edges"]),f["weights"];
        offset=f["offset"],scale=f["scale"],start=Dict(zip(labels,start)))
end
function stage_record(opt)
    metadata = QUBOTools.metadata(QUBOTools.solution(opt))
    d = metadata["decomposition"]
    Dict("calls"=>d["attempted_calls"], "completed_calls"=>d["completed_calls"],
        "candidate_evaluations"=>d["candidate_evaluations"], "child_sec"=>d["child_execution_sec"],
        "parent_sec"=>d["parent_processing_sec"], "effective_sec"=>metadata["time"]["effective"],
        "phase_sec"=>d["phase_sec"], "status"=>string(MOI.get(opt,MOI.TerminationStatus())),
        "stop_reason"=>d["stop_reason"], "state"=>QUBOTools.state(opt,1),
        "energy"=>QUBOTools.value(opt,1),
        "child_statuses"=>[c["public_status"] for c in d["calls"] if c["public_status"] !== nothing])
end
attempt = 0
parent_invocations = 0
aggregate_work = 0
for (fi,f) in enumerate(fixtures), repetition in 0:2
    order = isodd(fi+repetition) ? ("partition","coarse") : ("coarse","partition")
    for mode in order
        global attempt += 1
        attempt <= 18 || error("arm-attempt ceiling")
        row = Dict{String,Any}("attempt"=>attempt,"fixture"=>f["name"],"repetition"=>repetition,
            "warmup"=>repetition==0,"mode"=>mode,"outcome"=>"started")
        work = Ref(0); dimensions = Int[]
        stages = Dict{String,Any}[]
        bounded_save(joinpath(output,"attempt-$(lpad(attempt,2,'0'))-start.toml"),row,4096)
        started = time_ns()
        deadline = started/1e9 + 10.
        try
            state = copy(f["start"])
            calls = 0; evaluations = 0
            for stage in 1:2
                calls < 64 && evaluations < 1024 && time_ns()/1e9 < deadline ||
                    error("shared arm parent allowance exhausted before stage $stage")
                # Construction and supplied-group planning lie inside the arm timer.
                source = source_model(f,state)
                common = (;child_optimizer=()->GuardedExactChild(work,dimensions), max_variables=2,
                    max_child_calls=64-calls, max_candidate_evaluations=1024-evaluations,
                    absolute_deadline_sec=deadline, seed=41+calls)
                opt = stage == 2 && mode == "coarse" ? QUBODecomposition.Optimizer(;common...,
                    strategy=:coarse,coarse_groups=deepcopy(f["coarse"])) : QUBODecomposition.Optimizer(;common...,
                    selection=:partition,partition_plan=deepcopy(f["partition"]),
                    max_sweeps=stage==1 ? 3 : 1,stagnation_sweeps=3)
                QUBODrivers.set_model!(opt,source)
                global parent_invocations += 1
                parent_invocations <= 36 || error("parent invocation ceiling")
                MOI.optimize!(opt)
                # End solve timing at result attachment, before record extraction.
                stage_end = time_ns()
                record = stage_record(opt)
                push!(stages,record)
                calls += record["calls"]; evaluations += record["candidate_evaluations"]
                state = record["state"]
                record["attached_elapsed_sec"] = (stage_end-started)/1e9
                all(==("OPTIMAL"),record["child_statuses"]) || error("public exact child did not report OPTIMAL")
                status = MOI.get(opt,MOI.TerminationStatus())
                status in (MOI.OPTIMAL,MOI.LOCALLY_SOLVED,MOI.ITERATION_LIMIT) ||
                    error("arm stopped with $status: $(record["stop_reason"])")
                record["stop_reason"] in ("max_child_calls","max_candidate_evaluations","parent_time_limit") &&
                    error("shared parent allowance reached")
            end
            row["wall_sec"] = stages[2]["attached_elapsed_sec"]
            row["calls"] = calls; row["candidate_evaluations"] = evaluations
            row["state"] = state
            row["energy"] = stages[2]["energy"]
            row["oracle_optimum"] = oracles[f["name"]]
            row["oracle_suboptimality"] = row["energy"]-row["oracle_optimum"]
            row["outcome"] = "ok"
        catch err
            row["outcome"] = "failed"
            row["error"] = sprint(showerror,err)
            row["wall_sec"] = (time_ns()-started)/1e9
        finally
            # Independent original-objective checks lie outside measured arm time.
            try
                for record in stages
                    scalar(f,record["state"]) == record["energy"] || error("independent stage energy audit failed")
                end
            catch err
                row["outcome"] = "failed"
                row["audit_error"] = sprint(showerror,err)
            end
            row["stages"] = stages
            row["child_assignments"] = work[]
            row["child_dimensions"] = dimensions
            global aggregate_work += work[]
            aggregate_work <= 9216 || error("aggregate child-work ceiling")
            bounded_save(joinpath(output,"attempt-$(lpad(attempt,2,'0')).toml"),row,2*1024^2)
        end
    end
end
bounded_save(joinpath(output,"totals.toml"),Dict("arm_attempts"=>attempt,
    "parent_invocations"=>parent_invocations,"child_assignments"=>aggregate_work,
    "scalar_audit_assignments"=>audit_work[],"serialized_bytes_before_totals"=>retained_bytes[]),4096)
println("Retained ",attempt," arms and ",parent_invocations," parent invocations in ",output)

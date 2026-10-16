# SPDX-License-Identifier: MPL-2.0
# Run once within the documented finite campaign; no retries or old-file writes.
using QUBODecomposition, QUBODrivers, QUBOTools, LinearAlgebra, TOML, SHA, Pkg
import MathOptInterface as MOI
include("guarded_child.jl")
length(ARGS) == 1 || error("usage: compare.jl NEW_OUTPUT_DIRECTORY | --preflight")
preflight_only = only(ARGS) == "--preflight"
prior_audits = 0
Threads.nthreads() == 1 || error("one Julia thread required")
BLAS.set_num_threads(1)
pkgversion(QUBODrivers) >= v"0.6.6" || error("fixed public ExactSampler >=0.6.6 is required")
root = normpath(joinpath(@__DIR__,"../.."))
realpath(pathof(QUBODecomposition)) == realpath(joinpath(root,"src/QUBODecomposition.jl")) || error("wrong decomposition source")
fixtures = [
    Dict("name"=>"capacity_fit", "linear"=>[2.,3.,1.,2.,-2.,-1.],
        "edges"=>[[1,2],[2,3],[3,4],[4,5],[5,6]], "weights"=>[.25,.25,.25,.25,-1.], "offset"=>2., "scale"=>1.,
        "start"=>zeros(Int,6), "partition"=>[[1,2],[3,4],[5,6]]),
    Dict("name"=>"no_consensus", "linear"=>[-1.,-2.,-1.,-2.],
        "edges"=>[[1,2],[2,3],[3,4]], "weights"=>[-1.,-1.,-1.], "offset"=>1., "scale"=>1.,
        "start"=>zeros(Int,4), "partition"=>[[1,2],[3,4]]),
    Dict("name"=>"biased_barrier", "linear"=>ones(4),
        "edges"=>[[1,3],[1,4],[2,3],[2,4]], "weights"=>fill(-2.,4),
        "offset"=>0., "scale"=>1., "start"=>zeros(Int,4), "partition"=>[[1,2],[3,4]])]
# This preflight performs no oracle enumeration, parent solve or child call.
for f in fixtures
    n=length(f["linear"])
    1 <= n <= 8 || error("fixture original dimension ceiling")
    length(f["start"]) == n && all(x -> x in (0,1),f["start"]) || error("fixture start")
    sort(vcat(f["partition"]...)) == collect(1:n) || error("partition coverage")
    all(b -> 1 <= length(b) <= 2,f["partition"]) || error("partition capacity")
    length(f["edges"]) == length(f["weights"]) || error("fixture edge shape")
    all(e -> length(e)==2 && 1 <= e[1] < e[2] <= n,f["edges"]) || error("fixture edges")
end
planned_oracles=sum(1 << length(f["linear"]) for f in fixtures)
planned_scalar=planned_oracles+18*4 # original optima, two stage outputs and two pool rows
planned_scalar <= 512 || error("planned scalar audit allowance")
output = preflight_only ? nothing : abspath(first(ARGS))
if !preflight_only
    ispath(output) && error("output directory must be new; retain prior attempts")
    mkdir(output)
end
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
append!(source_paths,["Project.toml","examples/sample_fixing/compare.jl","examples/sample_fixing/guarded_child.jl","examples/sample_fixing/summarize.py"])
hashes = Dict(p=>bytes2hex(sha256(read(joinpath(root,p)))) for p in source_paths)
# Audit allowances include fixture oracle states and both stage outputs per arm.
audit_work = Ref(prior_audits)
function scalar(f,x)
    audit_work[] < 512 || error("independent scalar audit allowance")
    audit_work[] += 1
    return f["scale"]*(f["offset"] + sum(f["linear"].*x) +
        sum((c*x[i]*x[j] for ((i,j),c) in zip(f["edges"],f["weights"]));init=0.))
end
oracles = Dict{String,Float64}()
if !preflight_only
for f in fixtures
    n = length(f["linear"])
    n <= 8 || error("oracle dimension ceiling")
    audit_work[] + (1 << n) <= 512 || error("oracle aggregate allowance")
    # Scalar itself charges each assignment; the preflight precedes the iterator.
    oracles[f["name"]] = minimum(scalar(f,x) for x in Iterators.product(fill((0,1),n)...))
end
end
# Path-tracked candidate dependencies need content provenance as well as a
# Manifest entry. Bind the actual conversion, MOI and public child sources.
dependency_roots = Dict("QUBODrivers"=>pkgdir(QUBODrivers),
    "QUBOTools"=>pkgdir(QUBOTools), "MathOptInterface"=>pkgdir(MOI))
dependency_hashes = Dict{String,Dict{String,String}}()
for (name,directory) in dependency_roots
    files = ["Project.toml"]
    for part in ("src","ext")
        isdir(joinpath(directory,part)) || continue
        for (folder,_,names) in walkdir(joinpath(directory,part)), file in names
            endswith(file,".jl") && push!(files,relpath(joinpath(folder,file),directory))
        end
    end
    dependency_hashes[name] = Dict(file=>bytes2hex(sha256(read(joinpath(directory,file)))) for file in files)
end
isempty(readchomp(`git -C $root status --porcelain --untracked-files=no`)) || error("tracked source must be frozen before measurement")
driver_directory = pkgdir(QUBODrivers)
driver_revision = ispath(joinpath(driver_directory,".git")) ?
    readchomp(`git -C $driver_directory rev-parse HEAD`) : "installed package; see source hashes"
if preflight_only
    println((fixtures=fixtures,oracle_assignments=planned_oracles,planned_scalar_audits=planned_scalar,
        arms=18,parent_invocations=36,child_assignments_ceiling=9216,
        parent_solves_per_arm=2,pool_rows=2,fixing_threshold=1.0,
        source_head=readchomp(`git -C $root rev-parse HEAD`),
        source_tree=readchomp(`git -C $root rev-parse "HEAD^{tree}"`),
        manifest_sha256=bytes2hex(sha256(read(joinpath(dirname(Base.active_project()),"Manifest.toml")))),
        driver_revision=driver_revision,dependency_sources=length(dependency_hashes),
        actual_oracle_assignments=0,actual_parent_invocations=0,actual_child_assignments=0))
    exit()
end
plan = Dict("fixtures"=>fixtures, "oracle_optima"=>oracles, "source_sha256"=>hashes,
    "dependency_roots"=>dependency_roots, "dependency_sha256"=>dependency_hashes,
    "driver_revision"=>driver_revision,
    "source_tree"=>readchomp(`git -C $root rev-parse "HEAD^{tree}"`),
    "warmup_pairs"=>1, "measured_pairs"=>2, "max_arm_attempts"=>18, "max_parent_invocations"=>36,
    "max_child_variables"=>4, "max_child_assignments_per_arm"=>512,
    "max_child_assignments_total"=>9216, "max_scalar_audit_assignments"=>512,
    "prior_scalar_audit_assignments"=>prior_audits,
    "max_child_calls_per_arm"=>64, "max_candidate_evaluations_per_arm"=>1024,
    "deadline_sec_per_arm"=>10., "hard_process_timeout_sec"=>600,
    "virtual_address_limit_bytes"=>8*1024^3, "julia_threads"=>1, "blas_threads"=>1,
    "max_serialized_bytes_per_arm"=>2*1024^2, "max_serialized_bytes_total"=>64*1024^2,
    "max_logs_bytes"=>32*1024^2, "max_environment_bytes"=>4*1024^2,
    "pool_construction"=>"caller complete initial state plus generation parent public complete final state; copied and timed; duplicate rows retained",
    "pool_limitations"=>"two distinct rows with threshold greater than one half permit unanimous coordinates only; no sample distribution claim",
    "fixing_threshold"=>1.0,
    "first_stage"=>"partition, at most three sweeps; both output and initial state independently evaluated by generation parent", "control_second_stage"=>"one partition sweep",
    "treatment_second_stage"=>"one sample-guided unary fixing proposal", "seed"=>41,
    "source_head"=>readchomp(`git -C $root rev-parse HEAD`),
    "base"=>readchomp(`git -C $root rev-parse origin/main`),
    "stacked_design_base"=>"deea226fea4ecc6dfaf67f1c2780a06d144a96db",
    "reviewed_coarse_fix"=>"698d153b0ee673877d6432bbcdc592da4e558721", "julia_version"=>string(VERSION),
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
sum(filesize,readdir(output;join=true)) <= 4*1024^2 || error("environment/provenance aggregate ceiling")
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
    order = isodd(fi+repetition) ? ("partition","sample_fixing") : ("sample_fixing","partition")
    for mode in order
        global attempt += 1
        attempt <= 18 || error("arm-attempt ceiling")
        row = Dict{String,Any}("attempt"=>attempt,"fixture"=>f["name"],"repetition"=>repetition,
            "warmup"=>repetition==0,"mode"=>mode,"outcome"=>"started")
        work = Ref(0); dimensions = Int[]
        stages = Dict{String,Any}[]
        pool_rows = Vector{Int}[]
        pool_generation_sec = 0.0
        arm_parent_invocations = 0
        bounded_save(joinpath(output,"attempt-$(lpad(attempt,2,'0'))-start.toml"),row,4096)
        started = time_ns()
        deadline = started/1e9 + 10.
        try
            state = copy(f["start"])
            calls = 0; evaluations = 0
            push!(pool_rows,copy(state)) # attributed caller input, not a sampler output
            for stage in 1:2
                calls < 64 && evaluations < 1024 && time_ns()/1e9 < deadline ||
                    error("shared arm parent allowance exhausted before stage $stage")
                # Source construction, external pool copying and selection lie inside the arm timer.
                source = source_model(f,state)
                common = (;child_optimizer=()->SampleFixingExactChild(work,dimensions), max_variables=2,
                    max_child_calls=64-calls, max_candidate_evaluations=1024-evaluations,
                    absolute_deadline_sec=deadline, seed=41+calls)
                pool = stage == 2 ? (;labels=QUBOTools.variables(source),domain=:bool,
                    assignments=deepcopy(pool_rows),generation_sec=pool_generation_sec,
                    provenance="caller complete initial state plus generation parent public final state; bounded CPU partition generation") : nothing
                opt = stage == 2 && mode == "sample_fixing" ? QUBODecomposition.Optimizer(;common...,
                    strategy=:sample_fixing,sample_pool=pool,fixing_threshold=1.0) : QUBODecomposition.Optimizer(;common...,
                    selection=:partition,partition_plan=deepcopy(f["partition"]),
                    max_sweeps=stage==1 ? 3 : 1,stagnation_sweeps=3)
                QUBODrivers.set_model!(opt,source)
                arm_parent_invocations += 1
                global parent_invocations += 1
                parent_invocations <= 36 || error("parent invocation ceiling")
                MOI.optimize!(opt)
                # End solve timing at result attachment, before record extraction.
                stage_end = time_ns()
                record = stage_record(opt)
                push!(stages,record)
                calls += record["calls"]; evaluations += record["candidate_evaluations"]
                state = copy(record["state"])
                if stage == 1
                    push!(pool_rows,copy(state)) # public complete final state, no private callback
                    pool_generation_sec = (time_ns()-started)/1e9
                end
                if stage == 2 && mode == "sample_fixing"
                    info = QUBOTools.metadata(QUBOTools.solution(opt))["decomposition"]["sample_fixing"]
                    record["fixing_steps"] = [Dict("original_index"=>s["original_index"],
                        "value"=>s["value"],"score_numerator"=>s["score_numerator"],
                        "score_denominator"=>s["score_denominator"],"support_after"=>s["support_after"],
                        "retained_source_row_ids"=>s["retained_source_row_ids"],
                        "remaining_original_indices"=>s["remaining_original_indices"]) for s in info["steps"]]
                    record["pool_validated_rows"] = info["validated_rows"]
                    record["pool_distinct_rows"] = info["distinct_rows"]
                    if haskey(info,"global_incumbent_compatible")
                        record["global_incumbent_compatible"] = info["global_incumbent_compatible"]
                    end
                    record["original_proof"] = info["original_proof"]
                end
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
            row["pool_generation_sec"] = pool_generation_sec
            row["pool_rows"] = pool_rows
            row["pool_policy"] = "caller initial plus public generation-parent final; all supplied rows scored before distinct-state voting"
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
                row["pool_original_energies"] = [scalar(f,state) for state in pool_rows]
            catch err
                row["outcome"] = "failed"
                row["audit_error"] = sprint(showerror,err)
            end
            row["stages"] = stages
            row["parent_invocations"] = arm_parent_invocations
            row["recorded_parent_calls"] = sum(s["calls"] for s in stages;init=0)
            row["recorded_candidate_evaluations"] = sum(s["candidate_evaluations"] for s in stages;init=0)
            row["parent_counters_complete"] = length(stages) == arm_parent_invocations
            row["parent_work_accounting"] = row["parent_counters_complete"] ? "complete" : "partial/unknown; recorded counters are lower bounds, not total work"
            row["child_assignments"] = work[]
            row["child_dimensions"] = dimensions
            global aggregate_work += work[]
            aggregate_work <= 9216 || error("aggregate child-work ceiling")
            bounded_save(joinpath(output,"attempt-$(lpad(attempt,2,'0')).toml"),row,2*1024^2-4096)
        end
    end
end
bounded_save(joinpath(output,"totals.toml"),Dict("arm_attempts"=>attempt,
    "parent_invocations"=>parent_invocations,"child_assignments"=>aggregate_work,
    "scalar_audit_assignments"=>audit_work[],"serialized_bytes_before_totals"=>retained_bytes[]),4096)
println("Retained ",attempt," arms and ",parent_invocations," parent invocations in ",output)

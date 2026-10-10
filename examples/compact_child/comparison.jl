# SPDX-License-Identifier: MPL-2.0
module CompactComparison
using ..CompactChildExperiment
using QUBODecomposition, QUBODrivers, QUBOTools, LinearAlgebra, Statistics, SHA, TOML, Pkg, Dates
import MathOptInterface as MOI
const CCE = CompactChildExperiment
const ROOT = normpath(joinpath(@__DIR__, "../.."))
const BENCHMARK_SHA = "684a96b8e757b400964d062c4229aacc12a523e1"
const BASE_SHA = "5ac0f5439d39abf2ed8e8d21646008bf160d7eaf"
const PRIMARY_ATTEMPTS = 24
const ASSIGNMENT_ALLOWANCE = 15360 # primary + at most one complete rerun
const PARENT_ALLOWANCE = 15600
const ORACLE_ALLOWANCE = 1024
const TIME_ALLOWANCE = 300.0

function fixture(name)
    name in ("path15", "star33", "path8", "star8") || error("unknown fixture")
    n=name=="path15" ? 15 : name=="star33" ? 33 : 8
    edges=startswith(name,"path") ? [(i,i+1) for i in 1:n-1] : [(1,j) for j in 2:n]
    model=QUBOTools.Model{Int,Float64,Int}(1:n,1:n,fill(-1.,n),
        first.(edges),last.(edges),fill(-2.,length(edges));offset=3.,scale=1.5)
    return (;model,n,edges,separator=startswith(name,"path") ? [cld(n,2)] : [1],
        capacity=startswith(name,"path") ? cld(n,2)-1 : 1)
end
scalar(f,x)=1.5*(3-sum(x)-2sum(x[i]*x[j] for (i,j) in f.edges))
bound(f)=1.5*(3-f.n-2length(f.edges))
function description(f)
    return Dict("dimension"=>f.n,"domain"=>"BoolDomain","sense"=>"Min",
        "scale"=>1.5,"offset"=>3.,"linear"=>[[i,-1.] for i in 1:f.n],
        "quadratic"=>[[i,j,-2.] for (i,j) in f.edges],"separator"=>f.separator,"capacity"=>f.capacity)
end
# TOML representation is for retained diagnostics, not executable model input.
plain(x::AbstractDict)=Dict(string(k)=>plain(v) for (k,v) in x)
plain(x::Union{AbstractVector,Tuple})=plain.(collect(x))
plain(x::Union{Symbol,Enum,VersionNumber,MOI.VariableIndex})=string(x)
plain(::Nothing)="__nothing__"
plain(x)=x
function checkpoint(path,data)
    io=IOBuffer(); TOML.print(io,plain(data);sorted=true); payload=String(take!(io))
    temporary,out=mktemp(dirname(path))
    try
        write(out,payload);close(out)
        status=ccall(:jl_fs_rename,Int32,(Cstring,Cstring),temporary,path)
        Base.uv_error("checkpoint rename",status)
    finally
        isopen(out) && close(out)
        ispath(temporary) && rm(temporary)
    end
end
function preflight()
    plans=Dict{String,Any}[]
    for name in ("path15","star33")
        f=fixture(name)
        sizes=name=="path15" ? [7,7] : fill(1,32)
        assignments=2sum(CCE.exact_size(n) for n in sizes)
        calls=2length(sizes)
        push!(plans,Dict("fixture"=>name,"assignments"=>assignments,"calls"=>calls,
            "parent_bound"=>1+assignments+4,"all_rows"=>assignments,"compact_rows"=>calls))
    end
    totals=Dict("attempts"=>24,"assignments"=>12sum(p["assignments"] for p in plans),
        "parent_bound"=>12sum(p["parent_bound"] for p in plans),"oracle_assignments"=>512)
    totals==Dict("attempts"=>24,"assignments"=>7680,"parent_bound"=>7800,"oracle_assignments"=>512) || error("preflight drift")
    return plans,totals
end
function audit_small_families()
    for name in ("path8","star8")
        f=fixture(name); count=CCE.exact_size(f.n)
        minimum(scalar(f,[Int((mask>>(i-1))&1) for i in 1:f.n]) for mask in 0:count-1)==bound(f) || error("independent small family oracle failed")
    end
end
function execute(name,mode; allowance=1024,time_limit=10.)
    ledger=CCE.Ledger(allowance);opt=nothing;f=nothing;exception=nothing
    timed=@timed begin
        try
            f=fixture(name)
            opt=QUBODecomposition.Optimizer(child_optimizer=()->CCE.child(ledger;mode),
                max_variables=f.capacity,strategy=:separator,separator=f.separator,max_separator_size=1,
                max_child_calls=128,max_candidate_evaluations=2049,seed=41)
            MOI.set(opt,MOI.TimeLimitSec(),time_limit)
            QUBODrivers.set_model!(opt,f.model)
            MOI.optimize!(opt) # ends after result attachment
        catch err
            exception=sprint(showerror,err)
        end
    end
    r=Dict{String,Any}("fixture"=>name,"mode"=>String(mode),"elapsed_sec"=>timed.time,
        "allocation_bytes"=>timed.bytes,"gc_sec"=>timed.gctime,"exception"=>exception,
        "reserved_assignments"=>ledger.reserved,"actual_assignments"=>sum(c["actual_assignments"] for c in ledger.calls;init=0),
        "rows_emitted"=>sum(c["rows_emitted"] for c in ledger.calls;init=0),"child_calls"=>ledger.calls,"failed"=>true)
    # Audit AFTER @timed; retained separately and never used to skip validation.
    audit_started=time_ns()
    try
      if opt!==nothing && exception===nothing
        d=QUBOTools.metadata(QUBOTools.solution(opt))["decomposition"]
        r["decomposition"]=d;r["status"]=string(MOI.get(opt,MOI.TerminationStatus()))
        r["parent_evaluations"]=d["candidate_evaluations"]
        r["proof_complete"]=d["separator"]!==nothing && d["separator"]["proof_complete"]
        if MOI.get(opt,MOI.ResultCount())>0
            x=QUBOTools.state(opt,1);energy=QUBOTools.value(opt,1)
            r["state"]=copy(x);r["energy"]=energy;r["original_energy"]=scalar(f,x);r["reference"]=bound(f)
            r["failed"]=!(r["status"]=="OPTIMAL" && r["proof_complete"] &&
                length(x)==f.n && all(v->v in (0,1),x) && energy==scalar(f,x)==bound(f) &&
                all(c["certificate_checked"] && !c["failed"] for c in ledger.calls))
        end
      end
    catch err
        r["failed"]=true
        r["audit_error"]=sprint(showerror,err)
    end
    r["audit_sec"]=(time_ns()-audit_started)/1e9
    return r
end
distribution(xs)=Dict("min"=>minimum(xs),"q25"=>quantile(xs,.25),"median"=>median(xs),"q75"=>quantile(xs,.75),"max"=>maximum(xs))
function summary(runs)
    summaries=Dict{String,Any}()
    for name in ("path15","star33")
        rows=filter(r->r["fixture"]==name,runs)
        entry=Dict{String,Any}()
        for mode in ("all","compact")
            rs=filter(r->r["mode"]==mode && !r["failed"],rows)
            entry[mode]=Dict("completed"=>length(rs),"elapsed_sec"=>distribution([r["elapsed_sec"] for r in rs]),
                "allocation_bytes"=>distribution([r["allocation_bytes"] for r in rs]),"gc_sec"=>distribution([r["gc_sec"] for r in rs]))
        end
        paired=Dict{String,Any}[]
        for round in 1:5
            a=only(r for r in rows if r["mode"]=="all" && r["round"]==round)
            c=only(r for r in rows if r["mode"]=="compact" && r["round"]==round)
            a["failed"] || c["failed"] || push!(paired,Dict("round"=>round,
                "elapsed_sec"=>c["elapsed_sec"]-a["elapsed_sec"],"allocation_bytes"=>c["allocation_bytes"]-a["allocation_bytes"],
                "relative_time_change"=>c["elapsed_sec"]/a["elapsed_sec"]-1))
        end
        entry["paired_compact_minus_all"]=Dict("pairs"=>paired,
            "elapsed_sec"=>distribution([p["elapsed_sec"] for p in paired]),
            "allocation_bytes"=>distribution([p["allocation_bytes"] for p in paired]))
        summaries[name]=entry
    end
    return summaries
end
function environment()
    @assert pathof(QUBODecomposition)==joinpath(ROOT,"src","QUBODecomposition.jl")
    return Dict("producer_sha"=>readchomp(`git -C $ROOT rev-parse HEAD`),
        "producer_tree"=>readchomp(`git -C $ROOT rev-parse 'HEAD^{tree}'`),"production_base_sha"=>BASE_SHA,
        "benchmark_source_sha"=>BENCHMARK_SHA,"julia"=>string(VERSION),"julia_threads"=>Threads.nthreads(),
        "blas_threads"=>BLAS.get_num_threads(),"blas"=>string(BLAS.get_config()),"cpu"=>Sys.CPU_NAME,
        "machine"=>Sys.MACHINE,"kernel"=>string(Sys.KERNEL),"timestamp_utc"=>string(Dates.now(Dates.UTC)),
        "source_hashes"=>Dict(f=>bytes2hex(sha256(read(joinpath(@__DIR__,f)))) for f in ("adapter.jl","comparison.jl","run.jl")),
        "packages"=>Dict(i.name=>Dict("version"=>string(i.version),"tree_hash"=>i.tree_hash===nothing ? nothing : string(i.tree_hash),"git_revision"=>i.git_revision) for i in values(Pkg.dependencies()) if i.version!==nothing))
end
function run(output,aggregate_path)
    ispath(output) && error("use a new output directory; evidence is never overwritten")
    isempty(readchomp(`git -C $ROOT status --porcelain`)) || error("commit candidate before campaign")
    Threads.nthreads()==1 || error("one Julia thread required");BLAS.set_num_threads(1)
    plans,totals=preflight(); env=environment()
    aggregate=isfile(aggregate_path) ? TOML.parsefile(aggregate_path) : Dict("attempts"=>0,"assignments"=>0,"parent_bound"=>0,"oracle_assignments"=>0)
    # Reserve the ENTIRE batch before any audit or dispatch, including all failures.
    for (key,limit) in (("attempts",48),("assignments",ASSIGNMENT_ALLOWANCE),("parent_bound",PARENT_ALLOWANCE),("oracle_assignments",ORACLE_ALLOWANCE))
        aggregate[key]+totals[key]<=limit || error("cumulative allowance exhausted: $key")
        aggregate[key]+=totals[key]
    end
    mkpath(output); checkpoint(aggregate_path,aggregate)
    cp(Base.active_project(),joinpath(output,"Project.toml"))
    cp(joinpath(dirname(Base.active_project()),"Manifest.toml"),joinpath(output,"Manifest.toml"))
    result=Dict{String,Any}("environment"=>env,"preflight"=>totals,"plans"=>plans,"cumulative_reservations"=>aggregate,
        "fixtures"=>Dict(n=>description(fixture(n)) for n in ("path15","star33")),
        "attempts"=>Dict{String,Any}[],"summary"=>Dict{String,Any}(),
        "limits"=>Dict("child_variables"=>8,"child_assignments"=>256,"per_solve_assignments"=>1024,
            "parent_candidates"=>2049,"parent_calls"=>128,"per_solve_sec"=>10.,"campaign_sec"=>TIME_ALLOWANCE,
            "aggregate_assignments"=>ASSIGNMENT_ALLOWANCE,"aggregate_parent_bound"=>PARENT_ALLOWANCE,"aggregate_oracle_assignments"=>ORACLE_ALLOWANCE),
        "rerun"=>"julia --startup-file=no --threads=1 examples/compact_child/run.jl NEW_OUTPUT CUMULATIVE_LEDGER")
    checkpoint(joinpath(output,"results.toml"),result)
    started=time_ns(); audit_small_families()
    for round in 0:5, name in ("path15","star33")
        for mode in (isodd(round) ? (:all,:compact) : (:compact,:all))
            remaining=TIME_ALLOWANCE-(time_ns()-started)/1e9
            r=remaining>0 ? execute(name,mode;time_limit=min(10.,remaining)) :
                Dict{String,Any}("fixture"=>name,"mode"=>String(mode),"failed"=>true,"exception"=>"aggregate deadline before dispatch")
            r["round"]=round;r["warmup"]=round==0
            push!(result["attempts"],r);checkpoint(joinpath(output,"results.toml"),result)
        end
    end
    result["campaign_with_audits_and_checkpoints_sec"]=(time_ns()-started)/1e9
    runs=filter(r->!r["warmup"],result["attempts"])
    if all(!r["failed"] for r in runs)
        result["summary"]=summary(runs)
    end
    checkpoint(joinpath(output,"results.toml"),result)
    return result
end
end

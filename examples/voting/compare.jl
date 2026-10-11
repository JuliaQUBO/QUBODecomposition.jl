# SPDX-License-Identifier: MPL-2.0
# Finite evidence tooling, not a production child or performance threshold.
using TOML, SHA, LinearAlgebra
import MathOptInterface as MOI
import QUBODrivers, QUBOTools, QUBODecomposition
include(joinpath(@__DIR__, "../../test/fixtures.jl"))

const LIMITS = (fixtures=3, repetitions=2, attempts=30, child_dimension=3,
    assignments_per_attempt=256, assignments_campaign=7680, parent_evaluations_campaign=1920,
    oracle_dimension=7, oracle_assignments=256, calls=24, candidates=64,
    sweeps=3, parent_seconds=5., campaign_seconds=120.)
const MODES = (:serial, :voting, :repair)

function fixtures()
    edges=[(1,2),(1,3),(2,3),(3,4),(4,5),(4,6),(5,6)]
    clusters=QUBOTools.Model{Int,Float64,Int}(collect(1:7),collect(1:7),
        [1.,1.,1.,1.,1.,1.,-0.5],first.(edges),last.(edges),[-2.,-2.,-2.,4.,-2.,-2.,-2.];offset=7.25)
    edges=[(i,j) for i in 1:6 for j in i+1:6]
    trap=QUBOTools.Model{Int,Float64,Int}(collect(1:6),collect(1:6),ones(6),first.(edges),last.(edges),fill(-2.,15))
    frustrated=QUBOTools.Model{Int,Float64,Int}(collect(1:4),collect(1:4),[-1.,2.,-1.,-1.],
        [1,1,3,1,2,2],[3,4,4,2,3,4],[3.,3.,3.,-4.,-4.,-4.])
    return [("clusters",clusters,3),("trap",trap,2),("frustrated",frustrated,2)]
end
function oracle(name,x)
    name=="trap" && return 2sum(x)-sum(x)^2
    name=="frustrated" && return -x[1]+2x[2]-x[3]-x[4]+3(x[1]*x[3]+x[1]*x[4]+x[3]*x[4])-4x[2]*(x[1]+x[3]+x[4])
    return 7.25+sum(x[1:6])-0.5x[7]-2(x[1]*x[2]+x[1]*x[3]+x[2]*x[3]+x[4]*x[5]+x[4]*x[6]+x[5]*x[6])+4x[3]*x[4]
end
portable(x)=x===nothing ? "nothing" : x isa AbstractDict ? Dict(string(k)=>portable(v) for (k,v) in x) :
    x isa Tuple || x isa AbstractVector ? [portable(v) for v in x] :
    x isa Symbol || x isa Function || x isa MOI.TerminationStatusCode ? string(x) : x

function run(output)
    ispath(output) && error("output must be new")
    root=normpath(joinpath(@__DIR__,"../.."))
    @assert Base.pathof(QUBODecomposition)==joinpath(root,"src/QUBODecomposition.jl")
    isempty(readchomp(`git -C $root status --porcelain`)) || error("commit candidate first")
    BLAS.set_num_threads(1)
    mkpath(output)
    source=Dict("head"=>readchomp(`git -C $root rev-parse HEAD`),"tree"=>readchomp(`git -C $root rev-parse HEAD^{tree}`),
        "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),"julia"=>string(VERSION),
        "threads"=>Threads.nthreads(),"blas_threads"=>BLAS.get_num_threads())
    for filename in ("Project.toml","Manifest.toml")
        cp(joinpath(dirname(Base.active_project()),filename),joinpath(output,filename))
    end
    start=time(); attempts=Ref(0);reserved_total=Ref(0);parent_total=Ref(0);oracle_reserved=0;oracle_completed=0
    outcomes=Any[];references=Dict{String,Float64}()
    function persist()
        open(joinpath(output,"evidence.toml"),"w") do io
            TOML.print(io,portable(Dict("limits"=>Dict(string(k)=>v for (k,v) in pairs(LIMITS)),"source"=>source,
                "attempts"=>outcomes,"charged_attempts"=>attempts[],"reserved_child_assignments"=>reserved_total[],
                "parent_evaluations"=>parent_total[],"oracle_reserved"=>oracle_reserved,"oracle_completed"=>oracle_completed,
                "references"=>references,"campaign_sec"=>time()-start)))
        end
    end
    function attempt(name,model,capacity,mode,repetition;warmup=false,allowance=LIMITS.assignments_per_attempt)
        attempts[] < LIMITS.attempts || error("attempt cap")
        time()-start < LIMITS.campaign_seconds || error("campaign wall cap")
        attempts[]+=1
        reserved=Ref(0);completed=Ref(0);term_work=Ref(0)
        factory=()->FixtureChild(callback=c->begin
            # Guard before shift, product construction or allocation. Reservations
            # are never refunded if this child later fails or is interrupted.
            n=length(MOI.get(c,MOI.ListOfVariableIndices()))
            1<=n<=LIMITS.child_dimension || error("refused exhaustive dimension")
            work=1<<n
            work<=allowance-reserved[] || error("refused attempt assignment allowance")
            work<=LIMITS.assignments_campaign-reserved_total[] || error("refused campaign assignment allowance")
            time()-start < LIMITS.campaign_seconds || error("campaign wall cap")
            reserved[]+=work;reserved_total[]+=work
            vars=sort(MOI.get(c.model,MOI.ListOfVariableIndices());by=v->-v.value)
            f=MOI.get(c.model,MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{Float64}}())
            best=nothing;energy=nothing
            for y in Iterators.product(fill((0,1),n)...)
                time()-start < LIMITS.campaign_seconds || error("campaign wall cap")
                x=Dict(v=>y[i] for (i,v) in enumerate(vars))
                e=f.constant
                for t in f.affine_terms
                    e+=t.coefficient*x[t.variable]
                end
                for t in f.quadratic_terms
                    e+=t.coefficient*x[t.variable_1]*x[t.variable_2]/(t.variable_1==t.variable_2 ? 2 : 1)
                end
                completed[]+=1
                term_work[]+=1+length(f.affine_terms)+length(f.quadratic_terms)
                if energy===nothing || e<energy || (e==energy && isless(y,best))
                    best,energy=y,e
                end
            end
            c.scripted=true;c.rows=Any[collect(best)];c.values=[energy]
        end)
        record=Dict{String,Any}("fixture"=>name,"mode"=>string(mode),"repetition"=>repetition,"warmup"=>warmup,
            "assignment_allowance"=>allowance,"failure"=>nothing)
        elapsed_start=time_ns()
        try
            opt=QUBODecomposition.Optimizer(child_optimizer=factory,max_variables=capacity,
                strategy=mode===:serial ? :components_then_sweeps : :frozen_batch,selection=:strongest_edge,
                batch_size=3,repair=mode===:repair,max_child_calls=LIMITS.calls,max_candidate_evaluations=LIMITS.candidates,
                max_sweeps=LIMITS.sweeps,stagnation_sweeps=1,seed=41)
            MOI.set(opt,MOI.TimeLimitSec(),LIMITS.parent_seconds)
            QUBODrivers.set_model!(opt,model);MOI.optimize!(opt)
            record["complete_execution_sec"]=(time_ns()-elapsed_start)/1e9
            x=QUBOTools.state(opt,1);energy=QUBOTools.value(opt,1)
            @assert energy==oracle(name,x)
            data=decomposition(opt);parent_total[]+=data["candidate_evaluations"]
            parent_total[]<=LIMITS.parent_evaluations_campaign || error("parent campaign cap")
            record["state"],record["energy"],record["status"],record["decomposition"]=x,energy,string(MOI.get(opt,MOI.TerminationStatus())),data
            data["stop_reason"]=="execution_failure" && (record["failure"]=get(data,"diagnostic","unknown"))
        catch err
            record["failure"]=sprint(showerror,err)
            record["complete_execution_sec"]=(time_ns()-elapsed_start)/1e9
        end
        record["reserved_assignments"],record["completed_assignments"],record["derived_term_work"]=reserved[],completed[],term_work[]
        push!(outcomes,record);persist()
    end
    for (name,model,cap) in fixtures()
        n=QUBOTools.dimension(model)
        n<=LIMITS.oracle_dimension || error("oracle dimension cap")
        work=1<<n
        work<=LIMITS.oracle_assignments-oracle_reserved || error("oracle assignment cap")
        oracle_reserved+=work
        best=Inf
        for x in Iterators.product(fill((0,1),n)...)
            best=min(best,oracle(name,x));oracle_completed+=1
        end
        references[name]=best
        for mode in MODES
            attempt(name,model,cap,mode,0;warmup=true)
        end
    end
    for repetition in 1:LIMITS.repetitions,(name,model,cap) in fixtures(),mode in MODES
        attempt(name,model,cap,mode,repetition)
    end
    for mode in MODES
        name,model,cap=fixtures()[2]
        attempt(name,model,cap,mode,-1;allowance=4)
    end
    @assert attempts[]==LIMITS.attempts
    persist()
    # Paired cost and quality deltas precede aggregation; retain every pair.
    paired=Any[]
    for (name,model,cap) in fixtures(),repetition in 1:LIMITS.repetitions
        rows=filter(r->r["fixture"]==name && r["repetition"]==repetition,outcomes)
        control=only(filter(r->r["mode"]=="serial",rows))
        for row in filter(r->r["mode"]!="serial",rows)
            if row["failure"]===nothing && control["failure"]===nothing
                push!(paired,Dict("fixture"=>name,"repetition"=>repetition,"mode"=>row["mode"],
                    "energy_delta"=>row["energy"]-control["energy"],
                    "execution_sec_delta"=>row["complete_execution_sec"]-control["complete_execution_sec"]))
            end
        end
    end
    open(joinpath(output,"paired.toml"),"w") do io
        TOML.print(io,Dict("pairs"=>paired))
    end
    println("charged attempts=",attempts[],", reserved child assignments=",reserved_total[],", parent evaluations=",parent_total[])
end
length(ARGS)==1 || error("provide new evidence directory")
run(only(ARGS))

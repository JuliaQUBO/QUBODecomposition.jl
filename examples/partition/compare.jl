# SPDX-License-Identifier: MPL-2.0
# A finite comparison using the same controlled exact public-MOI child as the
# independent boundary tests. This is evidence tooling, not a runtime adapter.
using TOML, SHA, LinearAlgebra
import MathOptInterface as MOI
import QUBODrivers, QUBOTools, QUBODecomposition
const VI = MOI.VariableIndex
include(joinpath(@__DIR__, "../../test/fixtures.jl"))
include(joinpath(@__DIR__, "region_growing.jl"))

const LIMITS = (fixtures=3, repetitions=1, attempts=20, child_dimension=3,
    assignments_per_attempt=128, assignments_campaign=2560, calls=16,
    candidates=129, sweeps=3, parent_seconds=5.0, campaign_seconds=120.0)

function fixtures()
    edges = [(1,2),(1,3),(2,3),(3,4),(4,5),(4,6),(5,6)]
    clusters = QUBOTools.Model{Int,Float64,Int}(collect(1:7),collect(1:7),
        [1.,1.,1.,1.,1.,1.,-0.5],first.(edges),last.(edges),[-2.,-2.,-2.,4.,-2.,-2.,-2.];offset=7.25)
    trap_edges = [(i,j) for i in 1:6 for j in i+1:6]
    trap = QUBOTools.Model{Int,Float64,Int}(collect(1:6),collect(1:6),ones(6),
        first.(trap_edges),last.(trap_edges),fill(-2.,15))
    path = QUBOTools.Model{Int,Float64,Int}(collect(1:6),collect(1:6),ones(6),
        collect(1:5),collect(2:6),fill(-2.,5))
    return [("clusters_bridge_isolate",clusters,3), ("coupled_trap",trap,2), ("path",path,3)]
end

function oracle(name, x)
    name == "coupled_trap" && return 2sum(x)-sum(x)^2
    name == "path" && return sum(x)-2sum(x[i]*x[i+1] for i in 1:5)
    return 7.25+sum(x[1:6])-0.5x[7]-2(x[1]*x[2]+x[1]*x[3]+x[2]*x[3]+x[4]*x[5]+x[4]*x[6]+x[5]*x[6])+4x[3]*x[4]
end

# TOML cannot encode nothing or integer dictionary keys; preserve those values
# explicitly in diagnostic records rather than dropping fields.
portable(x) = x === nothing ? "nothing" : x isa AbstractDict ?
    Dict(string(k)=>portable(v) for (k,v) in x) : x isa AbstractVector ? portable.(x) :
    x isa Symbol || x isa Function || x isa MOI.TerminationStatusCode ? string(x) : x

function run(output)
    ispath(output) && error("output must be a new path")
    root=normpath(joinpath(@__DIR__,"../.."))
    @assert Base.pathof(QUBODecomposition) == joinpath(root,"src/QUBODecomposition.jl")
    isempty(readchomp(`git -C $root status --porcelain`)) || error("commit the candidate before comparison")
    BLAS.set_num_threads(1)
    start=time(); attempts=Ref(3); total_reserved=Ref(0) # three retained pre-child harness failures
    outcomes=Any[]
    function attempt(name, model, capacity, selection, repetition; warmup=false, allowance=128)
        attempts[] < LIMITS.attempts || error("campaign attempt limit")
        time()-start < LIMITS.campaign_seconds || error("campaign wall limit")
        attempts[]+=1 # failed attempts also consume the allowance
        reserved=Ref(0); completed=Ref(0); term_work=Ref(0)
        factory=()->FixtureChild(callback=c -> begin
            n=length(MOI.get(c,MOI.ListOfVariableIndices()))
            n <= LIMITS.child_dimension || error("refused unsafe exhaustive dimension")
            work=1 << n
            work <= allowance-reserved[] || error("refused shared assignment allowance")
            work <= LIMITS.assignments_campaign-total_reserved[] || error("refused campaign assignment allowance")
            reserved[]+=work; total_reserved[]+=work
            f=MOI.get(c.model,MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{Float64}}())
            term_work[]+=work*(1+length(f.affine_terms)+length(f.quadratic_terms))
            completed[]+=work # FixtureChild enumeration follows immediately
        end)
        t=time_ns()
        opt=QUBODecomposition.Optimizer(;child_optimizer=factory,max_variables=capacity,
            selection,partition_plan=selection === :partition ? PartitionExample.region_growing : nothing,
            seed=41,max_child_calls=LIMITS.calls,max_candidate_evaluations=LIMITS.candidates,
            max_sweeps=LIMITS.sweeps,stagnation_sweeps=1)
        MOI.set(opt,MOI.TimeLimitSec(),LIMITS.parent_seconds)
        QUBODrivers.set_model!(opt,model)
        MOI.optimize!(opt)
        elapsed=(time_ns()-t)/1e9 # includes planning/conditioning/attachment
        state=QUBOTools.state(opt,1); value=QUBOTools.value(opt,1)
        @assert value == oracle(name,state)
        data=decomposition(opt)
        push!(outcomes,Dict("fixture"=>name,"selection"=>String(selection),"repetition"=>repetition,
            "warmup"=>warmup,"allowance"=>allowance,"reserved_assignments"=>reserved[],
            "completed_assignments"=>completed[],"child_term_evaluations"=>term_work[],
            "state"=>state,"energy"=>value,"effective_sec"=>elapsed,
            "status"=>string(MOI.get(opt,MOI.TerminationStatus())),"decomposition"=>portable(data)))
    end
    for (name,model,capacity) in fixtures(), selection in (:strongest_edge,:partition)
        attempt(name,model,capacity,selection,0;warmup=true)
    end
    # Paired repetitions alternate method order. Model starts remain all zero.
    for repetition in 1:LIMITS.repetitions, (name,model,capacity) in fixtures()
        order=isodd(repetition) ? (:strongest_edge,:partition) : (:partition,:strongest_edge)
        for selection in order
            attempt(name,model,capacity,selection,repetition)
        end
    end
    name,model,capacity=fixtures()[2]
    for selection in (:strongest_edge,:partition)
        attempt(name,model,capacity,selection,-1;allowance=4)
    end
    references=Dict{String,Any}()
    for (name,model,_) in fixtures()
        n=QUBOTools.dimension(model)
        n<=7 || error("independent oracle dimension limit")
        references[name]=minimum(oracle(name,x) for x in Iterators.product(fill((0,1),n)...))
    end
    @assert attempts[] == 17 <= LIMITS.attempts
    mkpath(output)
    evidence=Dict("source_sha"=>readchomp(`git -C $root rev-parse HEAD`),
        "source_tree"=>readchomp(Cmd(["git","-C",root,"rev-parse","HEAD^{tree}"])),
        "julia"=>string(VERSION),"threads"=>Threads.nthreads(),"blas_threads"=>BLAS.get_num_threads(),
        "limits"=>Dict(string(k)=>v for (k,v) in pairs(LIMITS)),"seed"=>41,
        "fixture_sha256"=>bytes2hex(sha256(read(@__FILE__))),"global_reference"=>references,
        "attempts"=>outcomes,"charged_attempts"=>attempts[],"pre_child_harness_failures"=>3,"reserved_assignments_campaign"=>total_reserved[],
        "campaign_sec"=>time()-start,
        "oracle_assignments"=>256,"oracle_assignment_limit"=>256,
        "versions"=>Dict("QUBOTools"=>string(pkgversion(QUBOTools)),"QUBODrivers"=>string(pkgversion(QUBODrivers))))
    open(joinpath(output,"evidence.toml"),"w") do io
        TOML.print(io,evidence;sorted=true)
    end
    for file in ("Project.toml","Manifest.toml")
        cp(joinpath(dirname(Base.active_project()),file),joinpath(output,file))
    end
    return evidence
end

if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    run(only(ARGS))
end

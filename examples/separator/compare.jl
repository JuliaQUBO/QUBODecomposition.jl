# SPDX-License-Identifier: MPL-2.0
module SeparatorComparison
using ..DecompositionPilot
using QUBODecomposition, QUBOTools, QUBODrivers, Pkg, LinearAlgebra, Test
import MathOptInterface as MOI
const DP = DecompositionPilot
const NAMES = ("path", "star_trap", "clusters")
const METHODS = (:direct, :strongest_edge, :single_flip_gain, :bfs, :random_blocks, :separator, :articulation)

function fixture(name)
    n, edges, linear, weights, separator, capacity = if name == "path"
        (5, [(1,2),(2,3),(3,4),(4,5)], ones(5), fill(-2.,4), [3], 2)
    elseif name == "star_trap"
        (5, [(1,2),(1,3),(1,4),(1,5)], [2.,1.,1.,1.,1.], fill(-2.,4), [1], 1)
    elseif name == "clusters"
        (7, [(1,2),(1,3),(2,3),(1,4),(1,5),(4,5),(5,6)],
            [2.,1.,-2.,1.,-1.,2.,-1.], [-3.,2.,-2.,-4.,1.,-2.,-3.], [1], 3)
    else
        error("unknown fixture")
    end
    model = QUBOTools.Model{Int,Float64,Int}(collect(1:n),collect(1:n),linear,
        first.(edges),last.(edges),weights;offset=3.)
    # Oracle uses fixture scalars, independent of the package conditioner/lifter.
    scalar(x) = 3. + sum(linear .* x) + sum(weights[k]*x[i]*x[j] for (k,(i,j)) in enumerate(edges))
    return (;model,scalar,separator,capacity,n,edges,linear,weights)
end

function execute(name, method; allowance=512)
    ledger = DP.WorkLedger(allowance)
    start = time_ns()
    f = fixture(name)
    count = DP.exact_size(f.n)
    built = time_ns()
    opt = if method === :direct
        DP.guarded_child(ledger)
    else
        QUBODecomposition.Optimizer(child_optimizer=()->DP.guarded_child(ledger),
            max_variables=f.capacity, strategy=method in (:separator,:articulation) ? :separator : :components_then_sweeps,
            separator=method===:articulation ? :articulation : f.separator,
            selection=method in (:separator,:articulation) ? :strongest_edge : method,
            seed=41, max_sweeps=3, stagnation_sweeps=1, max_child_calls=64,
            max_candidate_evaluations=1025)
    end
    DP.load_model!(opt,f.model)
    loaded = time_ns()
    MOI.optimize!(opt)
    finished = time_ns()
    state = copy(QUBOTools.state(opt,1)); energy = QUBOTools.value(opt,1)
    status = MOI.get(opt,MOI.TerminationStatus())
    reference = minimum(f.scalar([Int((mask>>(i-1))&1) for i in 1:f.n]) for mask in 0:count-1)
    @assert energy == f.scalar(state)
    data = method===:direct ? nothing : QUBOTools.metadata(QUBOTools.solution(opt))["decomposition"]
    @assert ledger.used<=allowance
    if method in (:separator,:articulation)
        @assert data["separator"]["indices"] == f.separator
    end
    discovery = data===nothing || data["separator"]===nothing ? nothing : data["separator"]["discovery"]
    audited = time_ns()
    return Dict("fixture"=>name,"method"=>string(method),"seed"=>(method===:direct ? nothing : 41),"start"=>zeros(Int,f.n),
        "fixture_description"=>Dict("n"=>f.n,"edges"=>f.edges,"linear"=>f.linear,"weights"=>f.weights,"offset"=>3.),
        "separator"=>f.separator,"capacity"=>(method===:direct ? 8 : f.capacity),
        "energy"=>energy,"state"=>state,"reference"=>reference,"gap"=>energy-reference,
        "status"=>string(status),"public_certificate"=>status===MOI.OPTIMAL,
        "certificate_source"=>"Pilot GuardedExact public OPTIMAL adapter, not released ExactSampler public status",
        "reserved_assignments"=>ledger.used,"completed_assignments"=>sum(get(c,"reported_evaluations",0) for c in ledger.calls),
        "reserved_term_evaluations"=>sum(c["term_evaluations"] for c in ledger.calls if c["dispatched"]),
        "child_calls"=>ledger.calls,"decomposition"=>data,
        "discovery_sec"=>discovery===nothing ? 0.0 : discovery["elapsed_sec"],
        "execution_sec"=>(finished-start)/1e9,"construction_sec"=>(built-start)/1e9,
        "loading_sec"=>(loaded-built)/1e9,"solve_sec"=>(finished-loaded)/1e9,"audit_sec"=>(audited-finished)/1e9)
end

function run(root,pilot,output)
    @assert realpath(dirname(dirname(pathof(QUBODecomposition))))==realpath(root)
    @assert Threads.nthreads()==1
    BLAS.set_num_threads(1)
    head=readchomp(`git -C $root rev-parse HEAD`)
    tree=readchomp(`git -C $root rev-parse 'HEAD^{tree}'`)
    @testset "Exhaustive guards" begin
        @test_throws ArgumentError DP.exact_size(64)
        ledger=DP.WorkLedger(3); child=DP.guarded_child(ledger)
        DP.load_model!(child,fixture("path").model)
        @test_throws ArgumentError MOI.optimize!(child)
        @test ledger.used==0
        @test !only(ledger.calls)["dispatched"]
    end
    warmups=[execute(name,method) for name in NAMES for method in METHODS]
    runs=Any[]
    for repetition in 1:3, name in NAMES
        for method in (isodd(repetition) ? METHODS : reverse(METHODS))
            result=execute(name,method);result["repetition"]=repetition;push!(runs,result)
        end
    end
    @assert all(r["gap"]==0 && r["public_certificate"] for r in runs if r["method"] in ("direct","separator","articulation"))
    @assert all(!r["public_certificate"] for r in runs if !(r["method"] in ("direct","separator","articulation")))
    @assert isempty(readchomp(`git -C $root status --porcelain`))
    @assert readchomp(`git -C $root rev-parse HEAD`)==head
    environment=Dict(string(k)=>Dict("name"=>v.name,"version"=>string(v.version),
        "tree_hash"=>v.tree_hash===nothing ? nothing : string(v.tree_hash)) for (k,v) in Pkg.dependencies())
    evidence=Dict("candidate_head"=>head,"candidate_tree"=>tree,
        "pilot_head"=>readchomp(`git -C $pilot rev-parse HEAD`),"julia"=>string(VERSION),"environment"=>environment,
        "cpu"=>Sys.CPU_NAME,"threads"=>Threads.nthreads(),"blas_threads"=>BLAS.get_num_threads(),
        "limits"=>Dict("hard_child_variables"=>8,"hard_child_assignments"=>256,"shared_assignments"=>512,
            "parent_evaluations"=>1025,"child_calls"=>64,"sweeps"=>3,"stagnation_sweeps"=>1,"separator_size"=>8),
        "warmups"=>warmups,"runs"=>runs,
        "timing_contract"=>"Fresh model construction through attached result, including planning, conditioning, conversion, child solve, reconstruction and parent evaluation. Imports, symmetric warmup and separately timed independent oracle audit excluded. Direct uses the same guarded exhaustive child without the composite wrapper.")
    mkdir(output)
    write(joinpath(output,"evidence.json"),DP.canonical_json(DP.json_value(evidence))*"\n")
    cp(Base.active_project(),joinpath(output,"Project.toml"))
    cp(joinpath(dirname(Base.active_project()),"Manifest.toml"),joinpath(output,"Manifest.toml"))
    for r in runs
        println(r["fixture"]," ",r["method"]," rep=",r["repetition"]," energy=",r["energy"]," work=",r["completed_assignments"]," seconds=",r["execution_sec"])
    end
end
end

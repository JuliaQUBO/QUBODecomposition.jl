# SPDX-License-Identifier: MPL-2.0
module SelectionComparison
using ..DecompositionPilot
using QUBODecomposition, QUBOTools, QUBODrivers, Pkg, SHA, TOML, LinearAlgebra, Test
import MathOptInterface as MOI
const DP = DecompositionPilot
const NAMES = ("disconnected", "strongly_coupled", "constrained", "linear_state", "joint_move", "multi_hop_path")

function fixture(name)
    name in DP.FIXTURES && return DP.fixture(name)
    model = if name == "linear_state"
        QUBOTools.Model{Int,Float64,Int}(collect(1:4), collect(1:4),
            [0.0,0.0,-5.0,-4.0], [1,2,3], [2,3,4], [10.0,0.5,0.5])
    elseif name == "joint_move"
        QUBOTools.Model{Int,Float64,Int}([1,2,3], [1,2,3], [1.0,1.0,2.0],
            [1,2], [2,3], [-3.0,0.25])
    elseif name == "multi_hop_path"
        QUBOTools.Model{Int,Float64,Int}(collect(1:6), collect(1:6), ones(6),
            collect(1:5), collect(2:6), fill(-2.0,5))
    else
        error("unknown fixture")
    end
    return (; model, reformulation=nothing)
end

function reference(f, name)
    name in DP.FIXTURES && return DP.reference(f, name)
    n = QUBOTools.dimension(f.model)
    count = DP.exact_size(n)
    energies = Float64[]
    for mask in 0:count-1
        x = [Int((mask >> (i-1)) & 1) for i in 1:n]
        expected = name == "linear_state" ?
            -5x[3]-4x[4]+10x[1]*x[2]+0.5x[2]*x[3]+0.5x[3]*x[4] :
            name == "joint_move" ? x[1]+x[2]+2x[3]-3x[1]*x[2]+0.25x[2]*x[3] :
            sum(x)-2sum(x[i]*x[i+1] for i in 1:5)
        @assert expected == DP.scalar_energy(DP.description(f), x)
        push!(energies, expected)
    end
    return Dict("energy"=>minimum(energies), "enumerated_assignments"=>count)
end

function execute(name, selection; allowance=64)
    ledger = DP.WorkLedger(allowance)
    start = time_ns()
    f = fixture(name)
    DP.exact_size(QUBOTools.dimension(f.model))
    built = time_ns()
    opt = QUBODecomposition.Optimizer(; child_optimizer=()->DP.guarded_child(ledger),
        max_variables=name == "multi_hop_path" ? 4 : 2, selection, max_sweeps=3, max_child_calls=16,
        max_candidate_evaluations=257, stagnation_sweeps=1, seed=41)
    QUBODrivers.set_model!(opt, f.model)
    loaded = time_ns()
    MOI.optimize!(opt)
    finished = time_ns()
    data = QUBOTools.metadata(QUBOTools.solution(opt))["decomposition"]
    state = copy(QUBOTools.state(opt, 1))
    energy = QUBOTools.value(opt, 1)
    status = MOI.get(opt, MOI.TerminationStatus())
    # Audit outside execution timing against the independent, guarded oracle.
    ref = reference(f, name)
    @assert length(state) == QUBOTools.dimension(f.model) && all(x -> x in (0,1), state)
    @assert isapprox(energy, DP.scalar_energy(DP.description(f), state); atol=1e-10, rtol=1e-12)
    @assert all(diff(data["incumbent_energy_trace"]) .<= 0)
    @assert ledger.used <= allowance
    source = DP.source_evaluation(f, state)
    audited = time_ns()
    return Dict("fixture"=>name, "selection"=>string(selection), "seed"=>41,
        "fixture_hash"=>DP.fixture_hash(f), "fixture_description"=>DP.description(f),
        "initial_state"=>zeros(Int, QUBOTools.dimension(f.model)),
        "status"=>string(status), "failed"=>status in (MOI.INVALID_OPTION, MOI.OTHER_ERROR),
        "failure"=>get(data,"diagnostic",nothing), "state"=>state, "energy"=>energy,
        "reference"=>ref, "gap"=>energy-ref["energy"], "source"=>source,
        "assignment_allowance"=>allowance, "reserved_assignments"=>ledger.used,
        "completed_assignments"=>sum(get(c,"reported_evaluations",0) for c in ledger.calls),
        "reserved_term_evaluations"=>sum(c["term_evaluations"] for c in ledger.calls if c["dispatched"]),
        "child_calls"=>ledger.calls, "decomposition"=>data,
        "execution_sec"=>(finished-start)/1e9, "construction_sec"=>(built-start)/1e9,
        "loading_sec"=>(loaded-built)/1e9, "solve_sec"=>(finished-loaded)/1e9,
        "audit_sec"=>(audited-finished)/1e9)
end

function run(root, pilot, output)
    @assert realpath(dirname(dirname(pathof(QUBODecomposition)))) == realpath(root)
    @assert realpath(dirname(dirname(pathof(DP.QUBOBenchmarks)))) == realpath(pilot)
    info = Pkg.dependencies()[Base.UUID("142f39e9-ef93-42e3-b199-458fb82151e7")]
    @assert info.is_tracking_path && realpath(info.source) == realpath(root)
    @assert Threads.nthreads() == 1
    BLAS.set_num_threads(1)
    head = readchomp(`git -C $root rev-parse HEAD`)
    tree = readchomp(`git -C $root rev-parse 'HEAD^{tree}'`)
    @testset "Reused pilot guard before dispatch" begin
        @test_throws ArgumentError DP.exact_size(64)
        ledger = DP.WorkLedger(3)
        child = DP.guarded_child(ledger)
        DP.load_model!(child, QUBOTools.Model{Int,Float64,Int}([1,2], [1], [-1.0], Int[], Int[], Float64[]))
        @test_throws ArgumentError MOI.optimize!(child)
        @test ledger.used == 0
        @test !only(ledger.calls)["dispatched"]
    end
    policies = (:strongest_edge, :single_flip_gain, :bfs, :random_blocks)
    warmups = [execute(name, policy) for name in NAMES for policy in policies]
    # Warm refusal paths symmetrically and retain all measured failures too.
    for policy in policies
        execute("strongly_coupled", policy; allowance=4)
    end
    runs = Any[]
    for repetition in 1:3, name in NAMES
        for policy in (isodd(repetition) ? policies : reverse(policies))
            result = execute(name, policy)
            result["repetition"] = repetition
            push!(runs, result)
        end
    end
    failures = [execute("strongly_coupled", policy; allowance=4) for policy in policies]
    @assert all(r["failed"] && r["reserved_assignments"] == 4 for r in failures)
    @assert all(r["gap"] == 24 for r in runs if r["fixture"] == "strongly_coupled")
    @assert readchomp(`git -C $root rev-parse HEAD`) == head
    @assert isempty(readchomp(`git -C $root status --porcelain`))
    environment = Dict(string(k)=>Dict("name"=>v.name, "version"=>string(v.version),
        "tree_hash"=>v.tree_hash === nothing ? nothing : string(v.tree_hash),
        "tracking_path"=>v.is_tracking_path) for (k,v) in Pkg.dependencies())
    evidence = Dict("candidate_head"=>head, "candidate_tree"=>tree,
        "pilot_head"=>readchomp(`git -C $pilot rev-parse HEAD`),
        "candidate_source_verified"=>true, "julia"=>string(VERSION),
        "cpu"=>Sys.CPU_NAME, "threads"=>Threads.nthreads(), "blas_threads"=>BLAS.get_num_threads(),
        "environment"=>environment, "warmups"=>warmups, "runs"=>runs, "failures"=>failures,
        "limits"=>Dict("child_variables"=>Dict(name=>(name == "multi_hop_path" ? 4 : 2) for name in NAMES), "hard_exact_variables"=>8,
            "hard_exact_assignments"=>256, "assignment_allowance"=>64,
            "parent_candidate_evaluations"=>257, "child_calls"=>16, "sweeps"=>3),
        "timing_contract"=>"Fresh construction through result attachment; includes selection, conditioning, conversion, child solving, reconstruction and parent evaluation. Imports, installation, symmetric warmup and oracle audit excluded. Raw repetitions are paired; no timing thresholds.",
        "conclusion"=>"Adopt as opt-in only; retain strongest_edge default. Tiny deterministic fixtures do not establish universal quality or speed gains. The coupled two-variable local trap remains. Broader comparison belongs to QUBOBenchmarks #27.")
    mkdir(output)
    write(joinpath(output,"evidence.json"), DP.canonical_json(DP.json_value(evidence)) * "\n")
    cp(Base.active_project(), joinpath(output,"Project.toml"))
    cp(joinpath(dirname(Base.active_project()),"Manifest.toml"), joinpath(output,"Manifest.toml"))
    println("Results: ", joinpath(output,"evidence.json"))
    for r in runs
        println(r["fixture"], " ", r["selection"], " rep=", r["repetition"],
            " energy=", r["energy"], " work=", r["completed_assignments"], " seconds=", r["execution_sec"])
    end
end
end

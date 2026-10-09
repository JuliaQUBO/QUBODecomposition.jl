# SPDX-License-Identifier: MPL-2.0
import Random

function graph_fixture(n, edges; labels=collect(1:n), bias=0.0, weight=0.5)
    QUBOTools.Model{eltype(labels),Float64,Int}(labels, collect(1:n), fill(bias,n),
        first.(edges), last.(edges), fill(weight,length(edges)))
end
block_trace(opt) = [(c["component"], c["sweep"], c["anchor"], c["selected_indices"])
    for c in decomposition(opt)["calls"]]

@testset "BFS discovery, capacity, topology and original-index order" begin
    # Exact discovery orders distinguish breadth-first from depth-first and from
    # repeatedly expanding only the anchor. The last index is always an isolate.
    cases = (
        ([(i,i+1) for i in 1:5], 3, [3,2,4,1,5,6]),
        ([(1,2),(2,3),(3,4),(4,5),(1,5)], 1, [1,2,5,3,4]),
        ([(1,i) for i in 2:6], 4, [4,1,2,3,5,6]),
        ([(i,j) for i in 1:5 for j in i+1:6], 5, [5,1,2,3,4,6]),
        (Tuple{Int,Int}[], 4, [4]),
    )
    for (edges, anchor, order) in cases
        model = graph_fixture(7, edges; labels=[:z,:a,:q,:b,:y,:c,:isolated])
        adjacency, _ = QUBODecomposition.interaction_graph(QUBODecomposition.snapshot(model))
        neighbors = [sort!(collect(keys(a))) for a in adjacency]
        seen = falses(7)
        for capacity in (1,2,4,7,10), repetition in 1:2
            selected = QUBODecomposition.bfs_neighborhood(neighbors, seen, anchor, capacity)
            @test selected == order[1:min(capacity,length(order))]
            @test length(unique(selected)) == length(selected)
            @test !any(seen)
            @test QUBODecomposition.bfs_neighborhood(neighbors, seen, 7, capacity) == [7]
        end
    end
    path = graph_fixture(6, [(i,i+1) for i in 1:5])
    bfs = solve_model(path; budget=4, selection=:bfs, max_sweeps=1)
    control = solve_model(path; budget=4, max_sweeps=1)
    @test [c["selected_indices"] for c in decomposition(bfs)["calls"]] ==
        [[1,2,3,4],[1,2,3,4],[1,2,3,4],[2,3,4,5],[3,4,5,6],[3,4,5,6]]
    @test [c["anchor"] for c in decomposition(bfs)["calls"]] == collect(1:6)
    @test first(decomposition(control)["calls"])["selected_indices"] == [1,2]
    @test maximum(length(c["selected_indices"]) for c in decomposition(control)["calls"]) == 3
    @test decomposition(bfs)["completed_sweeps"] == 1
end

@testset "Random partitions cover components once per completed sweep" begin
    edges = [(1,2),(2,3),(3,4),(4,5),(6,7),(7,8),(8,9),(9,10)]
    model = graph_fixture(11, edges; labels=[91,3,47,2,29,5,7,20,8,17,100])
    for selection in (:bfs, :random_blocks), capacity in (1,2,4,5,12)
        opt = solve_model(model; budget=capacity, selection, seed=41,
            max_sweeps=3, stagnation_sweeps=2)
        data = decomposition(opt)
        @test data["selection"] == string(selection)
        @test data["labels"] == QUBOTools.variables(model)
        @test all(1 <= length(c["selected_indices"]) <= capacity for c in data["calls"])
        @test data["selection_sec"] >= 0
        @test data["selection_sec"] <= data["phase_sec"]["preparation"]
        if capacity >= 5
            @test data["completed_sweeps"] == 0
            @test MOI.get(opt,MOI.TerminationStatus()) === MOI.OPTIMAL
            @test data["selection_seed"] === nothing
            continue
        end
        @test data["completed_sweeps"] == data["stagnation"] == 2
        @test MOI.get(opt, MOI.TerminationStatus()) === MOI.LOCALLY_SOLVED
        @test first(data["calls"])["selected_indices"] == [11]
        @test !data["separable_proof"]
        for sweep in 1:2, component in 1:2
            calls = filter(c -> c["sweep"] == sweep && c["component"] == component, data["calls"])
            indices = vcat([c["selected_indices"] for c in calls]...)
            expected = collect(component == 1 ? (1:5) : (6:10))
            @test all(i -> i in expected, indices)
            @test all(length(unique(c["selected_indices"])) == length(c["selected_indices"]) for c in calls)
            if selection === :random_blocks
                @test sort(indices) == expected
                @test length(calls) == cld(5,capacity)
                @test length(last(calls)["selected_indices"]) == mod1(5,capacity)
                @test all(c["anchor"] === nothing for c in calls)
            else
                @test [c["anchor"] for c in calls] == expected
            end
        end
        @test [c["seed"] for c in data["calls"]] == collect(41:40+data["attempted_calls"])
    end
end

@testset "Solve-local randomness, seed replay, repeated solves and changed inputs" begin
    model = graph_fixture(9, [(i,i+1) for i in 1:7]; bias=-1.0)
    for seed in (nothing, 0, 41, 2^31-2)
        Random.seed!(713)
        expected_global = rand(UInt64,8)
        Random.seed!(713)
        opt = solve_model(model; budget=3, selection=:random_blocks, seed, max_sweeps=2)
        @test rand(UInt64,8) == expected_global
        data = decomposition(opt)
        @test data["selection_seed"] isa Integer
        @test data["selection_rng"] == "Random.Xoshiro"
        # Replay the actual groups from recorded RNG input, including the
        # nondeterministic no-parent-seed case. No global RNG participates.
        rng = Random.Xoshiro(data["selection_seed"])
        calls = filter(c -> c["kind"] == "neighborhood", data["calls"])
        for sweep in 1:data["completed_sweeps"]
            perm = Random.shuffle(rng, collect(1:8))
            expected = [sort(perm[i:min(i+2,8)]) for i in 1:3:8]
            @test [c["selected_indices"] for c in calls if c["sweep"] == sweep] == expected
        end
        @test all(c["seed"] === nothing for c in data["calls"]) == (seed === nothing)
        if seed !== nothing
            @test [c["seed"] for c in data["calls"]] ==
                [mod(seed+k-1,2^31-1) for k in 1:data["attempted_calls"]]
            trace, state = block_trace(opt), copy(QUBOTools.state(opt,1))
            MOI.optimize!(opt)
            @test block_trace(opt) == trace
            @test QUBOTools.state(opt,1) == state
            # Child seed support and private child draws do not advance selection.
            noisy_child = () -> FixtureChild(seed_supported=false,
                callback=_ -> rand(Random.Xoshiro(98),100))
            other = solve_model(model; budget=3, selection=:random_blocks, seed,
                max_sweeps=2, child=noisy_child)
            @test block_trace(other) == trace
        end
    end
    for selection in (:bfs, :random_blocks)
        opt = solve_model(model; budget=3, selection, seed=41, max_sweeps=2)
        old_trace = block_trace(opt)
        # Mutate the actual attached backend: change topology and coefficients,
        # then compare with a newly constructed optimizer on that exact input.
        form = QUBOTools.form(QUBOTools.backend(opt))
        QUBOTools.data(QUBOTools.quadratic_form(form))[4,5] = 0.0
        QUBOTools.data(QUBOTools.linear_form(form))[1] = 9.0
        QUBOTools.attach!(QUBOTools.backend(opt), 2=>1)
        MOI.optimize!(opt)
        fresh = solve_model(QUBOTools.backend(opt); budget=3, selection, seed=41, max_sweeps=2)
        @test decomposition(opt)["components"] == [[1,2,3,4],[5,6,7,8],[9]]
        @test block_trace(opt) != old_trace
        @test block_trace(opt) == block_trace(fresh)
        @test QUBOTools.state(opt,1) == QUBOTools.state(fresh,1)
        @test QUBOTools.value(opt,1) == QUBOTools.value(fresh,1)
        QUBODrivers.set_model!(opt, direct_model(;labels=[27,1,90,5],domain=:spin,sense=:max))
        MOI.optimize!(opt)
        @test decomposition(opt)["labels"] == [27,1,90,5]
        @test decomposition(opt)["completed_sweeps"] == 0
        @test decomposition(opt)["selection_seed"] === nothing
    end
end

@testset "New policies: independent conditioned and lifted scalar energies" begin
    for selection in (:bfs,:random_blocks), domain in (:bool,:spin), sense in (:min,:max),
        scale in (2.5,-1.5), capacity in (1,2,4), storage in (:dict,:sparse,:dense)
        labels = [:z,:b,:a,:y,:q]
        base = QUBOTools.Model{Symbol,Float64,Int}(labels, collect(1:5),
            [-3.0,2.0,-1.0,0.75,-0.125], [1,2,3,4], [2,3,4,5], [4.0,-2.0,0.5,-0.25];
            domain,sense,scale,offset=7.25)
        model = QUBOTools.Model{Symbol,Float64,Int}(
            QUBOTools.VariableMap{Symbol}(Dict(i=>v for (i,v) in enumerate(labels))),
            QUBOTools.form(base,storage,Float64))
        values = domain === :bool ? (0,1) : (-1,1)
        start = [values[1],values[2],values[1],values[2],values[1]]
        for i in 1:5
            QUBOTools.attach!(model,labels[i]=>start[i])
        end
        energy(x) = scale*(7.25-3x[1]+2x[2]-x[3]+0.75x[4]-0.125x[5]+
            4x[1]*x[2]-2x[2]*x[3]+0.5x[3]*x[4]-0.25x[4]*x[5])
        children = FixtureChild[]
        factory = () -> (child=FixtureChild(); push!(children,child); child)
        opt = solve_model(model; budget=capacity, selection, seed=41, max_sweeps=2, child=factory)
        data = decomposition(opt)
        @test data["completed_calls"] == length(children) > 0
        incumbent = copy(start)
        for (call,child) in zip(data["calls"],children)
            map = call["original_to_reduced"]
            fixed = Dict(i=>incumbent[i] for i in 1:5 if !haskey(map,i))
            candidates = Vector{Int}[]
            for reduced in Iterators.product(fill(values,length(map))...)
                full = [haskey(fixed,i) ? fixed[i] : reduced[map[i]] for i in 1:5]
                @test QUBOTools.lift_state(collect(reduced),fixed,map,5) == full
                @test boundary_energy(first(child.log).objective,reduced) == energy(full)
                push!(candidates,full)
            end
            child_best = (sense === :min ? minimum : maximum)(energy(x) for x in candidates)
            row = only(child.rows)
            candidate = [haskey(fixed,i) ? fixed[i] : row[VI(call["source_to_child"][map[i]])] for i in 1:5]
            @test energy(candidate) == child_best
            if sense === :min ? child_best < energy(incumbent) : child_best > energy(incumbent)
                incumbent = candidate
            end
            @test call["committed_energy"] == energy(incumbent)
        end
        @test QUBOTools.state(opt,1) == incumbent
        @test QUBOTools.value(opt,1) == energy(incumbent)
        @test all(sense === :min ? diff(data["incumbent_energy_trace"]) .<= 0 :
            diff(data["incumbent_energy_trace"]) .>= 0)
        @test !data["separable_proof"]
    end
end

@testset "New selectors preserve caps, failures, interruption and heuristic status" begin
    model = graph_fixture(5, [(i,i+1) for i in 1:4]; bias=-3.0)
    for selection in (:bfs,:random_blocks)
        for (kwargs,completed,reason) in (((;max_child_calls=1),1,"max_child_calls"),
            ((;max_candidate_evaluations=2),1,"max_candidate_evaluations"),
            ((;max_sweeps=0),0,"max_sweeps"), ((;max_child_calls=0),0,"max_child_calls"))
            opt = solve_model(model; budget=2, selection, seed=41, kwargs...)
            @test decomposition(opt)["completed_calls"] == completed
            @test decomposition(opt)["completed_sweeps"] == 0
            @test decomposition(opt)["stop_reason"] == reason
            @test MOI.get(opt,MOI.TerminationStatus()) === MOI.ITERATION_LIMIT
            @test length(QUBOTools.state(opt,1)) == 5
        end
        one = solve_model(model; budget=2, selection, seed=41, max_child_calls=1)
        for phase in (:selection,:conditioning,:before_child,:reconstruct,:before_commit), timed in (false,true)
            opt = QUBODecomposition.Optimizer(; child_optimizer=()->FixtureChild(), max_variables=2, selection, seed=41)
            QUBODrivers.set_model!(opt,model)
            visits, ticks = Ref(0), Ref(0.0)
            opt.clock = () -> ticks[]
            timed && MOI.set(opt,MOI.TimeLimitSec(),1.0)
            opt.checkpoint = p -> begin
                if p === phase
                    visits[] += 1
                    visits[] == 2 && (timed ? (ticks[]=2.0) : throw(InterruptException()))
                end
                nothing
            end
            MOI.optimize!(opt)
            @test MOI.get(opt,MOI.TerminationStatus()) === (timed ? MOI.TIME_LIMIT : MOI.INTERRUPTED)
            @test decomposition(opt)["completed_calls"] == 1
            @test decomposition(opt)["completed_sweeps"] == 0
            @test QUBOTools.state(opt,1) == QUBOTools.state(one,1)
        end
        count = Ref(0)
        child = () -> FixtureChild(callback=_ -> (count[]+=1; count[]==2 && error("child failure")))
        opt = solve_model(model; budget=2, selection, seed=41, child)
        @test MOI.get(opt,MOI.TerminationStatus()) === MOI.OTHER_ERROR
        @test decomposition(opt)["completed_calls"] == 1
        @test decomposition(opt)["completed_sweeps"] == 0
        @test QUBOTools.state(opt,1) == QUBOTools.state(one,1)
        early = solve_model(model; budget=2, selection, seed=41, max_sweeps=1,
            child=()->FixtureChild(status=MOI.TIME_LIMIT))
        @test decomposition(early)["completed_sweeps"] == 1
        @test decomposition(early)["completed_calls"] > 1
        @test all(c["public_status"] == "TIME_LIMIT" for c in decomposition(early)["calls"])
        trap = graph_fixture(6, [(i,j) for i in 1:5 for j in i+1:6]; bias=1.0, weight=-2.0)
        trapped = solve_model(trap; budget=2, selection, seed=41, stagnation_sweeps=1)
        oracle(x) = sum(x)-2sum(x[i]*x[j] for i in 1:5 for j in i+1:6)
        @test minimum(oracle(x) for x in Iterators.product(fill((0,1),6)...)) == -24
        @test QUBOTools.value(trapped,1) == oracle(QUBOTools.state(trapped,1)) == 0
        @test MOI.get(trapped,MOI.TerminationStatus()) === MOI.LOCALLY_SOLVED
        @test !decomposition(trapped)["separable_proof"]
    end
end

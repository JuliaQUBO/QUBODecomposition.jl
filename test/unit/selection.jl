# SPDX-License-Identifier: MPL-2.0
@testset "Single-flip gains against independent scalar energies" begin
    for domain in (:bool, :spin), sense in (:min, :max), scale in (2.5, -1.5, 0.0)
        model = direct_model(; domain, sense, scale, offset=7.25)
        snap = QUBODecomposition.snapshot(model)
        energy(x) = scale * (7.25 - 3x[1] + 2x[2] - x[3] +
            4x[1]*x[2] - 2x[2]*x[3])
        values = domain === :bool ? (0, 1) : (-1, 1)
        for state in Iterators.product(fill(values, 4)...)
            x = collect(state)
            gains = QUBODecomposition.single_flip_gains(snap, x)
            for i in 1:4
                flipped = copy(x)
                flipped[i] = domain === :bool ? 1-x[i] : -x[i]
                delta = energy(flipped) - energy(x)
                @test gains[i] == (sense === :min ? -delta : delta)
            end
            @test gains[4] == 0 # zero-bias isolate
        end
        opt = solve_model(model; budget=1, selection=:single_flip_gain)
        @test QUBOTools.value(opt, 1) == energy(QUBOTools.state(opt, 1))
        trace = decomposition(opt)["incumbent_energy_trace"]
        @test all(sense === :min ? diff(trace) .<= 0 : diff(trace) .>= 0)
        @test length(QUBOTools.state(opt, 1)) == 4
        @test all(v -> v in values, QUBOTools.state(opt, 1))
    end
end

@testset "Selection configuration and unchanged control" begin
    opt = QUBODecomposition.Optimizer()
    attr = MOI.RawOptimizerAttribute("selection")
    @test MOI.supports(opt, attr)
    @test MOI.get(opt, attr) === :strongest_edge
    for invalid in (:bfs, :random, :gain, "single_flip_gain", nothing, 1)
        @test_throws ArgumentError MOI.set(opt, attr, invalid)
    end
    model = QUBOTools.Model{Int,Float64,Int}(collect(1:4), collect(1:4),
        [0.0,0.0,-5.0,-4.0], [1,2,3], [2,3,4], [10.0,0.5,0.5])
    default = solve_model(model; budget=2, max_child_calls=1)
    control = solve_model(model; budget=2, max_child_calls=1, selection=:strongest_edge)
    gain = solve_model(model; budget=2, max_child_calls=1, selection=:single_flip_gain)
    @test only(decomposition(default)["calls"])["selected_indices"] == [1,2]
    @test QUBOTools.state(default, 1) == QUBOTools.state(control, 1)
    @test only(decomposition(gain)["calls"])["selected_indices"] == [3,4]
    @test only(decomposition(gain)["calls"])["selected_gains"] == [5.0,4.0]
    @test QUBOTools.value(gain, 1) == -8.5 < QUBOTools.value(control, 1)
    MOI.set(gain, attr, :strongest_edge)
    @test MOI.get(gain, MOI.ResultCount()) == 0
    @test MOI.get(gain, MOI.TerminationStatus()) === MOI.OPTIMIZE_NOT_CALLED
end

@testset "Gain block coverage, ties and latest incumbent" begin
    # The sixth variable is an isolate. No single or joint selected flip improves.
    model = QUBOTools.Model{Symbol,Float64,Int}([:z,:b,:q,:a,:y,:isolate],
        Int[], Float64[], [1,2,3,4], [2,3,4,5], fill(0.5,4))
    for capacity in (1,2,4)
        opt = solve_model(model; budget=capacity, selection=:single_flip_gain,
            max_sweeps=3, stagnation_sweeps=2, seed=41)
        data = decomposition(opt)
        @test first(data["calls"])["selected_indices"] == [6]
        @test data["completed_sweeps"] == data["stagnation"] == 2
        @test MOI.get(opt, MOI.TerminationStatus()) === MOI.LOCALLY_SOLVED
        for sweep in 1:2
            calls = filter(c -> c["sweep"] == sweep, data["calls"])
            @test vcat([c["selected_indices"] for c in calls]...) == collect(1:5)
            @test length(calls) == cld(5, capacity)
            @test all(all(iszero, c["selected_gains"]) for c in calls)
            @test length(last(calls)["selected_indices"]) == mod1(5, capacity)
        end
        @test [c["seed"] for c in data["calls"]] == collect(41:40+data["attempted_calls"])
        @test !data["separable_proof"]
    end
    model = QUBOTools.Model{Int,Float64,Int}(collect(1:4), collect(1:4),
        [-5.0,-4.0,-3.0,-2.0], [1,2,3], [2,3,4], [10.0,0.5,0.5])
    opt = solve_model(model; budget=1, selection=:single_flip_gain, max_sweeps=1)
    calls = decomposition(opt)["calls"]
    @test [only(c["selected_indices"]) for c in calls] == [1,3,4,2]
    @test [only(c["selected_gains"]) for c in calls] == [5.0,3.0,1.5,-6.5]
    @test [c["conditioning_incumbent_version"] for c in calls] == [0,1,2,3]
    @test QUBOTools.state(opt, 1) == [1,0,1,1]
    # Repeated solve and a changed start must rebuild gains and coverage.
    MOI.optimize!(opt)
    @test [c["selected_indices"] for c in decomposition(opt)["calls"]] == [[1],[3],[4],[2]]
    QUBOTools.attach!(model, 1=>1)
    QUBODrivers.set_model!(opt, model)
    MOI.optimize!(opt)
    @test first(decomposition(opt)["calls"])["selected_indices"] == [3]
    fresh = solve_model(model; budget=1, selection=:single_flip_gain, max_sweeps=1)
    @test QUBOTools.state(opt, 1) == QUBOTools.state(fresh, 1)
    @test [c["selected_gains"] for c in decomposition(opt)["calls"]] ==
        [c["selected_gains"] for c in decomposition(fresh)["calls"]]
end

@testset "Nonpositive flip gains can yield a jointly improving block" begin
    model = QUBOTools.Model{Int,Float64,Int}([1,2,3], [1,2,3], [1.0,1.0,2.0],
        [1,2], [2,3], [-3.0,0.25])
    opt = solve_model(model; budget=2, selection=:single_flip_gain, max_sweeps=1)
    @test first(decomposition(opt)["calls"])["selected_gains"] == [-1.0,-1.0]
    @test QUBOTools.state(opt, 1) == [1,1,0]
    @test QUBOTools.value(opt, 1) == -1.0
    @test MOI.get(opt, MOI.TerminationStatus()) === MOI.ITERATION_LIMIT
    @test !decomposition(opt)["separable_proof"]
end

@testset "Numerically equal signed-zero gains tie by original index" begin
    for domain in (:bool, :spin), sense in (:min, :max), scale in (2.5, -1.5)
        spin = domain === :spin
        state = spin ? [-1,1,-1] : [0,1,0]
        middle_bias = spin ? 2.0 : 0.0
        model = QUBOTools.Model{Int,Float64,Int}([1,2,3], [1,2,3],
            [-1.0,middle_bias,-1.0], [1,2], [2,3], [1.0,1.0];
            domain, sense, scale, offset=7.25)
        for i in 1:3
            QUBOTools.attach!(model, i=>state[i])
        end
        energy(x) = scale*(7.25-x[1]+middle_bias*x[2]-x[3]+x[1]*x[2]+x[2]*x[3])
        for i in 1:3
            flipped = copy(state)
            flipped[i] = spin ? -state[i] : 1-state[i]
            @test energy(flipped) == energy(state)
        end
        snap = QUBODecomposition.snapshot(model)
        gains = QUBODecomposition.single_flip_gains(snap, state)
        @test all(iszero, gains)
        @test first(QUBODecomposition.gain_neighborhood(snap, state, Set(1:3), 2)) == [1,2]
        opt = solve_model(model; budget=1, selection=:single_flip_gain, max_child_calls=1)
        @test only(decomposition(opt)["calls"])["selected_indices"] == [1]
        @test QUBOTools.state(opt, 1) == state
    end
end

@testset "Gain selection preserves transactions and limits" begin
    model = QUBOTools.Model{Int,Float64,Int}(collect(1:4), collect(1:4),
        [-5.0,-4.0,-3.0,-2.0], [1,2,3], [2,3,4], [10.0,0.5,0.5])
    for (kwargs, completed, reason) in (( (;max_child_calls=1), 1, "max_child_calls"),
        ((;max_candidate_evaluations=2), 1, "max_candidate_evaluations"),
        ((;max_sweeps=0), 0, "max_sweeps"))
        opt = solve_model(model; budget=1, selection=:single_flip_gain, kwargs...)
        @test decomposition(opt)["completed_calls"] == completed
        @test decomposition(opt)["completed_sweeps"] == 0
        @test decomposition(opt)["stop_reason"] == reason
        @test MOI.get(opt, MOI.TerminationStatus()) === MOI.ITERATION_LIMIT
        @test length(QUBOTools.state(opt, 1)) == 4
    end
    for phase in (:selection, :conditioning, :before_child, :reconstruct, :before_commit)
        for timed in (false, true)
            opt = QUBODecomposition.Optimizer(child_optimizer=()->FixtureChild(),
                max_variables=1, selection=:single_flip_gain)
            QUBODrivers.set_model!(opt, model)
            ticks, visits = Ref(0.0), Ref(0)
            opt.clock = () -> ticks[]
            timed && MOI.set(opt, MOI.TimeLimitSec(), 1.0)
            opt.checkpoint = p -> begin
                if p === phase
                    visits[] += 1
                    if visits[] == 2
                        timed ? (ticks[]=2.0) : throw(InterruptException())
                    end
                end
                nothing
            end
            MOI.optimize!(opt)
            @test MOI.get(opt, MOI.TerminationStatus()) === (timed ? MOI.TIME_LIMIT : MOI.INTERRUPTED)
            @test decomposition(opt)["completed_calls"] == 1
            @test decomposition(opt)["completed_sweeps"] == 0
            @test QUBOTools.state(opt, 1) == [1,0,0,0]
            @test QUBOTools.value(opt, 1) == -5.0
        end
    end
    count = Ref(0)
    child = () -> FixtureChild(callback=_ -> (count[] += 1; count[] == 2 && error("child failure")))
    opt = solve_model(model; budget=1, selection=:single_flip_gain, child)
    @test MOI.get(opt, MOI.TerminationStatus()) === MOI.OTHER_ERROR
    @test decomposition(opt)["completed_calls"] == 1
    @test decomposition(opt)["completed_sweeps"] == 0
    @test QUBOTools.state(opt, 1) == [1,0,0,0]
    @test QUBOTools.value(opt, 1) == -5.0
end

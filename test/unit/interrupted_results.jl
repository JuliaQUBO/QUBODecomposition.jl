# SPDX-License-Identifier: MPL-2.0
@testset "Normally returned interruption preserves an improving child" begin
    opt = solve_model(direct_model(); child=()->FixtureChild(
        rows=[[1,0,1,0]], values=[900.0], status=MOI.INTERRUPTED))
    @test MOI.get(opt,MOI.TerminationStatus()) === MOI.INTERRUPTED
    @test QUBOTools.state(opt,1) == [1,0,1,0]
    @test QUBOTools.value(opt,1) == 2.0 # 2*(5 - 3 - 1), independently evaluated
    @test decomposition(opt)["candidate_evaluations"] == 2
end

@testset "Interrupted result validation, strict acceptance and frame conversion" begin
    initial = zeros(Int,4)
    for rows in (Any[], [[0,0,0,1]], [[0,1,0,0]])
        opt = solve_model(direct_model(); child=()->FixtureChild(;rows,status=MOI.INTERRUPTED))
        data = decomposition(opt); call = only(data["calls"])
        @test QUBOTools.state(opt,1) == initial
        @test QUBOTools.value(opt,1) == 10.0
        @test MOI.get(opt,MOI.TerminationStatus()) === MOI.INTERRUPTED
        @test data["stop_reason"] == "child_interrupted"
        @test data["completed_calls"] == 1 && !data["incomplete_scan"]
        @test call["reported_results"] == call["valid_results"] == length(rows)
        @test call["public_status"] == "INTERRUPTED" && !call["exact"]
        @test data["accepted_improvements"] == 0
    end
    opt = solve_model(direct_model(); child=()->FixtureChild(
        rows=[[1,0,0,0],[1,0,1,1],[1,0,1,0]],values=[-1000.,1000.,17.],status=MOI.INTERRUPTED))
    @test QUBOTools.state(opt,1) == [1,0,1,0]
    @test QUBOTools.value(opt,1) == 2.0
    @test decomposition(opt)["candidate_evaluations"] == 4
    @test decomposition(opt)["accepted_improvements"] == 1
    @test only(decomposition(opt)["calls"])["valid_results"] == 3
    @test !only(decomposition(opt)["calls"])["exact"]

    # Independent original-objective oracle; shifted/reversed fixture MOI indices
    # and nonalphabetical labels exercise the existing copy/reconstruction path.
    for domain in (:bool,:spin), sense in (:min,:max), scale in (-2.5,1.5)
        low = domain === :bool ? 0 : -1
        scalar(x) = scale*(5 - 3x[1] + 2x[2] - x[3] + 4x[1]*x[2] - 2x[2]*x[3])
        states = vec([collect(x) for x in Iterators.product(fill((low,1),4)...)])
        sort!(states; by=x->((sense === :min ? 1 : -1)*scalar(x),Tuple(x)))
        best = first(states)
        @test scalar(best) != scalar(fill(low,4))
        opt = solve_model(direct_model(;labels=[:z,:a,:q,:unused],domain,sense,scale);
            child=()->FixtureChild(rows=[best],values=[900.],status=MOI.INTERRUPTED))
        @test QUBOTools.state(opt,1) == best
        @test QUBOTools.value(opt,1) == scalar(best)
        @test MOI.get(opt,MOI.TerminationStatus()) === MOI.INTERRUPTED
        @test decomposition(opt)["labels"] == [:z,:a,:q,:unused]
        @test only(decomposition(opt)["calls"])["source_to_child"] == [11,10,9,8]
    end

    for child in (
        ()->FixtureChild(rows=[[1,0,1,0],[1,0,1,2]],status=MOI.INTERRUPTED),
        ()->FixtureChild(rows=[[1,0,1,0],[1,0,1]],status=MOI.INTERRUPTED),
        ()->FixtureChild(rows=[[1,0,1,0],[1,0,1,NaN]],status=MOI.INTERRUPTED),
        ()->FixtureChild(rows=[[1,0,1,0],[1,0,1,0]],values=[0.,Inf],status=MOI.INTERRUPTED),
        ()->FixtureChild(rows=[[1,0,1,0]],row_status=MOI.NO_SOLUTION,status=MOI.INTERRUPTED),
        ()->FixtureChild(corrupt_map=true,status=MOI.INTERRUPTED))
        opt = solve_model(direct_model();child)
        @test MOI.get(opt,MOI.TerminationStatus()) === MOI.OTHER_ERROR
        @test QUBOTools.state(opt,1) == initial
        @test decomposition(opt)["completed_calls"] == 0
    end
    for result_count in (-1,true,1.0,NaN)
        opt = solve_model(direct_model();child=()->FixtureChild(;result_count,status=MOI.INTERRUPTED))
        @test MOI.get(opt,MOI.TerminationStatus()) === MOI.OTHER_ERROR
        @test QUBOTools.state(opt,1) == initial
        @test only(decomposition(opt)["calls"])["public_status"] == "INTERRUPTED"
    end
end

@testset "Interrupted calls obey scan and commit limits without salvage" begin
    for cap in (2,3)
        opt = solve_model(direct_model();max_candidate_evaluations=cap,
            child=()->FixtureChild(rows=[[1,0,0,0],[1,0,1,0]],status=MOI.INTERRUPTED))
        data = decomposition(opt)
        @test data["candidate_evaluations"] == cap
        @test MOI.get(opt,MOI.TerminationStatus()) === (cap == 2 ? MOI.ITERATION_LIMIT : MOI.INTERRUPTED)
        @test QUBOTools.state(opt,1) == (cap == 2 ? zeros(Int,4) : [1,0,1,0])
        @test data["incomplete_scan"] == (cap == 2)
        @test only(data["calls"])["public_status"] == "INTERRUPTED"
    end
    for phase in (:after_child,:before_row,:reconstruct,:before_commit)
        now = Ref(0.0); visits = Ref(0)
        opt = QUBODecomposition.Optimizer(max_variables=4,child_optimizer=()->FixtureChild(
            rows=[[1,0,0,0],[1,0,1,0]],status=MOI.INTERRUPTED))
        QUBODrivers.set_model!(opt,direct_model()); opt.clock=()->now[]
        opt.checkpoint=p->begin
            if p === phase
                visits[] += 1
                (phase !== :before_row || visits[] == 2) && (now[]=1.0)
            end
        end
        MOI.set(opt,MOI.TimeLimitSec(),1.0); MOI.optimize!(opt)
        data = decomposition(opt)
        @test MOI.get(opt,MOI.TerminationStatus()) === MOI.TIME_LIMIT
        @test data["stop_reason"] == "parent_time_limit"
        @test QUBOTools.state(opt,1) == zeros(Int,4)
        @test only(data["calls"])["public_status"] == "INTERRUPTED"
        @test data["completed_calls"] == 0 && data["incomplete_scan"]
        @test data["candidate_evaluations"] <= 3
    end
    for failure in (InterruptException(), ErrorException("failed invocation"))
        child = FixtureChild(rows=[[1,0,1,0]],status=MOI.INTERRUPTED,
            callback=_->throw(failure))
        opt = solve_model(direct_model();child=()->child)
        @test MOI.get(opt,MOI.TerminationStatus()) ===
            (failure isa InterruptException ? MOI.INTERRUPTED : MOI.OTHER_ERROR)
        @test QUBOTools.state(opt,1) == zeros(Int,4)
        @test only(decomposition(opt)["calls"])["public_status"] === nothing
        @test only(decomposition(opt)["calls"])["valid_results"] == 0
    end
end

@testset "Serial interruption stops dispatch and preserves earlier certificates" begin
    model = QUBOTools.Model{Symbol,Float64,Int}([:z,:a,:q],[1,2,3],[-1.,-2.,-3.],
        Int[],Int[],Float64[])
    calls = Ref(0)
    factory = ()->begin
        calls[] += 1
        FixtureChild(rows=[[1]],status=calls[] == 2 ? MOI.INTERRUPTED : MOI.OPTIMAL)
    end
    opt = solve_model(model;child=factory,budget=1,strategy=:components,max_child_calls=2,max_candidate_evaluations=3)
    data = decomposition(opt)
    @test calls[] == data["attempted_calls"] == data["completed_calls"] == 2
    @test QUBOTools.state(opt,1) == [1,1,0] && QUBOTools.value(opt,1) == -3.0
    @test data["accepted_improvements"] == 2
    @test data["component_exact"] == [true,false,false] && !data["separable_proof"]
    @test [c["exact"] for c in data["calls"]] == [true,false]
    @test MOI.get(opt,MOI.TerminationStatus()) === MOI.INTERRUPTED
    @test data["stop_reason"] == "child_interrupted"

    calls[] = 0
    opt = solve_model(direct_model();budget=1,child=()->begin
        calls[] += 1
        calls[] == 1 ? FixtureChild() : FixtureChild(rows=[[1]],status=MOI.INTERRUPTED)
    end)
    @test calls[] == 2
    @test last(decomposition(opt)["calls"])["kind"] == "neighborhood"
    @test QUBOTools.state(opt,1) == [1,0,0,0] && QUBOTools.value(opt,1) == 4.0
    @test MOI.get(opt,MOI.TerminationStatus()) === MOI.INTERRUPTED
    @test decomposition(opt)["started_sweeps"] == 1 && decomposition(opt)["completed_sweeps"] == 0

    interrupted = Ref(true)
    opt = solve_model(direct_model();child=()->FixtureChild(
        rows=interrupted[] ? [[1,0,1,0]] : [],status=MOI.INTERRUPTED))
    previous = decomposition(opt)
    interrupted[] = false; MOI.optimize!(opt)
    data = decomposition(opt)
    @test QUBOTools.state(opt,1) == zeros(Int,4) && QUBOTools.value(opt,1) == 10.0
    @test data["invocation"] == 2 && data["attempted_calls"] == data["completed_calls"] == 1
    @test data["candidate_evaluations"] == 1 && data["accepted_improvements"] == 0
    @test only(data["calls"])["valid_results"] == 0
    @test previous["accepted_improvements"] == 1
end

@testset "Interrupted separator and voting scratch work rolls back" begin
    model = QUBOTools.Model{Symbol,Float64,Int}([:root,:left,:right], [1,2,3], [2.,-1.,-1.],
        [1,1],[2,3],[-4.,-4.])
    calls = Ref(0)
    opt = solve_model(model;budget=1,strategy=:separator,separator=[1],child=()->begin
        calls[] += 1
        FixtureChild(status=calls[] == 4 ? MOI.INTERRUPTED : MOI.OPTIMAL)
    end)
    data = decomposition(opt); proof = data["separator"]
    @test calls[] == 4 && data["completed_calls"] == 4
    @test QUBOTools.state(opt,1) == [0,1,1] && QUBOTools.value(opt,1) == -2.0
    @test proof["completed_branches"] == proof["certified_branches"] == 1
    @test proof["component_certificates"] == [2,1]
    @test !proof["proof_complete"] && !last(data["calls"])["exact"]
    @test !last(data["calls"])["accepted_to_working"]
    @test last(data["calls"])["proposal_energy"] == -8.0
    @test MOI.get(opt,MOI.TerminationStatus()) === MOI.INTERRUPTED

    # Proposal failure after earlier valid proposals; repair failure after a full
    # electorate. Both routes must retain the frozen global assignment.
    for interrupted_call in (2,4), empty_results in (false,true)
        calls[] = 0
        proposals = ([[1,1]],[[0,1]],[[0,1]],[[1]])
        run = batch_harness(voting_fixture(),[[1,2],[2,3],[2,4]];child=()->begin
            calls[] += 1
            status = calls[] == interrupted_call ? MOI.INTERRUPTED : MOI.LOCALLY_SOLVED
            rows = empty_results && calls[] == interrupted_call ? [] : proposals[calls[]]
            FixtureChild(;rows,status)
        end)
        @test run.failure isa QUBODecomposition.StopSolve && run.failure.status === MOI.INTERRUPTED
        @test run.failure.reason == "child_interrupted"
        @test calls[] == run.data["attempted_calls"] == run.data["completed_calls"] == interrupted_call
        @test run.ctx.state == zeros(Int,4) && run.ctx.energy == 0.0
        @test !only(run.data["batches"])["complete"] && !only(run.data["batches"])["accepted"]
        @test !last(run.data["calls"])["accepted_to_working"] && !last(run.data["calls"])["exact"]
        @test only(run.data["batches"])["repair_completed_blocks"] == 0
        @test last(run.data["calls"])["valid_results"] == (empty_results ? 0 : 1)
    end
end

# SPDX-License-Identifier: MPL-2.0
@testset "Row 19: reused compiler/composite coefficients, maps and caches" begin
    f=binary_fixture()
    JuMP.set_attribute(f.model,TA.MaxPenaltyUpdates(),5)
    MOI.Utilities.reset_optimizer(f.model)
    JuMP.optimize!(f.model)
    oldreport=ToQUBO.feasibility_report(f.model)
    @test oldreport.feasible_count==1
    @test MOI.get(f.compiler,TA.ConstraintEncodingPenaltyHint(),JuMP.index(f.c))==-10
    # Refined attributes intentionally persist in 0.7; reset explicitly.
    JuMP.set_attribute(f.c,TA.ConstraintEncodingPenaltyHint(),-0.1)
    JuMP.set_attribute(f.model,TA.MaxPenaltyUpdates(),0)
    JuMP.@objective(f.model,Max,9+4*f.x[1]+2*f.x[2])
    MOI.Utilities.reset_optimizer(f.model)
    JuMP.optimize!(f.model)
    @test JuMP.value.(f.x)==[1,1]
    assert_source_result(f,15,1)
    @test ToQUBO.feasibility_report(f.model).feasible_count==0
    @test ToQUBO.feasibility_report(f.model)!==oldreport
    current=last(f.capture.log)
    fresh=binary_fixture()
    JuMP.@objective(fresh.model,Max,9+4*fresh.x[1]+2*fresh.x[2])
    JuMP.optimize!(fresh.model)
    @test isapprox(current.f,only(fresh.capture.log).f)
    @test current.meta==only(fresh.capture.log).meta
    @test current.state==only(fresh.capture.log).state
    @test current.data["invocation"]==4
    @test current.data["attempted_calls"]==1
    @test current.f!=first(f.capture.log).f

    # Rebuild the source through public construction, keeping the exact same
    # compiler/composite objects. Swap source index ownership at equal bit count,
    # then change encoding and dimensions. Compare each with a fresh instance.
    function populate!(m; reverse=false, unary=false)
        JuMP.empty!(m)
        JuMP.set_attribute(m,TA.StableCompilation(),true)
        JuMP.set_attribute(m,TA.MaxPenaltyUpdates(),0)
        if reverse
            b=JuMP.@variable(m,b,Bin); z=JuMP.@variable(m,0<=z<=3,Int)
        else
            z=JuMP.@variable(m,0<=z<=3,Int); b=JuMP.@variable(m,b,Bin)
        end
        JuMP.set_attribute(z,TA.VariableEncodingMethod(),unary ? ToQUBO.Encoding.Unary() : ToQUBO.Encoding.Binary())
        JuMP.@objective(m,Max,7+2*z+b)
        c=JuMP.@constraint(m,z+2*b<=3)
        # Explicitly replace the persistent hint from the earlier binary model.
        JuMP.set_attribute(c,TA.ConstraintEncodingPenaltyHint(),-10.0)
        return z,b,c
    end
    previous=nothing
    for (reverse,unary) in ((false,false),(true,false),(true,true),(false,false))
        z,b,c=populate!(f.model;reverse,unary)
        MOI.Utilities.reset_optimizer(f.model)
        JuMP.optimize!(f.model)
        g=compiler_fixture();zz,bb,cc=populate!(g.model;reverse,unary);JuMP.optimize!(g.model)
        a,h=last(f.capture.log),only(g.capture.log)
        assert_bit_inventory(a)
        @test isapprox(a.f,h.f) && a.meta==h.meta && a.state==h.state
        @test a.data["components"]==h.data["components"]
        @test a.data["component_exact"]==h.data["component_exact"]
        @test a.data["attempted_calls"]==1
        @test JuMP.value(z)+2*JuMP.value(b)<=3
        @test ToQUBO.source_objective_value(f.model)==7+2*JuMP.value(z)+JuMP.value(b)==13
        @test ToQUBO.feasibility_report(f.model).feasible_count==1
        if previous!==nothing && !unary && reverse
            @test length(a.vars)==length(previous.vars)
            @test a.meta["original_variables"]!=previous.meta["original_variables"]
        end
        previous=a
    end
end

@testset "Row 19: failed/limited reuse and transactional source feasibility" begin
    mode=Ref(:exact); count=Ref(0); childlog=Any[]
    factory=()->begin
        count[]+=1
        if mode[]==:missing
            FixtureChild(;rows=[[1]],status=MOI.TIME_LIMIT,log=childlog)
        elseif mode[]==:failure && count[]==2
            FixtureChild(;rows=[],status=MOI.OTHER_ERROR,log=childlog)
        else
            FixtureChild(;log=childlog)
        end
    end
    f=binary_fixture(;budget=2,child=factory)
    MOI.Utilities.reset_optimizer(f.model)
    JuMP.optimize!(f.model)
    @test JuMP.value.(f.x)==[1,1]
    @test JuMP.primal_status(f.model)==MOI.INFEASIBLE_POINT
    mode[]=:missing;count[]=0
    MOI.Utilities.reset_optimizer(f.model)
    JuMP.optimize!(f.model)
    @test JuMP.termination_status(f.model)==MOI.OTHER_ERROR
    @test JuMP.value.(f.x)==[0,0] # legitimate initial incumbent, no fabricated child bit
    @test last(f.capture.log).data["completed_calls"]==0
    assert_source_result(f,5,-1)
    @test !last(f.capture.log).data["separable_proof"]
    mode[]=:failure;count[]=0
    MOI.Utilities.reset_optimizer(f.model)
    JuMP.optimize!(f.model)
    call=last(f.capture.log)
    @test JuMP.termination_status(f.model)==MOI.OTHER_ERROR
    @test call.data["completed_calls"]==1
    @test JuMP.value.(f.x)==[1,1] # earlier committed neighborhood survives
    assert_source_result(f,11,1)
    @test !call.data["separable_proof"]
    mode[]=:exact;count[]=0
    JuMP.set_attribute(f.c,TA.ConstraintEncodingPenaltyHint(),-10)
    JuMP.set_attribute(f.model,MOI.RawOptimizerAttribute("max_child_calls"),0)
    MOI.Utilities.reset_optimizer(f.model)
    JuMP.optimize!(f.model)
    @test JuMP.termination_status(f.model)==MOI.ITERATION_LIMIT
    @test last(f.capture.log).data["attempted_calls"]==0
    @test JuMP.value.(f.x)==[0,0]
    assert_source_result(f,5,-1)
    JuMP.set_attribute(f.model,MOI.RawOptimizerAttribute("max_child_calls"),1000)
    MOI.Utilities.reset_optimizer(f.model)
    JuMP.optimize!(f.model)
    @test JuMP.termination_status(f.model)==MOI.LOCALLY_SOLVED
    @test ToQUBO.is_feasible(f.model)
    @test last(f.capture.log).data["candidate_evaluations"]>1
    @test !last(f.capture.log).data["separable_proof"]
    # A zero candidate cap invalidates prior results and feasibility reports.
    JuMP.set_attribute(f.model,MOI.RawOptimizerAttribute("max_candidate_evaluations"),0)
    MOI.Utilities.reset_optimizer(f.model)
    JuMP.optimize!(f.model)
    @test JuMP.result_count(f.model)==0
    @test JuMP.primal_status(f.model)==MOI.NO_SOLUTION
    @test_throws "No primal results are available" ToQUBO.feasibility_report(f.model)
end

@testset "Row 20: automatic refinement is a solve-count scope" begin
    for updates in (0,1,2,5)
        f=binary_fixture(;seed=93)
        JuMP.set_attribute(f.model,TA.MaxPenaltyUpdates(),updates)
        MOI.Utilities.reset_optimizer(f.model)
        JuMP.optimize!(f.model)
        expected=min(updates,2)
        @test MOI.get(f.compiler,TA.PenaltyUpdateCount())==expected
        @test length(f.capture.log)==1+expected<=1+updates
        @test all(c.data["attempted_calls"]==1 && c.data["candidate_evaluations"]==2 for c in f.capture.log)
        @test all(only(c.data["calls"])["seed"]==93 for c in f.capture.log)
        @test [c.data["invocation"] for c in f.capture.log]==collect(1:1+expected)
        @test ToQUBO.is_feasible(f.model)==(updates>=2)
    end
    # Already-feasible, no-result and unupdatable cases stop before the cap.
    f=binary_fixture();JuMP.set_attribute(f.c,TA.ConstraintEncodingPenaltyHint(),-10)
    JuMP.set_attribute(f.model,TA.MaxPenaltyUpdates(),5);JuMP.optimize!(f.model)
    @test length(f.capture.log)==1 && MOI.get(f.compiler,TA.PenaltyUpdateCount())==0
    for option in (:zero_time,:zero_candidates)
        g=binary_fixture()
        JuMP.set_attribute(g.model,TA.MaxPenaltyUpdates(),5)
        if option==:zero_time
            JuMP.set_attribute(g.model,MOI.TimeLimitSec(),0.0)
        else
            JuMP.set_attribute(g.model,MOI.RawOptimizerAttribute("max_candidate_evaluations"),0)
        end
        JuMP.optimize!(g.model)
        @test length(g.capture.log)==1 && MOI.get(g.compiler,TA.PenaltyUpdateCount())==0
        @test JuMP.result_count(g.model)==0
        @test JuMP.termination_status(g.model)==(option==:zero_time ? MOI.TIME_LIMIT : MOI.ITERATION_LIMIT)
    end
    g=binary_fixture()
    JuMP.set_attribute(g.model,TA.MaxPenaltyUpdates(),5)
    JuMP.set_attribute(g.model,TA.PenaltyUpdateStrategy(),TA.SubgradientUpdate())
    JuMP.optimize!(g.model)
    @test length(g.capture.log)==1 && !ToQUBO.is_feasible(g.model)

    # The child TIME_LIMIT status does not end refinement if a complete result
    # remains source-infeasible. Each invocation has a new parent deadline and
    # seed/counters. No sleep; the child's callback advances a controlled clock.
    now=Ref(0.0);childlog=Any[]
    g=binary_fixture(;child=()->FixtureChild(;rows=[[1,1,0]],status=MOI.TIME_LIMIT,
        callback=_->(now[]+=0.4),log=childlog,limit=0.2),seed=17,child_time_limit_sec=0.3)
    g.composite.clock=()->now[]
    compilation_times=Float64[]
    g.capture.before_solve=()->push!(compilation_times,MOI.get(g.compiler,TA.CompilationTime()))
    JuMP.set_attribute(g.model,MOI.TimeLimitSec(),0.5)
    JuMP.set_attribute(g.model,TA.MaxPenaltyUpdates(),3)
    JuMP.optimize!(g.model)
    @test length(g.capture.log)==4
    @test MOI.get(g.compiler,TA.PenaltyUpdateCount())==3
    @test now[]≈1.6 # more than a single 0.5 s allowance
    @test JuMP.termination_status(g.model)==MOI.TIME_LIMIT
    @test JuMP.primal_status(g.model)==MOI.INFEASIBLE_POINT
    @test all(c.data["completed_calls"]==1 && c.data["attempted_calls"]==1 for c in g.capture.log)
    @test all(e.seed==17 && e.limit==0.2 for e in childlog if hasproperty(e,:seed))
    @test all(c.data["parent_overrun_sec"]==0 for c in g.capture.log)
    @test MOI.get(g.compiler,MOI.SolveTimeSec())==QUBODrivers.effective_time(g.composite)
    @test length(compilation_times)==4
    @test all(t>=0 for t in compilation_times)
    @test MOI.get(g.compiler,TA.CompilationTime())==last(compilation_times)
    @test MOI.get(g.compiler,TA.CompilationTime())!=sum(compilation_times)

    # ExactSampler returns every row: initial evaluation + all 2^3 candidates.
    for cap in (8,9)
        h=binary_fixture(;child=()->QUBODrivers.ExactSampler.Optimizer(),max_candidate_evaluations=cap)
        JuMP.optimize!(h.model)
        call=only(h.capture.log)
        @test call.data["candidate_evaluations"]==cap
        @test call.status==(cap==8 ? MOI.ITERATION_LIMIT : MOI.LOCALLY_SOLVED)
        @test call.data["incomplete_scan"]==(cap==8)
        @test JuMP.value.(h.x)==(cap==8 ? [0,0] : [1,1])
    end
    # Serial repeated children obey one invocation's call cap and seed sequence.
    h=binary_fixture(;budget=2,seed=23,max_child_calls=2)
    JuMP.optimize!(h.model)
    call=only(h.capture.log)
    @test call.status==MOI.ITERATION_LIMIT
    @test call.data["attempted_calls"]==call.data["completed_calls"]==2
    @test [c["seed"] for c in call.data["calls"]]==[23,24]
end

include("../../examples/toqubo/deadline.jl")
@testset "Row 20: explicit outer absolute deadline, compilation and checking" begin
    now=Ref(0.0);log=Any[]
    # Each compile costs 0.2, each complete solve 0.25, checking costs 0.15.
    checkpoint=p->(p==:compiled ? (now[]+=0.2) : p==:checked ? (now[]+=0.15) : nothing)
    child=()->FixtureChild(;callback=_->(now[]+=0.25),log,
        rows=[[1,1,0]],status=MOI.TIME_LIMIT)
    result=DeadlineExample.run(;seconds=1.1,budget=8,clock=()->now[],checkpoint,child)
    @test result.reason==:deadline
    @test length(result.dispatched_limits)==2
    @test result.dispatched_limits≈[0.9,0.3]
    @test now[]≈1.2
    @test length(result.history)==2
    @test all(h.residual==1 && h.source_value==11 for h in result.history)
    @test [e.limit for e in log if hasproperty(e,:limit)]≈[0.9,0.3]
    now[]=0;empty!(log)
    result=DeadlineExample.run(;seconds=0.1,clock=()->now[],checkpoint,child)
    @test result.reason==:deadline && isempty(result.dispatched_limits) && isempty(log)
    now[]=0;empty!(log)
    overrun=()->FixtureChild(;callback=_->(now[]+=2.0),log)
    result=DeadlineExample.run(;seconds=1.0,clock=()->now[],checkpoint,child=overrun)
    @test result.reason==:deadline
    @test length(result.dispatched_limits)==1
    @test only(result.history).status==MOI.TIME_LIMIT
    @test now[]>result.deadline
end

@testset "Row 19 residual: ordinary ToQUBO 0.7.0 recompile retains target bits" begin
    # No reset here: this is the upstream regression, not the workaround above.
    f=binary_fixture()
    JuMP.optimize!(f.model)
    JuMP.optimize!(f.model)
    a,b=f.capture.log
    @test length(a.vars)==3
    @test_broken length(b.vars)==length(a.vars)
    @test length(b.vars)==4
    @test length(b.state)==4 # composite accounts for the extra bit, never drops it
    @test b.energy≈10.9
    @test JuMP.value.(f.x)==[1,1]
    @test JuMP.primal_status(f.model)==MOI.INFEASIBLE_POINT
    MOI.Utilities.reset_optimizer(f.model)
    JuMP.optimize!(f.model)
    @test length(last(f.capture.log).vars)==3
end

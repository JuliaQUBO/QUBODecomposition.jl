# SPDX-License-Identifier: MPL-2.0
@testset "Caller-owned absolute deadline" begin
    attr = MOI.RawOptimizerAttribute("absolute_deadline_sec")
    opt = QD.Optimizer()
    @test MOI.supports(opt, attr)
    @test MOI.get(opt, attr) === nothing
    for invalid in (true, -1., Inf, NaN, "1")
        @test_throws ArgumentError MOI.set(opt, attr, invalid)
    end
    # Same deadline survives delayed input preparation and repeated solves.
    jobs = QD.ComponentJob[]
    deadline = time_ns()/1e9 + 1000.
    opt = QD.Optimizer(child_optimizer=job->(push!(jobs,job);FixtureChild()),
        max_variables=2, strategy=:components,
        component_executor=QD.SequentialComponentExecutor(), absolute_deadline_sec=deadline)
    QUBODrivers.set_model!(opt,disconnected_fixture())
    for _ in 1:2
        MOI.optimize!(opt)
        @test MOI.get(opt,MOI.TerminationStatus()) == MOI.OPTIMAL
        @test decomposition(opt)["effective_deadline_sec"] == deadline
    end
    @test all(j.deadline == deadline for j in jobs)
    now = Ref(deadline)
    opt.clock = ()->now[]
    MOI.optimize!(opt)
    @test MOI.get(opt,MOI.TerminationStatus()) == MOI.TIME_LIMIT
    @test MOI.get(opt,MOI.ResultCount()) == 0
    @test length(jobs) == 6
    MOI.set(opt,attr,nothing)
    @test MOI.get(opt,attr) === nothing
    # The earlier of a relative and absolute limit wins, with no rebasing.
    for (absolute,relative,effective) in ((12.,5.,12.),(20.,5.,15.),(12.,nothing,12.))
        opt = QD.Optimizer(child_optimizer=()->FixtureChild(),max_variables=4,
            absolute_deadline_sec=absolute)
        QUBODrivers.set_model!(opt,direct_model())
        opt.clock = ()->10.
        MOI.set(opt,MOI.TimeLimitSec(),relative)
        MOI.optimize!(opt)
        @test decomposition(opt)["effective_deadline_sec"] == effective
        @test MOI.get(opt,MOI.TerminationStatus()) == MOI.OPTIMAL
    end
    # Expiry at each parent phase retains the committed initial state.
    for phase in (:after_child,:before_row,:reconstruct,:before_commit)
        now = Ref(time_ns()/1e9)
        opt = QD.Optimizer(child_optimizer=()->FixtureChild(),max_variables=2,
            strategy=:components,component_executor=QD.SequentialComponentExecutor(),
            absolute_deadline_sec=now[]+1000.)
        QUBODrivers.set_model!(opt,disconnected_fixture())
        opt.clock = ()->now[]
        opt.checkpoint = p->(p === phase ? (now[]+=2000.) : nothing)
        MOI.optimize!(opt)
        @test MOI.get(opt,MOI.TerminationStatus()) == MOI.TIME_LIMIT
        @test QUBOTools.state(opt,1) == zeros(Int,5)
        @test !decomposition(opt)["separable_proof"]
        @test decomposition(opt)["completed_calls"] == 0
    end
end

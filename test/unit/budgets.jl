# SPDX-License-Identifier: MPL-2.0
@testset "Work caps, scripted deadlines, interruption and seed forwarding" begin
    for cap in (0,1,2,3)
        opt=solve_model(direct_model();max_candidate_evaluations=cap)
        @test decomposition(opt)["candidate_evaluations"]<=cap
        @test MOI.get(opt,MOI.TerminationStatus())== (cap>=2 ? MOI.OPTIMAL : MOI.ITERATION_LIMIT)
        @test MOI.get(opt,MOI.ResultCount())==(cap==0 ? 0 : 1)
    end
    opt=solve_model(direct_model();max_child_calls=0)
    @test decomposition(opt)["attempted_calls"]==0
    @test MOI.get(opt,MOI.TerminationStatus())===MOI.ITERATION_LIMIT
    opt=solve_model(direct_model();max_candidate_evaluations=2,child=() -> FixtureChild(;rows=[[1,0,1,0],[1,0,1,1]]))
    @test MOI.get(opt,MOI.TerminationStatus())===MOI.ITERATION_LIMIT
    @test decomposition(opt)["incomplete_scan"]
    @test QUBOTools.state(opt,1)==zeros(Int,4)
    now=Ref(0.0);calls=Ref(0)
    opt=QUBODecomposition.Optimizer(;child_optimizer=() -> (calls[]+=1;FixtureChild()),max_variables=4)
    QUBODrivers.set_model!(opt,direct_model());opt.clock=()->now[]
    MOI.set(opt,MOI.TimeLimitSec(),0.0);MOI.optimize!(opt)
    @test calls[]==0
    @test MOI.get(opt,MOI.TerminationStatus())===MOI.TIME_LIMIT
    @test MOI.get(opt,MOI.ResultCount())==0
    @test MOI.get(opt,MOI.PrimalStatus())===MOI.NO_SOLUTION
    for time_supported in (true,false)
        now[]=0.0;log=Any[]
        factory=() -> FixtureChild(;callback=_ -> (now[]=3.0), time_supported,log,limit=0.75)
        opt=QUBODecomposition.Optimizer(;child_optimizer=factory,max_variables=4,child_time_limit_sec=1.0)
        QUBODrivers.set_model!(opt,direct_model());opt.clock=()->now[]
        MOI.set(opt,MOI.TimeLimitSec(),2.0);MOI.optimize!(opt)
        @test MOI.get(opt,MOI.TerminationStatus())===MOI.TIME_LIMIT
        @test decomposition(opt)["parent_overrun_sec"]==1.0
        @test only(decomposition(opt)["calls"])["time_limit_supported"]==time_supported
        @test !QUBODrivers.enforces_time_limit(opt)
        time_supported && @test last(log).limit==0.75
        @test QUBOTools.state(opt,1)==zeros(Int,4)
    end
    # A child's timeout with parent allowance is preserved as a valid public status.
    now[]=0.0
    opt=QUBODecomposition.Optimizer(;child_optimizer=() -> FixtureChild(;status=MOI.TIME_LIMIT,callback=_ -> (now[]=0.25)),max_variables=4)
    QUBODrivers.set_model!(opt,direct_model());opt.clock=()->now[]
    MOI.set(opt,MOI.TimeLimitSec(),1.0);MOI.optimize!(opt)
    @test MOI.get(opt,MOI.TerminationStatus())===MOI.TIME_LIMIT
    @test decomposition(opt)["completed_calls"]==1
    @test !only(decomposition(opt)["calls"])["exact"]
    for phase in (:before_factory,:reconstruct)
        opt=QUBODecomposition.Optimizer(;child_optimizer=() -> FixtureChild(),max_variables=4)
        QUBODrivers.set_model!(opt,direct_model())
        opt.checkpoint=p -> p===phase && throw(InterruptException())
        MOI.optimize!(opt)
        @test MOI.get(opt,MOI.TerminationStatus())===MOI.INTERRUPTED
        @test QUBOTools.state(opt,1)==zeros(Int,4)
    end
    for seed in (0,123,2^31-2), supported in (true,false)
        log=Any[]; factory=() -> FixtureChild(;seed_supported=supported,log)
        opt=solve_model(direct_model();child=factory,seed)
        state=copy(QUBOTools.state(opt,1));MOI.optimize!(opt)
        @test QUBOTools.state(opt,1)==state
        @test last(log).seed== (supported ? seed : nothing)
        @test only(decomposition(opt)["calls"])["seed"]==mod(big(seed),big(2)^31-1)
        @test only(decomposition(opt)["calls"])["seed_supported"]==supported
        @test decomposition(opt)["invocation"]==2
    end
    @test QUBODrivers.supports_seed(QUBODecomposition.Optimizer)
    @test !QUBODrivers.honors_final_reads(QUBODecomposition.Optimizer)
end

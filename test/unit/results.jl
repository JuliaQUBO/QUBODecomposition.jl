# SPDX-License-Identifier: MPL-2.0
@testset "Complete child-result validation and status policy" begin
    initial=zeros(Int,4)
    for status in QUBODecomposition.ACCEPTED_CHILD_STATUSES
        opt=solve_model(direct_model();child=() -> FixtureChild(;status))
        @test MOI.get(opt,MOI.TerminationStatus())===status
        @test MOI.get(opt,MOI.PrimalStatus())===MOI.FEASIBLE_POINT
        @test MOI.get(opt,MOI.DualStatus())===MOI.NO_SOLUTION
    end
    for status in (MOI.INFEASIBLE,MOI.DUAL_INFEASIBLE,MOI.NUMERICAL_ERROR,MOI.OTHER_ERROR,
        MOI.INVALID_OPTION,MOI.INVALID_MODEL,MOI.OPTIMIZE_NOT_CALLED,MOI.INFEASIBLE_OR_UNBOUNDED)
        opt=solve_model(direct_model();child=() -> FixtureChild(;status))
        @test MOI.get(opt,MOI.TerminationStatus())===MOI.OTHER_ERROR
        @test QUBOTools.state(opt,1)==initial
    end
    for rows in ([], [[1,0,1]], [[1,0,1,2]], [[1,0,1,NaN]], [[1,0,1,Inf]], [[1,0,1,0],[1,0,1,2]])
        opt=solve_model(direct_model();child=() -> FixtureChild(;rows))
        @test MOI.get(opt,MOI.TerminationStatus())===MOI.OTHER_ERROR
        @test QUBOTools.state(opt,1)==initial
    end
    for status in (MOI.OPTIMAL,MOI.LOCALLY_SOLVED)
        opt=solve_model(direct_model();child=() -> FixtureChild(;rows=[[1,0,1,0]],values=[Inf],status))
        @test MOI.get(opt,MOI.TerminationStatus())===MOI.OTHER_ERROR
    end
    opt=solve_model(direct_model();child=() -> FixtureChild(;rows=[[0,1,0,0]],status=MOI.OPTIMAL))
    @test MOI.get(opt,MOI.TerminationStatus())===MOI.OTHER_ERROR # false certificate worse than known incumbent
    opt=solve_model(direct_model();child=() -> FixtureChild(;rows=[[1,0,1,0]],row_status=MOI.NO_SOLUTION))
    @test MOI.get(opt,MOI.TerminationStatus())===MOI.OTHER_ERROR
    opt=solve_model(direct_model();child=() -> FixtureChild(;corrupt_map=true))
    @test MOI.get(opt,MOI.TerminationStatus())===MOI.OTHER_ERROR
    opt=solve_model(direct_model();child=() -> FixtureChild(;callback=_ -> throw(ArgumentError("child failed"))))
    @test MOI.get(opt,MOI.TerminationStatus())===MOI.OTHER_ERROR
    opt=solve_model(direct_model();child=() -> error("factory failed"))
    @test MOI.get(opt,MOI.TerminationStatus())===MOI.OTHER_ERROR
    @test decomposition(opt)["attempted_calls"]==1
    opt=solve_model(direct_model();child=() -> FixtureChild(;callback=_ -> error("child failed")))
    @test MOI.get(opt,MOI.TerminationStatus())===MOI.OTHER_ERROR
    for child in (() -> FixtureChild(;status=MOI.INTERRUPTED), () -> FixtureChild(;rows=[],status=MOI.INTERRUPTED),
        () -> FixtureChild(;callback=_ -> throw(InterruptException())))
        opt=solve_model(direct_model();child)
        @test MOI.get(opt,MOI.TerminationStatus())===MOI.INTERRUPTED
        @test QUBOTools.state(opt,1)==initial
    end
    opt=solve_model(direct_model();child=() -> FixtureChild(;rows=[[1,0,1,1],[1,0,1,0],[1,0,1,0]],values=[-900.0,900.0,17.0]))
    @test QUBOTools.state(opt,1)==[1,0,1,0]
    @test QUBOTools.value(opt,1)==2.0
    @test QUBOTools.reads(opt,1)==1
    @test decomposition(opt)["candidate_evaluations"]==4
    @test only(decomposition(opt)["calls"])["physical_reads"]===nothing
    for scale in (Inf,NaN), offset in (0.0,NaN)
        opt=solve_model(direct_model(;scale,offset))
        @test MOI.get(opt,MOI.TerminationStatus())===MOI.OTHER_ERROR
        @test MOI.get(opt,MOI.ResultCount())==0
    end
    # Finite inputs whose scaled coefficients or full energy overflow are rejected.
    model=QUBOTools.Model(Dict(:x=>floatmax(Float64)),Dict{Tuple{Symbol,Symbol},Float64}();scale=2.0)
    opt=solve_model(model)
    @test MOI.get(opt,MOI.TerminationStatus())===MOI.OTHER_ERROR
    model=direct_model()
    QUBOTools.attach!(model,:a=>2)
    opt=solve_model(model)
    @test MOI.get(opt,MOI.ResultCount())==0
end

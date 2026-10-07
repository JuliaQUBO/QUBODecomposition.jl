# SPDX-License-Identifier: MPL-2.0
@testset "Callback attachment, rounding ties and opaque legacy slots" begin
    constant = QUBOTools.Model(Dict(:a=>0.0), Dict{Tuple{Symbol,Symbol},Float64}(); offset=1.0)
    for callback in ((s, o)->error("callback failed"), (s, o)->throw(InterruptException()),
        (s, o)->QUBOTools.SampleSet{Float64,Int}(
            [QUBOTools.Sample{Float64,Int}([1], 2.0, 1)]; sense=:min, domain=:bool))
        opt = solve_model(constant)
        @test MOI.get(opt, MOI.TerminationStatus()) === MOI.OPTIMAL
        MOI.set(opt, QUBODrivers.PostSampleCallback(), callback)
        @test_throws Exception MOI.optimize!(opt)
        @test MOI.get(opt, MOI.TerminationStatus()) === MOI.OPTIMIZE_NOT_CALLED
        @test MOI.get(opt, MOI.ResultCount()) == 0
        @test MOI.get(opt, MOI.PrimalStatus()) === MOI.NO_SOLUTION
        MOI.set(opt, QUBODrivers.PostSampleCallback(), nothing)
        MOI.optimize!(opt)
        @test MOI.get(opt, MOI.TerminationStatus()) === MOI.OPTIMAL
        @test MOI.get(opt, MOI.ResultCount()) == 1
    end
    opt = solve_model(constant)
    @test_throws ArgumentError MOI.set(opt, QUBODrivers.PostSampleTransform(), true)
    @test MOI.get(opt, MOI.TerminationStatus()) === MOI.OPTIMIZE_NOT_CALLED
    @test MOI.get(opt, MOI.ResultCount()) == 0
    MOI.set(opt, QUBODrivers.PostSampleCallback(), (s, o)->(QUBOTools.metadata(s)["annotation"]="ok"; nothing))
    MOI.optimize!(opt)
    @test QUBOTools.metadata(QUBOTools.solution(opt))["annotation"] == "ok"
    @test MOI.get(opt, MOI.TerminationStatus()) === MOI.OPTIMAL

    for sense in (:min, :max)
        sign = sense === :min ? 1.0 : -1.0
        model = QUBOTools.Model(Dict(:x1=>-0.1sign,:x2=>-0.2sign,:x3=>-0.3sign),
            Dict((:x1,:x3)=>sign,(:x2,:x3)=>sign); sense)
        QUBOTools.attach!(model,:x1=>1); QUBOTools.attach!(model,:x2=>1)
        opt = solve_model(model; child=()->FixtureChild(rows=[[0,0,1]],status=MOI.OPTIMAL))
        @test MOI.get(opt, MOI.TerminationStatus()) === MOI.OPTIMAL
        @test QUBOTools.state(opt,1) == [1,1,0] # strict improvement still required
        @test MOI.get(opt, MOI.ObjectiveValue()) == sign * (-0.1-0.2)
        @test decomposition(opt)["accepted_improvements"] == 0
    end

    for spin in (false,true)
        source = MOI.Utilities.UniversalFallback(MOI.Utilities.Model{Float64}())
        vars = MOI.add_variables(source,2)
        for v in vars
            MOI.add_constraint(source,v,spin ? QUBODrivers.Spin() : MOI.ZeroOne())
        end
        MOI.add_constraint(source,vars[1],MOI.EqualTo(1.0))
        objective = MOI.ScalarQuadraticFunction(MOI.ScalarQuadraticTerm{Float64}[],
            [MOI.ScalarAffineTerm(2.0,v) for v in vars],7.0)
        MOI.set(source,MOI.ObjectiveFunction{typeof(objective)}(),objective)
        MOI.set(source,MOI.ObjectiveSense(),MOI.MIN_SENSE)
        opt = QUBODecomposition.Optimizer(child_optimizer=()->FixtureChild(),max_variables=1)
        map = MOI.copy_to(opt,source)
        for name in ("fixed_variables","moi_variables")
            MOI.set(opt,MOI.RawOptimizerAttribute(name),:unrelated_user_data)
            @test MOI.get(opt,MOI.RawOptimizerAttribute(name)) === :unrelated_user_data
        end
        MOI.optimize!(opt)
        @test MOI.get(opt,MOI.NumberOfVariables()) == 2
        @test MOI.get(opt,MOI.VariablePrimal(),map[vars[1]]) == 1
        @test MOI.get(opt,MOI.VariablePrimal(),map[vars[2]]) == (spin ? -1 : 0)
        @test MOI.get(opt,MOI.ObjectiveValue()) == (spin ? 7.0 : 9.0)
    end
    opt = solve_model(constant)
    @test MOI.get(opt,MOI.SolverVersion()) == pkgversion(QUBODecomposition)
    @test QUBOTools.metadata(QUBOTools.solution(opt))["backend"]["version"] == pkgversion(QUBODecomposition)
    @test MOI.get(opt.storage,MOI.SolverVersion()) == pkgversion(QUBODecomposition)
end

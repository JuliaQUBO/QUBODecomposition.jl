# SPDX-License-Identifier: MPL-2.0
@testset "Released driver conformance and ExactSampler status" begin
    # Every default conformance group stays enabled for both public child paths.
    for factory in (() -> FixtureChild(), () -> QUBODrivers.ExactSampler.Optimizer()), budget in (2,32)
        config! = opt -> begin
            MOI.set(opt,MOI.RawOptimizerAttribute("child_optimizer"),factory)
            MOI.set(opt,MOI.RawOptimizerAttribute("max_variables"),budget)
        end
        QUBODrivers.test(config!,QUBODecomposition.Optimizer)
    end
    for selection in (:bfs, :random_blocks), factory in (() -> FixtureChild(), () -> QUBODrivers.ExactSampler.Optimizer())
        config! = opt -> begin
            MOI.set(opt,MOI.RawOptimizerAttribute("child_optimizer"),factory)
            MOI.set(opt,MOI.RawOptimizerAttribute("max_variables"),2)
            MOI.set(opt,MOI.RawOptimizerAttribute("selection"),selection)
            MOI.set(opt,QUBODrivers.RandomSeed(),41)
        end
        QUBODrivers.test(config!,QUBODecomposition.Optimizer)
    end
    for factory in (() -> FixtureChild(), () -> QUBODrivers.ExactSampler.Optimizer()), separator in (Int[], :articulation)
        config! = opt -> begin
            MOI.set(opt,MOI.RawOptimizerAttribute("child_optimizer"),factory)
            MOI.set(opt,MOI.RawOptimizerAttribute("max_variables"),32)
            MOI.set(opt,MOI.RawOptimizerAttribute("strategy"),:separator)
            MOI.set(opt,MOI.RawOptimizerAttribute("separator"),separator)
        end
        QUBODrivers.test(config!,QUBODecomposition.Optimizer)
    end
    opt=solve_model(direct_model();child=()->QUBODrivers.ExactSampler.Optimizer())
    @test MOI.get(opt,MOI.TerminationStatus())===MOI.LOCALLY_SOLVED
    @test QUBOTools.value(opt,1)==2.0
    @test !only(decomposition(opt)["calls"])["exact"]
    @test all(x isa Integer for x in only(decomposition(opt)["calls"])["reported_multiplicities"])
    @test QUBOTools.reads(opt,1)==1
    @test MOI.get(opt,MOI.SolveTimeSec())==QUBODrivers.effective_time(opt)
    @test QUBODrivers.effective_time(opt)<=QUBODrivers.total_time(opt)
end

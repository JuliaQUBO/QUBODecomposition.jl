# SPDX-License-Identifier: MPL-2.0
import JuMP
@testset "Public JuMP/MOI path and fixed-variable reconstruction" begin
    for spin in (false,true), maximize in (false,true), fixed in (false,true)
        factory=() -> QUBODecomposition.Optimizer(;child_optimizer=()->FixtureChild(),max_variables=4)
        model=JuMP.Model(factory)
        if spin
            JuMP.@variable(model,x[1:4] in QUBODrivers.Spin())
        else
            JuMP.@variable(model,x[1:4],Bin)
        end
        f=5-3*x[1]+2*x[2]-x[3]+4*x[1]*x[2]-2*x[2]*x[3]+3*x[1]^2
        JuMP.@objective(model,Min,f)
        maximize && JuMP.set_objective_sense(model,MOI.MAX_SENSE)
        fixed && JuMP.fix(x[2],spin ? -1 : 1;force=false)
        JuMP.optimize!(model)
        states=Iterators.product(fill(spin ? (-1,1) : (0,1),4)...)
        oracle(x)=5-3*x[1]+2*x[2]-x[3]+4*x[1]*x[2]-2*x[2]*x[3]+3*x[1]^2
        values=[oracle(x) for x in states if !fixed || x[2]==(spin ? -1 : 1)]
        @test JuMP.termination_status(model)===MOI.OPTIMAL
        @test JuMP.objective_value(model)==(maximize ? maximum(values) : minimum(values))
        @test oracle(JuMP.value.(x))==JuMP.objective_value(model)
        fixed && @test JuMP.value(x[2])==(spin ? -1 : 1)
        raw=MOI.get(JuMP.backend(model),MOI.RawSolver())
        @test decomposition(raw)["dimension"]==(fixed ? 3 : 4)
        @test MOI.get(raw,MOI.NumberOfVariables())==4
    end
    for spin in (false,true)
        source=MOI.Utilities.UniversalFallback(MOI.Utilities.Model{Float64}())
        vars=MOI.add_variables(source,3)
        for v in vars
            MOI.add_constraint(source,v,spin ? QUBODrivers.Spin() : MOI.ZeroOne())
            MOI.add_constraint(source,v,MOI.EqualTo(spin ? -1.0 : 1.0))
        end
        f=MOI.ScalarQuadraticFunction(MOI.ScalarQuadraticTerm{Float64}[],[MOI.ScalarAffineTerm(2.0,v) for v in vars],7.0)
        MOI.set(source,MOI.ObjectiveFunction{typeof(f)}(),f)
        MOI.set(source,MOI.ObjectiveSense(),MOI.MIN_SENSE)
        opt=QUBODecomposition.Optimizer(;child_optimizer=()->error("fixed model called child"),max_variables=1)
        map=MOI.copy_to(opt,source);MOI.optimize!(opt)
        @test MOI.get(opt,MOI.TerminationStatus())===MOI.OPTIMAL
        @test MOI.get(opt,MOI.ObjectiveValue())==(spin ? 1.0 : 13.0)
        @test all(MOI.get(opt,MOI.VariablePrimal(),map[v])==(spin ? -1 : 1) for v in vars)
        @test MOI.get(opt,MOI.NumberOfVariables())==3
        MOI.copy_to(opt,source)
        @test MOI.get(opt,MOI.ResultCount())==0
    end
end

@testset "Serial JuMP fixed variables, full primals and coupled heuristic status" begin
    for spin in (false,true), maximize in (false,true), fixed in (false,true), coupled in (false,true)
        model=JuMP.Model(()->QUBODecomposition.Optimizer(;child_optimizer=()->FixtureChild(),max_variables=2))
        if spin
            JuMP.@variable(model,x[1:6] in QUBODrivers.Spin())
        else
            JuMP.@variable(model,x[1:6],Bin)
        end
        JuMP.@objective(model,Min,7-3*x[1]+2*x[2]-2*x[3]+x[4]-4*x[5]+3*x[6]+4*x[1]*x[2]-2*x[4]*x[5]+(coupled ? x[2]*x[4] : 0))
        maximize && JuMP.set_objective_sense(model,MOI.MAX_SENSE)
        fixed && JuMP.fix(x[6],spin ? -1 : 1;force=false)
        JuMP.optimize!(model)
        state=JuMP.value.(x)
        oracle(x)=7-3*x[1]+2*x[2]-2*x[3]+x[4]-4*x[5]+3*x[6]+4*x[1]*x[2]-2*x[4]*x[5]+(coupled ? x[2]*x[4] : 0)
        @test oracle(state)==JuMP.objective_value(model)
        @test JuMP.termination_status(model)==(coupled ? MOI.LOCALLY_SOLVED : MOI.OPTIMAL)
        @test length(state)==6
        fixed && @test state[6]==(spin ? -1 : 1)
        raw=MOI.get(JuMP.backend(model),MOI.RawSolver())
        @test MOI.get(raw,MOI.NumberOfVariables())==6
        @test decomposition(raw)["dimension"]==(fixed ? 5 : 6)
        if !coupled
            states=Iterators.product(fill(spin ? (-1,1) : (0,1),6)...)
            energies=[oracle(x) for x in states if !fixed || x[6]==(spin ? -1 : 1)]
            @test JuMP.objective_value(model)==(maximize ? maximum(energies) : minimum(energies))
        end
    end
end

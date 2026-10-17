# SPDX-License-Identifier: MPL-2.0
@testset "Root preprocessing public driver conformance" begin
    for factory in (() -> root_child(),() -> QUBODrivers.ExactSampler.Optimizer())
        configure! = opt -> begin
            MOI.set(opt,MOI.RawOptimizerAttribute("child_optimizer"),factory)
            MOI.set(opt,MOI.RawOptimizerAttribute("max_variables"),8)
            MOI.set(opt,MOI.RawOptimizerAttribute("preprocessing"),:dominance)
        end
        QUBODrivers.test(configure!,QUBODecomposition.Optimizer)
    end
end

@testset "Preprocessor and separate MOI-fixed index maps compose" begin
    for spin in (false,true),maximize in (false,true)
        model=JuMP.Model(()->QUBODecomposition.Optimizer(child_optimizer=()->root_child(),
            max_variables=8,preprocessing=:dominance))
        if spin
            JuMP.@variable(model,x[1:6] in QUBODrivers.Spin())
        else
            JuMP.@variable(model,x[1:6],Bin)
        end
        energy=3+6*x[2]-x[2]*(x[1]+x[3]+x[4]+x[5])-x[1]*x[3]-x[4]*x[5]+2*x[6]
        JuMP.@objective(model,Min,energy)
        maximize && JuMP.set_objective_sense(model,MOI.MAX_SENSE)
        fixed=spin ? -1 : 1
        JuMP.fix(x[6],fixed;force=false)
        JuMP.optimize!(model)
        states=Iterators.product(fill(spin ? (-1,1) : (0,1),5)...)
        scalar(s)=3+6*s[2]-s[2]*(s[1]+s[3]+s[4]+s[5])-s[1]*s[3]-s[4]*s[5]+2*fixed
        values=[scalar(s) for s in states]
        @test JuMP.termination_status(model)===MOI.OPTIMAL
        @test JuMP.objective_value(model)==(maximize ? maximum(values) : minimum(values))
        @test JuMP.value(x[6])==fixed
        @test length(JuMP.value.(x))==6
        @test scalar(JuMP.value.(x)[1:5])==JuMP.objective_value(model)
        raw=MOI.get(JuMP.backend(model),MOI.RawSolver())
        @test MOI.get(raw,MOI.NumberOfVariables())==6
        @test decomposition(raw)["dimension"]==5
        @test decomposition(raw)["preprocessing"]["original_dimension"]==5
        @test length(root_evidence(raw).exported |> QUBOPreprocessing.original_variables)==5
    end
end

function root_compiled_scalar(call,state)
    R=Rational{BigInt};values=Dict(zip(call.vars,state))
    value=R(call.f.constant)
    for term in call.f.affine_terms;value+=R(term.coefficient)*values[term.variable];end
    for term in call.f.quadratic_terms
        value+=R(term.coefficient)*values[term.variable_1]*values[term.variable_2]/
            (term.variable_1==term.variable_2 ? 2 : 1)
    end
    return value
end
function assert_root_compiled_optimum(call)
    n=length(call.vars)
    0<=n<=8 || error("compiled oracle guard precedes enumeration")
    values=[root_compiled_scalar(call,collect(bits)) for bits in binary_states(n)]
    @test call.status===MOI.OPTIMAL
    @test root_compiled_scalar(call,call.state)==(call.sense===MOI.MIN_SENSE ? minimum(values) : maximum(values))
    assert_bit_inventory(call)
end

@testset "ToQUBO full compiled lifting and penalty generation invalidation" begin
    # Deliberately weak input is a configuration diagnostic; refinement checks
    # source feasibility separately from the exact compiled objective.
    f=binary_fixture(budget=8,child=()->root_child(),preprocessing=:dominance,seed=41)
    JuMP.optimize!(f.model)
    @test !ToQUBO.is_feasible(f.model)
    @test ToQUBO.source_objective_value(f.model)==11
    initial=root_evidence(f.composite)
    JuMP.set_attribute(f.model,TA.MaxPenaltyUpdates(),5)
    JuMP.optimize!(f.model)
    @test ToQUBO.is_feasible(f.model)
    @test sum(JuMP.value.(f.x))<=1
    @test ToQUBO.source_objective_value(f.model)==8
    @test MOI.get(f.compiler,TA.PenaltyUpdateCount())==2
    @test length(f.capture.log)==4
    @test length(unique(call.data["preprocessing"]["generation"] for call in f.capture.log))==4
    @test QUBOPreprocessing.generation(initial.workspace)!=QUBOPreprocessing.generation(root_evidence(f.composite).workspace)
    for call in f.capture.log
        @test length(call.vars)==3 && length(call.state)==3
        assert_root_compiled_optimum(call)
    end
    for sense in (MOI.MIN_SENSE,MOI.MAX_SENSE)
        f=integer_fixture(;sense,budget=8,child=()->root_child(),preprocessing=:dominance)
        JuMP.optimize!(f.model)
        z,b=JuMP.value(f.z),JuMP.value(f.b)
        @test z in 0:3 && b in (0,1) && z+2*b<=3
        @test ToQUBO.source_objective_value(f.model)==7+2*z+b
        @test ToQUBO.source_objective_value(f.model)==(sense===MOI.MIN_SENSE ? 7 : 13)
        @test ToQUBO.is_feasible(f.model)
        call=only(f.capture.log)
        @test length(call.vars)==5 && length(call.state)==5 # encoded integer, binary and slack bits
        assert_root_compiled_optimum(call)
    end
end

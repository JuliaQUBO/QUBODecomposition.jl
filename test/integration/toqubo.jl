# SPDX-License-Identifier: MPL-2.0
include("fixtures.jl")
@testset "Row 17: binary source feasibility and public refinement" begin
    source=[(x=collect(x),value=5+3*x[1]+3*x[2],residual=x[1]+x[2]-1) for x in binary_states(2)]
    @test length(source)==4
    @test maximum(s.value for s in source if s.residual<=0)==8
    for budget in (32,2)
        childlog=Any[]
        f=binary_fixture(;budget,child=()->FixtureChild(;log=childlog),seed=41)
        @test MOI.get(f.compiler,TA.PrimalFeasibilityCheck())
        JuMP.optimize!(f.model)
        x=JuMP.value.(f.x)
        @test x==[1,1]
        assert_source_result(f,11,1)
        @test JuMP.objective_value(f.model)≈10.9
        @test JuMP.objective_value(f.model)!=ToQUBO.source_objective_value(f.model)
        MOI.set(f.compiler,TA.PrimalFeasibilityCheck(),false)
        @test MOI.get(f.compiler,MOI.PrimalStatus())==MOI.FEASIBLE_POINT
        @test !ToQUBO.is_feasible(f.model)
        MOI.set(f.compiler,TA.PrimalFeasibilityCheck(),true)
        JuMP.set_attribute(f.model,TA.MaxPenaltyUpdates(),5)
        JuMP.optimize!(f.model)
        @test MOI.get(f.compiler,TA.PenaltyUpdateCount())==2
        @test length(f.capture.log)==4 # first weak solve + weak/-1/-10 refinement
        @test MOI.get(f.compiler,TA.ConstraintEncodingPenaltyHint(),JuMP.index(f.c))≈-10
        x=JuMP.value.(f.x)
        assert_source_result(f,5+3*x[1]+3*x[2],x[1]+x[2]-1)
        @test x[1]+x[2]<=1
        budget==32 && @test ToQUBO.source_objective_value(f.model)==8
        @test JuMP.termination_status(f.model)==(budget==32 ? MOI.OPTIMAL : MOI.LOCALLY_SOLVED)
        @test all(length(e.variables)<=budget for e in childlog if hasproperty(e,:variables))
        @test any(e.objective!=first(childlog).objective for e in childlog if hasproperty(e,:objective))
        for (call,penalty) in zip(f.capture.log,(-0.1,-0.1,-1.0,-10.0))
            assert_bit_inventory(call)
            @test length(call.vars)==3 # two source bits + slack bit
            slack=only(call.meta["slack_variables"])
            seen=Set{Tuple{Int,Int}}()
            for bits in binary_states(3)
                d=decoded(call,bits); a,b=d[JuMP.index(f.x[1]).value],d[JuMP.index(f.x[2]).value]
                s=scalar_terms(slack["expansion_terms"],bits)
                push!(seen,(a,b))
                @test compiled_energy(call,bits)≈5+3*a+3*b+penalty*(a+b+s-1)^2
                @test ToQUBO.project_original_state(call.meta,collect(bits))==d
            end
            @test length(seen)==4
            if budget==32
                @test call.energy≈maximum(compiled_energy(call,bits) for bits in binary_states(3))
            else
                @test !call.data["separable_proof"]
                @test all(diff(call.data["incumbent_energy_trace"]).>=0)
            end
        end
        # Read current refined state from the compiler, not JuMP's cached input.
        @test JuMP.get_attribute(f.c,TA.ConstraintEncodingPenaltyHint())==-0.1
        JuMP.optimize!(f.model)
        @test MOI.get(f.compiler,TA.ConstraintEncodingPenaltyHint(),JuMP.index(f.c))==-10
        @test MOI.get(f.compiler,TA.PenaltyUpdateCount())==0
        @test ToQUBO.is_feasible(f.model)
        @test length(last(f.capture.log).vars)==3
        fresh=binary_fixture(;budget,seed=41)
        JuMP.set_attribute(fresh.c,TA.ConstraintEncodingPenaltyHint(),-10.0)
        JuMP.optimize!(fresh.model)
        assert_fresh_compilation(last(f.capture.log),only(fresh.capture.log))
        # Explicit reset is a supported operation and preserves the live hint.
        MOI.Utilities.reset_optimizer(f.model)
        JuMP.optimize!(f.model)
        @test MOI.get(f.compiler,TA.ConstraintEncodingPenaltyHint(),JuMP.index(f.c))==-10
        assert_fresh_compilation(last(f.capture.log),only(fresh.capture.log))
    end
end

@testset "Row 18: integer encoding, actual slack and all compiled bits" begin
    feasible=[7+2*z+b for z in 0:3 for b in 0:1 if z+2*b<=3]
    @test extrema(feasible)==(7,13)
    for sense in (MOI.MIN_SENSE,MOI.MAX_SENSE), budget in (32,2)
        f=integer_fixture(;sense,budget)
        JuMP.optimize!(f.model)
        call=only(f.capture.log); assert_bit_inventory(call)
        zentry=only(e for e in call.meta["original_variables"] if e["id"]==JuMP.index(f.z).value)
        @test length(zentry["target_variables"])==2
        slack=only(call.meta["slack_variables"])
        bentry=only(e for e in call.meta["original_variables"] if e["id"]==JuMP.index(f.b).value)
        @test length(bentry["target_variables"])==1
        @test length(slack["target_variables"])==2
        @test length(call.vars)==length(zentry["target_variables"])+length(bentry["target_variables"])+length(slack["target_variables"])
        rho=only(call.meta["constraint_encodings"])["penalty"]
        seen=Set{Tuple{Int,Int}}()
        envelope=Dict{Tuple{Int,Int},Float64}()
        for bits in binary_states(length(call.vars))
            d=decoded(call,bits); z,b=d[JuMP.index(f.z).value],d[JuMP.index(f.b).value]
            @test z in 0:3 && b in 0:1
            s=scalar_terms(slack["expansion_terms"],bits)
            e=compiled_energy(call,bits)
            @test e≈7+2*z+b+rho*(z+2*b+s-3)^2
            @test ToQUBO.project_original_state(call.meta,collect(bits))==d
            key=(z,b);push!(seen,key)
            envelope[key]=haskey(envelope,key) ? (sense==MOI.MIN_SENSE ? min(envelope[key],e) : max(envelope[key],e)) : e
        end
        @test seen==Set((z,b) for z in 0:3 for b in 0:1)
        for ((z,b),e) in envelope
            @test e≈7+2*z+b+rho*max(0,z+2*b-3)^2
        end
        z,b=JuMP.value(f.z),JuMP.value(f.b)
        assert_source_result(f,7+2*z+b,z+2*b-3)
        @test z+2*b<=3
        if budget==32
            expected=sense==MOI.MIN_SENSE ? 7 : 13
            @test ToQUBO.source_objective_value(f.model)==expected
            @test call.energy≈(sense==MOI.MIN_SENSE ? minimum : maximum)(values(envelope))
            @test JuMP.termination_status(f.model)==MOI.OPTIMAL
        else
            @test JuMP.termination_status(f.model)==MOI.LOCALLY_SOLVED
            @test !call.data["separable_proof"]
        end
    end
end

@testset "Row 18: lifted binary cubic with actual quadratization" begin
    # ToQUBO 0.7 accepts quadratic MOI input. Represent the cubic by y=x1*x2
    # and y*x3; squaring the product identity produces a cubic penalty. The
    # source lift and compiler-generated quadratization bits are separate.
    cubic(x)=5+2*x[1]-x[2]+x[3]-4*x[1]*x[2]*x[3]
    expected=extrema(cubic(x) for x in binary_states(3))
    @test expected==(3,8)
    for sense in (MOI.MIN_SENSE,MOI.MAX_SENSE),budget in (32,2)
        f=compiler_fixture(;budget);m=f.model
        JuMP.@variable(m,x[1:3],Bin);JuMP.@variable(m,y,Bin)
        c=JuMP.@constraint(m,y==x[1]*x[2])
        JuMP.@objective(m,Min,5+2*x[1]-x[2]+x[3]-4*y*x[3])
        JuMP.set_objective_sense(m,sense)
        JuMP.optimize!(m)
        call=only(f.capture.log);assert_bit_inventory(call)
        aux=[e["id"] for e in call.meta["target_variables"] if e["role"]=="quadratization"]
        @test !isempty(aux)
        @test isempty(call.meta["slack_variables"])
        @test length(call.vars)==4+length(aux)
        rho=only(call.meta["constraint_encodings"])["penalty"]
        envelope=Dict{NTuple{4,Int},Float64}()
        for bits in binary_states(length(call.vars))
            d=decoded(call,bits)
            key=Tuple(Int(d[JuMP.index(v).value]) for v in [x;y])
            @test ToQUBO.project_original_state(call.meta,collect(bits))==d
            e=compiled_energy(call,bits)
            envelope[key]=haskey(envelope,key) ? (sense==MOI.MIN_SENSE ? min(envelope[key],e) : max(envelope[key],e)) : e
        end
        @test length(envelope)==16
        for ((a,b,c,yvalue),e) in envelope
            # Independent unquadratized source + product-identity penalty.
            @test e≈5+2*a-b+c-4*yvalue*c+rho*(yvalue-a*b)^2
        end
        state=JuMP.value.(x)
        @test JuMP.value(y)==state[1]*state[2]
        @test ToQUBO.is_feasible(m)
        @test ToQUBO.source_objective_value(m)==cubic(state)
        if budget==32
            @test cubic(state)==expected[sense==MOI.MIN_SENSE ? 1 : 2]
            @test JuMP.termination_status(m)==MOI.OPTIMAL
        else
            @test JuMP.termination_status(m)==MOI.LOCALLY_SOLVED
            @test !call.data["separable_proof"]
        end
    end
end

# SPDX-License-Identifier: MPL-2.0
# Actual supported child, no test-only public status override. Expectations come
# from the released version contract, independently of the parent's observations.
@testset "Actual ExactSampler dependency contract and complete route proofs" begin
    child = MOI.instantiate(QUBODrivers.ExactSampler.Optimizer; with_bridge_type=Float64)
    x, _ = MOI.add_constrained_variables(child, [MOI.ZeroOne()])
    MOI.set(child, MOI.ObjectiveSense(), MOI.MIN_SENSE)
    MOI.set(child, MOI.ObjectiveFunction{VI}(), only(x))
    MOI.optimize!(child)
    @test MOI.get(child, MOI.TerminationStatus()) == EXACT_SAMPLER_STATUS
    @test MOI.get(child, MOI.ResultCount()) == 2
    @test MOI.get(child, MOI.ObjectiveValue()) == 0.0
    @test QUBOTools.metadata(QUBOTools.solution(MOI.get(child, MOI.RawSolver())))["termination_status"] == MOI.OPTIMAL

    function real_fixture(domain, sense, scale; edges=true)
        QUBOTools.Model{Symbol,Float64,Int}([:center,:right,:left,:isolate],
            [1,2,3], [2.,1.,-0.5], edges ? [1,1] : Int[],
            edges ? [2,3] : Int[], edges ? [-4.,-2.] : Float64[];
            domain, sense, scale, offset=1.25,
            # Interior-energy starts ensure a real child is needed for proof,
            # including pruning routes under either sense/signed scale.
            start=Dict(:center => (domain==:bool ? 0 : 1), :right=>1,
                :left => (domain==:bool ? 0 : 1), :isolate => (domain==:bool ? 0 : -1)))
    end
    function scalar_best(domain, sense, scale; edges=true)
        # Independent original polynomial, never child/conditioner coefficients.
        values=domain==:bool ? (0,1) : (-1,1)
        energies=[scale*(1.25+2a+b-0.5c+(edges ? -4a*b-2a*c : 0))
            for a in values for b in values for c in values for d in values]
        (sense==:min ? minimum : maximum)(energies)
    end
    function check_original_candidate(opt, domain, scale; edges=true)
        state=QUBOTools.state(opt,1)
        @test length(state)==4
        @test all(x -> x in (domain==:bool ? (0,1) : (-1,1)), state)
        a,b,c,d=state
        energy=scale*(1.25+2a+b-0.5c+(edges ? -4a*b-2a*c : 0))
        @test QUBOTools.value(opt,1)==energy
    end
    function real_solve(model; kwargs...)
        solve_model(model; child=()->QUBODrivers.ExactSampler.Optimizer(),
            max_child_calls=64, max_candidate_evaluations=512, kwargs...)
    end
    for domain in (:bool,:spin), sense in (:min,:max), scale in (-2.,1.5)
        model=real_fixture(domain,sense,scale)
        opt=real_solve(model;strategy=:whole_model,budget=4)
        @test MOI.get(opt,MOI.TerminationStatus()) == EXACT_SAMPLER_STATUS
        @test QUBOTools.value(opt,1) == scalar_best(domain,sense,scale)
        check_original_candidate(opt,domain,scale)
        @test only(decomposition(opt)["calls"])["exact"] == EXACT_SAMPLER_CERTIFIED
        @test only(decomposition(opt)["calls"])["public_status"] == string(EXACT_SAMPLER_STATUS)
        opt=real_solve(real_fixture(domain,sense,scale;edges=false);strategy=:components,budget=1)
        @test MOI.get(opt,MOI.TerminationStatus()) == EXACT_SAMPLER_STATUS
        @test decomposition(opt)["separable_proof"] == EXACT_SAMPLER_CERTIFIED
        @test all(decomposition(opt)["component_exact"]) == EXACT_SAMPLER_CERTIFIED
        @test QUBOTools.value(opt,1) == scalar_best(domain,sense,scale;edges=false)
        check_original_candidate(opt,domain,scale;edges=false)
        for separator in ([1],:articulation), pruning in (false,true)
            opt=real_solve(model;strategy=:separator,budget=1,separator,separator_pruning=pruning)
            proof=decomposition(opt)["separator"]
            @test MOI.get(opt,MOI.TerminationStatus()) == EXACT_SAMPLER_STATUS
            @test proof["proof_complete"] == EXACT_SAMPLER_CERTIFIED
            @test QUBOTools.value(opt,1) == scalar_best(domain,sense,scale)
            check_original_candidate(opt,domain,scale)
        end
    end

    # The real child sees free indices after MOI fixing; primals restore the
    # complete original source model, including a separately fixed variable.
    for strategy in (:whole_model,:separator)
        source=MOI.Utilities.UniversalFallback(MOI.Utilities.Model{Float64}())
        x,_=MOI.add_constrained_variables(source,fill(MOI.ZeroOne(),4))
        MOI.add_constraint(source,x[1],MOI.EqualTo(1.0))
        f=MOI.ScalarQuadraticFunction([MOI.ScalarQuadraticTerm(4.,x[2],x[3])],
            [MOI.ScalarAffineTerm(1.,x[1]),MOI.ScalarAffineTerm(-3.,x[2]),MOI.ScalarAffineTerm(2.,x[3])],5.)
        MOI.set(source,MOI.ObjectiveSense(),MOI.MIN_SENSE)
        MOI.set(source,MOI.ObjectiveFunction{typeof(f)}(),f)
        opt=QUBODecomposition.Optimizer(child_optimizer=QUBODrivers.ExactSampler.Optimizer,
            max_variables=strategy==:whole_model ? 3 : 1,strategy=strategy,
            separator=strategy==:separator ? [1] : Int[])
        map=MOI.copy_to(opt,source); MOI.optimize!(opt)
        values=[MOI.get(opt,MOI.VariablePrimal(),map[v]) for v in x]
        @test all(v -> v in (0,1),values)
        @test values[1]==1
        @test MOI.get(opt,MOI.ObjectiveValue())==5+values[1]-3values[2]+2values[3]+4values[2]*values[3]==3
        @test MOI.get(opt,MOI.TerminationStatus())==EXACT_SAMPLER_STATUS
    end

    model=real_fixture(:bool,:min,1.5)
    opt=real_solve(model;strategy=:whole_model,budget=4,max_candidate_evaluations=2)
    @test MOI.get(opt,MOI.TerminationStatus()) == MOI.ITERATION_LIMIT
    @test decomposition(opt)["incomplete_scan"]
    @test !only(decomposition(opt)["calls"])["exact"]
    @test only(decomposition(opt)["calls"])["public_status"] == string(EXACT_SAMPLER_STATUS)
    opt=real_solve(model;strategy=:separator,budget=1,separator=[1],max_child_calls=1)
    @test MOI.get(opt,MOI.TerminationStatus()) == MOI.ITERATION_LIMIT
    @test !decomposition(opt)["separator"]["proof_complete"]
    opt=real_solve(model;strategy=:whole_model,budget=4,absolute_deadline_sec=0.)
    @test MOI.get(opt,MOI.TerminationStatus()) == MOI.TIME_LIMIT
    @test decomposition(opt)["attempted_calls"] == 0
    constant=real_fixture(:bool,:min,0.)
    opt=real_solve(constant;budget=1)
    @test MOI.get(opt,MOI.TerminationStatus()) == MOI.OPTIMAL
    @test decomposition(opt)["attempted_calls"] == 0

    trap=QUBOTools.Model{Int,Float64,Int}(collect(1:6),collect(1:6),ones(6),
        [i for i in 1:5 for j in i+1:6],[j for i in 1:5 for j in i+1:6],fill(-2.,15))
    opt=real_solve(trap;budget=2,max_sweeps=2,stagnation_sweeps=1)
    @test MOI.get(opt,MOI.TerminationStatus()) == MOI.LOCALLY_SOLVED
    @test QUBOTools.value(opt,1) == 0.0 # independent original optimum is -24
    @test !decomposition(opt)["separable_proof"]
    @test all(c["exact"]==EXACT_SAMPLER_CERTIFIED for c in decomposition(opt)["calls"])
end

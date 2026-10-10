# SPDX-License-Identifier: MPL-2.0
@testset "Bounded separator conditioning" begin
    # Independent scalar oracle: no package conditioner, lift or value evaluator.
    function instance(n, edges; domain=:bool, sense=:min, scale=1.0, offset=3.25,
        linear=[(-1.0)^i * (i+1)/2 for i in 1:n], weights=[(-1.0)^k * (k+2)/4 for k in eachindex(edges)],
        labels=[Symbol("v", 2i+1) for i in 1:n])
        model = QUBOTools.Model{eltype(labels),Float64,Int}(labels, collect(1:n), linear,
            first.(edges), last.(edges), weights; domain, sense, scale, offset)
        scalar(x) = scale * (offset + sum((linear[i]*x[i] for i in 1:n); init=0.0) +
            sum((weights[k]*x[i]*x[j] for (k,(i,j)) in enumerate(edges)); init=0.0))
        n <= 10 || error("test oracle size guard")
        energies = [scalar(x) for x in Iterators.product(fill(domain===:bool ? (0,1) : (-1,1),n)...)]
        optimum = (sense===:min ? minimum : maximum)(energies)
        return model, scalar, optimum
    end
    sep_solve(m, s; kwargs...) = solve_model(m; strategy=:separator, separator=s, kwargs...)
    fixtures = [(5, [(1,2),(2,3),(3,4),(4,5)], [3], 2),
        (5, [(1,2),(1,3),(1,4),(1,5)], [1], 1),
        (7, [(1,2),(1,3),(2,3),(1,4),(1,5),(4,5),(5,6)], [1], 3),
        (5, [(1,2),(2,3),(3,4)], [3,2], 1)] # isolate, separator-only edge
    for (n,edges,s,budget) in fixtures, domain in (:bool,:spin), sense in (:min,:max), scale in (-2.5,0.75)
        m, scalar, optimum = instance(n, edges; domain, sense, scale)
        opt = sep_solve(m,s; budget)
        d = decomposition(opt); p = d["separator"]
        @test MOI.get(opt,MOI.TerminationStatus()) === MOI.OPTIMAL
        @test QUBOTools.value(opt,1) == optimum == scalar(QUBOTools.state(opt,1))
        @test p["proof_complete"] && !d["separable_proof"]
        @test p["completed_branches"] == p["certified_branches"] == p["required_branches"] == 2^length(s)
        @test p["component_certificates"] + p["constant_components"] == fill(2^length(s),length(p["residual_components"]))
        @test d["labels"] == QUBOTools.variables(m)
        @test all(c["selected_indices"] == p["residual_components"][c["component"]] for c in d["calls"])
        @test all(c["exact"] for c in d["calls"])
        @test all(sense===:min ? v<=0 : v>=0 for v in diff(d["incumbent_energy_trace"]))
    end

    # Separator=1 costs +2 at the all-zero start, but completing both leaves
    # gives -4; accepting only globally improving partial states would miss it.
    trap, trap_scalar, trap_optimum = instance(3,[(1,2),(1,3)]; linear=[2.,1.,1.], weights=[-4.,-4.], offset=0.)
    opt = sep_solve(trap,[1];budget=1)
    @test trap_scalar([1,0,0]) > trap_scalar([0,0,0])
    @test QUBOTools.state(opt,1) == [1,1,1]
    @test QUBOTools.value(opt,1) == trap_optimum == -4
    @test decomposition(opt)["incumbent_energy_trace"] == [0.,0.,-4.]
    @test [c["boundary_fixed_variables"] for c in decomposition(opt)["calls"]] ==
        [Dict(1=>0),Dict(1=>0),Dict(1=>1),Dict(1=>1)]
    @test [c["branch"] for c in decomposition(opt)["calls"]] == [1,1,2,2]

    @testset "Empty, full, constant, tied and isolated inputs" begin
        for domain in (:bool,:spin), n in (0,3), s in (Int[],collect(1:n)), scale in (0.,-2.)
            m,scalar,optimum = instance(n,Tuple{Int,Int}[];domain,scale,linear=zeros(n))
            o = sep_solve(m,s;budget=1,max_child_calls=0)
            @test MOI.get(o,MOI.TerminationStatus())===MOI.OPTIMAL
            @test QUBOTools.value(o,1)==optimum==scalar(QUBOTools.state(o,1))
            @test decomposition(o)["attempted_calls"]==0
            @test decomposition(o)["separator"]["completed_branches"]==2^length(s)
        end
        for s in (Int[],[2],[3,1,2]), domain in (:bool,:spin)
            m,scalar,optimum = instance(3,Tuple{Int,Int}[];domain,linear=[-1.,2.,0.])
            o=sep_solve(m,s;budget=1)
            @test MOI.get(o,MOI.TerminationStatus())===MOI.OPTIMAL
            @test QUBOTools.value(o,1)==optimum==scalar(QUBOTools.state(o,1))
        end
        # Tie keeps the input start; deterministic branch bit order still covers all.
        m,_,_=instance(2,[(1,2)];linear=[0.,0.],weights=[1.],offset=0.)
        QUBOTools.attach!(m,QUBOTools.variable(m,1)=>1)
        o=sep_solve(m,[2,1];budget=1,max_child_calls=0,max_candidate_evaluations=9)
        @test QUBOTools.state(o,1)==[1,0]
        @test decomposition(o)["candidate_evaluations"]==9
        @test decomposition(o)["separator"]["indices"]==[1,2]
    end

    @testset "Preflight and option ownership" begin
        for s in ([1,1],[0],[-1],[true],[1.0],[big(typemax(Int))+1],"1")
            @test_throws ArgumentError QUBODecomposition.Optimizer(separator=s)
        end
        for cap in (-1,17,true,1.0,typemax(Int))
            @test_throws ArgumentError QUBODecomposition.Optimizer(max_separator_size=cap)
        end
        count=Ref(0); child=()->(count[]+=1;FixtureChild())
        for (s,cap,budget) in (([4],8,1),([1],0,1),(Int[],8,1),(collect(1:64),16,1))
            o=sep_solve(trap,s;child,budget,max_separator_size=cap)
            @test MOI.get(o,MOI.TerminationStatus())===MOI.INVALID_OPTION
            @test count[]==0
            @test !decomposition(o)["separator"]["proof_complete"]
        end
        s=[1];o=QUBODecomposition.Optimizer(separator=s)
        s[1]=2
        returned=MOI.get(o,MOI.RawOptimizerAttribute("separator"));returned[1]=3
        @test MOI.get(o,MOI.RawOptimizerAttribute("separator"))==[1]
    end

    @testset "Public certificates and failed transactions" begin
        for status in (MOI.LOCALLY_SOLVED,MOI.ALMOST_OPTIMAL,MOI.TIME_LIMIT)
            o=sep_solve(trap,[1];budget=1,child=()->FixtureChild(;status))
            @test MOI.get(o,MOI.TerminationStatus())===MOI.LOCALLY_SOLVED
            @test QUBOTools.value(o,1)==trap_optimum
            @test !decomposition(o)["separator"]["proof_complete"]
            @test decomposition(o)["separator"]["incomplete_reason"]=="uncertified_components"
        end
        released=sep_solve(trap,[1];budget=1,child=()->QUBODrivers.ExactSampler.Optimizer())
        @test MOI.get(released,MOI.TerminationStatus())===MOI.LOCALLY_SOLVED
        @test QUBOTools.value(released,1)==trap_optimum
        @test all(c["public_status"]=="LOCALLY_SOLVED" && !c["exact"] for c in decomposition(released)["calls"])
        for bad in (() -> FixtureChild(rows=[]), () -> FixtureChild(rows=[[2]]),
            () -> FixtureChild(rows=[[1]],values=[NaN]), () -> FixtureChild(rows=[Int[]]),
            () -> FixtureChild(status=MOI.OTHER_ERROR), () -> FixtureChild(callback=_->error("failure")),
            () -> FixtureChild(row_status=MOI.NO_SOLUTION))
            calls=Ref(0)
            child=()->(calls[]+=1;calls[]==4 ? bad() : FixtureChild())
            o=sep_solve(trap,[1];budget=1,child)
            @test MOI.get(o,MOI.TerminationStatus())===MOI.OTHER_ERROR
            @test QUBOTools.state(o,1)==[0,0,0] # discard partly improved second branch
            @test decomposition(o)["separator"]["completed_branches"]==1
            @test !decomposition(o)["separator"]["proof_complete"]
        end
        # A public certificate contradicted by a known branch-local state fails.
        calls=Ref(0)
        o=sep_solve(trap,[1];budget=1,child=()->(calls[]+=1; calls[]==1 ? FixtureChild(rows=[[1]]) : FixtureChild()))
        @test MOI.get(o,MOI.TerminationStatus())===MOI.OTHER_ERROR
        @test occursin("contradicts",decomposition(o)["diagnostic"])
    end

    @testset "Shared budgets, interruption and exact boundaries" begin
        complete=sep_solve(trap,[1];budget=1)
        need=decomposition(complete)["candidate_evaluations"]
        @test need==9 # initial + 2*(branch initial + 2 child rows + final)
        for cap in 0:need-1
            o=sep_solve(trap,[1];budget=1,max_candidate_evaluations=cap)
            @test MOI.get(o,MOI.TerminationStatus())===MOI.ITERATION_LIMIT
            @test cap==0 || !decomposition(o)["separator"]["proof_complete"] # absent plan before initial evaluation
            @test MOI.get(o,MOI.ResultCount())==(cap==0 ? 0 : 1)
            cap>0 && @test QUBOTools.state(o,1)==[0,0,0]
        end
        for calls in 0:3
            o=sep_solve(trap,[1];budget=1,max_child_calls=calls)
            @test MOI.get(o,MOI.TerminationStatus())===MOI.ITERATION_LIMIT
            @test decomposition(o)["attempted_calls"]==calls
            @test QUBOTools.state(o,1)==[0,0,0]
        end
        o=sep_solve(trap,[1];budget=1,max_child_calls=4,max_candidate_evaluations=need)
        @test MOI.get(o,MOI.TerminationStatus())===MOI.OPTIMAL
        @test decomposition(o)["separator"]["proof_complete"]
        for phase in (:separator_initial,:separator_conditioning,:reconstruct,:separator_candidate,:separator_commit)
            o=QUBODecomposition.Optimizer(child_optimizer=()->FixtureChild(),max_variables=1,strategy=:separator,separator=[1])
            QUBODrivers.set_model!(o,trap)
            visits=Ref(0)
            o.checkpoint=p->(if p===phase;visits[]+=1;visits[]==2 && throw(InterruptException());end)
            MOI.optimize!(o)
            @test MOI.get(o,MOI.TerminationStatus())===MOI.INTERRUPTED
            @test QUBOTools.state(o,1)==[0,0,0]
            @test !decomposition(o)["separator"]["proof_complete"]
        end
        o=QUBODecomposition.Optimizer(child_optimizer=()->FixtureChild(rows=[[0],[1]]),max_variables=1,strategy=:separator,separator=[1],max_candidate_evaluations=3)
        QUBODrivers.set_model!(o,trap);MOI.optimize!(o)
        @test MOI.get(o,MOI.TerminationStatus())===MOI.ITERATION_LIMIT
        @test decomposition(o)["completed_calls"]==0
        @test QUBOTools.state(o,1)==[0,0,0]
        for failure in (false,true)
            clock=Ref(0.)
            o=QUBODecomposition.Optimizer(child_optimizer=()->FixtureChild(callback=_->(clock[]=2.),status=failure ? MOI.OTHER_ERROR : MOI.OPTIMAL),max_variables=1,strategy=:separator,separator=[1])
            QUBODrivers.set_model!(o,trap);o.clock=()->clock[];MOI.set(o,MOI.TimeLimitSec(),1.)
            MOI.optimize!(o)
            @test MOI.get(o,MOI.TerminationStatus())===(failure ? MOI.OTHER_ERROR : MOI.TIME_LIMIT)
            @test QUBOTools.state(o,1)==[0,0,0]
        end
        # Full separator needs no calls; charge each direct branch evaluation.
        for cap in (16,17)
            o=sep_solve(trap,[1,2,3];budget=1,max_child_calls=0,max_candidate_evaluations=cap)
            @test MOI.get(o,MOI.TerminationStatus())===(cap==17 ? MOI.OPTIMAL : MOI.ITERATION_LIMIT)
            @test decomposition(o)["attempted_calls"]==0
        end
    end

    @testset "Mixed constant residuals and certificate isolation" begin
        m, scalar, expected = instance(2,[(1,2)];linear=[2.,-1.],weights=[1.],offset=0.)
        o=sep_solve(m,[1];budget=1,max_child_calls=1,max_candidate_evaluations=7)
        p=decomposition(o)["separator"]
        @test MOI.get(o,MOI.TerminationStatus())===MOI.OPTIMAL
        @test QUBOTools.value(o,1)==expected==scalar(QUBOTools.state(o,1))
        @test p["component_certificates"]==[1] && p["constant_components"]==[1]
        @test decomposition(o)["candidate_evaluations"]==7
        calls=Ref(0)
        child=()->(calls[]+=1;FixtureChild(status=calls[]==2 ? MOI.LOCALLY_SOLVED : MOI.OPTIMAL))
        o=sep_solve(trap,[1];budget=1,child)
        p=decomposition(o)["separator"]
        @test p["certified_branches"]==1 && p["completed_branches"]==2
        @test p["component_certificates"]==[2,1]
        @test !p["proof_complete"]
        # Once a complete branch improves the incumbent, a failed later branch
        # retains it; no branch starts from the partially explored predecessor.
        negative,_,_=instance(3,[(1,2),(1,3)];linear=[2.,-1.,-1.],weights=[-4.,-4.],offset=0.)
        calls[]=0
        child=()->(calls[]+=1;calls[]==4 ? FixtureChild(status=MOI.INTERRUPTED) : FixtureChild())
        o=sep_solve(negative,[1];budget=1,child)
        @test MOI.get(o,MOI.TerminationStatus())===MOI.INTERRUPTED
        @test QUBOTools.state(o,1)==[0,1,1]
        @test QUBOTools.value(o,1)==-2.
        @test decomposition(o)["separator"]["completed_branches"]==1
    end

    @testset "Review: metadata ownership and certificate reasons" begin
        o=sep_solve(trap,[1];budget=1)
        decomposition(o)["configured_caps"]["separator"][1]=2
        @test MOI.get(o,MOI.RawOptimizerAttribute("separator"))==[1]
        MOI.optimize!(o)
        @test decomposition(o)["separator"]["indices"]==[1]
        @test QUBOTools.value(o,1)==trap_optimum
        for (calls,evals) in ((4,100),(10,13),(4,13))
            o=sep_solve(trap,[1];budget=1,child=()->QUBODrivers.ExactSampler.Optimizer(),
                max_child_calls=calls,max_candidate_evaluations=evals)
            d=decomposition(o);p=d["separator"]
            @test MOI.get(o,MOI.TerminationStatus())===MOI.ITERATION_LIMIT
            @test p["completed_branches"]==p["required_branches"]==2
            @test p["incomplete_reason"]=="uncertified_components"
            @test d["stop_reason"]==(calls==4 ? "max_child_calls" : "max_candidate_evaluations")
        end
    end

    @testset "Original free indices after MOI fixing and label reordering" begin
        # Original variable 1 is fixed; free index 1 is original variable 2.
        # Giving separator=[2] here would leave an oversized residual edge.
        for spin in (false,true), maximize in (false,true), separator in ([1],:articulation)
            source=MOI.Utilities.UniversalFallback(MOI.Utilities.Model{Float64}())
            vars=MOI.add_variables(source,4)
            for v in vars
                MOI.add_constraint(source,v,spin ? QUBODrivers.Spin() : MOI.ZeroOne())
            end
            fixed=spin ? -1. : 1.
            MOI.add_constraint(source,vars[1],MOI.EqualTo(fixed))
            f=MOI.ScalarQuadraticFunction(
                [MOI.ScalarQuadraticTerm(c,vars[i],vars[j]) for (i,j,c) in ((1,2,3.),(2,3,-4.),(2,4,-4.))],
                [MOI.ScalarAffineTerm(c,v) for (c,v) in zip([2.,2.,1.,1.],vars)],5.)
            MOI.set(source,MOI.ObjectiveFunction{typeof(f)}(),f)
            MOI.set(source,MOI.ObjectiveSense(),maximize ? MOI.MAX_SENSE : MOI.MIN_SENSE)
            o=QUBODecomposition.Optimizer(child_optimizer=()->FixtureChild(),max_variables=1,
                strategy=:separator,separator=separator)
            map=MOI.copy_to(o,source);MOI.optimize!(o)
            x=[MOI.get(o,MOI.VariablePrimal(),map[v]) for v in vars]
            scalar(x)=5+2x[1]+2x[2]+x[3]+x[4]+3x[1]*x[2]-4x[2]*x[3]-4x[2]*x[4]
            values=[scalar([fixed;y...]) for y in Iterators.product(fill(spin ? (-1,1) : (0,1),3)...)]
            @test MOI.get(o,MOI.TerminationStatus())===MOI.OPTIMAL
            @test x[1]==fixed
            @test scalar(x)==MOI.get(o,MOI.ObjectiveValue())==(maximize ? maximum(values) : minimum(values))
            @test decomposition(o)["labels"]==[map[v] for v in vars[2:4]]
            @test QUBOTools.state(o,1)==x[2:4]
            @test decomposition(o)["separator"]["residual_components"]==[[2],[3]]
            @test all(c["boundary_fixed_variables"]==Dict(1=>(c["branch"]==1 ? (spin ? -1 : 0) : 1))
                for c in decomposition(o)["calls"])
        end
        # Dictionary construction canonicalizes labels: the named center :z is
        # index 3, despite being inserted first. Coefficients are label keyed.
        m=QUBOTools.Model(Dict(:z=>2.,:a=>1.,:m=>1.),Dict((:z,:a)=>-4.,(:z,:m)=>-4.))
        @test QUBOTools.variables(m)==[:a,:m,:z]
        o=sep_solve(m,[QUBOTools.index(m,:z)];budget=1)
        @test MOI.get(o,MOI.TerminationStatus())===MOI.OPTIMAL
        @test QUBOTools.value(o,1)==-4.
        @test QUBOTools.state(o,1)==[1,1,1]
        @test decomposition(o)["separator"]["indices"]==[3]
    end

    @testset "Repeated solves rebuild branch and proof state" begin
        o=sep_solve(trap,[1];budget=1)
        for (s,budget) in ((Int[],1),(Int[],3),([1,2,3],1),([1],1))
            MOI.set(o,MOI.RawOptimizerAttribute("separator"),s)
            MOI.set(o,MOI.RawOptimizerAttribute("max_variables"),budget)
            @test MOI.get(o,MOI.ResultCount())==0
            MOI.optimize!(o)
            @test MOI.get(o,MOI.TerminationStatus())===(isempty(s)&&budget==1 ? MOI.INVALID_OPTION : MOI.OPTIMAL)
            isempty(s)&&budget==1 && continue
            @test QUBOTools.value(o,1)==trap_optimum
            @test decomposition(o)["separator"]["completed_branches"]==2^length(s)
        end
        QUBODrivers.set_model!(o,first(instance(1,Tuple{Int,Int}[];linear=[-2.])))
        MOI.optimize!(o)
        @test decomposition(o)["dimension"]==1
        @test QUBOTools.state(o,1)==[1]
        MOI.set(o,MOI.RawOptimizerAttribute("max_separator_size"),0);MOI.optimize!(o)
        @test MOI.get(o,MOI.TerminationStatus())===MOI.INVALID_OPTION
        MOI.set(o,MOI.RawOptimizerAttribute("strategy"),:whole_model);MOI.optimize!(o)
        @test MOI.get(o,MOI.TerminationStatus())===MOI.OPTIMAL
        @test decomposition(o)["separator"]===nothing
    end
end

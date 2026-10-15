# SPDX-License-Identifier: MPL-2.0
# Independent rational_child and original_oracle are defined in pruning.jl.
# Every consensus solve gets a fresh aggregate enumeration guard, including calls
# that fail. The guard reserves before enumeration or allocation.
function consensus_oracle_child(work=Ref(0); status=MOI.OPTIMAL)
    c = rational_child(; status)
    enumerate = c.callback
    c.callback = child -> begin
        n = length(MOI.get(child.model,MOI.ListOfVariableIndices()))
        n <= 4 || error("consensus test child limited to four variables")
        work[] + (1 << n) <= 1024 || error("consensus test child aggregate allowance")
        work[] += 1 << n
        enumerate(child)
    end
    return c
end
function consensus_solve(m, plan; child=nothing, kwargs...)
    work=Ref(0)
    factory=child === nothing ? ()->consensus_oracle_child(work) : child
    solve_model(m; strategy=:consensus, consensus_plan=plan, budget=4, child=factory, kwargs...)
end

@testset "Bounded serial Lagrangian consensus" begin
    @testset "Ownership, lifting, domains, senses and original oracle" begin
        for domain in (:bool,:spin), sense in (:min,:max), scale in (-2.5,0.,.75,1.)
            m=QUBOTools.Model{Symbol,Float64,Int}([:z,:a,:q,:isolate],
                [1,2,3,4],[-2.,3.,-1.,.5],[1,2],[2,3],[-4.,2.];domain,sense,scale,offset=3.25)
            plan=[[2,1],[3,2],[4]]
            o=consensus_solve(m,plan;consensus_iterations=6)
            d=decomposition(o); c=d["consensus"]
            @test MOI.get(o,MOI.TerminationStatus()) === (scale==0 ? MOI.OPTIMAL : MOI.LOCALLY_SOLVED)
            @test c["blocks"]==[[1,2],[2,3],[4]]
            @test c["linear_owners"]==[1,1,2,3]
            @test c["quadratic_owners"]==[1,2]
            @test c["equalities"]==[(2,1,1,2)]
            energy,optimum=original_oracle(m)
            sign=sense===:min ? 1 : -1
            @test c["incumbent_normalized"]==sign*energy(QUBOTools.state(o,1))
            @test c["best_lower_bound"] <= sign*optimum <= c["incumbent_normalized"]
            @test c["absolute_gap"]==c["incumbent_normalized"]-c["best_lower_bound"]
            # Independently distribute terms and evaluate equal-copy and relaxed
            # identities, without production plan/energy/transfer helpers.
            values=domain===:bool ? (0,1) : (-1,1)
            q=Rational{BigInt}
            for row in Iterators.product(fill(values,4)...)
                copies=[collect(row[b]) for b in c["blocks"]]
                total=sign*q(scale)*q(QUBOTools.offset(m))
                for (i,a) in QUBOTools.linear_terms(m)
                    owner=findfirst(b->i in b,c["blocks"])
                    total+=sign*q(scale)*q(a)*copies[owner][findfirst(==(i),c["blocks"][owner])]
                end
                for ((i,j),a) in QUBOTools.quadratic_terms(m)
                    owner=findfirst(b->i in b && j in b,c["blocks"])
                    total+=sign*q(scale)*q(a)*copies[owner][findfirst(==(i),c["blocks"][owner])]*copies[owner][findfirst(==(j),c["blocks"][owner])]
                end
                @test total==sign*energy(row)
                @test all(copies[p][j]==copies[rp][rj] for (p,j,rp,rj) in c["equalities"])
            end
            for h in c["history"]
                @test h["candidate_normalized"]==sign*energy(h["candidate"])
                @test h["lower_bound"]<=sign*optimum
                # Enumerate the independent intended block polynomials and add
                # constant once; this is an independent exact dual oracle.
                g=sign*q(scale)*q(QUBOTools.offset(m))
                for (p,b) in enumerate(c["blocks"])
                    block_values=Rational{BigInt}[]
                    for z in Iterators.product(fill(values,length(b))...)
                        value=big(0)//1
                        for (i,a) in QUBOTools.linear_terms(m)
                            findfirst(bb->i in bb,c["blocks"])==p || continue
                            value+=sign*q(scale)*q(a)*z[findfirst(==(i),b)]
                        end
                        for ((i,j),a) in QUBOTools.quadratic_terms(m)
                            findfirst(bb->i in bb && j in bb,c["blocks"])==p || continue
                            value+=sign*q(scale)*q(a)*z[findfirst(==(i),b)]*z[findfirst(==(j),b)]
                        end
                        for ((ep,ej,rp,rj),lambda) in zip(c["equalities"],h["multipliers"])
                            ep==p && (value+=q(lambda)*z[ej])
                            rp==p && (value-=q(lambda)*z[rj])
                        end
                        push!(block_values,value)
                    end
                    g+=minimum(block_values)
                end
                @test h["lower_bound"]<=g
                h["supergradient_certified"] && @test h["lower_bound"]==g
            end
            @test all(length(call["selected_indices"])<=4 for call in d["calls"])
        end
    end
    @testset "Surrogate ranking is independent of lifted original ranking" begin
        m=QUBOTools.Model(Dict(:a=>2.,:b=>0.,:c=>0.),Dict((:a,:b)=>-4.,(:b,:c)=>10.))
        QUBOTools.attach!(m,Dict(:c=>1))
        count=Ref(0)
        child=()->begin
            count[]+=1
            FixtureChild(rows=count[]==1 ? [[1,1],[0,0]] : [[0,0]],
                values=count[]==1 ? [-2.,0.] : [0.])
        end
        o=consensus_solve(m,[[1,2],[2,3]];child,consensus_iterations=1)
        @test QUBOTools.state(o,1)==[1,1,0]
        @test QUBOTools.value(o,1)==-2.
        @test decomposition(o)["consensus"]["history"][1]["copy_solutions"]==[[1,1],[0,0]]
        @test decomposition(o)["consensus"]["best_lower_bound"]==-2
        @test occursin("surrogate",QUBOTools.metadata(QUBOTools.solution(o))["reads"]["meaning"])
    end
    @testset "Disagreement, ties, gap and honest children" begin
        triangle=QUBOTools.Model(Dict(:a=>0.,:b=>0.,:c=>0.),
            Dict((:a,:b)=>1.,(:b,:c)=>1.,(:a,:c)=>1.);domain=:spin)
        plan=[[1,2],[2,3],[1,3]]
        o=consensus_solve(triangle,plan;consensus_iterations=8,consensus_stagnation=8)
        c=decomposition(o)["consensus"]
        @test any(!all(iszero,h["disagreement"]) for h in c["history"])
        @test c["absolute_gap"]>0
        @test c["best_lower_bound"] < -1
        @test MOI.get(o,MOI.TerminationStatus())===MOI.LOCALLY_SOLVED
        @test c["history"][1]["multipliers"]==zeros(3)
        @test c["history"][2]["multipliers"]==Float64.(c["history"][1]["disagreement"])
        for factory in (() -> consensus_oracle_child(;status=MOI.LOCALLY_SOLVED),
            () -> QUBODrivers.ExactSampler.Optimizer(),
            () -> FixtureChild(status=MOI.LOCALLY_SOLVED,rows=[[1,1]]))
            o=consensus_solve(triangle,plan;child=factory)
            c=decomposition(o)["consensus"]
            @test c["best_lower_bound"]===nothing
            @test c["absolute_gap"]===nothing
            @test all(h["lower_bound"]===nothing && !h["supergradient_certified"] for h in c["history"])
            @test MOI.get(o,MOI.TerminationStatus())===MOI.LOCALLY_SOLVED
        end
        # Certificate evidence persists when a later completed iteration has only
        # heuristic children. An interruption in that iteration is also atomic.
        for interrupt in (false,true)
            count=Ref(0); work=Ref(0)
            factory=()->begin
                count[]+=1
                consensus_oracle_child(work;status=count[]<=3 ? MOI.OPTIMAL : interrupt ? MOI.INTERRUPTED : MOI.LOCALLY_SOLVED)
            end
            o=consensus_solve(triangle,plan;child=factory,consensus_iterations=3,consensus_stagnation=3)
            c=decomposition(o)["consensus"]
            @test c["best_lower_bound"]==-3
            @test c["best_bound_iteration"]==1
            @test c["completed_iterations"]==(interrupt ? 1 : 3)
            @test MOI.get(o,MOI.TerminationStatus())===(interrupt ? MOI.INTERRUPTED : MOI.LOCALLY_SOLVED)
        end
        o=consensus_solve(triangle,plan;consensus_iterations=4,consensus_stagnation=4,
            consensus_history_limit=1,consensus_multiplier_limit=.25)
        c=decomposition(o)["consensus"]
        @test length(c["history"])==1
        @test c["history_dropped"]==c["completed_iterations"]-1
        @test all(abs(x)<=.25 for x in c["history"][1]["multipliers"])
        # Spin disagreements have magnitude two: finite step overflow must stop,
        # preserving the committed first iteration, never clamping infinity.
        o=consensus_solve(triangle,plan;consensus_step=floatmax(Float64))
        @test MOI.get(o,MOI.TerminationStatus())===MOI.NORM_LIMIT
        @test decomposition(o)["consensus"]["completed_iterations"]==1
    end
    @testset "Invalid plans and combinations precede any dispatch" begin
        m=direct_model()
        for plan in ([],[[1,2],[2,3]],[[1,2],[3,4]],[[1,1],[2,3],[4]],[[1,2,3,4,1]],[[0],[1,2],[2,3],[4]],[[1,2],[2,3],[5]], [Int[],[1,2],[2,3],[4]])
            # Invalid positive-index syntax is rejected by the setter; remaining
            # structural checks run at solve time, always before a child factory.
            if any(any(i->i<1,b) for b in plan)
                @test_throws ArgumentError consensus_solve(m,plan)
            else
                count=Ref(0)
                o=consensus_solve(m,plan;child=()->(count[]+=1;consensus_oracle_child()))
                @test MOI.get(o,MOI.TerminationStatus())===MOI.INVALID_OPTION
                @test count[]==0
            end
        end
        for options in ((;selection=:partition,partition_plan=[[1,2],[3,4]]),
            (;separator=[1]),(;separator_pruning=true), (;selection=:bfs))
            o=consensus_solve(m,[[1,2],[2,3],[4]];options...)
            @test MOI.get(o,MOI.TerminationStatus())===MOI.INVALID_OPTION
            @test decomposition(o)["attempted_calls"]==0
        end
        for (key,bad) in ((:consensus_iterations,0),(:consensus_step,Inf),(:consensus_step,NaN),
            (:consensus_multiplier_limit,0),(:consensus_history_limit,10001),(:consensus_stagnation,true))
            @test_throws ArgumentError QUBODecomposition.Optimizer(;Dict(key=>bad)...)
        end
        # Validate topology even for a constant/zero-scale input.
        m=direct_model(;scale=0.)
        o=consensus_solve(m,[[1,2],[3,4]])
        @test MOI.get(o,MOI.TerminationStatus())===MOI.INVALID_OPTION
    end
    @testset "Fixed-variable reconstruction and failure transactions" begin
        for spin in (false,true), maximize in (false,true)
            source=MOI.Utilities.UniversalFallback(MOI.Utilities.Model{Float64}())
            vars=MOI.add_variables(source,4)
            for v in vars
                MOI.add_constraint(source,v,spin ? QUBODrivers.Spin() : MOI.ZeroOne())
            end
            fixed=spin ? -1. : 1.
            MOI.add_constraint(source,vars[1],MOI.EqualTo(fixed))
            f=MOI.ScalarQuadraticFunction(
                [MOI.ScalarQuadraticTerm(c,vars[i],vars[j]) for (i,j,c) in ((1,2,3.),(2,3,-4.),(3,4,2.))],
                [MOI.ScalarAffineTerm(c,v) for (c,v) in zip([2.,2.,1.,1.],vars)],5.)
            MOI.set(source,MOI.ObjectiveFunction{typeof(f)}(),f)
            MOI.set(source,MOI.ObjectiveSense(),maximize ? MOI.MAX_SENSE : MOI.MIN_SENSE)
            work=Ref(0)
            o=QUBODecomposition.Optimizer(child_optimizer=()->consensus_oracle_child(work),
                max_variables=2,strategy=:consensus,consensus_plan=[[1,2],[2,3]])
            map=MOI.copy_to(o,source); MOI.optimize!(o)
            x=[MOI.get(o,MOI.VariablePrimal(),map[v]) for v in vars]
            scalar(x)=5+2x[1]+2x[2]+x[3]+x[4]+3x[1]*x[2]-4x[2]*x[3]+2x[3]*x[4]
            values=[scalar([fixed;y...]) for y in Iterators.product(fill(spin ? (-1,1) : (0,1),3)...)]
            sign=maximize ? -1 : 1
            c=decomposition(o)["consensus"]
            @test x[1]==fixed
            @test c["incumbent_normalized"]==sign*scalar(x)
            @test c["best_lower_bound"]<=minimum(sign.*values)
            @test MOI.get(o,MOI.TerminationStatus())===MOI.LOCALLY_SOLVED
        end
        triangle=QUBOTools.Model(Dict(:a=>0.,:b=>0.,:c=>0.),
            Dict((:a,:b)=>1.,(:b,:c)=>1.,(:a,:c)=>1.);domain=:spin)
        plan=[[1,2],[2,3],[1,3]]
        for status in (MOI.ALMOST_OPTIMAL, MOI.TIME_LIMIT)
            o=consensus_solve(triangle,plan;child=()->consensus_oracle_child(;status))
            @test decomposition(o)["consensus"]["best_lower_bound"]===nothing
        end
        for mode in (:cap,:interrupt,:malformed)
            count=Ref(0); work=Ref(0)
            factory=()->begin
                count[]+=1
                count[]==4 && mode===:malformed && return FixtureChild(rows=[[NaN,1]])
                consensus_oracle_child(work)
            end
            o=consensus_solve(triangle,plan;child=factory,
                max_child_calls=mode===:cap ? 4 : 64)
            if mode===:interrupt
                count[]=0; work[]=0
                o.checkpoint=p->(p===:consensus_update && throw(InterruptException()))
                MOI.optimize!(o)
            end
            c=decomposition(o)["consensus"]
            @test c["completed_iterations"]==1
            @test c["best_lower_bound"]==-3
            @test length(c["history"])==1
            @test MOI.get(o,MOI.TerminationStatus())===(mode===:cap ? MOI.ITERATION_LIMIT : mode===:interrupt ? MOI.INTERRUPTED : MOI.OTHER_ERROR)
        end
        m=QUBOTools.Model{Int,Float64,Int}(collect(1:5),[1],[-1.],Int[],Int[],Float64[])
        o=consensus_solve(m,[collect(1:5)])
        @test MOI.get(o,MOI.TerminationStatus())===MOI.INVALID_OPTION
        @test decomposition(o)["attempted_calls"]==0
    end
    @testset "Rounding and cancellation" begin
        for domain in (:bool,:spin), sense in (:min,:max)
            m=direct_model(;domain,sense,scale=.1,offset=2.0^54)
            o=consensus_solve(m,[[1,2],[2,3],[4]])
            energy,optimum=original_oracle(m); sign=sense===:min ? 1 : -1
            c=decomposition(o)["consensus"]
            @test c["best_lower_bound"]<=sign*optimum
            @test all(!h["supergradient_certified"] for h in c["history"])
            @test any(!call["transfer_preserved"] for call in decomposition(o)["calls"])
            @test c["absolute_gap"]>=0
            @test c["incumbent_normalized"]==sign*energy(QUBOTools.state(o,1))
        end
        # Iteration two adds H to the owned -1 coefficient. Dispatch rounds
        # H-1 to H and its tied minimum [0,0] is suboptimal for the intended
        # block. Without the exact residual correction the proposed lower bound
        # would exceed the original optimum by one.
        H=2.0^54
        rounded=QUBOTools.Model(Dict(:a=>0.,:b=>-1.,:c=>-2H),
            Dict((:a,:b)=>-H,(:b,:c)=>H))
        o=consensus_solve(rounded,[[1,2],[2,3]];consensus_step=H,
            consensus_multiplier_limit=H,consensus_iterations=2)
        c=decomposition(o)["consensus"]
        @test c["history"][2]["copy_solutions"][1]==[0,0]
        @test !c["history"][2]["supergradient_certified"]
        @test c["best_lower_bound"]==-2big(Int(H))-1
        @test c["incumbent_normalized"]==c["best_lower_bound"]
        @test MOI.get(o,MOI.TerminationStatus())===MOI.LOCALLY_SOLVED
        H=2.0^54
        m=QUBOTools.Model(Dict(:a=>0.,:b=>-1.),Dict((:a,:b)=>0.);offset=H)
        o=consensus_solve(m,[[1],[2]])
        @test QUBOTools.state(o,1)==[0,1]
        @test decomposition(o)["consensus"]["incumbent_normalized"]==big(Int(H))-1
        @test decomposition(o)["consensus"]["absolute_gap"]==0
        @test MOI.get(o,MOI.TerminationStatus())===MOI.LOCALLY_SOLVED
    end
    @testset "Interruption, shared caps and repeated solve invalidation" begin
        m=direct_model(); plan=[[1,2],[2,3],[4]]
        for cap in (0,1,2)
            o=consensus_solve(m,plan;max_child_calls=cap)
            @test decomposition(o)["attempted_calls"]==cap
            @test decomposition(o)["consensus"]["completed_iterations"]==0
            @test QUBOTools.state(o,1)==[0,0,0,0]
            @test MOI.get(o,MOI.TerminationStatus())===MOI.ITERATION_LIMIT
        end
        for cap in 1:4
            o=consensus_solve(m,plan;max_candidate_evaluations=cap)
            @test decomposition(o)["candidate_evaluations"]==cap
            @test decomposition(o)["consensus"]["best_lower_bound"]===nothing
            @test MOI.get(o,MOI.TerminationStatus())===MOI.ITERATION_LIMIT
        end
        for phase in (:consensus_plan,:consensus_surrogate,:consensus_block_energy,
            :consensus_reconcile,:consensus_iteration_commit)
            o=consensus_solve(m,plan)
            o.checkpoint=p->(p===phase && throw(InterruptException()))
            MOI.optimize!(o)
            @test MOI.get(o,MOI.TerminationStatus())===MOI.INTERRUPTED
            @test QUBOTools.state(o,1)==[0,0,0,0]
            @test decomposition(o)["consensus"]["completed_iterations"]==0
            o.checkpoint=_->nothing
            MOI.optimize!(o)
            @test MOI.get(o,MOI.TerminationStatus())===MOI.LOCALLY_SOLVED
        end
        o=consensus_solve(m,plan)
        now=Ref(0.); o.clock=()->now[]
        MOI.set(o,MOI.TimeLimitSec(),1.)
        o.checkpoint=p->(p===:consensus_surrogate && (now[]=2.))
        MOI.optimize!(o)
        @test MOI.get(o,MOI.TerminationStatus())===MOI.TIME_LIMIT
        @test decomposition(o)["attempted_calls"]==0
        @test decomposition(o)["consensus"]["best_lower_bound"]===nothing
        MOI.set(o,MOI.RawOptimizerAttribute("consensus_plan"),[[1,2],[3,4]])
        @test MOI.get(o,MOI.TerminationStatus())===MOI.OPTIMIZE_NOT_CALLED
        @test MOI.get(o,MOI.ResultCount())==0
    end
end

include("../../examples/consensus/offline.jl")
@test ConsensusExample.run().child_assignments <= 1024

# SPDX-License-Identifier: MPL-2.0
# Independent exhaustive oracle and child: neither calls the production bound,
# conditioner, lift, or energy routine. Guard before constructing a state product.
function original_oracle(m)
    n = QUBOTools.dimension(m)
    n <= 8 || error("original oracle limited to eight variables")
    q = x -> Rational{BigInt}(x)
    energy(x) = q(QUBOTools.scale(m)) * (q(QUBOTools.offset(m)) +
        sum((q(c)*x[i] for (i,c) in QUBOTools.linear_terms(m)); init=big(0)//1) +
        sum((q(c)*x[i]*x[j] for ((i,j),c) in QUBOTools.quadratic_terms(m)); init=big(0)//1))
    states = Iterators.product(fill(QUBOTools.domain(m) === QUBOTools.BoolDomain ? (0,1) : (-1,1), n)...)
    values = [energy(x) for x in states]
    return energy, (QUBOTools.sense(m) === QUBOTools.Min ? minimum : maximum)(values)
end

function rational_child(;status=MOI.OPTIMAL)
    return FixtureChild(;status, callback=c->begin
        vars = sort(MOI.get(c.model, MOI.ListOfVariableIndices()); by=v -> -v.value)
        length(vars) <= 8 || error("certified child limited to eight variables")
        f = MOI.get(c.model, MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{Float64}}())
        spin = !isempty(MOI.get(c.model, MOI.ListOfConstraintIndices{VI,QUBODrivers.Spin}()))
        sense = MOI.get(c.model, MOI.ObjectiveSense())
        best, value = nothing, nothing
        for row in Iterators.product(fill(spin ? (-1,1) : (0,1), length(vars))...)
            x = Dict(v=>row[i] for (i,v) in enumerate(vars))
            e = Rational{BigInt}(f.constant)
            for t in f.affine_terms
                e += Rational{BigInt}(t.coefficient)*x[t.variable]
            end
            for t in f.quadratic_terms
                e += Rational{BigInt}(t.coefficient)*x[t.variable_1]*x[t.variable_2] /
                    (t.variable_1 == t.variable_2 ? 2 : 1)
            end
            if value === nothing || (sense === MOI.MIN_SENSE ? e < value : e > value)
                best, value = collect(row), e
            end
        end
        c.scripted = true
        c.rows, c.values = Any[best], [Float64(value)]
    end)
end

prune_solve(m, s; enabled=true, child=rational_child, budget=2, kwargs...) =
    solve_model(m; strategy=:separator, separator=s, separator_pruning=enabled, child, budget, kwargs...)

@testset "Certified separator pruning" begin
    @test MOI.get(QUBODecomposition.Optimizer(), MOI.RawOptimizerAttribute("separator_pruning")) === false
    for bad in (0, 1, nothing, Symbol("true"))
        @test_throws ArgumentError QUBODecomposition.Optimizer(separator_pruning=bad)
    end
    @test_throws ErrorException original_oracle(QUBOTools.Model{Int,Float64,Int}(collect(1:9),Int[],Float64[],Int[],Int[],Float64[]))
    @testset "Original objective domain, sense, signed scale and maps" begin
        for domain in (:bool,:spin), sense in (:min,:max), scale in (-2.5, 0., .75, 1.), s in ([2],:articulation)
            m = QUBOTools.Model{Symbol,Float64,Int}([:a,:b,:c,:isolate],
                [1,2,3], [-2.,3.,-1.], [1,2], [2,3], [-4.,2.]; domain,sense,scale,offset=3.25)
            energy, optimum = original_oracle(m)
            off, on = prune_solve(m,s;enabled=false), prune_solve(m,s)
            for o in (off,on)
                @test energy(QUBOTools.state(o,1)) == optimum
                @test MOI.get(o,MOI.TerminationStatus()) === MOI.OPTIMAL
            end
            d=decomposition(on); p=d["separator"]
            @test p["completed_branches"] + p["certified_pruned_branches"] == p["required_branches"]
            @test p["unfinished_branches"] == 0
            @test p["bound_method"] == "exact_rational_original_termwise_v1"
            @test d["phase_sec"]["bound"] >= 0
            @test all(c["branch"] <= p["required_branches"] for c in d["calls"])
            @test !haskey(decomposition(off)["phase_sec"],"bound")
        end
        for spin in (false,true), maximize in (false,true)
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
            o=QUBODecomposition.Optimizer(child_optimizer=rational_child,max_variables=1,
                strategy=:separator,separator=[1],separator_pruning=true)
            map=MOI.copy_to(o,source);MOI.optimize!(o)
            x=[MOI.get(o,MOI.VariablePrimal(),map[v]) for v in vars]
            scalar(x)=5+2x[1]+2x[2]+x[3]+x[4]+3x[1]*x[2]-4x[2]*x[3]-4x[2]*x[4]
            values=[scalar([fixed;y...]) for y in Iterators.product(fill(spin ? (-1,1) : (0,1),3)...)]
            @test x[1]==fixed
            @test scalar(x)==(maximize ? maximum(values) : minimum(values))
            @test MOI.get(o,MOI.TerminationStatus())===MOI.OPTIMAL
        end
    end
    # First branch finds -2 from a poor all-zero start; later branch cannot beat it.
    useful=QUBOTools.Model(Dict(:a=>10.,:b=>-2.,:c=>-1.),Dict((:a,:b)=>1.,(:a,:c)=>1.);offset=4.)
    off,on=prune_solve(useful,[1];enabled=false,budget=1),prune_solve(useful,[1];budget=1)
    @test decomposition(on)["attempted_calls"] < decomposition(off)["attempted_calls"]
    @test decomposition(on)["separator"]["completed_branches"]==1
    @test decomposition(on)["separator"]["certified_pruned_branches"]==1
    @test QUBOTools.state(on,1)==[0,1,1]
    @test all(c["branch"]==1 for c in decomposition(on)["calls"])
    # Inconsistent term minima make this lower bound weak for both assignments.
    weak=QUBOTools.Model(Dict(:a=>-.25,:b=>-1.,:c=>-1.),Dict((:a,:b)=>.25,(:a,:c)=>.25,(:b,:c)=>4.))
    a,b=prune_solve(weak,[1];enabled=false),prune_solve(weak,[1])
    @test decomposition(a)["attempted_calls"]==decomposition(b)["attempted_calls"]==2
    @test decomposition(b)["separator"]["certified_pruned_branches"]==0
    tied=QUBOTools.Model(Dict(:a=>0.,:b=>0.),Dict((:a,:b)=>0.))
    o=prune_solve(tied,[1];max_child_calls=0)
    @test QUBOTools.state(o,1)==[0,0]
    @test decomposition(o)["separator"]["certified_pruned_branches"]==2
    @test MOI.get(o,MOI.TerminationStatus())===MOI.OPTIMAL

    @testset "Original arithmetic and incumbent replacement" begin
        # Summation erases x2's unit improvement when x1=x3=1. Enumerate every
        # variable directly so no child certificate or conditioning is involved.
        H=2.0^54
        m=QUBOTools.Model{Symbol,Float64,Int}([:a,:b,:c], [1,2,3], [H,-1.,-H],
            [1,2], [2,3], [H,H];offset=H)
        energy,optimum=original_oracle(m)
        o=prune_solve(m,[1,2,3])
        @test energy(QUBOTools.state(o,1))==optimum
        @test MOI.get(o,MOI.TerminationStatus())===MOI.OPTIMAL
        # Branch 0 is excluded at U=-2.5. Branch 1 has true optimum -2,
        # but scalar Float64 accumulation reports -2.75. Replacing the retained
        # incumbent by that rounded "improvement" would invalidate exclusion 0.
        # Put the large offset before the small cancellation terms.
        m=QUBOTools.Model{Symbol,Float64,Int}([:a,:b,:c],[1,2,3],[-1.25,-H,-.5],
            [1,2],[3,3],[1.75,-2.];offset=H)
        QUBOTools.attach!(m,Dict(:a=>0,:b=>1,:c=>1))
        energy,optimum=original_oracle(m)
        o=prune_solve(m,[1];budget=2)
        @test energy([1,1,1])==-2 && optimum==-5//2
        @test QUBODecomposition.full_energy([1,1,1],collect(QUBOTools.linear_terms(m)),
            collect(QUBOTools.quadratic_terms(m)),1.,H)==-2.75
        @test QUBOTools.state(o,1)==[0,1,1]
        @test energy(QUBOTools.state(o,1))==optimum
        @test decomposition(o)["separator"]["certified_pruned_branches"]==1
        @test only(decomposition(o)["calls"])["branch"]==2
        @test MOI.get(o,MOI.TerminationStatus())===MOI.OPTIMAL
        # A just-below bound rounds to the same Float64 as the incumbent.
        m=QUBOTools.Model(Dict(:a=>-1.,:b=>0.),Dict((:a,:b)=>0.);offset=H)
        o=prune_solve(m,[1,2])
        @test QUBOTools.state(o,1)==[1,0]
        @test decomposition(o)["separator"]["completed_branches"]==1
        @test decomposition(o)["separator"]["certified_pruned_branches"]==3
        # Conditioning loses the unit coefficient: do not transfer OPTIMAL from
        # the rounded child to the original mathematical objective.
        m=QUBOTools.Model(Dict(:a=>-H,:b=>1.,:c=>0.),Dict((:a,:b)=>H,(:b,:c)=>-H))
        energy,optimum=original_oracle(m)
        o=prune_solve(m,[1];budget=2)
        @test energy(QUBOTools.state(o,1))==optimum
        @test !decomposition(o)["separator"]["proof_complete"]
        @test decomposition(o)["separator"]["arithmetic_uncertified_branches"]>0
        @test MOI.get(o,MOI.TerminationStatus())!==MOI.OPTIMAL
    end

    @testset "Bounds against independent original branch oracles" begin
        for domain in (:bool,:spin), sense in (:min,:max), scale in (-.75,1.5)
            m=QUBOTools.Model{Int,Float64,Int}([91,3,47,2], [1,2,3,4],
                [2.25,-1.,.5,-3.], [1,1,2,3], [2,3,4,4], [-4.,2.,1.25,-.5];
                domain,sense,scale,offset=5.25)
            snap=QUBODecomposition.snapshot(m)
            o=QUBODecomposition.Optimizer()
            ctx=QUBODecomposition.SolveState(snap.state,0.,0,0,nothing,
                Dict{String,Any}("phase_sec"=>Dict("bound"=>0.)))
            cert=QUBODecomposition.prepare_pruning(o,ctx,snap)
            energy,_=original_oracle(m)
            values=domain===:bool ? (0,1) : (-1,1)
            for assigned in Iterators.product(values,values)
                state=[assigned[1],assigned[2],first(values),first(values)]
                lower=QUBODecomposition.separator_lower_bound(o,ctx,cert,state,[1,2])
                reference=minimum((sense===:min ? 1 : -1)*energy([assigned...;rest...])
                    for rest in Iterators.product(values,values))
                @test lower <= reference
            end
            unavailable=merge(snap,(;linear=[1=>NaN]))
            @test QUBODecomposition.prepare_pruning(o,ctx,unavailable)===nothing
            @test_throws ErrorException QUBODecomposition.pruning_energy(o,ctx,cert,[0])
        end
    end

    @testset "Heuristics, atomicity, deadlines, shared caps and reset" begin
        for child in (() -> rational_child(status=MOI.LOCALLY_SOLVED), () -> QUBODrivers.ExactSampler.Optimizer())
            o=prune_solve(weak,[1];child)
            @test MOI.get(o,MOI.TerminationStatus())===MOI.LOCALLY_SOLVED
            @test !decomposition(o)["separator"]["proof_complete"]
            @test all(!c["exact"] for c in decomposition(o)["calls"])
        end
        for phase in (:bound_prepare,:bound_incumbent,:bound_branch,:bound_terms,:bound_transfer,:bound_prune_commit)
            o=QUBODecomposition.Optimizer(child_optimizer=rational_child,max_variables=2,
                strategy=:separator,separator=[1],separator_pruning=true)
            QUBODrivers.set_model!(o,weak)
            o.checkpoint=p->(p===phase && throw(InterruptException()))
            MOI.optimize!(o)
            @test MOI.get(o,MOI.TerminationStatus())===MOI.INTERRUPTED
            @test QUBOTools.state(o,1)==[0,0,0]
            @test !decomposition(o)["separator"]["proof_complete"]
        end
        for cap in (0,1)
            o=prune_solve(weak,[1];max_child_calls=cap)
            @test MOI.get(o,MOI.TerminationStatus())===MOI.ITERATION_LIMIT
            @test decomposition(o)["attempted_calls"]==cap
            @test decomposition(o)["separator"]["unfinished_branches"]>0
        end
        for cap in 1:5
            o=prune_solve(weak,[1];max_candidate_evaluations=cap)
            @test MOI.get(o,MOI.TerminationStatus())===MOI.ITERATION_LIMIT
            @test decomposition(o)["candidate_evaluations"]==cap
            @test !decomposition(o)["separator"]["proof_complete"]
        end
        o=prune_solve(weak,[1])
        clock=Ref(0.)
        o.clock=()->clock[]
        MOI.set(o,MOI.TimeLimitSec(),1.)
        o.checkpoint=p->(p===:bound_terms && (clock[]=2.))
        MOI.optimize!(o)
        @test MOI.get(o,MOI.TerminationStatus())===MOI.TIME_LIMIT
        @test decomposition(o)["attempted_calls"]==0
        @test !decomposition(o)["separator"]["proof_complete"]
        o.checkpoint=_->nothing;clock[]=0.
        MOI.optimize!(o)
        @test decomposition(o)["separator"]["unfinished_branches"]==0
        @test MOI.get(o,MOI.TerminationStatus())===MOI.OPTIMAL
        MOI.set(o,MOI.RawOptimizerAttribute("separator_pruning"),false)
        MOI.optimize!(o)
        @test !haskey(decomposition(o)["phase_sec"],"bound")
        @test decomposition(o)["separator"]["certified_pruned_branches"]==0
        for bad in (() -> FixtureChild(rows=[]), () -> FixtureChild(rows=[[0,0]],values=[NaN]))
            o=prune_solve(weak,[1];child=bad)
            @test MOI.get(o,MOI.TerminationStatus())===MOI.OTHER_ERROR
            @test !decomposition(o)["separator"]["proof_complete"]
            @test QUBOTools.state(o,1)==[0,0,0]
        end
        m=QUBOTools.Model(Dict(:a=>NaN),Dict{Tuple{Symbol,Symbol},Float64}())
        o=prune_solve(m,[1])
        @test MOI.get(o,MOI.TerminationStatus())===MOI.OTHER_ERROR
        @test MOI.get(o,MOI.ResultCount())==0
    end
end

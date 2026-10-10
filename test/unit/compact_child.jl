# SPDX-License-Identifier: MPL-2.0
include("../../examples/compact_child/adapter.jl")
const CCE = CompactChildExperiment
@testset "Certified exhaustive versus compact child results" begin
    function fixture(; domain=:bool, sense=:min, scale=1.5, edges=[(1,2),(2,3),(3,4)])
        labels=[:zeta,:alpha,:mu,:isolated]
        linear=[-2.,1.,-3.,0.]; weights=[-4.,2.,-1.][1:length(edges)]
        m=QUBOTools.Model{Symbol,Float64,Int}(labels,1:4,linear,
            first.(edges),last.(edges),weights; domain,sense,scale,offset=3.25)
        scalar(x)=scale*(3.25+sum(linear .* x)+sum(weights[k]*x[i]*x[j] for (k,(i,j)) in enumerate(edges);init=0.))
        states=collect(Iterators.product(fill(domain===:bool ? (0,1) : (-1,1),4)...))
        oracle=(sense===:min ? minimum : maximum)(scalar.(states))
        return m,scalar,oracle
    end
    function solve(m,mode; ledger=CCE.Ledger(), source_hook=identity, kwargs...)
        o=solve_model(m;child=()->CCE.child(ledger;mode,source_hook),kwargs...)
        return o,ledger
    end
    for domain in (:bool,:spin), sense in (:min,:max), scale in (-2.5,0.75), route in (:whole_model,:components,:separator)
        edges=route===:components ? [(1,2),(3,4)] : [(1,2),(2,3),(3,4)]
        m,scalar,oracle=fixture(;domain,sense,scale,edges)
        options=route===:separator ? (;strategy=route,separator=[2],budget=2) : (;strategy=route,budget=route===:components ? 2 : 4)
        work=Int[];rows=Int[]
        for mode in (:all,:compact)
            o,l=solve(m,mode;options...)
            @test MOI.get(o,MOI.TerminationStatus())===MOI.OPTIMAL
            @test QUBOTools.value(o,1)==scalar(QUBOTools.state(o,1))==oracle
            @test all(x->x in (domain===:bool ? (0,1) : (-1,1)),QUBOTools.state(o,1))
            @test decomposition(o)["labels"]==QUBOTools.variables(m)
            @test all(c["certificate_checked"] && !c["failed"] && c["reserved_assignments"]==c["actual_assignments"] for c in l.calls)
            @test all(c["valid_results"]==c["reported_results"] && c["invalid_results"]==0 for c in decomposition(o)["calls"])
            if route===:separator
                @test decomposition(o)["separator"]["proof_complete"]
                @test decomposition(o)["separator"]["certified_branches"]==2
            end
            push!(work,l.reserved); push!(rows,sum(c["rows_emitted"] for c in l.calls))
        end
        @test work[1]==work[2]
        @test rows[1]>rows[2]
    end
    @testset "Tie choice, exhaustive guard and independent work ledger" begin
        for domain in (:bool,:spin), mode in (:all,:compact)
            # Two tied optimal states differ in the second variable.
            m=QUBOTools.Model{VI,Float64,Int}(VI.(1:2),[1],[-1.],Int[],Int[],Float64[];domain)
            l=CCE.Ledger(4); c=CCE.child(l;mode); QUBODrivers.set_model!(c,m); MOI.optimize!(c)
            if mode===:compact
                @test QUBOTools.state(c,1)==[1,domain===:bool ? 0 : -1]
                @test MOI.get(c,MOI.ResultCount())==1
                @test QUBOTools.reads(c,1)==1
            end
            @test l.reserved==only(l.calls)["actual_assignments"]==4
            @test QUBOTools.metadata(QUBOTools.solution(c))["optimizer"]["evaluations"]==4
        end
        @test CCE.exact_size(8)==256
        for n in (-1,9,typemax(Int),true)
            @test_throws ArgumentError CCE.exact_size(n)
        end
        m,_,_=fixture()
        o,l=solve(m,:compact;ledger=CCE.Ledger(15))
        @test MOI.get(o,MOI.TerminationStatus())===MOI.OTHER_ERROR
        @test l.reserved==0 && !only(l.calls)["dispatched"]
        huge=QUBOTools.Model{Int,Float64,Int}(1:9,1:9,fill(-1.,9),Int[],Int[],Float64[])
        o,l=solve(huge,:compact;budget=9)
        @test MOI.get(o,MOI.TerminationStatus())===MOI.OTHER_ERROR
        @test isempty(l.calls) && l.reserved==0
    end
    @testset "Compaction must not hide malformed exhaustive source" begin
        faults=[
            s->delete!(QUBOTools.metadata(QUBOTools.solution(s)),"termination_status"),
            s->(QUBOTools.metadata(QUBOTools.solution(s))["termination_status"]=MOI.TIME_LIMIT),
            s->(QUBOTools.metadata(QUBOTools.solution(s))["optimizer"]["evaluations"]=1),
            s->(QUBOTools.metadata(QUBOTools.solution(s))["execution"]["mode"]="heuristic"),
            s->pop!(QUBOTools.solution(s).data),
            s->(QUBOTools.state(s,length(QUBOTools.solution(s)))[1]=2),
            s->(QUBOTools.solution(s).data[end]=QUBOTools.solution(s).data[1]),
            s->(QUBOTools.solution(s).data[end]=QUBOTools.Sample{Float64,Int}(copy(QUBOTools.state(s,length(QUBOTools.solution(s)))),NaN,1)),
            s->(QUBOTools.solution(s).data[end]=QUBOTools.Sample{Float64,Int}(copy(QUBOTools.state(s,length(QUBOTools.solution(s)))),12345.,1)),
            s->(QUBOTools.solution(s).data[end]=QUBOTools.Sample{Float64,Int}(copy(QUBOTools.state(s,length(QUBOTools.solution(s)))),QUBOTools.value(s,length(QUBOTools.solution(s))),2)),
        ]
        m,_,_=fixture()
        for mode in (:all,:compact), fault in faults
            o,l=solve(m,mode;source_hook=fault)
            @test MOI.get(o,MOI.TerminationStatus())===MOI.OTHER_ERROR
            @test l.reserved==only(l.calls)["actual_assignments"]==16
            @test !only(l.calls)["certificate_checked"] && only(l.calls)["rows_emitted"]==0
            @test QUBOTools.state(o,1)==zeros(Int,4)
            @test decomposition(o)["completed_calls"]==0
        end
    end
    @testset "Incomplete branches, child interruption and exhausted budgets" begin
        m,_,_=fixture()
        for mode in (:all,:compact), which in (:child,:branch,:candidates,:calls,:ledger,:deadline)
            l=CCE.Ledger(which===:ledger ? 2 : 1024)
            hook=which===:child ? s->throw(InterruptException()) : identity
            o=QUBODecomposition.Optimizer(child_optimizer=()->CCE.child(l;mode,source_hook=hook),
                max_variables=2,strategy=:separator,separator=[2],
                max_candidate_evaluations=which===:candidates ? 3 : 100,
                max_child_calls=which===:calls ? 1 : 100)
            QUBODrivers.set_model!(o,m)
            which===:branch && (o.checkpoint=p->(p===:separator_candidate && throw(InterruptException())))
            which===:deadline && MOI.set(o,MOI.TimeLimitSec(),0.)
            MOI.optimize!(o)
            @test MOI.get(o,MOI.TerminationStatus())!==MOI.OPTIMAL
            p=decomposition(o)["separator"]
            @test p===nothing || !p["proof_complete"]
            @test decomposition(o)["completed_calls"]<4
            which===:child && @test only(l.calls)["actual_assignments"]==2 && l.reserved==2
            which===:deadline && @test isempty(l.calls)
        end
        # A genuinely incomplete child cannot be promoted merely by retaining one row.
        o,l=solve(m,:compact;source_hook=s->(QUBOTools.metadata(QUBOTools.solution(s))["termination_status"]=MOI.INTERRUPTED))
        @test MOI.get(o,MOI.TerminationStatus())===MOI.OTHER_ERROR
        @test only(l.calls)["rows_emitted"]==0
    end
    @testset "Repeated parent/adapter solves clear result and proof" begin
        m,_,_=fixture(); l=CCE.Ledger(); fail=Ref(false)
        hook=s->(fail[] && error("later failed source"))
        o=solve_model(m;child=()->CCE.child(l;mode=:compact,source_hook=hook),budget=2,strategy=:separator,separator=[2])
        @test MOI.get(o,MOI.TerminationStatus())===MOI.OPTIMAL
        fail[]=true; MOI.optimize!(o)
        @test MOI.get(o,MOI.TerminationStatus())===MOI.OTHER_ERROR
        @test !decomposition(o)["separator"]["proof_complete"]
        @test QUBOTools.state(o,1)==zeros(Int,4)
        fail[]=false; MOI.optimize!(o)
        @test MOI.get(o,MOI.TerminationStatus())===MOI.OPTIMAL
        @test decomposition(o)["invocation"]==3
        c=CCE.child(CCE.Ledger();mode=:compact,source_hook=hook)
        cm=QUBOTools.Model{VI,Float64,Int}(VI.(1:2),1:2,[-1.,-2.],Int[],Int[],Float64[])
        QUBODrivers.set_model!(c,cm); MOI.optimize!(c)
        fail[]=true
        @test_throws ErrorException MOI.optimize!(c)
        @test MOI.get(c,MOI.TerminationStatus())===MOI.OPTIMIZE_NOT_CALLED
        @test MOI.get(c,MOI.ResultCount())==0
    end
end

@testset "Compact certified result after MOI fixing and relabeling" begin
    for mode in (:all,:compact), spin in (false,true), sense in (MOI.MIN_SENSE,MOI.MAX_SENSE)
        src=MOI.Utilities.UniversalFallback(MOI.Utilities.Model{Float64}())
        unused=MOI.add_variables(src,5); MOI.delete(src,unused)
        vars=MOI.add_variables(src,4)
        for v in vars
            MOI.add_constraint(src,v,spin ? QUBODrivers.Spin() : MOI.ZeroOne())
        end
        fixed=spin ? -1. : 1.
        MOI.add_constraint(src,vars[1],MOI.EqualTo(fixed))
        f=MOI.ScalarQuadraticFunction([MOI.ScalarQuadraticTerm(c,vars[i],vars[j]) for (i,j,c) in ((1,2,3.),(2,3,-4.),(2,4,-4.))],
            [MOI.ScalarAffineTerm(c,v) for (c,v) in zip([2.,2.,1.,1.],vars)],5.)
        MOI.set(src,MOI.ObjectiveFunction{typeof(f)}(),f); MOI.set(src,MOI.ObjectiveSense(),sense)
        ledger=CCE.Ledger()
        o=QUBODecomposition.Optimizer(child_optimizer=()->CCE.child(ledger;mode),max_variables=1,strategy=:separator,separator=[1])
        map=MOI.copy_to(o,src); MOI.optimize!(o)
        x=[MOI.get(o,MOI.VariablePrimal(),map[v]) for v in vars]
        scalar(x)=5+2x[1]+2x[2]+x[3]+x[4]+3x[1]*x[2]-4x[2]*x[3]-4x[2]*x[4]
        values=[scalar([fixed;y...]) for y in Iterators.product(fill(spin ? (-1,1) : (0,1),3)...)]
        @test MOI.get(o,MOI.TerminationStatus())===MOI.OPTIMAL
        @test x[1]==fixed
        @test scalar(x)==MOI.get(o,MOI.ObjectiveValue())==(sense===MOI.MIN_SENSE ? minimum(values) : maximum(values))
        @test decomposition(o)["labels"]==[map[v] for v in vars[2:4]]
        @test decomposition(o)["separator"]["proof_complete"]
    end
end

# A public-result proxy checks that the certificate validator actually queries
# primal status rather than trusting exhaustive-count metadata alone.
struct BadPrimalSource{S}
    source::S
end
QUBOTools.solution(s::BadPrimalSource)=QUBOTools.solution(s.source)
QUBOTools.backend(s::BadPrimalSource)=QUBOTools.backend(s.source)
MOI.get(s::BadPrimalSource,a,args...)=MOI.get(s.source,a,args...)
MOI.get(::BadPrimalSource,::MOI.PrimalStatus)=MOI.NO_SOLUTION
@testset "Source primal status and mapping are certificate premises" begin
    model=QUBOTools.Model{VI,Float64,Int}(VI.(1:2),1:2,[-1.,-2.],Int[],Int[],Float64[])
    source=QUBODrivers.ExactSampler.Optimizer();QUBODrivers.set_model!(source,copy(model));MOI.optimize!(source)
    @test_throws ErrorException CCE.validate_source(BadPrimalSource(source),model,4)
    altered=QUBOTools.Model{VI,Float64,Int}(VI.([5,8]),1:2,[-1.,-2.],Int[],Int[],Float64[])
    @test_throws ErrorException CCE.validate_source(source,altered,4)
    @test CCE.validate_source(source,model,4)==([1,1],-3.)
    @test MOI.get(source,MOI.TerminationStatus())===MOI.LOCALLY_SOLVED
end

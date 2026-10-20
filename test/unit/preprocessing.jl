# SPDX-License-Identifier: MPL-2.0
import QUBOPreprocessing

function root_scalar(model,state)
    R=Rational{BigInt}
    value=R(QUBOTools.offset(model))
    for (i,c) in QUBOTools.linear_terms(model);value+=R(c)*state[i];end
    for ((i,j),c) in QUBOTools.quadratic_terms(model);value+=R(c)*state[i]*state[j];end
    return R(QUBOTools.scale(model))*value
end
function root_oracle(model;scope=Dict())
    n=QUBOTools.dimension(model)
    0<=n<=8 || throw(ArgumentError("root oracle requires n<=8 before exponentiation"))
    low=QUBOTools.domain(model)===QUBOTools.BoolDomain ? 0 : -1
    energies=Rational{BigInt}[]
    for mask in 0:(1<<n)-1
        state=[isodd(mask>>(i-1)) ? 1 : low for i in 1:n]
        all(state[i]==v for (i,v) in scope) || continue
        push!(energies,root_scalar(model,state))
    end
    return QUBOTools.sense(model)===QUBOTools.Min ? minimum(energies) : maximum(energies)
end
function root_child(;callback=_ -> nothing,kwargs...)
    return FixtureChild(;callback=c -> begin
        0<=length(MOI.get(c.model,MOI.ListOfVariableIndices()))<=8 ||
            throw(ArgumentError("root child requires <=8 compiled variables before enumeration"))
        callback(c)
    end,kwargs...)
end
function root_work_bound(child,problem,remaining,deadline)
    0<=problem.n<=8 || throw(ArgumentError("root child work guard precedes exponentiation"))
    problem.linear isa Tuple && problem.quadratic isa Tuple || error("owned immutable numerical callback input required")
    return (1<<problem.n)*4*(problem.n+length(problem.linear)+length(problem.quadratic)+1)
end
function root_split_fixture(;domain=:bool,sense=:min,scale=1.0,offset=0.0,
    labels=[(:leaf,9),(:center,1),(:leaf,3),(:leaf,7),(:leaf,2)])
    return QUBOTools.Model{eltype(labels),Float64,Int}(labels,[2],[6.0],
        [2,2,2,2,1,4],[1,3,4,5,3,5],fill(-1.0,6);domain,sense,scale,offset)
end
root_evidence(opt)=MOI.get(opt,MOI.RawOptimizerAttribute("preprocessing_result"))

@testset "Root preprocessing exact parity and owned generations" begin
    for domain in (:bool,:spin),sense in (:min,:max),scale in (-2.0,0.0,0.5)
        model=root_split_fixture(;domain,sense,scale,offset=0.75)
        for mode in (:off,:dominance)
            opt=solve_model(model;child=()->root_child(),budget=5,preprocessing=mode,
                max_work=100_000,child_work_bound=root_work_bound,seed=41)
            @test MOI.get(opt,MOI.TerminationStatus())===MOI.OPTIMAL
            @test length(QUBOTools.state(opt,1))==5
            @test root_scalar(model,QUBOTools.state(opt,1))==root_oracle(model)
            @test QUBOTools.value(opt,1)==Float64(root_scalar(model,QUBOTools.state(opt,1)))
            @test decomposition(opt)["labels"]==QUBOTools.variables(model)
            @test decomposition(opt)["work"]["used"]<=100_000
            @test decomposition(opt)["candidate_evaluations"]<=100_000
            @test !haskey(decomposition(opt),"_work_budget") && !haskey(decomposition(opt),"_root_certificate")
            if mode===:dominance
                e=root_evidence(opt)
                @test e.exported.certificate.scope===:original
                @test isempty(QUBOPreprocessing.assumptions(e.workspace))
                if e.exported isa QUBOPreprocessing.ConditionedExport
                    @test QUBOPreprocessing.verify_certificate(e.workspace,e.exported.certificate.proof).valid
                end
                @test decomposition(opt)["preprocessing"]["original_candidate_committed"]
            end
        end
    end
    model=root_split_fixture()
    opt=solve_model(model;child=()->root_child(),budget=2,strategy=:components,preprocessing=:dominance)
    prior=root_evidence(opt)
    oldproof=prior.exported.certificate.proof
    MOI.optimize!(opt)
    fresh=root_evidence(opt)
    @test QUBOPreprocessing.generation(prior.workspace)!=QUBOPreprocessing.generation(fresh.workspace)
    @test !QUBOPreprocessing.verify_certificate(fresh.workspace,oldproof).valid
    @test QUBOPreprocessing.verify_certificate(prior.workspace,oldproof).valid
    # Every accepted source change and label order gets a fresh root scope.
    for changed in (root_split_fixture(scale=-1.0),root_split_fixture(offset=1.0),
        root_split_fixture(domain=:spin),root_split_fixture(sense=:max),
        root_split_fixture(labels=reverse(QUBOTools.variables(model))),
        QUBOTools.Model(Dict(:p=>0.0,:q=>0.0),Dict((:p,:q)=>1.0)))
        QUBODrivers.set_model!(opt,changed)
        @test root_evidence(opt)===nothing
        MOI.set(opt,MOI.RawOptimizerAttribute("max_variables"),8)
        MOI.optimize!(opt)
        @test MOI.get(opt,MOI.TerminationStatus())===MOI.OPTIMAL
        @test root_scalar(changed,QUBOTools.state(opt,1))==root_oracle(changed)
        @test !QUBOPreprocessing.verify_certificate(root_evidence(opt).workspace,oldproof).valid
    end
end

@testset "Residual graph capacity, index composition and local completion" begin
    model=root_split_fixture()
    off=solve_model(model;child=()->root_child(),budget=2,strategy=:components)
    @test MOI.get(off,MOI.TerminationStatus())===MOI.INVALID_OPTION
    opt=solve_model(model;child=()->root_child(),budget=2,strategy=:components,preprocessing=:dominance)
    d=decomposition(opt);p=d["preprocessing"]
    @test MOI.get(opt,MOI.TerminationStatus())===MOI.OPTIMAL
    @test d["attempted_calls"]==2 && d["separable_proof"]
    @test p["original_dimension"]==5 && p["residual_dimension"]==4
    @test p["original_to_residual"]==[1,0,2,3,4]
    @test p["residual"]["dimension"]==4
    @test p["residual"]["labels"]==QUBOTools.variables(model)[[1,3,4,5]]
    @test d["components"]==[[1,3],[4,5]]
    @test all(c["selected_indices"] in ([1,3],[4,5]) && c["objective_preserved"] for c in d["calls"])
    @test all(c["preprocessing_fixed_variable_count"]==1 && c["fixed_variable_count"]==3 for c in d["calls"])
    @test QUBOTools.state(opt,1)==[1,0,1,1,1]
    @test root_scalar(model,QUBOTools.state(opt,1))==root_oracle(model)
    for model in (QUBOTools.Model(Dict(:a=>1.0,:b=>2.0),Dict{Tuple{Symbol,Symbol},Float64}();offset=0.5),
        QUBOTools.Model(Dict{Int,Float64}(),Dict{Tuple{Int,Int},Float64}();offset=2.0))
        opt=solve_model(model;child=()->error("all-fixed must not dispatch"),budget=1,
            preprocessing=:dominance,max_child_calls=0)
        @test MOI.get(opt,MOI.TerminationStatus())===MOI.OPTIMAL
        @test decomposition(opt)["attempted_calls"]==0
        @test root_scalar(model,QUBOTools.state(opt,1))==root_oracle(model)
    end
    # A no-fix, nonconstant model retains its original free capacity requirement.
    nofix=QUBOTools.Model(Dict(i=>0.0 for i in 1:3),Dict((1,2)=>-1.0,(2,3)=>-1.0))
    opt=solve_model(nofix;child=()->error("oversized residual dispatched"),budget=1,
        strategy=:components,preprocessing=:dominance,preprocessing_max_work=0)
    @test MOI.get(opt,MOI.TerminationStatus())===MOI.INVALID_OPTION
    @test decomposition(opt)["attempted_calls"]==0
end

@testset "Truthful child, numerical export and heuristic statuses" begin
    model=root_split_fixture()
    for status in (MOI.LOCALLY_SOLVED,MOI.TIME_LIMIT,MOI.INTERRUPTED)
        opt=solve_model(model;child=()->root_child(;status),budget=5,preprocessing=:dominance)
        @test MOI.get(opt,MOI.TerminationStatus())===status
        @test length(QUBOTools.state(opt,1))==5
        @test root_scalar(model,QUBOTools.state(opt,1))==root_oracle(model)
        @test QUBOTools.value(opt,1)<0 # improving interrupted result, not only old fallback
        @test !decomposition(opt)["separable_proof"]
    end
    for child in (() -> root_child(rows=[[1]]),() -> root_child(status=MOI.OTHER_ERROR),
        () -> root_child(callback=_ -> error("scripted backend failure")))
        opt=solve_model(model;child,budget=5,preprocessing=:dominance)
        @test MOI.get(opt,MOI.TerminationStatus())===MOI.OTHER_ERROR
        @test QUBOTools.state(opt,1)==zeros(Int,5)
        @test !decomposition(opt)["separable_proof"]
    end
    # Root evidence cannot turn coupled exact neighborhood calls into a global proof.
    coupled=QUBOTools.Model(Dict(i=>0.0 for i in 1:3),Dict((1,2)=>-1.0,(2,3)=>-1.0))
    for selection in (:strongest_edge,:bfs,:random_blocks,:single_flip_gain)
        opt=solve_model(coupled;child=()->root_child(),budget=1,preprocessing=:dominance,
            selection,max_sweeps=1,seed=41)
        @test MOI.get(opt,MOI.TerminationStatus())!==MOI.OPTIMAL
        @test length(QUBOTools.state(opt,1))==3
        @test !decomposition(opt)["separable_proof"]
    end
    # Scaling dispatch rounds a variable-dependent coefficient: keep a feasible
    # point but do not transfer the rounded objective's public exact status.
    rounded=QUBOTools.Model(Dict(:x=>0.0,:y=>0.0),Dict((:x,:y)=>-1.1);scale=1.1)
    opt=solve_model(rounded;child=()->root_child(),budget=2,preprocessing=:dominance)
    @test MOI.get(opt,MOI.TerminationStatus())===MOI.LOCALLY_SOLVED
    @test !only(decomposition(opt)["calls"])["objective_preserved"]
    @test only(decomposition(opt)["calls"])["public_status"]=="OPTIMAL"
    @test root_scalar(rounded,QUBOTools.state(opt,1))==root_oracle(rounded)
    # A strict root fixing leaves an unrepresentable free field. Funded fallback
    # solves the original, without claiming the unused reduction was exported.
    unsafe=QUBOTools.Model(Dict(:x=>-2.0,:y=>1.0,:z=>0.0),Dict((:x,:y)=>2.0^-53,(:y,:z)=>-2.0))
    opt=solve_model(unsafe;child=()->root_child(),budget=3,preprocessing=:dominance)
    @test decomposition(opt)["preprocessing"]["reason"]=="unsafe_export"
    @test !decomposition(opt)["preprocessing"]["applied"]
    @test root_evidence(opt).exported===nothing
    @test MOI.get(opt,MOI.TerminationStatus())===MOI.OPTIMAL
    @test root_scalar(unsafe,QUBOTools.state(opt,1))==root_oracle(unsafe)
end

@testset "Shared structural work, candidate reserve and deadlines" begin
    model=QUBOTools.Model(Dict(:x=>0.0,:y=>0.0),Dict((:x,:y)=>-1.0))
    for cap in (0,1,64,128,256,512,1024)
        opt=solve_model(model;child=()->root_child(),budget=2,preprocessing=:dominance,
            max_work=cap,child_work_bound=root_work_bound)
        @test decomposition(opt)["work"]["used"]<=cap
        @test decomposition(opt)["work"]["used"]+decomposition(opt)["work"]["remaining"]==cap
        @test MOI.get(opt,MOI.TerminationStatus()) in (MOI.OPTIMAL,MOI.ITERATION_LIMIT)
        @test MOI.get(opt,MOI.ResultCount())==0 || length(QUBOTools.state(opt,1))==2
    end
    unsupported=solve_model(model;child=()->root_child(),budget=2,preprocessing=:dominance,max_work=100_000)
    @test MOI.get(unsupported,MOI.TerminationStatus())===MOI.INVALID_OPTION
    @test all(c["public_status"]===nothing for c in decomposition(unsupported)["calls"])
    funded=solve_model(model;child=()->root_child(),budget=2,preprocessing=:dominance,
        max_work=100_000,child_work_bound=root_work_bound)
    @test MOI.get(funded,MOI.TerminationStatus())===MOI.OPTIMAL
    @test sum(c["child_work_reserved"] for c in decomposition(funded)["calls"])>0
    @test decomposition(funded)["work"]["phases"]["reserved_original_lift"]>0
    # Discover bounded refusals from public evidence, without baking reservation
    # constants into the expected cap. Both stops must retain original frames.
    verification_stop=nothing
    for cap in 300:600
        candidate=solve_model(root_split_fixture();child=()->root_child(),budget=5,
            preprocessing=:dominance,max_work=cap,child_work_bound=root_work_bound)
        e=root_evidence(candidate)
        if e!==nothing && e.verification!==nothing && !e.verification.valid
            verification_stop=candidate
            break
        end
    end
    @test verification_stop!==nothing
    if verification_stop!==nothing
        @test root_evidence(verification_stop).verification.stop_reason===:work_limit
        @test MOI.get(verification_stop,MOI.TerminationStatus())===MOI.ITERATION_LIMIT
        @test QUBOTools.state(verification_stop,1)==zeros(Int,5)
        @test decomposition(verification_stop)["attempted_calls"]==0
        @test !decomposition(verification_stop)["preprocessing"]["proof_verified"]
    end
    unsafe=QUBOTools.Model(Dict(:x=>-2.0,:y=>1.0,:z=>0.0),Dict((:x,:y)=>2.0^-53,(:y,:z)=>-2.0))
    fallback_stop=nothing
    for cap in 250:450
        candidate=solve_model(unsafe;child=()->root_child(),budget=3,preprocessing=:dominance,
            max_work=cap,child_work_bound=root_work_bound)
        data=decomposition(candidate)
        if get(data["preprocessing"],"reason",nothing)=="unsafe_export" &&
            MOI.get(candidate,MOI.TerminationStatus())===MOI.ITERATION_LIMIT
            fallback_stop=candidate
            break
        end
    end
    @test fallback_stop!==nothing
    if fallback_stop!==nothing
        @test QUBOTools.state(fallback_stop,1)==zeros(Int,3)
        @test decomposition(fallback_stop)["attempted_calls"]==0
        @test decomposition(fallback_stop)["preprocessing"]["fallback"]=="original_objective"
    end
    for cap in 0:5
        opt=solve_model(model;child=()->root_child(),budget=2,preprocessing=:dominance,
            max_candidate_evaluations=cap)
        @test decomposition(opt)["candidate_evaluations"]<=cap
        @test MOI.get(opt,MOI.TerminationStatus())== (cap>=4 ? MOI.OPTIMAL : MOI.ITERATION_LIMIT)
        @test MOI.get(opt,MOI.ResultCount())==0 || length(QUBOTools.state(opt,1))==2
    end
    # Guard known exponential children before exponentiation, copying or dispatch.
    oversized=QUBOTools.Model(Dict(i=>0.0 for i in 1:21),Dict((i,i+1)=>-1.0 for i in 1:20))
    seen=Ref{Any}()
    opt=solve_model(oversized;child=()->(seen[]=QUBODrivers.ExactSampler.Optimizer()),budget=64,
        preprocessing=:dominance)
    @test MOI.get(opt,MOI.TerminationStatus())===MOI.INVALID_OPTION
    @test QUBOTools.dimension(seen[])==0 && isempty(QUBOTools.solution(seen[]))
    @test occursin("20-variable",decomposition(opt)["diagnostic"])
    limits_log=Any[]
    limited=QUBODecomposition.Optimizer(child_optimizer=()->root_child(
        time_supported=false,limit=0.125,log=limits_log),max_variables=2,preprocessing=:dominance)
    QUBODrivers.set_model!(limited,model)
    MOI.set(limited,MOI.TimeLimitSec(),60.0);MOI.optimize!(limited)
    @test MOI.get(limited,MOI.TerminationStatus())===MOI.OPTIMAL
    @test last(limits_log).limit==0.125
    @test only(decomposition(limited)["calls"])["effective_time_limit_sec"]==0.125
    now=Ref(0.0);overrun=Ref(false)
    factory=()->root_child(callback=_ -> (overrun[] && (now[]=2.0)))
    opt=QUBODecomposition.Optimizer(child_optimizer=factory,max_variables=5,preprocessing=:dominance)
    QUBODrivers.set_model!(opt,root_split_fixture());opt.clock=()->now[]
    MOI.set(opt,MOI.TimeLimitSec(),60.0);MOI.optimize!(opt) # warm the UInt64 QP deadline path
    @test MOI.get(opt,MOI.TerminationStatus())===MOI.OPTIMAL
    overrun[]=true;MOI.set(opt,MOI.TimeLimitSec(),1.0);MOI.optimize!(opt)
    @test MOI.get(opt,MOI.TerminationStatus())===MOI.TIME_LIMIT
    @test QUBOTools.state(opt,1)==zeros(Int,5)
    @test !decomposition(opt)["separable_proof"]
    now[]=0.0;overrun[]=false
    opt.checkpoint=p -> p===:before_original_commit && (now[]=2.0)
    MOI.optimize!(opt)
    @test MOI.get(opt,MOI.TerminationStatus())===MOI.TIME_LIMIT
    @test QUBOTools.state(opt,1)==zeros(Int,5)
    # Expire at the final public result check, after an independently audited
    # original candidate was already committed. No elapsed-time threshold used.
    clock_calls=Ref(0);expire_at=Ref(typemax(Int))
    opt.checkpoint=_ -> nothing
    opt.clock=()->(clock_calls[]+=1;clock_calls[]>=expire_at[] ? 2.0 : 0.0)
    MOI.set(opt,MOI.TimeLimitSec(),60.0)
    for _ in 1:2
        clock_calls[]=0;MOI.optimize!(opt)
        @test MOI.get(opt,MOI.TerminationStatus())===MOI.OPTIMAL
    end
    expire_at[]=clock_calls[];clock_calls[]=0
    MOI.set(opt,MOI.TimeLimitSec(),1.0);MOI.optimize!(opt)
    @test MOI.get(opt,MOI.TerminationStatus())===MOI.TIME_LIMIT
    @test decomposition(opt)["stopped_phase"]=="public_result"
    @test decomposition(opt)["preprocessing"]["original_candidate_committed"]
    @test root_scalar(root_split_fixture(),QUBOTools.state(opt,1))==root_oracle(root_split_fixture())
end

@testset "Caller branch evidence stays scoped and unsupported combinations fail" begin
    empty_opt=QUBODecomposition.Optimizer()
    evidence_attr=MOI.RawOptimizerAttribute("preprocessing_result")
    @test MOI.get(empty_opt,evidence_attr)===nothing
    @test !MOI.supports(empty_opt,evidence_attr) # supports describes copyable/settable optimizer parameters
    @test_throws MOI.UnsupportedAttribute MOI.set(empty_opt,evidence_attr,nothing)
    model=root_split_fixture()
    ws=QUBOPreprocessing.Workspace(model;rules=:dominance)
    cp=QUBOPreprocessing.checkpoint(ws)
    QUBOPreprocessing.assume!(ws,QUBOTools.variable(model,1),0)
    QUBOPreprocessing.propagate!(ws)
    proof=QUBOPreprocessing.export_certificate(ws)
    result=QUBOPreprocessing.sample_preprocessed(ws,()->QUBODecomposition.Optimizer(
        child_optimizer=()->root_child(),max_variables=5,preprocessing=:dominance))
    @test result.scope===:assumptions && result.scope_optimal && !result.optimal
    @test root_scalar(model,first(result.samples).state)==root_oracle(model;scope=Dict(1=>0))
    QUBOPreprocessing.rollback!(ws,cp)
    @test !QUBOPreprocessing.verify_certificate(ws,proof).valid
    @test isempty(QUBOPreprocessing.deductions(ws)) && isempty(QUBOPreprocessing.assumptions(ws))
    for kwargs in ((;strategy=:separator),(;strategy=:coarse,coarse_groups=[[1,2],[3,4,5]]),
        (;selection=:partition,partition_plan=[[1],[2],[3],[4],[5]]))
        opt=solve_model(model;child=()->error("unsupported combination dispatched"),budget=5,
            preprocessing=:dominance,kwargs...)
        @test MOI.get(opt,MOI.TerminationStatus())===MOI.INVALID_OPTION
        @test decomposition(opt)["attempted_calls"]==0
    end
    for (key,value) in ((:max_work,-1),(:preprocessing,:heuristic),(:preprocessing_max_work,true))
        @test_throws ArgumentError QUBODecomposition.Optimizer(;key=>value)
    end
    @test_throws ArgumentError root_oracle(QUBOTools.Model(Dict(i=>0.0 for i in 1:9),Dict{Tuple{Int,Int},Float64}()))
end

@testset "Root timing capability refusals and stale proof never dispatch" begin
    model=QUBOTools.Model(Dict(:x=>0.0,:y=>0.0),Dict((:x,:y)=>-1.0))
    unsupported=MOI.UnsupportedAttribute(MOI.TimeLimitSec())
    log=Any[]
    positive=solve_model(model;child=()->root_child(time_supported=false,
        time_get_error=unsupported,log=log),budget=2,preprocessing=:dominance,
        child_time_limit_sec=0.125)
    @test MOI.get(positive,MOI.TerminationStatus())===MOI.OPTIMAL
    @test root_scalar(model,QUBOTools.state(positive,1))==root_oracle(model)
    @test last(log).limit==0.125
    # A conservative supports query is different from an actually rejected setter.
    # Neither public rejection form may silently dispatch an unbounded child.
    for rejection in (unsupported,MOI.SetAttributeNotAllowed(MOI.TimeLimitSec()))
        optimized=Ref(0)
        opt=solve_model(model;child=()->root_child(time_supported=false,
            time_get_error=unsupported,time_set_error=rejection,
            callback=_ -> (optimized[]+=1)),budget=2,preprocessing=:dominance,
            child_time_limit_sec=0.125)
        @test MOI.get(opt,MOI.TerminationStatus())===MOI.INVALID_OPTION
        @test occursin("bounded root solve requires a child accepting",decomposition(opt)["diagnostic"])
        @test optimized[]==0
        @test decomposition(opt)["completed_calls"]==0
        @test QUBOTools.state(opt,1)==zeros(Int,2)
        @test root_scalar(model,QUBOTools.state(opt,1))==0
        @test !decomposition(opt)["separable_proof"]
    end
    # Changing the producer generation after export invalidates its real proof;
    # the adapter must retain its original incumbent without creating any child.
    original=root_split_fixture()
    factories=Ref(0)
    opt=QUBODecomposition.Optimizer(child_optimizer=()->(factories[]+=1;root_child()),
        max_variables=2,preprocessing=:dominance)
    QUBODrivers.set_model!(opt,original)
    opt.checkpoint=phase -> phase===:verification &&
        QUBOPreprocessing.reset!(root_evidence(opt).workspace,original)
    MOI.optimize!(opt)
    @test MOI.get(opt,MOI.TerminationStatus())===MOI.OTHER_ERROR
    @test occursin("root preprocessing certificate rejected",decomposition(opt)["diagnostic"])
    @test root_evidence(opt).verification.stop_reason===:stale_generation
    @test !root_evidence(opt).verification.valid
    @test factories[]==0
    @test decomposition(opt)["attempted_calls"]==0
    @test QUBOTools.state(opt,1)==zeros(Int,5)
    @test root_scalar(original,QUBOTools.state(opt,1))==0
    @test !decomposition(opt)["preprocessing"]["proof_verified"]
    @test !decomposition(opt)["preprocessing"]["applied"]
end

# SPDX-License-Identifier: MPL-2.0
function separable_model(; labels=[:z,:a,:internal,:q,:b,:trailing], domain=:bool, sense=:min, scale=2.0, offset=7.0)
    QUBOTools.Model{eltype(labels),Float64,Int}(labels,
        collect(1:6), [-3.0,2.0,-2.0,1.0,-4.0,3.0], [1,4], [2,5], [4.0,-2.0]; domain,sense,scale,offset)
end
separable_oracle(x, scale, offset=7) = scale*(offset-3*x[1]+2*x[2]-2*x[3]+x[4]-4*x[5]+3*x[6]+4*x[1]*x[2]-2*x[4]*x[5])
function linear_model(n=4)
    QUBOTools.Model{Int,Float64,Int}(collect(1:n), collect(1:n), fill(-1.0,n), Int[], Int[], Float64[])
end
function boundary_energy(f, x)
    f.constant + sum((t.coefficient*x[t.variable.value] for t in f.affine_terms); init=0.0) +
        sum((t.coefficient*x[t.variable_1.value]*x[t.variable_2.value] / (t.variable_1==t.variable_2 ? 2 : 1) for t in f.quadratic_terms);init=0.0)
end

@testset "Conditioned components: independent scalar identities and global optima" begin
    for domain in (:bool,:spin), sense in (:min,:max), scale in (2.0,-3.0,0.0),
        labels in ([:z,:a,:internal,:q,:b,:trailing],[91,3,47,2,29,5]), storage in (:sparse,:dense,:dict),
        strategy in (:components,:components_then_sweeps)
        base=separable_model(;labels,domain,sense,scale)
        form=QUBOTools.form(base,storage,Float64)
        model=QUBOTools.Model{eltype(labels),Float64,Int}(QUBOTools.VariableMap{eltype(labels)}(Dict(i=>v for (i,v) in enumerate(labels))),form)
        log=Any[]
        opt=solve_model(model;budget=2,strategy,child=()->FixtureChild(;log))
        states=Iterators.product(fill(domain===:bool ? (0,1) : (-1,1),6)...)
        expected=(sense===:min ? minimum : maximum)(separable_oracle(x,scale) for x in states)
        @test QUBOTools.value(opt,1)==expected==separable_oracle(QUBOTools.state(opt,1),scale)
        @test MOI.get(opt,MOI.TerminationStatus())===MOI.OPTIMAL
        @test QUBOTools.variables(opt)==labels
        @test QUBOTools.domain(opt)===QUBOTools.domain(model)
        @test QUBOTools.sense(opt)===QUBOTools.sense(model)
        @test length(QUBOTools.state(opt,1))==6
        @test QUBOTools.reads(opt,1)==1
        @test isempty(QUBODrivers.validate_metadata(QUBOTools.solution(opt)))
        scale==0 && continue
        data=decomposition(opt)
        @test data["components"]==[[1,2],[3],[4,5],[6]]
        @test data["completed_calls"]==data["attempted_calls"]==4
        @test data["separable_proof"] && all(data["component_exact"])
        @test data["candidate_evaluations"]==5
        @test data["completed_sweeps"]==0
        incumbent=fill(domain===:bool ? 0 : -1,6)
        incumbent_version=0
        for (call, copied) in zip(data["calls"],log[1:2:end])
            @test length(unique(call["selected_indices"]))<=2
            map=call["original_to_reduced"]
            fixed=Dict(i=>incumbent[i] for i in 1:6 if !haskey(map,i))
            @test call["fixed_variable_count"]==length(fixed)
            @test call["conditioning_incumbent_version"]==incumbent_version
            @test isempty(call["boundary_fixed_variables"]) # independent components
            @test !haskey(call,"fixed_variables")
            candidates=Vector{Int}[]
            @test sort(collect(keys(map)))==call["selected_indices"]
            for reduced in Iterators.product(fill(domain===:bool ? (0,1) : (-1,1),length(map))...)
                # Rebuild manually, independently of QUBOTools.lift_state.
                full=[haskey(fixed,i) ? fixed[i] : reduced[map[i]] for i in 1:6]
                lifted=QUBOTools.lift_state(collect(reduced),fixed,map,6)
                @test lifted==full
                @test boundary_energy(copied.objective,reduced)==separable_oracle(full,scale)
                push!(candidates,full)
            end
            @test call["physical_reads"]===nothing
            # Independently derive the next committed complement from scalar
            # enumeration, without reading the parent's retained fixed values.
            sort!(candidates;by=x -> (sense===:min ? separable_oracle(x,scale) : -separable_oracle(x,scale),Tuple(x)))
            best=first(candidates)
            if sense===:min ? separable_oracle(best,scale)<separable_oracle(incumbent,scale) : separable_oracle(best,scale)>separable_oracle(incumbent,scale)
                incumbent=best
                incumbent_version+=1
            end
        end
        @test QUBOTools.state(opt,1)==incumbent
    end
    # The design's two worked conditional expressions, with explicit offset delta.
    for domain in (:bool,:spin), sense in (:min,:max), scale in (2.0,-3.0,0.0), storage in (:sparse,:dense,:dict)
        model=direct_model(;domain,sense,scale)
        form=QUBOTools.form(model,storage,Float64)
        fixed=Dict(2=>(domain===:bool ? 1 : -1))
        reduced,delta,map=QUBOTools.fix_variables(form,fixed)
        @test map==Dict(1=>1,3=>2,4=>3)
        @test QUBOTools.offset(reduced)==5+delta
        for x in Iterators.product(fill(domain===:bool ? (0,1) : (-1,1),3)...)
            full=QUBOTools.lift_state(collect(x),fixed,map,4)
            original=scale*(5-3*full[1]+2*full[2]-full[3]+4*full[1]*full[2]-2*full[2]*full[3])
            conditional=domain===:bool ? scale*(7+x[1]-3*x[2]) : scale*(3-7*x[1]+x[2])
            @test QUBOTools.value(collect(x),reduced)==original==conditional
        end
    end
end

@testset "Singleton reference policy, proof completion and strict preflight" begin
    opt=solve_model(linear_model();budget=2,max_child_calls=3)
    d=decomposition(opt)
    @test [c["selected_indices"] for c in d["calls"]]==[[1],[2],[3]]
    @test QUBOTools.state(opt,1)==[1,1,1,0]
    @test QUBOTools.value(opt,1)==-3
    @test d["attempted_calls"]==d["completed_calls"]==3
    @test !d["separable_proof"] && d["component_exact"]==[true,true,true,false]
    @test MOI.get(opt,MOI.TerminationStatus())===MOI.ITERATION_LIMIT
    # A certificate completed at the exact work cap survives later checks.
    opt=solve_model(linear_model();budget=2,max_child_calls=4,max_candidate_evaluations=5)
    @test MOI.get(opt,MOI.TerminationStatus())===MOI.OPTIMAL
    @test decomposition(opt)["separable_proof"]
    for strategy in (:components,:whole_model), callcap in (0,100)
        model=separable_model() # fitting singleton first is not dispatched before strict rejection
        opt=solve_model(model;budget=1,strategy,max_child_calls=callcap)
        @test MOI.get(opt,MOI.TerminationStatus())===MOI.INVALID_OPTION
        @test decomposition(opt)["attempted_calls"]==0
        @test length(QUBOTools.state(opt,1))==6
        @test occursin("budget 1",decomposition(opt)["diagnostic"])
    end
    for strategy in (:components,:components_then_sweeps,:whole_model)
        opt=solve_model(direct_model();budget=4,strategy,max_sweeps=0)
        @test MOI.get(opt,MOI.TerminationStatus())===MOI.OPTIMAL
        @test only(decomposition(opt)["calls"])["kind"]=="whole_model"
    end
    @test MOI.get(QUBODecomposition.Optimizer(),MOI.RawOptimizerAttribute("strategy"))===:components_then_sweeps
end

@testset "Coupled sweeps, deterministic neighborhoods and strict full-energy commits" begin
    for domain in (:bool,:spin), sense in (:min,:max), scale in (2.0,-3.0,0.0), budget in (1,2)
        model=direct_model(;domain,sense,scale)
        opt=solve_model(model;budget,stagnation_sweeps=2)
        data=decomposition(opt); trace=data["incumbent_energy_trace"]
        @test MOI.get(opt,MOI.TerminationStatus())== (scale==0 ? MOI.OPTIMAL : MOI.LOCALLY_SOLVED)
        @test length(QUBOTools.state(opt,1))==4
        x=QUBOTools.state(opt,1)
        oracle(x)=scale*(5-3*x[1]+2*x[2]-x[3]+4*x[1]*x[2]-2*x[2]*x[3])
        @test QUBOTools.value(opt,1)==oracle(x)
        states=Iterators.product(fill(domain===:bool ? (0,1) : (-1,1),4)...)
        reference=(sense===:min ? minimum : maximum)(oracle(x) for x in states)
        @test sense===:min ? oracle(x)>=reference : oracle(x)<=reference
        @test all(sense===:min ? trace[i+1]<=trace[i] : trace[i+1]>=trace[i] for i in 1:length(trace)-1)
        @test count(!iszero,diff(trace))==data["accepted_improvements"]
        @test data["completed_sweeps"]<=20
        @test !data["separable_proof"]
        for c in data["calls"]
            @test 1<=length(c["selected_indices"])<=budget
            c["kind"]=="neighborhood" && budget==1 && @test c["selected_indices"]==[c["anchor"]]
        end
    end
    # Direct boundary observation establishes latest-committed-state conditioning.
    opt=solve_model(direct_model();budget=1,stagnation_sweeps=1)
    calls=decomposition(opt)["calls"]
    @test calls[3]["boundary_fixed_variables"][1]==1 # anchor 1 committed before anchor 2
    @test calls[3]["conditioning_incumbent_version"]==1
    @test calls[4]["conditioning_incumbent_version"]==1
    @test calls[4]["boundary_fixed_variables"]==Dict(2=>0) # no unrelated anchor 1
    @test all(!haskey(c,"fixed_variables") for c in calls)
    star=QUBOTools.Model{Int,Float64,Int}(collect(1:5),[1],[-1.0],[1,1,1,1],[2,3,4,5],[-4.0,4.0,1.0,0.0])
    opt=solve_model(star;budget=3,max_sweeps=1)
    neighborhoods=filter(c->c["kind"]=="neighborhood",decomposition(opt)["calls"])
    @test first(neighborhoods)["selected_indices"]==[1,2,3]
    @test neighborhoods[2]["selected_indices"]==[1,2] # no padding
    @test all(length(c["selected_indices"])==length(unique(c["selected_indices"])) for c in neighborhoods)
    @test MOI.get(opt,MOI.TerminationStatus())===MOI.ITERATION_LIMIT
    # Duplicate edge input normalizes; the selected logical set remains distinct.
    duplicate=QUBOTools.Model{Int,Float64,Int}([1,2,3],[1],[-1.0],[1,1,2],[2,2,3],[2.0,2.0,1.0])
    opt=solve_model(duplicate;budget=2,max_child_calls=2)
    @test [c["selected_indices"] for c in decomposition(opt)["calls"]]==[[1,2],[1,2]]
end

@testset "Serial transactions retain prior committed work" begin
    for factory2 in (() -> FixtureChild(;rows=[]), () -> FixtureChild(;rows=[[1],[2]]),
        () -> FixtureChild(;rows=[[NaN]]), () -> FixtureChild(;rows=[[]]),
        () -> FixtureChild(;values=[Inf],rows=[[1]]),
        () -> FixtureChild(;status=MOI.INFEASIBLE), () -> error("factory failed"),
        () -> FixtureChild(;callback=_ -> error("execution failed")))
        n=Ref(0)
        opt=solve_model(linear_model();budget=2,child=()->(n[]+=1; n[]==1 ? FixtureChild() : factory2()))
        @test MOI.get(opt,MOI.TerminationStatus())===MOI.OTHER_ERROR
        @test QUBOTools.state(opt,1)==[1,0,0,0]
        @test decomposition(opt)["completed_calls"]==1
        @test decomposition(opt)["attempted_calls"]==2
        @test !decomposition(opt)["separable_proof"]
    end
    for factory2 in (() -> FixtureChild(;status=MOI.INTERRUPTED,rows=[]),
        () -> FixtureChild(;callback=_ -> throw(InterruptException())))
        n=Ref(0)
        opt=solve_model(linear_model();budget=2,child=()->(n[]+=1;n[]==1 ? FixtureChild() : factory2()))
        @test MOI.get(opt,MOI.TerminationStatus())===MOI.INTERRUPTED
        @test QUBOTools.state(opt,1)==[1,0,0,0]
    end
    n=Ref(0)
    opt=solve_model(linear_model();budget=2,max_candidate_evaluations=3,
        child=()->(n[]+=1; n[]==1 ? FixtureChild() : FixtureChild(;rows=[[1],[1]])))
    @test MOI.get(opt,MOI.TerminationStatus())===MOI.ITERATION_LIMIT
    @test QUBOTools.state(opt,1)==[1,0,0,0]
    @test decomposition(opt)["candidate_evaluations"]==3
    @test decomposition(opt)["incomplete_scan"]
    opt=solve_model(linear_model();budget=2,child=()->FixtureChild(;rows=[[1],[1],[1]],values=[-99,99,0]))
    @test MOI.get(opt,MOI.TerminationStatus())===MOI.OPTIMAL
    @test decomposition(opt)["candidate_evaluations"]==13
    @test QUBOTools.reads(opt,1)==1
    # Malformed in-flight scans under a sweep do not undo successful earlier calls.
    n[]=0
    opt=solve_model(direct_model();budget=1,child=()->(n[]+=1; n[]==3 ? FixtureChild(;rows=[[1],[2]]) : FixtureChild()))
    @test MOI.get(opt,MOI.TerminationStatus())===MOI.OTHER_ERROR
    @test QUBOTools.state(opt,1)==[1,0,0,0]
    @test decomposition(opt)["started_sweeps"]==1
    @test decomposition(opt)["completed_sweeps"]==0
end

@testset "Serial budgets, early-child continuation, seed sequences and timing" begin
    for status in QUBODecomposition.ACCEPTED_CHILD_STATUSES
        opt=solve_model(linear_model();budget=2,child=()->FixtureChild(;status))
        @test decomposition(opt)["completed_calls"]==4
        @test MOI.get(opt,MOI.TerminationStatus())== (status===MOI.OPTIMAL ? MOI.OPTIMAL : MOI.LOCALLY_SOLVED)
        @test QUBOTools.state(opt,1)==ones(Int,4)
    end
    for cap in 0:5
        opt=solve_model(linear_model();budget=2,max_candidate_evaluations=cap)
        @test decomposition(opt)["candidate_evaluations"]<=cap
        @test decomposition(opt)["completed_calls"]==max(0,min(4,cap-1))
        @test MOI.get(opt,MOI.TerminationStatus())==(cap==5 ? MOI.OPTIMAL : MOI.ITERATION_LIMIT)
    end
    for cap in (0,1,2)
        opt=solve_model(direct_model();budget=1,max_sweeps=cap)
        @test MOI.get(opt,MOI.TerminationStatus())===MOI.ITERATION_LIMIT
        @test decomposition(opt)["started_sweeps"]==decomposition(opt)["completed_sweeps"]==cap
        @test decomposition(opt)["stop_reason"]=="max_sweeps"
    end
    for supported in (true,false), seed in (0,123,2^31-2)
        log=Any[]; opt=solve_model(linear_model();budget=2,seed,child=()->FixtureChild(;log,seed_supported=supported))
        expected=[Int(mod(big(seed)+k-1,big(2)^31-1)) for k in 1:4]
        @test [c["seed"] for c in decomposition(opt)["calls"]]==expected
        @test [c.seed for c in log[2:2:end]]== (supported ? expected : fill(nothing,4))
        MOI.optimize!(opt)
        @test [c["seed"] for c in decomposition(opt)["calls"]]==expected
    end
    for failure in (false,true)
        now=Ref(0.0); n=Ref(0);log=Any[]
        child=()->(n[]+=1; FixtureChild(;log,limit=0.4,callback=_ -> (now[]+=0.6), status=failure && n[]==2 ? MOI.OTHER_ERROR : MOI.TIME_LIMIT))
        opt=QUBODecomposition.Optimizer(;child_optimizer=child,max_variables=2,child_time_limit_sec=0.5)
        QUBODrivers.set_model!(opt,linear_model()); opt.clock=()->now[]
        MOI.set(opt,MOI.TimeLimitSec(),1.0);MOI.optimize!(opt)
        @test MOI.get(opt,MOI.TerminationStatus())== (failure ? MOI.OTHER_ERROR : MOI.TIME_LIMIT)
        @test QUBOTools.state(opt,1)==[1,0,0,0]
        @test decomposition(opt)["attempted_calls"]==2
        @test decomposition(opt)["completed_calls"]==1
        @test decomposition(opt)["parent_overrun_sec"]≈ (failure ? 0.0 : 0.2)
        @test [x.limit for x in log[2:2:end]]≈[0.4,0.4]
    end
    for phase in (:before_factory,:reconstruct,:before_commit)
        count=Ref(0)
        opt=QUBODecomposition.Optimizer(;child_optimizer=()->FixtureChild(),max_variables=2)
        QUBODrivers.set_model!(opt,linear_model())
        opt.checkpoint=p -> (p===phase && (count[]+=1; count[]==2 && throw(InterruptException()));nothing)
        MOI.optimize!(opt)
        @test MOI.get(opt,MOI.TerminationStatus())===MOI.INTERRUPTED
        @test QUBOTools.state(opt,1)==[1,0,0,0]
    end
    for budget in (1,2,8)
        opt=solve_model(separable_model();budget)
        data=decomposition(opt); phases=data["phase_sec"]
        @test Set(keys(phases))==Set(["preparation","conditioning","copying","execution","validation_reconstruction","full_energy"])
        @test all(isfinite(v) && v>=0 for v in values(phases))
        @test phases["copying"]>0 && phases["execution"]>0 && phases["full_energy"]>0 && phases["validation_reconstruction"]>0
        budget<6 && @test phases["conditioning"]>0
        @test sum(values(phases))<=QUBODrivers.effective_time(opt)
        @test data["child_execution_sec"]==phases["execution"]
        for key in ("conditioning","copying","execution","validation_reconstruction")
            @test phases[key]≈sum(c["phase_sec"][key] for c in data["calls"])
        end
        @test MOI.get(opt,MOI.SolveTimeSec())==QUBODrivers.effective_time(opt)<=QUBODrivers.total_time(opt)
    end
end

@testset "Rebuilt serial plans, maps, coefficients and proof state" begin
    opt=QUBODecomposition.Optimizer(;child_optimizer=()->FixtureChild(),max_variables=2)
    for model in (separable_model(),separable_model(;labels=[:trailing,:b,:q,:internal,:a,:z]),
        separable_model(;domain=:spin,sense=:max,scale=-2.0,offset=13.0),
        direct_model(),separable_model(;scale=0.0))
        QUBODrivers.set_model!(opt,model);MOI.optimize!(opt)
        fresh=solve_model(model;budget=2)
        @test QUBOTools.state(opt,1)==QUBOTools.state(fresh,1)
        @test decomposition(opt)["components"]==decomposition(fresh)["components"]
        @test decomposition(opt)["component_exact"]==decomposition(fresh)["component_exact"]
        @test QUBOTools.value(opt,1)==QUBOTools.value(fresh,1)
    end
    QUBODrivers.set_model!(opt,linear_model());MOI.optimize!(opt)
    form=QUBOTools.form(QUBOTools.backend(opt))
    QUBOTools.data(QUBOTools.quadratic_form(form))[1,2]=-3.0
    QUBOTools.data(QUBOTools.linear_form(form))[1]=2.0
    MOI.optimize!(opt)
    @test decomposition(opt)["components"]==[[1,2],[3],[4]]
    @test QUBOTools.value(opt,1)==-4.0
    @test decomposition(opt)["attempted_calls"]==3
end


@testset "Review regression: serial multiplicities, interrupted sweeps and cap boundaries" begin
    # A connected five-variable chain exposes only its crossing interaction
    # boundary, rather than every unrelated complement value in retained metadata.
    chain=QUBOTools.Model{Int,Float64,Int}(collect(1:5),collect(1:5),fill(-1.0,5),[1,2,3,4],[2,3,4,5],fill(0.5,4))
    opt=solve_model(chain;budget=2,max_child_calls=1)
    call=only(decomposition(opt)["calls"])
    @test call["selected_indices"]==[1,2]
    @test call["fixed_variable_count"]==3
    @test call["boundary_fixed_variables"]==Dict(3=>0)
    @test !haskey(call,"fixed_variables")

    n=Ref(0)
    model=linear_model(2)
    factory=()->begin
        n[]+=1
        child=MultiplicityChild()
        MOI.set(child,MOI.RawOptimizerAttribute("physical_reads"),n[]==1 ? 3 : 7)
        return child
    end
    opt=solve_model(model;budget=1,child=factory)
    @test [c["reported_multiplicities"] for c in decomposition(opt)["calls"]]==[[3],[7]]
    @test QUBOTools.reads(opt,1)==1 # never 3*7
    @test decomposition(opt)["emitted_multiplicity"]==1
    @test decomposition(opt)["candidate_evaluations"]==3
    @test QUBOTools.value(opt,1)==-2.0
    @test MOI.get(opt,MOI.TerminationStatus())===MOI.LOCALLY_SOLVED
    @test all(c["physical_reads"]===nothing for c in decomposition(opt)["calls"])
    opt=solve_model(linear_model();budget=2,child=()->QUBODrivers.ExactSampler.Optimizer())
    @test all(all(x isa Int for x in c["reported_multiplicities"]) for c in decomposition(opt)["calls"])
    @test QUBOTools.reads(opt,1)==1

    count=Ref(0)
    opt=QUBODecomposition.Optimizer(;child_optimizer=()->FixtureChild(),max_variables=1)
    QUBODrivers.set_model!(opt,direct_model())
    # Fitting isolate, anchor 1, then interruption during anchor 2 reconstruction.
    opt.checkpoint=p -> (p===:reconstruct && (count[]+=1;count[]==3 && throw(InterruptException()));nothing)
    MOI.optimize!(opt)
    @test MOI.get(opt,MOI.TerminationStatus())===MOI.INTERRUPTED
    @test QUBOTools.state(opt,1)==[1,0,0,0]
    @test QUBOTools.value(opt,1)==4.0
    @test decomposition(opt)["attempted_calls"]==3
    @test decomposition(opt)["completed_calls"]==2
    @test decomposition(opt)["started_sweeps"]==1
    @test decomposition(opt)["completed_sweeps"]==0
    @test !decomposition(opt)["separable_proof"]

    # Exactly reached work caps precede heuristic completion, even when the pass
    # is complete. Public exact independent certificates have a separate proof rule.
    for (callcap,candidatecap,reason) in ((4,100,"max_child_calls"),(100,5,"max_candidate_evaluations"))
        opt=solve_model(linear_model();budget=2,max_child_calls=callcap,max_candidate_evaluations=candidatecap,
            child=()->FixtureChild(;status=MOI.LOCALLY_SOLVED))
        @test decomposition(opt)["completed_calls"]==4
        @test MOI.get(opt,MOI.TerminationStatus())===MOI.ITERATION_LIMIT
        @test decomposition(opt)["stop_reason"]==reason
        @test !decomposition(opt)["separable_proof"]
    end
    model=direct_model()
    for pair in (:a=>1,:b=>0,:c=>1,:isolate=>0) # optimum; first sweep stagnates
        QUBOTools.attach!(model,pair)
    end
    for sweeps in (1,2)
        opt=solve_model(model;budget=1,max_sweeps=sweeps,stagnation_sweeps=1)
        @test decomposition(opt)["completed_sweeps"]==1
        @test decomposition(opt)["stagnation"]==1
        @test MOI.get(opt,MOI.TerminationStatus())== (sweeps==1 ? MOI.ITERATION_LIMIT : MOI.LOCALLY_SOLVED)
        @test decomposition(opt)["stop_reason"]== (sweeps==1 ? "max_sweeps" : "stagnation_sweeps")
    end
end


@testset "Coupled scalar global reference exposes a heuristic gap" begin
    model=QUBOTools.Model{Int,Float64,Int}([1,2,3],[1,2],[1.0,1.0],[1],[2],[-3.0])
    oracle(x)=x[1]+x[2]-3*x[1]*x[2]
    reference=minimum(oracle(x) for x in Iterators.product((0,1),(0,1),(0,1)))
    opt=solve_model(model;budget=1,stagnation_sweeps=1)
    @test reference==-1
    @test QUBOTools.value(opt,1)==oracle(QUBOTools.state(opt,1))==0
    @test QUBOTools.value(opt,1)-reference==1
    @test MOI.get(opt,MOI.TerminationStatus())===MOI.LOCALLY_SOLVED
    @test !decomposition(opt)["separable_proof"]
end

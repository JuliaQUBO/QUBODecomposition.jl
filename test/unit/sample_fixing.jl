# SPDX-License-Identifier: MPL-2.0
const SAMPLE18_ORACLE_WORK = Ref(0)
const SAMPLE18_CHILD_WORK = Ref(0)
function sample18_states(domain,n)
    0 <= n <= 8 || error("sample-fixing oracle dimension ceiling")
    work = 1 << n
    SAMPLE18_ORACLE_WORK[] + work <= 16_384 || error("sample-fixing oracle aggregate ceiling")
    SAMPLE18_ORACLE_WORK[] += work
    Iterators.product(fill(domain === :bool ? (0,1) : (-1,1),n)...)
end
function sample18_child(;callback=_->nothing,kwargs...)
    child=FixtureChild(;kwargs...)
    child.callback = c -> begin
        n=length(MOI.get(c.model,MOI.ListOfVariableIndices()))
        n <= 4 || error("sample-fixing child dimension ceiling")
        if !c.scripted
            work=1 << n
            SAMPLE18_CHILD_WORK[] + work <= 65_536 || error("sample-fixing child aggregate ceiling")
            SAMPLE18_CHILD_WORK[] += work
        end
        callback(c)
    end
    child
end
function sample18_pool(model,rows;labels=QUBOTools.variables(model),provenance="independent test input",kwargs...)
    (;labels=copy(labels),domain=QUBOTools.domain(model) === QUBOTools.BoolDomain ? :bool : :spin,
        assignments=[copy(row) for row in rows],provenance,kwargs...)
end
sample18_solve(model,pool;budget=2,child=()->sample18_child(),kwargs...) =
    solve_model(model;strategy=:sample_fixing,sample_pool=pool,budget,child,kwargs...)
function sample18_fixture(;domain=:bool,sense=:min,scale=1.)
    labels=[:z,:a,:q,:internal,:isolate]
    low=domain === :bool ? 0 : -1
    start=[low,1,low,1,low]
    m=QUBOTools.Model{Symbol,Float64,Int}(labels,[1,2,3,4,5],[-3.,2.,-1.,4.,.5],
        [1,3,1,2,3,4],[2,4,3,4,5,5],[3.,-1.,-2.,5.,-4.,1.];
        domain,sense,scale,offset=7.,start=Dict(zip(labels,start)))
    scalar(x)=scale*(7-3x[1]+2x[2]-x[3]+4x[4]+.5x[5]+3x[1]*x[2]-x[3]*x[4]-
        2x[1]*x[3]+5x[2]*x[4]-4x[3]*x[5]+x[4]*x[5])
    # Distinct rows agree on1; after fixing2, support shrinks and3 becomes unanimous.
    rows=[[1,1,1,low,low],[1,1,1,1,1],[1,low,low,1,low]]
    m,start,rows,scalar
end

@testset "Sample pool ownership, validation and finite bounds" begin
    m=direct_model()
    rows=[[1,0,1,0],[1,0,1,0],[0,0,0,0]]
    pool=sample18_pool(m,rows)
    opt=sample18_solve(m,pool;budget=4)
    rows[1][1]=0; pool.labels[1]=:changed
    getter=MOI.get(opt,MOI.RawOptimizerAttribute("sample_pool")); getter.assignments[1][1]=0
    @test MOI.get(opt,MOI.RawOptimizerAttribute("sample_pool")).assignments[1] == [1,0,1,0]
    @test MOI.get(opt,MOI.RawOptimizerAttribute("sample_pool")).labels == [:a,:b,:c,:isolate]
    d=decomposition(opt)["sample_fixing"]
    @test d["supplied_rows"] == d["validated_rows"] == 3
    @test d["distinct_rows"] == 2 && d["duplicate_rows"] == 1
    @test d["reported_generation_sec"] === nothing && !d["generation_cost_measured_by_parent"]
    @test decomposition(opt)["candidate_evaluations"] == 5 # initial + all3 supplied +1 child
    for bad in (nothing,"invalid",(;labels=[:a],domain=:bool,assignments=[[0]]),
        (;labels=[:a],domain=:other,assignments=[[0]],provenance="x"),
        (;labels=[:a],domain=:bool,assignments=[0],provenance="x"),
        (;labels=[:a],domain=:bool,assignments=fill([0],257),provenance="x"),
        (;labels=[:a],domain=:bool,assignments=[zeros(Int,65_537)],provenance="x"),
        (;labels=[:a],domain=:bool,assignments=[[0]],provenance=repeat("x",1025)),
        (;labels=[:a],domain=:bool,assignments=[[0]],provenance="x",generation_sec=-1.),
        (;labels=[:a],domain=:bool,assignments=[[0]],provenance="x",generation_sec=NaN))
        if bad === nothing
            opt=sample18_solve(m,bad)
            @test MOI.get(opt,MOI.TerminationStatus()) === MOI.INVALID_OPTION
        else
            @test_throws ArgumentError QUBODecomposition.Optimizer(sample_pool=bad)
        end
    end
    for value in (true,.5,0.,1.1,NaN,Inf)
        @test_throws ArgumentError QUBODecomposition.Optimizer(fixing_threshold=value)
    end
    for key in ("max_fixings","max_pool_size"), value in (-1,257,true,1.5)
        @test_throws ArgumentError MOI.set(opt,MOI.RawOptimizerAttribute(key),value)
    end
    for altered in ((;labels=[:a,:b,:c,:unknown]),(;labels=[:a,:a,:c,:isolate]),(;domain=:spin),
        (;assignments=[[1,0,1,0],[1,0,1]]),(;assignments=[[1,0,1,0],[1,0,2,0]]),
        (;assignments=[[1,0,1,0],[1,0,NaN,0]]))
        opt=sample18_solve(m,merge(sample18_pool(m,[[1,0,1,0]]),altered))
        @test MOI.get(opt,MOI.TerminationStatus()) === MOI.INVALID_OPTION
        @test QUBOTools.state(opt,1) == zeros(Int,4) # no partial pool-best commit
        @test decomposition(opt)["attempted_calls"] == 0
    end
    opt=sample18_solve(m,sample18_pool(m,[[1,0,1,0],[1,0,1,0]]);max_pool_size=1)
    @test MOI.get(opt,MOI.TerminationStatus()) === MOI.INVALID_OPTION
    for options in ((selection=:partition,), (partition_plan=[[1]],), (consensus_plan=[[1]],),
        (coarse_groups=[[1]],), (separator=[1],), (separator_pruning=true,),
        (component_executor=QUBODecomposition.SequentialComponentExecutor(),))
        opt=sample18_solve(m,sample18_pool(m,[[1,0,1,0]]);options...)
        @test MOI.get(opt,MOI.TerminationStatus()) === MOI.INVALID_OPTION
        @test decomposition(opt)["attempted_calls"] == 0
    end
end

@testset "Unary support changes and independent restricted-objective identities" begin
    for domain in (:bool,:spin), sense in (:min,:max), scale in (-2.5,0.,.75)
        m,start,rows,scalar=sample18_fixture(;domain,sense,scale)
        permutation=[5,3,1,4,2]
        pool=sample18_pool(m,[r[permutation] for r in rows];labels=QUBOTools.variables(m)[permutation],
            generation_sec=0.)
        opt=sample18_solve(m,pool;fixing_threshold=2/3)
        data=decomposition(opt); info=data["sample_fixing"]
        @test info["original_to_pool"] == invperm(permutation)
        @test info["reported_generation_sec"] == 0.
        @test info["pool_complete"] && info["validated_rows"] == 3
        @test QUBOTools.value(opt,1) == scalar(QUBOTools.state(opt,1))
        @test !info["original_proof"] && !data["separable_proof"]
        if scale == 0
            @test MOI.get(opt,MOI.TerminationStatus()) === MOI.OPTIMAL
            @test data["attempted_calls"] == 0 && isempty(info["steps"])
            continue
        end
        @test MOI.get(opt,MOI.TerminationStatus()) === MOI.LOCALLY_SOLVED
        @test [s["original_index"] for s in info["steps"]] == [1,2,3]
        @test [s["support_after"] for s in info["steps"]] == [3,2,2]
        @test [s["score_numerator"] for s in info["steps"]] == [3,2,2]
        @test [s["score_denominator"] for s in info["steps"]] == [3,3,2]
        @test info["support_source_row_ids"] == [1,2]
        @test only(data["calls"])["selected_indices"] == [4,5]
        @test !only(data["calls"])["original_proof"]
        # Evaluate every actual prefix restriction using independent explicit
        # insertion and the original scalar polynomial, without production lift.
        snap=QUBODecomposition.snapshot(m)
        fixed=Dict{Int,Int}()
        for step in info["steps"]
            fixed[step["original_index"]]=step["value"]
            selected=[i for i in 1:5 if !haskey(fixed,i)]
            r=first(filter(r->all(r[i]==v for (i,v) in fixed),rows))
            problem,actual,map,delta=QUBODecomposition.conditioned_problem(snap,r,selected)
            @test actual == fixed
            @test step["remaining_original_indices"] == selected
            @test step["offset_delta"] == delta && step["restricted_offset"] == problem.offset
            for z in sample18_states(domain,length(selected))
                full=[haskey(fixed,i) ? fixed[i] : z[findfirst(==(i),selected)] for i in 1:5]
                value=problem.scale*(problem.offset+sum(c*z[i] for (i,c) in problem.linear;init=0.)+
                    sum(c*z[i]*z[j] for ((i,j),c) in problem.quadratic;init=0.))
                @test value == scalar(full)
                @test QUBOTools.lift_state(collect(z),fixed,map,5) == full
            end
        end
        @test data["accepted_improvements"] >= 0
    end
end

@testset "Exact fractions, deduplication, ties, abstention and fixing cap" begin
    m=QUBOTools.Model{Int,Float64,Int}([1,2,3],[1],[-1.],Int[],Int[],Float64[])
    rows=[[1,1,0],[1,0,1],[0,1,1]]
    for threshold in (2/3,nextfloat(2/3),1.)
        opt=sample18_solve(m,sample18_pool(m,rows);budget=2,fixing_threshold=threshold)
        info=decomposition(opt)["sample_fixing"]
        @test length(info["steps"]) == (threshold == 2/3 ? 1 : 0)
        @test decomposition(opt)["attempted_calls"] == (threshold == 2/3 ? 1 : 0)
        @test MOI.get(opt,MOI.TerminationStatus()) === MOI.LOCALLY_SOLVED
    end
    # Repeated duplicate rows do not turn a distinct-state half tie into evidence.
    balanced=[[0,0,0],[1,1,1]]
    for rows in (balanced,vcat(fill([1,1,1],7),[[0,0,0]]))
        opt=sample18_solve(m,sample18_pool(m,rows);budget=1,fixing_threshold=nextfloat(.5))
        @test isempty(decomposition(opt)["sample_fixing"]["steps"])
        @test decomposition(opt)["stop_reason"] == "sample_fixing_abstained"
        @test decomposition(opt)["attempted_calls"] == 0
    end
    opt=sample18_solve(m,sample18_pool(m,Vector{Int}[]);budget=1)
    @test decomposition(opt)["stop_reason"] == "sample_fixing_empty_pool"
    @test decomposition(opt)["attempted_calls"] == 0
    opt=sample18_solve(m,sample18_pool(m,[[1,1,1]]);budget=1,max_fixings=0)
    @test decomposition(opt)["stop_reason"] == "sample_fixing_cap"
    @test QUBOTools.state(opt,1) == ones(Int,3)
    @test decomposition(opt)["attempted_calls"] == 0
    # Default unanimity uses one fixing at a time and stops as soon as it fits.
    opt=sample18_solve(m,sample18_pool(m,[[1,1,1]]);budget=1)
    @test [s["original_index"] for s in decomposition(opt)["sample_fixing"]["steps"]] == [1,2]
    @test length(only(decomposition(opt)["calls"])["source_to_child"]) == 1
end

@testset "Biased restriction preserves a superior global incumbent and checks feasible witnesses" begin
    m=QUBOTools.Model{Symbol,Float64,Int}([:a,:b,:c],[1,2,3],[4.,-2.,-1.],Int[],Int[],Float64[];
        start=Dict(:a=>0,:b=>1,:c=>1))
    scalar(x)=4x[1]-2x[2]-x[3]
    pool=sample18_pool(m,[[1,0,0],[1,1,0],[1,0,1]])
    opt=sample18_solve(m,pool;budget=2)
    info=decomposition(opt)["sample_fixing"]
    @test info["fixed_variables"] == Dict(1=>1)
    @test !info["global_incumbent_compatible"]
    @test info["restricted_initial_energy"] == 2.
    @test QUBOTools.state(opt,1) == [0,1,1]
    @test QUBOTools.value(opt,1) == minimum(scalar(x) for x in sample18_states(:bool,3)) == -3.
    @test only(decomposition(opt)["calls"])["proposal_energy"] == 1.
    @test MOI.get(opt,MOI.TerminationStatus()) === MOI.LOCALLY_SOLVED
    # With no fixing, global is feasible and must remain the strongest witness.
    opt=sample18_solve(m,pool;budget=3,child=()->sample18_child(rows=[[1,1,1]],status=MOI.OPTIMAL))
    @test decomposition(opt)["sample_fixing"]["global_incumbent_compatible"]
    @test decomposition(opt)["sample_fixing"]["restricted_initial_energy"] == -3.
    @test MOI.get(opt,MOI.TerminationStatus()) === MOI.OTHER_ERROR
    @test occursin("OPTIMAL contradicts",decomposition(opt)["diagnostic"])
    @test QUBOTools.state(opt,1) == [0,1,1]
end

@testset "Pool and terminal transactions under failures, interruption and caps" begin
    m=direct_model()
    basepool=sample18_pool(m,[[0,0,0,0]])
    for status in (MOI.OPTIMAL,MOI.LOCALLY_SOLVED,MOI.INTERRUPTED,MOI.TIME_LIMIT)
        opt=sample18_solve(m,basepool;budget=4,child=()->sample18_child(rows=[[1,0,1,0]],status=status))
        @test QUBOTools.state(opt,1) == [1,0,1,0]
        @test QUBOTools.value(opt,1) == 2.
        @test decomposition(opt)["sample_fixing"]["terminal_improved_incumbent"]
        @test only(decomposition(opt)["calls"])["public_status"] == string(status)
        @test !only(decomposition(opt)["calls"])["original_proof"]
        @test MOI.get(opt,MOI.TerminationStatus()) ===
            (status in (MOI.INTERRUPTED,MOI.TIME_LIMIT) ? status : MOI.LOCALLY_SOLVED)
    end
    for factory in (
        ()->sample18_child(rows=[[1,0,1,0],[1,0,2,0]],status=MOI.INTERRUPTED),
        ()->sample18_child(rows=[[1,0,1,0],[1,0,1]],status=MOI.INTERRUPTED),
        ()->sample18_child(rows=[[1,0,1,0]],callback=_->throw(InterruptException())),
        ()->sample18_child(rows=[[1,0,1,0]],callback=_->error("child failed")),
        ()->error("factory failed"))
        opt=sample18_solve(m,basepool;budget=4,child=factory)
        @test QUBOTools.state(opt,1) == zeros(Int,4)
        @test decomposition(opt)["accepted_improvements"] == 0
        @test !decomposition(opt)["sample_fixing"]["terminal_complete"]
    end
    for pool in (sample18_pool(m,[[1,0,0,0],[1,0,1,0]]),sample18_pool(m,[[1,0,0,0],[1,0,0,0]]))
        opt=sample18_solve(m,pool;budget=4,max_candidate_evaluations=2)
        @test MOI.get(opt,MOI.TerminationStatus()) === MOI.ITERATION_LIMIT
        @test QUBOTools.state(opt,1) == zeros(Int,4)
        @test !decomposition(opt)["sample_fixing"]["pool_complete"]
    end
    # A committed pool-best remains valid after failed terminal child work.
    pool=sample18_pool(m,[[1,0,1,0]])
    opt=sample18_solve(m,pool;budget=4,child=()->error("factory failed"))
    @test QUBOTools.state(opt,1) == [1,0,1,0]
    @test decomposition(opt)["sample_fixing"]["pool_improved_incumbent"]
    for cap in (3,4)
        opt=sample18_solve(m,basepool;budget=4,max_candidate_evaluations=cap,
            child=()->sample18_child(rows=[[1,0,0,0],[1,0,1,0]],status=MOI.INTERRUPTED))
        @test QUBOTools.state(opt,1) == (cap == 3 ? zeros(Int,4) : [1,0,1,0])
        @test MOI.get(opt,MOI.TerminationStatus()) === (cap == 3 ? MOI.ITERATION_LIMIT : MOI.INTERRUPTED)
        @test decomposition(opt)["candidate_evaluations"] == cap
    end
    for caps in ((max_child_calls=0,), (max_candidate_evaluations=2,))
        opt=sample18_solve(m,pool;budget=4,caps...)
        @test QUBOTools.state(opt,1) == [1,0,1,0]
        @test decomposition(opt)["attempted_calls"] == 0
        @test MOI.get(opt,MOI.TerminationStatus()) === MOI.ITERATION_LIMIT
    end
end

@testset "Sample-fixing deadlines preserve transaction boundaries" begin
    m,start,rows,scalar=sample18_fixture()
    for phase in (:sample_pool_labels,:sample_pool_row,:sample_pool_after_row,:sample_pool_commit,
        :sample_fixing_selection,:sample_fixing_score,:sample_fixing_filter,:sample_fixing_conditioning,
        :sample_fixing_after_conditioning,:sample_fixing_step_commit,:sample_fixing_working,
        :before_factory,:before_child,:after_child,:before_row,:before_commit,:sample_fixing_global_commit)
        now=Ref(0.)
        opt=QUBODecomposition.Optimizer(strategy=:sample_fixing,sample_pool=sample18_pool(m,rows),
            fixing_threshold=2/3,max_variables=2,child_optimizer=()->sample18_child())
        QUBODrivers.set_model!(opt,m);opt.clock=()->now[]
        opt.checkpoint=p->(p === phase && (now[]=1.);nothing)
        MOI.set(opt,MOI.TimeLimitSec(),1.);MOI.optimize!(opt)
        @test MOI.get(opt,MOI.TerminationStatus()) === MOI.TIME_LIMIT
        @test QUBOTools.value(opt,1) == scalar(QUBOTools.state(opt,1))
        info=decomposition(opt)["sample_fixing"]
        @test !info["original_proof"] && !info["complete"]
        if phase in (:sample_pool_labels,:sample_pool_row,:sample_pool_after_row,:sample_pool_commit)
            @test QUBOTools.state(opt,1) == start && !info["pool_complete"]
        else
            @test info["pool_complete"]
            @test scalar(QUBOTools.state(opt,1)) <= scalar(start)
        end
    end
end

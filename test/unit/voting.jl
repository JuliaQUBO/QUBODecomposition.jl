# SPDX-License-Identifier: MPL-2.0
# Internal transaction harness supplies explicit overlapping neighborhoods so the
# scalar fixtures test aggregation independently of a particular graph selector.
function batch_harness(model, neighborhoods; child=()->FixtureChild(), budget=2, checkpoint=_ -> nothing, deadline=nothing, clock=()->0., kwargs...)
    opt = QUBODecomposition.Optimizer(;child_optimizer=child,max_variables=budget,
        strategy=:frozen_batch,batch_size=64,kwargs...)
    QUBODrivers.set_model!(opt,model)
    opt.checkpoint=checkpoint;opt.clock=clock
    snap=QUBODecomposition.snapshot(QUBOTools.backend(opt))
    data=Dict{String,Any}("calls"=>Any[],"batches"=>Any[],"attempted_calls"=>0,
        "completed_calls"=>0,"incomplete_scan"=>false,"invocation"=>1,
        "incumbent_energy_trace"=>Float64[],"parent_overrun_sec"=>0.,
        "phase_sec"=>Dict(k=>0. for k in ("conditioning","copying","execution","validation_reconstruction","full_energy","aggregation")))
    energy=QUBODecomposition.full_energy(snap.state,snap.linear,snap.quadratic,snap.scale,snap.offset)
    ctx=QUBODecomposition.SolveState(copy(snap.state),energy,1,0,deadline,data)
    failure=nothing
    try
        QUBODecomposition.frozen_batch!(opt,ctx,snap,neighborhoods)
    catch err
        failure=err
    end
    return (; opt,ctx,data,failure)
end

function voting_fixture(;domain=:bool,sense=:min,scale=1.,offset=0.)
    # E = -x1+2x2-x3-x4 +3(x1x3+x1x4+x3x4)-4x2(x1+x3+x4).
    QUBOTools.Model{Symbol,Float64,Int}([:z,:a,:q,:b],collect(1:4),[-1.,2.,-1.,-1.],
        [1,1,3,1,2,2],[3,4,4,2,3,4],[3.,3.,3.,-4.,-4.,-4.];domain,sense,scale,offset)
end
voting_scalar(x,scale=1.,offset=0.) = scale*(offset-x[1]+2x[2]-x[3]-x[4]+3(x[1]*x[3]+x[1]*x[4]+x[3]*x[4])-4x[2]*(x[1]+x[3]+x[4]))

@testset "Independent unweighted vote oracle: agreements/conflicts/ties/uncovered" begin
    for low in (0,-1)
        frozen=[1,low,1,low,1]
        blocks=[[1,2,3],[2,3,4],[2,4]]
        proposals=[(;state=[low,1,low,low,1]),(;state=[1,low,low,1,1]),(;state=[1,1,1,low,1])]
        consensus,conflicts,ties,votes=QUBODecomposition.batch_votes(frozen,blocks,proposals)
        @test consensus == [low,1,low,low,1] # 2 majority, 4 tie retains low, 5 uncovered
        @test conflicts == [2,4]
        @test ties == [4]
        @test votes == Dict(1=>(1,0),2=>(1,2),3=>(2,0),4=>(1,1))
    end
end

@testset "Frozen boundaries, full-objective proposals and repairing a worse consensus" begin
    blocks=[[1,2],[2,3],[2,4]]
    for repair in (false,true), duplicate in (false,true)
        children=FixtureChild[]; counter=Ref(0)
        rows=([[1,1]],duplicate ? [[0,1],[0,1],[0,1]] : [[0,1]],[[0,1]])
        factory=()->begin
            counter[]+=1
            c=counter[]<=3 ? FixtureChild(rows=rows[counter[]],values=fill(1000. * counter[],length(rows[counter[]])),status=MOI.LOCALLY_SOLVED) : FixtureChild()
            push!(children,c);c
        end
        run=batch_harness(voting_fixture(),blocks;child=factory,repair)
        @test run.failure === nothing
        record=only(run.data["batches"])
        @test record["proposal_energies"] == [-3.,-1.,-1.]
        @test record["consensus_energy"] == 6.
        @test record["disagreement"] == [2]
        @test run.ctx.state == (repair ? ones(Int,4) : [1,1,0,0])
        @test run.ctx.energy == (repair ? -4. : -3.)
        @test record["repaired_energy"] == (repair ? -4. : 6.)
        @test run.ctx.improvements == 1
        @test record["complete"] && record["accepted"]
        @test all(c["conditioning_incumbent_version"] == 0 for c in run.data["calls"][1:3])
        @test all(all(iszero,values(c["boundary_fixed_variables"])) for c in run.data["calls"][1:3])
        @test run.ctx.evaluations == 1 + sum(length(r) for r in rows) + 2 + Int(repair)
        if repair
            # Independently inspect actual reduced coefficients. Bare diagonal
            # would choose x2=0; the fixed 1011 boundary gives -10*x2 + 6.
            objective=first(children[4].log).objective
            @test boundary_energy(objective,(0,)) == 6.
            @test boundary_energy(objective,(1,)) == -4.
            @test run.data["calls"][4]["boundary_fixed_variables"] == Dict(1=>1,3=>1,4=>1)
        end
        # Every possible row of every frozen child has the original scalar energy,
        # independently of public reported offsets or reversed MOI child indices.
        for (selected,child) in zip(blocks,children)
            for y in Iterators.product((0,1),(0,1))
                x=zeros(Int,4);x[selected]=collect(y)
                @test boundary_energy(first(child.log).objective,y) == voting_scalar(x)
            end
        end
    end
    # Every proposal and their consensus worsen E=sum(x); preserve the incumbent.
    linear=QUBOTools.Model{Int,Float64,Int}(collect(1:4),collect(1:4),ones(4),Int[],Int[],Float64[])
    run=batch_harness(linear,blocks;child=()->FixtureChild(rows=[[1,1]],status=MOI.LOCALLY_SOLVED))
    @test run.ctx.state == zeros(Int,4)
    @test run.ctx.energy == 0
    @test only(run.data["batches"])["consensus_energy"] == 4
    @test isempty(only(run.data["batches"])["repair_blocks"])
end

@testset "Bounded disagreement blocks condition sequential scratch boundaries" begin
    model=QUBOTools.Model{Int,Float64,Int}(collect(1:5),collect(1:5),fill(-1.,5),
        [1,2,3,4],[2,3,4,5],fill(-2.,4);offset=3.)
    blocks=[[1,2],[2,3],[3,4],[4,5],[1,5]]
    scripted=([[1,1]],[[0,0]],[[1,1]],[[0,0]],[[0,1]])
    children=FixtureChild[]; counter=Ref(0)
    factory=()->begin
        counter[]+=1
        c=counter[]<=5 ? FixtureChild(rows=scripted[counter[]],status=MOI.LOCALLY_SOLVED) : FixtureChild()
        push!(children,c);c
    end
    run=batch_harness(model,blocks;child=factory)
    @test run.failure === nothing
    record=only(run.data["batches"])
    @test record["disagreement"] == collect(1:5)
    @test record["repair_blocks"] == [[1,2],[3,4],[5]]
    @test record["repair_completed_blocks"] == 3
    @test run.ctx.state == ones(Int,5)
    @test all(length(c["selected_indices"])<=2 for c in run.data["calls"])
    scratch=zeros(Int,5)
    scalar(x)=3-sum(x)-2sum(x[i]*x[i+1] for i in 1:4)
    for (call,child) in zip(run.data["calls"][6:end],children[6:end])
        selected=call["selected_indices"]
        @test call["boundary_fixed_variables"] == Dict(i=>scratch[i] for i in keys(call["boundary_fixed_variables"]))
        for y in Iterators.product(fill((0,1),length(selected))...)
            x=copy(scratch);x[selected]=collect(y)
            @test boundary_energy(first(child.log).objective,y) == scalar(x)
        end
        scratch[selected].=1
    end
    @test scalar(run.ctx.state)==run.ctx.energy
end

@testset "Proposal energy ties deterministic; multiplicity is diagnostic" begin
    model=QUBOTools.Model{Int,Float64,Int}(collect(1:3),[1],[-1.],Int[],Int[],Float64[])
    for rows in ([[1,1],[1,0]],[[1,0],[1,1],[1,1]])
        run=batch_harness(model,[[1,2]];repair=false,
            child=()->FixtureChild(rows=rows,values=collect(100.:100.:100length(rows)),status=MOI.LOCALLY_SOLVED))
        @test run.ctx.state == [1,0,0]
        @test only(run.data["batches"])["votes"] == Dict(1=>(0,1),2=>(1,0))
    end
    for reads in (1,97)
        run=batch_harness(model,[[1,2],[1,3]];repair=false,
            child=()->begin
                c=MultiplicityChild();MOI.set(c,MOI.RawOptimizerAttribute("physical_reads"),reads);c
            end)
        @test run.failure === nothing
        @test only(run.data["batches"])["votes"] == Dict(1=>(0,2),2=>(0,1),3=>(0,1))
        @test all(c["reported_multiplicities"]==[reads] for c in run.data["calls"])
        @test run.ctx.evaluations == 5
    end
end

@testset "Batch aborts preserve committed assignment and spend shared budgets" begin
    blocks=[[1,2],[2,3],[2,4]]
    for bad in (FixtureChild(rows=[[0,1],[2,0]],status=MOI.LOCALLY_SOLVED),
        FixtureChild(status=MOI.OTHER_ERROR),FixtureChild(status=MOI.INTERRUPTED),
        FixtureChild(rows=[[0,1]],status=MOI.TIME_LIMIT))
        k=Ref(0)
        run=batch_harness(voting_fixture(),blocks;child=()->(k[]+=1;k[]==2 ? bad : FixtureChild(rows=[[1,1]],status=MOI.LOCALLY_SOLVED)))
        @test run.failure !== nothing
        @test run.ctx.state == zeros(Int,4) && run.ctx.energy == 0.
        @test !only(run.data["batches"])["complete"]
        @test run.data["attempted_calls"] == 2
    end
    # Failures in the repair child also roll back earlier validated proposals.
    k=Ref(0)
    run=batch_harness(voting_fixture(),blocks;child=()->(k[]+=1;
        k[]==4 ? FixtureChild(rows=[[1],[2]],status=MOI.LOCALLY_SOLVED) :
        FixtureChild(rows=[k[]==1 ? [1,1] : [0,1]],status=MOI.LOCALLY_SOLVED)))
    @test run.failure !== nothing
    @test run.ctx.state == zeros(Int,4)
    for phase in (:batch_generation,:batch_voting,:batch_consensus,:batch_repair,:batch_repaired,:batch_acceptance,:before_batch_commit)
        k=Ref(0)
        run=batch_harness(voting_fixture(),blocks;
            checkpoint=p->(p===phase && throw(InterruptException());nothing),
            child=()->(k[]+=1;FixtureChild(rows=[k[]==1 ? [1,1] : k[]<=3 ? [0,1] : [1]],status=MOI.LOCALLY_SOLVED)))
        @test run.failure isa InterruptException
        @test run.ctx.state == zeros(Int,4)
        @test !only(run.data["batches"])["complete"]
    end
    for (cap,calls) in ((1,0),(2,1),(4,3),(5,3),(6,4))
        k=Ref(0)
        run=batch_harness(voting_fixture(),blocks;max_candidate_evaluations=cap,
            child=()->(k[]+=1;FixtureChild(rows=[k[]==1 ? [1,1] : k[]<=3 ? [0,1] : [1]],status=MOI.LOCALLY_SOLVED)))
        @test run.failure isa QUBODecomposition.StopSolve
        @test run.ctx.evaluations <= cap
        @test run.ctx.state == zeros(Int,4)
        @test run.data["attempted_calls"] == calls
    end
    for cap in (0,1,2,3)
        run=batch_harness(voting_fixture(),blocks;max_child_calls=cap,
            child=()->FixtureChild(rows=[[1,1]],status=MOI.LOCALLY_SOLVED))
        cap<3 && @test run.failure isa QUBODecomposition.StopSolve
        @test run.data["attempted_calls"] <= cap
        cap<3 && @test run.ctx.state == zeros(Int,4)
    end
end

@testset "Public strategy frames, repeated solves, limits and exact special cases" begin
    for domain in (:bool,:spin),sense in (:min,:max),scale in (2.5,-1.5),selection in (:strongest_edge,:bfs)
        model=voting_fixture(;domain,sense,scale,offset=7.25)
        start=domain===:bool ? [0,1,0,1] : [-1,1,-1,1]
        for (v,x) in zip(QUBOTools.variables(model),start)
            QUBOTools.attach!(model,v=>x)
        end
        children=FixtureChild[]
        opt=solve_model(model;budget=2,strategy=:frozen_batch,selection,batch_size=3,
            max_sweeps=2,seed=41,child=()->(c=FixtureChild();push!(children,c);c))
        data=decomposition(opt)
        @test data["labels"] == [:z,:a,:q,:b]
        @test voting_scalar(QUBOTools.state(opt,1),scale,7.25) == QUBOTools.value(opt,1)
        @test MOI.get(opt,MOI.TerminationStatus()) in (MOI.LOCALLY_SOLVED,MOI.ITERATION_LIMIT)
        @test !data["separable_proof"]
        for batch in data["batches"]
            @test batch["complete"]
            calls=filter(c->get(c,"batch",nothing)==batch["batch"] && c["kind"]=="batch_proposal",data["calls"])
            @test all(c["conditioning_incumbent_version"]==batch["frozen_incumbent_version"] for c in calls)
            # Pairwise shared boundary variables must have the same frozen value.
            for a in calls,b in calls,i in intersect(keys(a["boundary_fixed_variables"]),keys(b["boundary_fixed_variables"]))
                @test a["boundary_fixed_variables"][i] == b["boundary_fixed_variables"][i]
            end
        end
        previous=(QUBOTools.state(opt,1),QUBOTools.value(opt,1),block_trace(opt))
        MOI.optimize!(opt)
        @test (QUBOTools.state(opt,1),QUBOTools.value(opt,1),block_trace(opt)) == previous
        MOI.set(opt,MOI.RawOptimizerAttribute("batch_size"),1)
        @test MOI.get(opt,MOI.ResultCount()) == 0
        MOI.optimize!(opt)
        @test all(length(b["neighborhoods"])==1 for b in decomposition(opt)["batches"])
    end
    for selection in (:single_flip_gain,:random_blocks,:partition)
        opt=solve_model(voting_fixture();budget=2,strategy=:frozen_batch,selection)
        @test MOI.get(opt,MOI.TerminationStatus()) === MOI.INVALID_OPTION
        @test decomposition(opt)["attempted_calls"] == 0
    end
    for batch_size in (0,65,true,1.5), repair in (0,:yes)
        @test_throws ArgumentError QUBODecomposition.Optimizer(;batch_size)
        @test_throws ArgumentError QUBODecomposition.Optimizer(;repair)
    end
    for (model,budget) in ((separable_model(),2),(voting_fixture(),4))
        opt=solve_model(model;budget,strategy=:frozen_batch)
        @test MOI.get(opt,MOI.TerminationStatus()) === MOI.OPTIMAL
        @test isempty(decomposition(opt)["batches"])
    end
    trap=graph_fixture(6,[(i,j) for i in 1:6 for j in i+1:6];bias=1.,weight=-2.)
    opt=solve_model(trap;budget=2,strategy=:frozen_batch,stagnation_sweeps=1)
    @test QUBOTools.value(opt,1)==0.
    @test minimum(2sum(x)-sum(x)^2 for x in Iterators.product(fill((0,1),6)...)) == -24.
    @test all(c["exact"] for c in decomposition(opt)["calls"])
    @test MOI.get(opt,MOI.TerminationStatus()) === MOI.LOCALLY_SOLVED
    for phase in (:batch_generation,:batch_voting,:batch_acceptance),timed in (false,true)
        opt=QUBODecomposition.Optimizer(child_optimizer=()->FixtureChild(),max_variables=2,strategy=:frozen_batch)
        QUBODrivers.set_model!(opt,voting_fixture())
        ticks=Ref(0.);opt.clock=()->ticks[]
        timed && MOI.set(opt,MOI.TimeLimitSec(),1.)
        opt.checkpoint=p->(p===phase && (timed ? (ticks[]=2.) : throw(InterruptException()));nothing)
        MOI.optimize!(opt)
        @test MOI.get(opt,MOI.TerminationStatus()) === (timed ? MOI.TIME_LIMIT : MOI.INTERRUPTED)
        @test QUBOTools.state(opt,1)==zeros(Int,4)
    end
end


@testset "Batch deadlines, prior committed batches and MOI fixed reconstruction" begin
    blocks=[[1,2],[2,3],[2,4]]
    for phase in (:batch_generation,:batch_voting,:batch_consensus,:batch_repair,:batch_repaired,:batch_acceptance,:before_batch_commit)
        k=Ref(0);ticks=Ref(0.)
        run=batch_harness(voting_fixture(),blocks;deadline=1.,clock=()->ticks[],
            checkpoint=p->(p===phase && (ticks[]=2.);nothing),
            child=()->(k[]+=1;FixtureChild(rows=[k[]==1 ? [1,1] : k[]<=3 ? [0,1] : [1]],status=MOI.LOCALLY_SOLVED)))
        @test run.failure isa QUBODecomposition.StopSolve
        @test run.failure.status === MOI.TIME_LIMIT
        @test run.ctx.state==zeros(Int,4)
        @test !only(run.data["batches"])["complete"]
        @test only(run.data["batches"])["reason"]=="parent_time_limit"
    end
    k=Ref(0)
    opt=solve_model(voting_fixture();budget=2,strategy=:frozen_batch,batch_size=3,repair=false,
        child=()->(k[]+=1;k[]==4 ? FixtureChild(status=MOI.OTHER_ERROR) :
            FixtureChild(rows=[k[]<=2 ? [1,1] : [0,1]],status=MOI.LOCALLY_SOLVED)))
    @test MOI.get(opt,MOI.TerminationStatus()) === MOI.OTHER_ERROR
    @test QUBOTools.state(opt,1)==[1,1,1,0]
    @test QUBOTools.value(opt,1)==-5.
    @test decomposition(opt)["batches"][1]["complete"]
    @test !decomposition(opt)["batches"][2]["complete"]
    @test decomposition(opt)["batches"][2]["frozen_incumbent_version"]==1
    for spin in (false,true),maximize in (false,true)
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
        opt=QUBODecomposition.Optimizer(child_optimizer=()->FixtureChild(),max_variables=2,strategy=:frozen_batch)
        map=MOI.copy_to(opt,source);MOI.optimize!(opt)
        x=[MOI.get(opt,MOI.VariablePrimal(),map[v]) for v in vars]
        @test x[1]==fixed
        @test 5+2x[1]+2x[2]+x[3]+x[4]+3x[1]*x[2]-4x[2]*x[3]-4x[2]*x[4] == MOI.get(opt,MOI.ObjectiveValue())
        @test decomposition(opt)["labels"]==[map[v] for v in vars[2:4]]
        @test QUBOTools.state(opt,1)==x[2:4]
        @test all(all(i<=3 for i in c["selected_indices"]) for c in decomposition(opt)["calls"])
        @test MOI.get(opt,MOI.TerminationStatus())===MOI.LOCALLY_SOLVED
    end
end

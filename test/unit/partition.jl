# SPDX-License-Identifier: MPL-2.0
include(joinpath(@__DIR__, "../../examples/partition/region_growing.jl"))

@testset "Partition ownership and pre-dispatch validation" begin
    model = graph_fixture(7, [(i,i+1) for i in 1:5]; bias=-1.0)
    good = [[3,2,1],[6,5,4],[7]]
    plans = ([[1,1],[2,3],[4,5],[6,7]], [[1,2],[2,3],[4,5],[6,7]],
        [[1,2,3],[4,5,6]], [[1,2,3],[4,5,6],[8]], [Int[],collect(1:7)],
        [collect(1:7)], [[1,2,3],[4,5,6],[true]], [[1,2,3],[4,5,6],[0]])
    for plan in plans
        calls = Ref(0)
        # Callback permits malformed outputs to reach solve-time validation.
        opt = solve_model(model; budget=3, selection=:partition,
            partition_plan=(indices,graph,cap)->plan,
            child=()->(calls[]+=1; FixtureChild()))
        @test MOI.get(opt,MOI.TerminationStatus()) === MOI.INVALID_OPTION
        @test calls[] == decomposition(opt)["attempted_calls"] == 0
        @test QUBOTools.state(opt,1) == zeros(Int,7)
        @test !decomposition(opt)["separable_proof"]
    end
    @test_throws ArgumentError QUBODecomposition.Optimizer(partition_plan=[[true]])
    @test_throws ArgumentError QUBODecomposition.Optimizer(partition_plan="invalid")
    opt = solve_model(model; budget=3, selection=:partition, partition_plan=good, max_sweeps=1)
    @test good == [[3,2,1],[6,5,4],[7]]
    good[1][1] = 7
    getter = MOI.get(opt,MOI.RawOptimizerAttribute("partition_plan"))
    getter[1][1] = 6
    @test MOI.get(opt,MOI.RawOptimizerAttribute("partition_plan"))[1] == [3,2,1]
    data = decomposition(opt)
    @test data["partition"]["blocks"] == [[1,2,3],[4,5,6],[7]]
    @test data["partition"]["block_sizes"] == [3,3,1]
    @test data["partition"]["cut_edges"] == 1
    @test data["partition"]["cut_absolute_weight"] == 0.5
    @test data["partition"]["planning_sec"] >= 0
    @test [c["selected_indices"] for c in data["calls"] if c["kind"] == "partition"] == [[1,2,3],[4,5,6],[7]]
    @test sum(c["phase_sec"]["conditioning"] for c in data["calls"]) <= data["phase_sec"]["conditioning"]
    # Flat callback: an unchanged oversized region is rejected, never recursed.
    called = Ref(0)
    opt = solve_model(model; budget=1, selection=:partition,
        partition_plan=(indices,g,c)->(called[]+=1; [indices]))
    @test called[] == 1
    @test MOI.get(opt,MOI.TerminationStatus()) === MOI.INVALID_OPTION
    for plan in (nothing, (i,g,c)->nothing)
        opt = solve_model(model; budget=3, selection=:partition, partition_plan=plan)
        @test MOI.get(opt,MOI.TerminationStatus()) === MOI.INVALID_OPTION
    end
    for failure in (ErrorException("callback failed"), InterruptException())
        opt = solve_model(model; budget=3, selection=:partition, partition_plan=(i,g,c)->throw(failure))
        @test MOI.get(opt,MOI.TerminationStatus()) === (failure isa InterruptException ? MOI.INTERRUPTED : MOI.OTHER_ERROR)
        @test decomposition(opt)["attempted_calls"] == 0
    end
    # Validation also precedes fitting/constant shortcuts.
    for m in (linear_model(3), graph_fixture(3,[(1,2)];bias=0.0,weight=0.0))
        opt = solve_model(m; budget=4, selection=:partition, partition_plan=[[1,2]])
        @test MOI.get(opt,MOI.TerminationStatus()) === MOI.INVALID_OPTION
        @test decomposition(opt)["attempted_calls"] == 0
    end
end

@testset "Partition positions after MOI fixing and retained exact routes" begin
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
        seen=Any[]
        opt=QUBODecomposition.Optimizer(child_optimizer=()->FixtureChild(),max_variables=2,
            selection=:partition,partition_plan=(indices,g,c)->(push!(seen,copy(indices));[[2,1],[3]]))
        map=MOI.copy_to(opt,source); MOI.optimize!(opt)
        x=[MOI.get(opt,MOI.VariablePrimal(),map[v]) for v in vars]
        scalar(x)=5+2x[1]+2x[2]+x[3]+x[4]+3x[1]*x[2]-4x[2]*x[3]-4x[2]*x[4]
        @test seen == [[1,2,3]]
        @test x[1] == fixed
        @test scalar(x) == MOI.get(opt,MOI.ObjectiveValue())
        @test decomposition(opt)["labels"] == [map[v] for v in vars[2:4]]
        @test QUBOTools.state(opt,1) == x[2:4]
        @test decomposition(opt)["partition"]["blocks"] == [[1,2],[3]]
        @test MOI.get(opt,MOI.TerminationStatus()) === MOI.LOCALLY_SOLVED
    end
    empty=QUBOTools.Model{Int,Float64,Int}(Int[],Int[],Float64[],Int[],Int[],Float64[])
    opt=solve_model(empty;budget=1,selection=:partition,partition_plan=Vector{Int}[])
    @test MOI.get(opt,MOI.TerminationStatus()) === MOI.OPTIMAL
    @test isempty(decomposition(opt)["partition"]["blocks"])
    model=graph_fixture(5,[(i,i+1) for i in 1:4];bias=-1.)
    opt=solve_model(model;budget=2,strategy=:separator,separator=[3],selection=:partition)
    @test MOI.get(opt,MOI.TerminationStatus()) === MOI.OPTIMAL
    @test decomposition(opt)["partition"] === nothing
end

@testset "Region callback: isolates, capacity one and fresh graph ownership" begin
    model = graph_fixture(7, [(1,2),(2,3),(3,4),(4,5),(5,6)]; bias=-1.0)
    for capacity in (1,2,3,8)
        opt = solve_model(model; budget=capacity, selection=:partition,
            partition_plan=PartitionExample.region_growing, max_sweeps=1)
        blocks = decomposition(opt)["partition"]["blocks"]
        @test sort(vcat(blocks...)) == collect(1:7)
        @test all(1 <= length(b) <= capacity for b in blocks)
        @test last(blocks) == [7]
        capacity == 1 && @test blocks == [[i] for i in 1:7]
    end
    observed = Any[]
    callback = (indices,g,c) -> begin
        push!(observed,deepcopy(g))
        blocks = PartitionExample.region_growing(indices,g,c)
        empty!(indices); empty!(g[1])
        return blocks
    end
    opt = solve_model(model; budget=3, selection=:partition, partition_plan=callback, max_sweeps=1)
    first_trace = block_trace(opt)
    MOI.optimize!(opt)
    @test observed[1] == observed[2]
    @test block_trace(opt) == first_trace
    form = QUBOTools.form(QUBOTools.backend(opt))
    QUBOTools.data(QUBOTools.quadratic_form(form))[3,4] = 0.0
    MOI.optimize!(opt)
    fresh = solve_model(QUBOTools.backend(opt); budget=3, selection=:partition, partition_plan=callback,max_sweeps=1)
    @test block_trace(opt) == block_trace(fresh)
    @test QUBOTools.state(opt,1) == QUBOTools.state(fresh,1)
    @test observed[3] != observed[2]
    QUBODrivers.set_model!(opt,linear_model(2))
    MOI.optimize!(opt)
    @test decomposition(opt)["partition"]["blocks"] == [[1],[2]]
    @test MOI.get(opt,MOI.TerminationStatus()) === MOI.OPTIMAL
    MOI.set(opt,MOI.RawOptimizerAttribute("partition_plan"),[[1],[2],[3]])
    @test MOI.get(opt,MOI.ResultCount()) == 0
    MOI.optimize!(opt)
    @test MOI.get(opt,MOI.TerminationStatus()) === MOI.INVALID_OPTION
    @test decomposition(opt)["attempted_calls"] == 0
end

# Two complete three-vertex clusters, joined only by edge (3,4).
cluster_edges = [(1,2),(1,3),(2,3),(3,4),(4,5),(4,6),(5,6)]
cluster_weights = [-2.0,-2.0,-2.0,4.0,-2.0,-2.0,-2.0]
function partition_clusters(;domain=:bool,sense=:min,scale=1.0,storage=:dict)
    labels = [:z,:a,:q,:b,:y,:c,:isolate]
    base = QUBOTools.Model{Symbol,Float64,Int}(labels,collect(1:7),
        [1.0,1.0,1.0,1.0,1.0,1.0,-0.5],first.(cluster_edges),last.(cluster_edges),cluster_weights;
        domain,sense,scale,offset=7.25)
    QUBOTools.Model{Symbol,Float64,Int}(QUBOTools.VariableMap{Symbol}(Dict(i=>v for (i,v) in enumerate(labels))),QUBOTools.form(base,storage,Float64))
end
cluster_energy(x,scale) = scale*(7.25+sum(x[1:6])-0.5x[7]-2(x[1]*x[2]+x[1]*x[3]+x[2]*x[3]+x[4]*x[5]+x[4]*x[6]+x[5]*x[6])+4x[3]*x[4])

@testset "Dense clusters: all conditioned/lifted energies against scalar oracle" begin
    for domain in (:bool,:spin), sense in (:min,:max), scale in (2.5,-1.5), storage in (:dict,:sparse,:dense)
        model = partition_clusters(;domain,sense,scale,storage)
        values = domain === :bool ? (0,1) : (-1,1)
        start = [values[1],values[2],values[1],values[2],values[1],values[2],values[1]]
        for (label,x) in zip(QUBOTools.variables(model),start)
            QUBOTools.attach!(model,label=>x)
        end
        children = FixtureChild[]
        opt = solve_model(model; budget=3, selection=:partition,
            partition_plan=[[6,5,4],[7],[3,2,1]], max_sweeps=2,
            child=()->(c=FixtureChild();push!(children,c);c))
        data = decomposition(opt)
        @test data["labels"] == QUBOTools.variables(model)
        @test data["partition"]["cut_edges"] == 1
        @test data["partition"]["cut_absolute_weight"] == abs(scale*4)
        incumbent = copy(start)
        for (call,child) in zip(data["calls"],children)
            map = call["original_to_reduced"]
            fixed = Dict(i=>incumbent[i] for i in 1:7 if !haskey(map,i))
            energies = Float64[]
            for reduced in Iterators.product(fill(values,length(map))...)
                full = [haskey(fixed,i) ? fixed[i] : reduced[map[i]] for i in 1:7]
                @test QUBOTools.lift_state(collect(reduced),fixed,map,7) == full
                @test boundary_energy(first(child.log).objective,reduced) == cluster_energy(full,scale)
                push!(energies,cluster_energy(full,scale))
            end
            best = (sense === :min ? minimum : maximum)(energies)
            row = only(child.rows)
            candidate = [haskey(fixed,i) ? fixed[i] : row[VI(call["source_to_child"][map[i]])] for i in 1:7]
            @test cluster_energy(candidate,scale) == best
            if sense === :min ? best < cluster_energy(incumbent,scale) : best > cluster_energy(incumbent,scale)
                incumbent = candidate
            end
            @test call["committed_energy"] == cluster_energy(incumbent,scale)
        end
        @test QUBOTools.state(opt,1) == incumbent
        @test QUBOTools.value(opt,1) == cluster_energy(incumbent,scale)
        @test !data["separable_proof"]
        @test all(sense === :min ? diff(data["incumbent_energy_trace"]) .<= 0 : diff(data["incumbent_energy_trace"]) .>= 0)
    end
    # Start left cluster at 111 and right at 000. Bare principal submatrix
    # selects right 111 (internal energy -3); the true boundary adds 4*x4.
    # Its minimum is right 011 (energy 0), so strict acceptance keeps 000.
    model = partition_clusters()
    for i in 1:3
        QUBOTools.attach!(model,QUBOTools.variable(model,i)=>1)
    end
    opt = solve_model(model; budget=3, selection=:partition,
        partition_plan=[[1,2,3],[4,5,6],[7]],max_sweeps=1)
    @test QUBOTools.state(opt,1)[1:6] == [1,1,1,0,0,0]
    bare(y) = sum(y)-2(y[1]*y[2]+y[1]*y[3]+y[2]*y[3])
    states = collect(Iterators.product((0,1),(0,1),(0,1)))
    @test states[argmin(bare.(states))] == (1,1,1)
    @test bare((1,1,1))+4 > bare((0,1,1))
    @test decomposition(opt)["calls"][3]["boundary_fixed_variables"] == Dict(3=>1)
end

@testset "Exact children do not certify coupled partitions; caps and failures" begin
    n=6
    trap = graph_fixture(n,[(i,j) for i in 1:n for j in i+1:n];bias=1.0,weight=-2.0)
    plan = [[1,2],[3,4],[5,6]]
    opt = solve_model(trap;budget=2,selection=:partition,partition_plan=plan,stagnation_sweeps=1)
    @test QUBOTools.value(opt,1) == 0
    @test minimum(2sum(x)-sum(x)^2 for x in Iterators.product(fill((0,1),n)...)) == -24
    @test all(c["exact"] for c in decomposition(opt)["calls"])
    @test MOI.get(opt,MOI.TerminationStatus()) === MOI.LOCALLY_SOLVED
    @test !decomposition(opt)["separable_proof"]
    for (kwargs,calls) in (((;max_child_calls=1),1),((;max_candidate_evaluations=2),1),((;max_sweeps=0),0))
        capped=solve_model(trap;budget=2,selection=:partition,partition_plan=plan,kwargs...)
        @test MOI.get(capped,MOI.TerminationStatus()) === MOI.ITERATION_LIMIT
        @test decomposition(capped)["completed_calls"] == calls
        @test decomposition(capped)["completed_sweeps"] == 0
        @test QUBOTools.state(capped,1) == zeros(Int,n)
    end
    for phase in (:partition_planning,:conditioning,:before_child,:reconstruct,:before_commit), timed in (false,true)
        opt=QUBODecomposition.Optimizer(child_optimizer=()->FixtureChild(),max_variables=2,
            selection=:partition,partition_plan=plan)
        QUBODrivers.set_model!(opt,trap)
        ticks=Ref(0.0); opt.clock=()->ticks[]
        timed && MOI.set(opt,MOI.TimeLimitSec(),1.0)
        opt.checkpoint=p -> (p === phase && (timed ? (ticks[]=2.0) : throw(InterruptException()));nothing)
        MOI.optimize!(opt)
        @test MOI.get(opt,MOI.TerminationStatus()) === (timed ? MOI.TIME_LIMIT : MOI.INTERRUPTED)
        @test decomposition(opt)["completed_calls"] == 0
        @test !decomposition(opt)["separable_proof"]
        @test QUBOTools.state(opt,1) == zeros(Int,n)
        opt.checkpoint=_ -> nothing; opt.clock=()->0.0
        MOI.optimize!(opt)
        @test MOI.get(opt,MOI.TerminationStatus()) === MOI.LOCALLY_SOLVED
    end
    for child in (() -> FixtureChild(rows=[[2,0]]), () -> FixtureChild(status=MOI.INTERRUPTED), () -> FixtureChild(status=MOI.OTHER_ERROR))
        opt=solve_model(trap;budget=2,selection=:partition,partition_plan=plan,child)
        @test MOI.get(opt,MOI.TerminationStatus()) in (MOI.OTHER_ERROR,MOI.INTERRUPTED)
        @test QUBOTools.state(opt,1) == zeros(Int,n)
        @test decomposition(opt)["completed_calls"] == 0
    end
    # Existing independent-component and whole-model routes retain certificates.
    for (model,budget,plan) in ((separable_model(),2,[[1,2],[3],[4,5],[6]]),(trap,6,[collect(1:6)]))
        opt=solve_model(model;budget,selection=:partition,partition_plan=plan)
        @test MOI.get(opt,MOI.TerminationStatus()) === MOI.OPTIMAL
        @test decomposition(opt)["completed_sweeps"] == 0
    end
end

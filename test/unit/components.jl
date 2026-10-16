# SPDX-License-Identifier: MPL-2.0
const QD = QUBODecomposition
using Distributed

# A custom public executor deliberately returns component 2 before component 1.
# Synchronization uses a channel, never a speed threshold.
mutable struct ShuffledExecutor <: QD.AbstractComponentExecutor
    jobs::Vector{QD.ComponentJob}
    completed::Vector{Int}
    gate::Channel{Nothing}
    transform::Function
end
ShuffledExecutor(; transform=identity) = ShuffledExecutor(QD.ComponentJob[], Int[], Channel{Nothing}(1), transform)
QD.executor_width(::ShuffledExecutor) = 2
struct FixtureHandle
    task::Task
end
Base.isready(h::FixtureHandle) = istaskdone(h.task)
Base.fetch(h::FixtureHandle) = fetch(h.task)
function QD.submit_component(e::ShuffledExecutor, factory, job)
    push!(e.jobs, job)
    return FixtureHandle(@async begin
        k = job.id[3]
        k == 1 && take!(e.gate)
        try
            result = QD.execute_component(factory, job)
            push!(e.completed, k)
            e.transform(result)
        finally
            k == 2 && put!(e.gate, nothing)
        end
    end)
end

function disconnected_fixture(; domain=:bool, sense=:min, scale=1.0, offset=7.0)
    QUBOTools.Model{String,Float64,Int}(["z", "label α", "isolate", "y", "x"],
        [1,2,3,4,5], [-3.,1.,-2.,-1.,2.], [1,4], [2,5], [-1.,-3.]; domain,sense,scale,offset)
end
function oracle(model)
    n = QUBOTools.dimension(model)
    @assert n <= 8
    values = QUBOTools.domain(model) === QUBOTools.BoolDomain ? (0,1) : (-1,1)
    energies = [QUBOTools.value(model, collect(x)) for x in Iterators.product(fill(values,n)...)]
    QUBOTools.sense(model) === QUBOTools.Min ? minimum(energies) : maximum(energies)
end
component_solve(model; executor=QD.SequentialComponentExecutor(), kwargs...) =
    solve_model(model; strategy=:components, component_executor=executor, kwargs...)

@testset "Frozen component inputs, equivalence and original objective" begin
    for domain in (:bool,:spin), sense in (:min,:max), scale in (2.,-2.,0.)
        model = disconnected_fixture(; domain,sense,scale)
        serial_jobs = QD.ComponentJob[]
        factory = job -> (push!(serial_jobs,job); FixtureChild())
        serial = component_solve(model; child=factory, seed=2^31-2)
        executor = ShuffledExecutor()
        parallel = component_solve(model; executor, seed=2^31-2)
        @test MOI.get(serial,MOI.TerminationStatus()) == MOI.OPTIMAL
        @test MOI.get(parallel,MOI.TerminationStatus()) == MOI.OPTIMAL
        @test QUBOTools.state(serial,1) == QUBOTools.state(parallel,1)
        @test QUBOTools.value(parallel,1) == oracle(model)
        @test QUBOTools.value(model,QUBOTools.state(parallel,1)) == QUBOTools.value(parallel,1)
        @test decomposition(parallel)["components"] == [[1,2],[3],[4,5]]
        @test decomposition(parallel)["parent_processing_sec"] === nothing
        if scale != 0
            @test decomposition(parallel)["separable_proof"]
            @test executor.completed[1:2] == [2,1]
            @test decomposition(parallel)["execution"]["commit_order"] == [1,2,3]
            @test [j.seed for j in serial_jobs] == [2^31-2,0,1]
            @test [j.problem for j in serial_jobs] == [j.problem for j in executor.jobs]
            @test [j.candidate_limit for j in serial_jobs] == [j.candidate_limit for j in executor.jobs] == fill(99999,3)
            @test [j.reference for j in serial_jobs] == [j.reference for j in executor.jobs]
            @test [j.labels for j in serial_jobs] == [j.labels for j in executor.jobs]
            @test all(j.id[2] == 1 for j in executor.jobs)
            @test all(j.id[1] == executor.jobs[1].id[1] for j in executor.jobs)
            @test [j.indices for j in executor.jobs] == [(1,2),(3,),(4,5)]
            @test decomposition(parallel)["execution"]["max_observed_inflight"] == 2
            @test decomposition(parallel)["attempted_calls"] == 3
        else
            @test isempty(executor.jobs)
        end
    end
    # Default retains the whole-model shortcut; either explicit executor bypasses it.
    model = disconnected_fixture()
    @test length(decomposition(solve_model(model; strategy=:components))["calls"]) == 1
    @test length(decomposition(component_solve(model; budget=8))["calls"]) == 3
    # A frozen stale complement would lose the first independently improving block.
    model = QUBOTools.Model{Symbol,Float64,Int}([:first,:second], [1,2], [-2.,-3.], Int[],Int[],Float64[])
    opt = component_solve(model; executor=ShuffledExecutor())
    @test QUBOTools.state(opt,1) == [1,1]
    @test QUBOTools.value(opt,1) == -5.
    @test decomposition(opt)["accepted_improvements"] == 2
end

@testset "Configuration and constant cases" begin
    for strategy in (:whole_model,:separator,:frozen_batch,:components_then_sweeps)
        opt = solve_model(disconnected_fixture(); strategy, component_executor=QD.SequentialComponentExecutor())
        @test MOI.get(opt,MOI.TerminationStatus()) == MOI.INVALID_OPTION
        @test decomposition(opt)["attempted_calls"] == 0
    end
    for kwargs in ((;selection=:bfs),(;selection=:partition,partition_plan=[[1,2],[3],[4,5]]),(;separator=[1]))
        opt = component_solve(disconnected_fixture(); kwargs...)
        @test MOI.get(opt,MOI.TerminationStatus()) == MOI.INVALID_OPTION
        @test decomposition(opt)["attempted_calls"] == 0
    end
    opt = component_solve(disconnected_fixture(); budget=1)
    @test MOI.get(opt,MOI.TerminationStatus()) == MOI.INVALID_OPTION
    @test decomposition(opt)["attempted_calls"] == 0
    for labels in (Symbol[],[:a,:b])
        model = QUBOTools.Model{Symbol,Float64,Int}(labels, Int[],Float64[],Int[],Int[],Float64[]; offset=9.,scale=-2.)
        opt = component_solve(model)
        @test MOI.get(opt,MOI.TerminationStatus()) == MOI.OPTIMAL
        @test QUBOTools.value(opt,1) == -18.
        @test decomposition(opt)["attempted_calls"] == 0
    end
    @test_throws ArgumentError QD.ProcessComponentExecutor(WorkerPool(Int[]))
    @test_throws ArgumentError QD.Optimizer(component_executor=:threads)
end

@testset "Caps, complete scans and truthful certificates" begin
    model = disconnected_fixture()
    for executor in (QD.SequentialComponentExecutor(),ShuffledExecutor())
        opt = component_solve(model; executor, max_child_calls=3, max_candidate_evaluations=4)
        @test MOI.get(opt,MOI.TerminationStatus()) == MOI.OPTIMAL
        @test decomposition(opt)["candidate_evaluations"] == 4
    end
    for cap in (0,1,2)
        opt = component_solve(model; max_child_calls=cap)
        @test MOI.get(opt,MOI.TerminationStatus()) == MOI.ITERATION_LIMIT
        @test decomposition(opt)["attempted_calls"] == cap
        @test !decomposition(opt)["separable_proof"]
    end
    for cap in (0,1,2,3)
        # ShuffledExecutor requires two concurrent jobs for its handshake.
        opt = component_solve(model; max_candidate_evaluations=cap)
        @test MOI.get(opt,MOI.TerminationStatus()) == MOI.ITERATION_LIMIT
        @test decomposition(opt)["candidate_evaluations"] == cap
        @test !decomposition(opt)["separable_proof"]
    end
    opt = component_solve(model; child=()->FixtureChild(status=MOI.LOCALLY_SOLVED))
    @test MOI.get(opt,MOI.TerminationStatus()) == MOI.LOCALLY_SOLVED
    @test !decomposition(opt)["separable_proof"]
    opt = component_solve(model; child=()->QUBODrivers.ExactSampler.Optimizer(), budget=2)
    @test MOI.get(opt,MOI.TerminationStatus()) == EXACT_SAMPLER_STATUS
    @test decomposition(opt)["separable_proof"] == EXACT_SAMPLER_CERTIFIED
    # More rows than the remaining scan allowance: no partially scanned commit.
    opt = component_solve(model; child=()->FixtureChild(rows=[[1,1],[0,0]]), max_candidate_evaluations=2)
    @test MOI.get(opt,MOI.TerminationStatus()) == MOI.ITERATION_LIMIT
    @test decomposition(opt)["completed_calls"] == 0
    @test QUBOTools.state(opt,1) == zeros(Int,5)
end

@testset "Protocol rejection, interruption and cancellation" begin
    model = disconnected_fixture()
    for transform in (
        r -> QD.ComponentResult((r.id[1]+1,r.id[2],r.id[3]),r.status,r.reported_results,r.rows,r.diagnostics),
        r -> QD.ComponentResult((r.id[1],r.id[2]+1,r.id[3]),r.status,r.reported_results,r.rows,r.diagnostics),
        r -> QD.ComponentResult((r.id[1],r.id[2],1),r.status,r.reported_results,r.rows,r.diagnostics),
        r -> QD.ComponentResult(r.id,r.status,r.reported_results,(),r.diagnostics),
        r -> QD.ComponentResult(r.id,r.status,r.reported_results,r.rows,(;execution_sec=-1.)),
        r -> :malformed)
        executor = ShuffledExecutor(;transform)
        opt = component_solve(model; executor)
        @test MOI.get(opt,MOI.TerminationStatus()) == MOI.OTHER_ERROR
        @test decomposition(opt)["attempted_calls"] == 2
        @test !decomposition(opt)["separable_proof"]
        @test all(c["job_state"] in ("drained_uncommitted","failed_or_unknown") for c in decomposition(opt)["calls"])
    end
    factory = job -> FixtureChild(status=job.id[3]==2 ? MOI.INTERRUPTED : MOI.OPTIMAL)
    opt = component_solve(model; executor=ShuffledExecutor(),child=factory)
    @test MOI.get(opt,MOI.TerminationStatus()) == MOI.INTERRUPTED
    @test decomposition(opt)["attempted_calls"] == 2
    @test decomposition(opt)["completed_calls"] == 2
    @test decomposition(opt)["execution"]["commit_order"] == [1,2]
    @test QUBOTools.state(opt,1)[3] == 1
    @test QUBOTools.value(opt,1) < QUBOTools.value(model,zeros(Int,5))
    @test !decomposition(opt)["separable_proof"]
    for child in (()->FixtureChild(rows=Any[],status=MOI.INTERRUPTED), ()->FixtureChild(rows=[[2,0]]),
        ()->FixtureChild(rows=[[1,0]],values=[NaN]), ()->FixtureChild(corrupt_map=true),
        ()->FixtureChild(callback=_ -> error("worker fixture failed")), ()->FixtureChild(status=MOI.OTHER_ERROR))
        opt = component_solve(model;child)
        @test MOI.get(opt,MOI.TerminationStatus()) in (MOI.INTERRUPTED,MOI.OTHER_ERROR)
        @test decomposition(opt)["attempted_calls"] == 1
        @test !decomposition(opt)["separable_proof"]
    end
    opt = QD.Optimizer(child_optimizer=()->FixtureChild(),max_variables=2,strategy=:components,
        component_executor=QD.SequentialComponentExecutor())
    QUBODrivers.set_model!(opt,model)
    MOI.set(opt,MOI.TimeLimitSec(),0.)
    MOI.optimize!(opt)
    @test MOI.get(opt,MOI.TerminationStatus()) == MOI.TIME_LIMIT
    @test decomposition(opt)["attempted_calls"] == 0
    # Coordinator cancellation after dispatch: outstanding results drain and never commit.
    opt = QD.Optimizer(child_optimizer=()->FixtureChild(),max_variables=2,strategy=:components,component_executor=ShuffledExecutor())
    QUBODrivers.set_model!(opt,model)
    opt.checkpoint = phase -> phase === :component_poll && opt.invocation > 0 &&
        length(opt.options[:component_executor].jobs)==2 ? throw(InterruptException()) : nothing
    MOI.optimize!(opt)
    @test MOI.get(opt,MOI.TerminationStatus()) == MOI.INTERRUPTED
    @test decomposition(opt)["completed_calls"] == 0
    @test all(c["job_state"] == "drained_uncommitted" for c in decomposition(opt)["calls"])
    @test QUBOTools.state(opt,1) == zeros(Int,5)
    # Explicit duplicate rejection on the same current invocation identity.
    job = first(opt.options[:component_executor].jobs)
    result = QD.execute_component(()->FixtureChild(),job)
    seen = Set{Tuple{UInt128,Int,Int}}()
    QD.validate_component_envelope(result,job,seen)
    @test_throws ErrorException QD.validate_component_envelope(result,job,seen)
end

@testset "Fixed-variable reconstruction in the component pipeline" begin
    for domain in (:bool,:spin), sense in (:min,:max), scale in (2.,-2.)
        source = MOI.Utilities.UniversalFallback(MOI.Utilities.Model{Float64}())
        vars = MOI.add_variables(source,6)
        for v in vars
            MOI.add_constraint(source,v,domain===:bool ? MOI.ZeroOne() : QUBODrivers.Spin())
        end
        fixed_value = domain===:bool ? 1 : -1
        MOI.add_constraint(source,vars[2],MOI.EqualTo(Float64(fixed_value)))
        coefficients = [-3.,2.,-1.,1.,-2.,-4.]
        f = MOI.ScalarQuadraticFunction([
            MOI.ScalarQuadraticTerm(scale*4.,vars[1],vars[2]),
            MOI.ScalarQuadraticTerm(scale*(-2.),vars[2],vars[3]),
            MOI.ScalarQuadraticTerm(scale*(-3.),vars[4],vars[5])],
            [MOI.ScalarAffineTerm(scale*c,vars[i]) for (i,c) in enumerate(coefficients)],scale*7.)
        MOI.set(source,MOI.ObjectiveFunction{typeof(f)}(),f)
        MOI.set(source,MOI.ObjectiveSense(),sense===:min ? MOI.MIN_SENSE : MOI.MAX_SENSE)
        scalar(x)=scale*(7+sum(coefficients[i]*x[i] for i in 1:6)+4x[1]*x[2]-2x[2]*x[3]-3x[4]*x[5])
        energies=[scalar(x) for x in Iterators.product(fill(domain===:bool ? (0,1) : (-1,1),6)...) if x[2]==fixed_value]
        for executor in (QD.SequentialComponentExecutor(),ShuffledExecutor())
            opt=QD.Optimizer(child_optimizer=()->FixtureChild(),max_variables=2,strategy=:components,component_executor=executor)
            map=MOI.copy_to(opt,source)
            MOI.optimize!(opt)
            @test MOI.get(opt,MOI.TerminationStatus()) == MOI.OPTIMAL
            state=[MOI.get(opt,MOI.VariablePrimal(),map[v]) for v in vars]
            @test state[2] == fixed_value
            @test scalar(state) == MOI.get(opt,MOI.ObjectiveValue()) == (sense===:min ? minimum(energies) : maximum(energies))
            @test decomposition(opt)["dimension"] == 5
            @test decomposition(opt)["components"] == [[1],[2],[3,4],[5]]
        end
    end
end

@testset "Deadline stops, partial interruption, limits and ties" begin
    model = disconnected_fixture()
    for phase in (:after_child,:reconstruct,:before_commit)
        opt=QD.Optimizer(child_optimizer=()->FixtureChild(status=MOI.INTERRUPTED),max_variables=2,
            strategy=:components,component_executor=QD.SequentialComponentExecutor())
        QUBODrivers.set_model!(opt,model)
        now=Ref(QD.monotonic_seconds())
        opt.clock=()->now[]
        MOI.set(opt,MOI.TimeLimitSec(),1000.)
        opt.checkpoint=p->(p===phase ? (now[]+=2000.) : nothing)
        MOI.optimize!(opt)
        @test MOI.get(opt,MOI.TerminationStatus()) == MOI.TIME_LIMIT
        @test QUBOTools.state(opt,1) == zeros(Int,5)
        @test decomposition(opt)["completed_calls"] == 0
        @test !decomposition(opt)["separable_proof"]
    end
    executor=ShuffledExecutor()
    opt=QD.Optimizer(child_optimizer=()->FixtureChild(),max_variables=2,strategy=:components,component_executor=executor)
    QUBODrivers.set_model!(opt,model)
    now=Ref(QD.monotonic_seconds())
    opt.clock=()->now[]
    MOI.set(opt,MOI.TimeLimitSec(),1000.)
    opt.checkpoint=p->(p===:component_poll && length(executor.jobs)==2 ? (now[]+=2000.) : nothing)
    MOI.optimize!(opt)
    @test MOI.get(opt,MOI.TerminationStatus()) == MOI.TIME_LIMIT
    @test decomposition(opt)["attempted_calls"] == 2
    @test decomposition(opt)["completed_calls"] == 0
    @test all(c["job_state"]=="drained_uncommitted" for c in decomposition(opt)["calls"])
    @test !decomposition(opt)["separable_proof"]
    for cap in (2,3)
        opt=component_solve(model;child=()->FixtureChild(rows=[[1,0],[1,1]],status=MOI.INTERRUPTED),max_candidate_evaluations=cap)
        @test MOI.get(opt,MOI.TerminationStatus()) == (cap==2 ? MOI.ITERATION_LIMIT : MOI.INTERRUPTED)
        @test decomposition(opt)["candidate_evaluations"] == cap
        @test decomposition(opt)["completed_calls"] == (cap==2 ? 0 : 1)
        @test QUBOTools.state(opt,1) == (cap==2 ? zeros(Int,5) : [1,0,0,0,0])
    end
    for status in (MOI.TIME_LIMIT,MOI.ITERATION_LIMIT,MOI.ALMOST_OPTIMAL,MOI.LOCALLY_SOLVED)
        opt=component_solve(model;child=()->FixtureChild(;status))
        @test MOI.get(opt,MOI.TerminationStatus()) == MOI.LOCALLY_SOLVED
        @test !decomposition(opt)["separable_proof"]
    end
    opt=component_solve(model;child=()->FixtureChild(limit=7.),child_time_limit_sec=3.,seed=29)
    @test all(c["effective_time_limit_sec"]==3. && c["seed_supported"] for c in decomposition(opt)["calls"])
    opt=component_solve(model;child=()->FixtureChild(seed_supported=false,time_supported=false),child_time_limit_sec=3.,seed=29)
    @test all(!c["seed_supported"] && !c["time_limit_supported"] for c in decomposition(opt)["calls"])
    # Two tied improving rows: order does not change the chosen component state.
    tied=QUBOTools.Model{Int,Float64,Int}([1,2], [1,2], [-1.,-1.], [1], [2], [2.])
    for rows in ([[1,0],[0,1]],[[0,1],[1,0]])
        opt=component_solve(tied;child=()->FixtureChild(;rows,status=MOI.LOCALLY_SOLVED))
        @test QUBOTools.state(opt,1) == [0,1]
        @test QUBOTools.value(opt,1) == -1.
    end
end

@testset "Concurrent reservations and an incomplete later component" begin
    # Both children are dispatched before either commits. The first consumes two
    # rows, leaving only one evaluation for the second child's complete two-row
    # transaction. Keep the first improvement, reject the second's provisional
    # improvement, and never dispatch the queued third component.
    model=QUBOTools.Model{Symbol,Float64,Int}([:a,:b,:c],
        [1,2,3],[-2.,-3.,-4.],Int[],Int[],Float64[])
    executor=ShuffledExecutor()
    opt=component_solve(model;executor,child=()->FixtureChild(rows=[[1],[0]]),
        max_candidate_evaluations=4)
    @test executor.completed == [2,1]
    @test length(executor.jobs) == 2
    @test MOI.get(opt,MOI.TerminationStatus()) == MOI.ITERATION_LIMIT
    @test QUBOTools.state(opt,1) == [1,0,0]
    @test QUBOTools.value(opt,1) == -2.
    data=decomposition(opt)
    @test data["attempted_calls"] == 2 && data["completed_calls"] == 1
    @test data["candidate_evaluations"] == 4 && data["incomplete_scan"]
    @test data["component_exact"] == [true,false,false]
    @test !data["separable_proof"]
    @test data["calls"][2]["valid_results"] == 1
    @test data["calls"][2]["job_state"] == "rejected"
    @test data["execution"]["commit_order"] == [1]
end

struct StopRaceHandle
    task::Task
end
Base.isready(h::StopRaceHandle)=istaskdone(h.task)
Base.fetch(h::StopRaceHandle)=fetch(h.task)
mutable struct StopRaceExecutor <: QD.AbstractComponentExecutor
    jobs::Vector{QD.ComponentJob}
    handles::Vector{StopRaceHandle}
    first_gate::Channel{Nothing}
    second_gate::Channel{Nothing}
    released::Bool
    fail_first::Bool
end
StopRaceExecutor(;fail_first=false)=StopRaceExecutor(QD.ComponentJob[],StopRaceHandle[],Channel{Nothing}(1),Channel{Nothing}(1),false,fail_first)
QD.executor_width(::StopRaceExecutor)=3
function release_second!(e)
    if !e.released
        put!(e.second_gate,nothing)
        e.released=true
    end
end
function QD.submit_component(e::StopRaceExecutor,factory,job)
    k=job.id[3]
    push!(e.jobs,job)
    if k==2
        put!(e.first_gate,nothing)
        # Deterministically make the earlier handle ready while submitting job 2.
        while !isready(e.handles[1])
            yield()
        end
    elseif k==3
        release_second!(e)
    end
    handle=StopRaceHandle(@async begin
        k==1 && take!(e.first_gate)
        k==2 && take!(e.second_gate)
        e.fail_first && k==1 && error("first job failed")
        QD.execute_component(factory,job)
    end)
    push!(e.handles,handle)
    return handle
end

@testset "Observable earlier stop prevents queued third dispatch" begin
    for stop_kind in (:interrupted,:failed_handle,:failure_status)
        e=StopRaceExecutor(;fail_first=stop_kind===:failed_handle)
        factory=job->FixtureChild(status=job.id[3]==1 ?
            (stop_kind===:failure_status ? MOI.OTHER_ERROR : MOI.INTERRUPTED) : MOI.OPTIMAL)
        model=QUBOTools.Model{Symbol,Float64,Int}([:a,:b,:c],[1,2,3],[-2.,-3.,-4.],Int[],Int[],Float64[])
        opt=QD.Optimizer(child_optimizer=factory,max_variables=1,strategy=:components,component_executor=e)
        QUBODrivers.set_model!(opt,model)
        opt.checkpoint=phase->(phase===:component_poll && length(e.jobs)==2 ? release_second!(e) : nothing)
        MOI.optimize!(opt)
        @test length(e.jobs)==2
        @test all(isready,e.handles)
        @test !decomposition(opt)["separable_proof"]
        @test decomposition(opt)["attempted_calls"]==2
        @test MOI.get(opt,MOI.TerminationStatus())==(stop_kind===:interrupted ? MOI.INTERRUPTED : MOI.OTHER_ERROR)
    end
end

@testset "Invalid-row diagnostics distinguish failures from shared stops" begin
    model=disconnected_fixture()
    for child in (()->FixtureChild(rows=[[2,0]]),
        ()->FixtureChild(rows=[[1,0]],values=[NaN]),
        ()->FixtureChild(rows=[[1,0]],row_status=MOI.NO_SOLUTION))
        opt=component_solve(model;child)
        @test MOI.get(opt,MOI.TerminationStatus())==MOI.OTHER_ERROR
        @test only(decomposition(opt)["calls"])["invalid_results"]==1
        @test QUBOTools.state(opt,1)==zeros(Int,5)
    end
    opt=component_solve(model;child=()->FixtureChild(rows=[[1,0],[0,0]]),max_candidate_evaluations=2)
    @test MOI.get(opt,MOI.TerminationStatus())==MOI.ITERATION_LIMIT
    @test only(decomposition(opt)["calls"])["invalid_results"]==0
    opt=QD.Optimizer(child_optimizer=()->FixtureChild(),max_variables=2,
        strategy=:components,component_executor=QD.SequentialComponentExecutor())
    QUBODrivers.set_model!(opt,model)
    opt.checkpoint=phase->(phase===:reconstruct ? throw(InterruptException()) : nothing)
    MOI.optimize!(opt)
    @test MOI.get(opt,MOI.TerminationStatus())==MOI.INTERRUPTED
    @test only(decomposition(opt)["calls"])["invalid_results"]==0
end

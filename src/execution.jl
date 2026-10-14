# SPDX-License-Identifier: MPL-2.0
"""
    ComponentJob

Owned immutable input to a component child factory. `id` is `(solve_token,
invocation, component)`; `indices` and `labels` map reduced positions to original
free variables. `problem` contains immutable normalized coefficients, domain,
sense, scale and conditioned offset. `reference` is the frozen component start.
`seed`, absolute local-host monotonic `deadline`, `child_time_limit_sec`, and
`candidate_limit` are generic limits. Factories may accept this job or no arguments.
Do not transport an optimizer or a shared mutable observer in a factory closure.
"""
struct ComponentJob
    id::Tuple{UInt128,Int,Int}
    indices::Tuple
    labels::Tuple
    problem::NamedTuple
    reference::Tuple
    seed::Union{Int,Nothing}
    deadline::Union{Float64,Nothing}
    child_time_limit_sec::Union{Float64,Nothing}
    candidate_limit::Int
end

"""
    ComponentResult(id, status, reported_results, rows, diagnostics)

Owned child output. Each row is `(state=tuple, energy=reported_energy,
primal_status=MOI.FEASIBLE_POINT, multiplicity=nothing_or_count)`. The coordinator
validates the identity, complete scan and all rows, reconstructs only the owning
component and independently evaluates the full original objective. `diagnostics`
is a NamedTuple with `execution_sec` and may include executor-specific fields.
"""
struct ComponentResult
    id::Tuple{UInt128,Int,Int}
    status::MOI.TerminationStatusCode
    reported_results::Int
    rows::Tuple
    diagnostics::NamedTuple
end

"""
    AbstractComponentExecutor

Independent-component executor protocol: implement `executor_width(executor)`
and `submit_component(executor, factory, job)`. Submission returns a handle with
`isready(handle)` and `fetch(handle)` producing exactly one `ComponentResult` or
throwing an execution error. Submission must return promptly and dispatch at most
one job. Handles must remain fetchable for draining after a stop. Executors must
isolate mutable child state, preserve job identity and never retry implicitly.
"""
abstract type AbstractComponentExecutor end

"""    SequentialComponentExecutor()

Execute the same frozen component jobs locally, one at a time. Explicit selection
bypasses the whole-model shortcut, just like the process executor.
"""
struct SequentialComponentExecutor <: AbstractComponentExecutor end

"""
    ProcessComponentExecutor(pool::Distributed.WorkerPool; max_inflight=length(workers(pool)))

Use an explicitly supplied caller-owned local-host worker pool. Initialize the
package and factory definitions on each worker before solving. One optimizer is
constructed on its worker per job; no workers are created or terminated. A pool
must be dedicated to these solves (do not concurrently use the same executor or
pool). The coordinator drains submitted jobs on every exit, returning workers to
the pool; opaque child calls can overrun the cooperative deadline during draining.
"""
struct ProcessComponentExecutor <: AbstractComponentExecutor
    pool::Distributed.WorkerPool
    max_inflight::Int
    function ProcessComponentExecutor(pool::Distributed.WorkerPool;
        max_inflight=length(Distributed.workers(pool)))
        pids = Distributed.workers(pool)
        !isempty(pids) && all(pid -> pid != Distributed.myid() && pid in Distributed.workers(), pids) ||
            throw(ArgumentError("pool must contain explicitly supplied worker processes"))
        max_inflight isa Integer && !(max_inflight isa Bool) && 1 <= max_inflight <= length(pids) ||
            throw(ArgumentError("max_inflight must be in 1:length(workers(pool))"))
        new(pool, Int(max_inflight))
    end
end

"""    executor_width(executor)

Maximum number of submitted, uncommitted component jobs owned by an executor.
"""
executor_width(::SequentialComponentExecutor) = 1
executor_width(e::ProcessComponentExecutor) = e.max_inflight

struct LocalComponentHandle
    result::ComponentResult
end
Base.isready(::LocalComponentHandle) = true
Base.fetch(h::LocalComponentHandle) = h.result

"""    submit_component(executor, factory, job)

Submit one reserved component job and return a fetchable handle. Custom executors
can use the supported job context to configure allocation and attach diagnostics.
"""
submit_component(::SequentialComponentExecutor, factory, job) =
    LocalComponentHandle(execute_component(factory, job))
struct ComponentTaskHandle
    task::Task
end
Base.isready(h::ComponentTaskHandle) = istaskdone(h.task)
Base.fetch(h::ComponentTaskHandle) = fetch(h.task)

function submit_component(e::ProcessComponentExecutor, factory, job)
    # An async task owns the acquired worker until its remote result/error arrives.
    # The parent drains this task even on errors and interruption.
    return ComponentTaskHandle(@async begin
        worker = take!(e.pool)
        try
            Distributed.remotecall_fetch(execute_component, worker, factory, job)
        finally
            put!(e.pool, worker)
        end
    end)
end

const EXECUTOR_CHILDREN = WeakKeyDict{Any,Nothing}()
monotonic_seconds() = time_ns() / 1e9

"""
    execute_component(factory, job::ComponentJob) -> ComponentResult

Construct, copy, configure and execute an isolated child where called, extracting
bounded owned rows. This worker-side boundary does not accept incumbents or
certify global results. Parent deadlines are cooperative and require a shared
local-host monotonic clock; distributed hosts are outside the supported executor.
"""
function execute_component(factory, job::ComponentJob)
    copying_start = monotonic_seconds()
    expired() = job.deadline !== nothing && monotonic_seconds() >= job.deadline
    expired() && throw(StopSolve(MOI.TIME_LIMIT, "parent_time_limit"))
    child = applicable(factory, job) ? factory(job) : factory()
    child isa MOI.AbstractOptimizer || throw(UnsupportedChild("factory must return an MOI optimizer"))
    MOI.is_empty(child) || throw(UnsupportedChild("factory must return an empty optimizer"))
    haskey(EXECUTOR_CHILDREN, child) && throw(UnsupportedChild("factory reused a live child optimizer"))
    EXECUTOR_CHILDREN[child] = nothing
    problem = job.problem
    domain_set = problem.domain === QUBOTools.BoolDomain ? MOI.ZeroOne : QUBODrivers.Spin
    MOI.supports_constraint(child, VI, domain_set) &&
        MOI.supports(child, MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{Float64}}()) &&
        MOI.supports(child, MOI.ObjectiveSense()) ||
        throw(UnsupportedChild("child must support the original domain, sense and Float64 quadratic objective"))
    source, variables = child_model(problem)
    map = MOI.copy_to(child, source)
    mapped = [map[v] for v in variables]
    length(unique(mapped)) == problem.n && Set(mapped) == Set(MOI.get(child, MOI.ListOfVariableIndices())) ||
        error("inconsistent copied child index map")
    seed_supported = MOI.supports(child, QUBODrivers.RandomSeed())
    job.seed !== nothing && seed_supported && MOI.set(child, QUBODrivers.RandomSeed(), job.seed)
    time_supported = MOI.supports(child, MOI.TimeLimitSec())
    limits = Any[job.child_time_limit_sec]
    job.deadline !== nothing && push!(limits, max(0.0, job.deadline - monotonic_seconds()))
    time_supported && push!(limits, MOI.get(child, MOI.TimeLimitSec()))
    filter!(!isnothing, limits)
    all(x isa Real && !(x isa Bool) && isfinite(x) && x >= 0 for x in limits) ||
        throw(UnsupportedChild("invalid factory-configured child time limit"))
    effective_limit = isempty(limits) ? nothing : Float64(minimum(limits))
    time_supported && effective_limit !== nothing && MOI.set(child, MOI.TimeLimitSec(), effective_limit)
    expired() && throw(StopSolve(MOI.TIME_LIMIT, "parent_time_limit"))
    execution_start = monotonic_seconds()
    MOI.optimize!(child)
    execution_end = monotonic_seconds()
    status = MOI.get(child, MOI.TerminationStatus())
    count = MOI.get(child, MOI.ResultCount())
    count isa Integer && !(count isa Bool) && 0 <= count <= typemax(Int) || error("invalid child result count")
    # Transport is bounded even when an opaque child exposes enormous results.
    rows = Tuple((; state=Tuple(MOI.get(child, MOI.VariablePrimal(row), v) for v in mapped),
        energy=MOI.get(child, MOI.ObjectiveValue(row)),
        primal_status=MOI.get(child, MOI.PrimalStatus(row)),
        multiplicity=child isa QUBODrivers.AbstractSampler ? QUBOTools.reads(child, row) : nothing)
        for row in 1:min(count, job.candidate_limit))
    diagnostics = (; execution_sec=execution_end-execution_start,
        copying_sec=execution_start-copying_start, extraction_sec=monotonic_seconds()-execution_end,
        worker=Distributed.myid(), execution_start, execution_end,
        seed_supported, time_limit_supported=time_supported,
        time_limit_enforced=child isa QUBODrivers.AbstractSampler && QUBODrivers.enforces_time_limit(child),
        effective_time_limit_sec=effective_limit, source_to_child=Tuple(v.value for v in mapped))
    return ComponentResult(job.id, status, Int(count), rows, diagnostics)
end

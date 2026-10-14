# SPDX-License-Identifier: MPL-2.0
function validate_component_configuration(opt)
    if opt.options[:component_executor] === nothing
        applicable(opt.options[:child_optimizer]) ||
            throw(UnsupportedChild("serial child_optimizer must accept no arguments"))
        return nothing
    end
    opt.options[:strategy] === :components && opt.options[:selection] === :strongest_edge &&
        opt.options[:partition_plan] === nothing && opt.options[:separator] == Int[] ||
        throw(UnsupportedChild("component_executor requires strategy=:components, default selection, no partition_plan or separator"))
    width = executor_width(opt.options[:component_executor])
    width isa Integer && !(width isa Bool) && width > 0 ||
        throw(UnsupportedChild("executor_width must be a positive integer"))
    return nothing
end

function prepare_component_job(opt, ctx, snap, component, k, token)
    problem, fixed, map, delta = phase!(ctx, "conditioning") do
        check_time(opt, ctx, :conditioning)
        conditioned_problem(snap, snap.state, component)
    end
    indices = Tuple(sort!(collect(component)))
    all(map[i] == j for (j,i) in enumerate(indices)) || error("noncanonical component map")
    immutable_problem = (; n=problem.n, domain=problem.domain, sense=problem.sense,
        linear=Tuple(problem.linear), quadratic=Tuple(problem.quadratic),
        scale=problem.scale, offset=problem.offset)
    seed = opt.options[:seed]
    child_seed = seed === nothing ? nothing : Int(mod(big(seed) + k - 1, big(2)^31-1))
    job = ComponentJob((token, opt.invocation, k), indices,
        deepcopy(Tuple(snap.labels[i] for i in indices)), immutable_problem,
        Tuple(snap.state[i] for i in indices), child_seed, ctx.deadline,
        opt.options[:child_time_limit_sec], opt.options[:max_candidate_evaluations] - 1)
    call = Dict{String,Any}("attempt"=>k, "kind"=>"component", "component"=>k,
        "job_id"=>job.id, "selected_indices"=>collect(indices),
        "original_to_reduced"=>copy(map), "fixed_variable_count"=>length(fixed),
        "boundary_fixed_variables"=>Dict{Int,Int}(), "offset_delta"=>delta,
        "conditioning_incumbent_version"=>0, "seed"=>child_seed,
        "public_status"=>nothing, "valid_results"=>0, "invalid_results"=>0,
        "reported_multiplicities"=>Any[], "physical_reads"=>nothing,
        "physical_reads_meaning"=>"unknown; enumeration is not hardware reads",
        "exact"=>false, "job_state"=>"reserved",
        "phase_sec"=>Dict(k=>0.0 for k in keys(ctx.data["phase_sec"])))
    return job, call
end

function validate_component_envelope(result, job, seen)
    result isa ComponentResult || error("malformed component result envelope")
    result.id in seen && error("duplicate component result identity")
    result.id == job.id || error("stale or mismatched component result identity")
    result.reported_results >= 0 || error("invalid child result count")
    length(result.rows) == min(result.reported_results, job.candidate_limit) ||
        error("malformed component result row count")
    haskey(result.diagnostics, :execution_sec) &&
        result.diagnostics.execution_sec isa Real && isfinite(result.diagnostics.execution_sec) &&
        result.diagnostics.execution_sec >= 0 || error("invalid child execution timing")
    result.status === MOI.INTERRUPTED || result.status in ACCEPTED_CHILD_STATUSES ||
        error("failure-class child status: $(result.status)")
    result.reported_results > 0 || result.status === MOI.INTERRUPTED || error("child returned no valid results")
    push!(seen, result.id)
    return nothing
end

function commit_component!(opt, ctx, snap, job, result, call)
    check_time(opt, ctx, :after_child)
    best_state, best_energy = nothing, nothing
    for row in result.rows
        check_time(opt, ctx, :before_row)
        ctx.evaluations < opt.options[:max_candidate_evaluations] || begin
            ctx.data["incomplete_scan"] = true
            throw(StopSolve(MOI.ITERATION_LIMIT, "max_candidate_evaluations"))
        end
        candidate = phase!(ctx, "validation_reconstruction", call) do
            row isa NamedTuple && all(k -> haskey(row, k), (:state, :energy, :primal_status, :multiplicity)) ||
                error("malformed child row")
            row.primal_status === MOI.FEASIBLE_POINT || error("child row is not a feasible point")
            row.state isa Tuple && length(row.state) == length(job.indices) &&
                all(x -> valid_value(x, snap.domain), row.state) || error("invalid component assignment")
            row.energy isa Real && isfinite(row.energy) || error("child reports non-finite energy")
            row.multiplicity === nothing || (row.multiplicity isa Integer && !(row.multiplicity isa Bool) && row.multiplicity > 0) ||
                error("invalid child multiplicity")
            candidate = copy(ctx.state)
            for (i, value) in zip(job.indices, row.state)
                candidate[i] = Int(value)
            end
            return candidate
        end
        reserve_evaluation!(opt, ctx)
        energy = phase!(ctx, "full_energy", call) do
            full_energy(candidate, snap.linear, snap.quadratic, snap.scale, snap.offset)
        end
        opt.checkpoint(:reconstruct)
        check_time(opt, ctx, :after_row)
        call["valid_results"] += 1
        push!(call["reported_multiplicities"], row.multiplicity)
        if best_energy === nothing || better(energy, best_energy, snap.sense) ||
            (energy == best_energy && isless(Tuple(candidate), Tuple(best_state)))
            best_state, best_energy = candidate, energy
        end
    end
    if result.reported_results > length(result.rows)
        ctx.data["incomplete_scan"] = true
        throw(StopSolve(MOI.ITERATION_LIMIT, "max_candidate_evaluations"))
    end
    result.status === MOI.OPTIMAL && better(ctx.energy, best_energy, snap.sense) &&
        !isapprox(ctx.energy, best_energy; atol=1e-12, rtol=1e-12) &&
        error("child OPTIMAL contradicts independently evaluated incumbent")
    check_time(opt, ctx, :before_commit)
    if best_energy !== nothing && better(best_energy, ctx.energy, snap.sense)
        ctx.state, ctx.energy = best_state, best_energy
        ctx.improvements += 1
    end
    call["exact"] = result.status === MOI.OPTIMAL
    call["proposal_energy"], call["committed_energy"] = best_energy, ctx.energy
    call["accepted_to_working"] = true
    call["job_state"] = "committed"
    ctx.data["completed_calls"] += 1
    ctx.data["component_exact"][job.id[3]] = call["exact"]
    push!(ctx.data["incumbent_energy_trace"], ctx.energy)
    push!(ctx.data["execution"]["commit_order"], job.id[3])
    result.status === MOI.INTERRUPTED && throw(StopSolve(MOI.INTERRUPTED, "child_interrupted"))
    return nothing
end

function record_component_result!(ctx, call, result)
    call["public_status"] = string(result.status)
    call["reported_results"] = result.reported_results
    call["executor_diagnostics"] = result.diagnostics
    for key in (:seed_supported, :time_limit_supported, :time_limit_enforced,
        :effective_time_limit_sec, :source_to_child)
        haskey(result.diagnostics, key) && (call[String(key)] = getproperty(result.diagnostics, key))
    end
    call["phase_sec"]["execution"] = result.diagnostics.execution_sec
    ctx.data["child_execution_sec"] += result.diagnostics.execution_sec
    return nothing
end

function component_execution!(opt, ctx, snap)
    executor = opt.options[:component_executor]
    components = phase!(ctx, "preparation") do
        _, components = interaction_graph(snap; checkpoint=()->check_time(opt, ctx, :graph))
        components
    end
    data = ctx.data
    data["components"] = deepcopy(components)
    data["component_exact"] = falses(length(components))
    all(c -> length(c) <= opt.options[:max_variables], components) ||
        throw(UnsupportedChild("component exceeds max_variables in component_executor mode"))
    # Capacity and strategy validation precede constant/empty short circuits.
    if snap.constant
        opt.termination = MOI.OPTIMAL
        data["stop_reason"] = "constant_objective"
        return nothing
    end
    width = min(executor_width(executor), length(components))
    token = rand(Random.RandomDevice(), UInt128)
    data["execution"] = Dict{String,Any}("width"=>width, "max_observed_inflight"=>0,
        "wait_sec"=>0.0, "drain_sec"=>0.0, "dispatch_stopped"=>false,
        "result_order"=>Int[], "commit_order"=>Int[])
    pending = Dict{Int,Any}()
    seen = Set{Tuple{UInt128,Int,Int}}()
    next_dispatch, next_commit = 1, 1
    stop_at = nothing
    try
        while next_commit <= length(components)
            check_time(opt, ctx, :component_poll)
            # Observe every ready result before refilling; interrupted/failing jobs
            # stop queued dispatch regardless of their completion order.
            for k in sort!(collect(keys(pending)))
                entry = pending[k]
                entry.result !== nothing && continue
                isready(entry.handle) || continue
                result = fetch(entry.handle)
                validate_component_envelope(result, entry.job, seen)
                record_component_result!(ctx, entry.call, result)
                entry.call["job_state"] = "returned"
                pending[k] = (; entry..., result)
                push!(data["execution"]["result_order"], k)
                if result.status === MOI.INTERRUPTED
                    stop_at = stop_at === nothing ? k : min(stop_at, k)
                    data["execution"]["dispatch_stopped"] = true
                end
            end
            # Commit only the stable prefix. An incomplete row scan is atomic:
            # no provisional candidate is accepted.
            if haskey(pending, next_commit) && pending[next_commit].result !== nothing
                entry = pop!(pending, next_commit)
                try
                    commit_component!(opt, ctx, snap, entry.job, entry.result, entry.call)
                catch err
                    entry.call["job_state"] = entry.call["job_state"] == "committed" ? "committed" : "rejected"
                    entry.call["diagnostic"] = sprint(showerror, err)
                    rethrow()
                end
                next_commit += 1
                continue
            end
            while stop_at === nothing && next_dispatch <= length(components) && length(pending) < width
                check_time(opt, ctx, :before_component_dispatch)
                # Minimum candidate reservation for all outstanding jobs. A child
                # can expose extra rows, which still consume the shared scan cap.
                data["attempted_calls"] < opt.options[:max_child_calls] || break
                ctx.evaluations + length(pending) < opt.options[:max_candidate_evaluations] || break
                k = next_dispatch
                job, call = prepare_component_job(opt, ctx, snap, components[k], k, token)
                check_time(opt, ctx, :dispatch)
                push!(data["calls"], call)
                data["attempted_calls"] += 1
                handle = try
                    submit_component(executor, opt.options[:child_optimizer], job)
                catch err
                    call["job_state"] = "failed_or_unknown"
                    call["diagnostic"] = sprint(showerror, err)
                    rethrow()
                end
                call["job_state"] = "dispatched"
                pending[k] = (; job, call, handle, result=nothing)
                next_dispatch += 1
                data["execution"]["max_observed_inflight"] = max(data["execution"]["max_observed_inflight"], length(pending))
                # Synchronous/local completion must be inspected before dispatching
                # again. Async submissions yield so their work can actually start.
                yield()
                isready(handle) && break
            end
            if isempty(pending)
                check_work(opt, ctx, :component_capacity)
                error("component executor made no progress")
            end
            wait_start = monotonic_seconds()
            sleep(0.001) # bounded cooperative polling, not a timing/speedup assertion
            data["execution"]["wait_sec"] += monotonic_seconds() - wait_start
        end
        if all(data["component_exact"])
            data["separable_proof"] = true
            data["stop_reason"] = "components_complete"
            opt.termination = MOI.OPTIMAL
        else
            check_work(opt, ctx, :heuristic_completion)
            data["stop_reason"] = "components_heuristic_complete"
            opt.termination = MOI.LOCALLY_SOLVED
        end
    finally
        data["execution"]["dispatch_stopped"] = true
        drain_start = monotonic_seconds()
        # Never kill caller workers or pretend cancellation unspent reservations.
        # No acceptance occurs here, including for a late valid improvement.
        for k in sort!(collect(keys(pending)))
            entry = pending[k]
            try
                result = entry.result === nothing ? fetch(entry.handle) : entry.result
                if entry.result === nothing
                    validate_component_envelope(result, entry.job, seen)
                    record_component_result!(ctx, entry.call, result)
                end
                entry.call["job_state"] = "drained_uncommitted"
            catch err
                entry.call["job_state"] = "failed_or_unknown"
                entry.call["diagnostic"] = sprint(showerror, err)
            end
        end
        data["execution"]["drain_sec"] = monotonic_seconds() - drain_start
        ctx.deadline !== nothing && (data["parent_overrun_sec"] = max(0.0, opt.clock() - ctx.deadline))
    end
    return nothing
end

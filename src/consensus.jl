# SPDX-License-Identifier: MPL-2.0
function validate_consensus_configuration(opt)
    opt.options[:strategy] === :consensus || return nothing
    opt.options[:consensus_plan] !== nothing ||
        throw(UnsupportedChild("consensus requires an explicit consensus_plan"))
    opt.options[:component_executor] === nothing && opt.options[:selection] === :strongest_edge &&
        opt.options[:partition_plan] === nothing && opt.options[:separator] == Int[] &&
        !opt.options[:separator_pruning] ||
        throw(UnsupportedChild("consensus supports only serial execution, default selection, no partition_plan, separator or pruning"))
    return nothing
end

function consensus_plan(opt, ctx, snap, cert)
    check() = check_time(opt, ctx, :consensus_plan)
    blocks = Vector{Int}[]
    for raw in opt.options[:consensus_plan]
        check()
        !isempty(raw) && length(raw) <= opt.options[:max_variables] &&
            length(unique(raw)) == length(raw) && all(i -> 1 <= i <= snap.n, raw) ||
            throw(UnsupportedChild("consensus blocks must be nonempty, unique, in range and fit max_variables"))
        push!(blocks, sort(copy(raw)))
    end
    occurrences = [Tuple{Int,Int}[] for _ in 1:snap.n]
    for (p, block) in enumerate(blocks), (j, i) in enumerate(block)
        check()
        push!(occurrences[i], (p,j))
    end
    all(!isempty, occurrences) || throw(UnsupportedChild("consensus must cover all free indices, including isolates"))
    # The empty original domain has one empty assignment and no copied blocks.
    snap.n == 0 && !isempty(blocks) && throw(UnsupportedChild("empty model requires an empty plan"))
    linear = [zeros(Rational{BigInt}, length(b)) for b in blocks]
    quadratic = [Pair{Tuple{Int,Int},Rational{BigInt}}[] for _ in blocks]
    linear_owners = zeros(Int, snap.n)
    for i in 1:snap.n
        check()
        p,j = first(occurrences[i])
        linear[p][j] = cert.linear[i]
        linear_owners[i] = p
    end
    quadratic_owners = Int[]
    for ((i,j), c) in snap.quadratic
        check()
        iszero(c) && continue
        p = findfirst(b -> i in b && j in b, blocks)
        p === nothing && throw(UnsupportedChild("every nonzero interaction needs a containing consensus block"))
        a, b = findfirst(==(i), blocks[p]), findfirst(==(j), blocks[p])
        # Normalize from stored inputs, rather than multiplying Float64 first.
        factor = (snap.sense === QUBOTools.Min ? 1 : -1) * Rational{BigInt}(snap.scale)
        push!(quadratic[p], (a,b) => factor * Rational{BigInt}(c))
        push!(quadratic_owners, p)
    end
    equalities = Tuple{Int,Int,Int,Int}[]
    for copies in occurrences
        check()
        isempty(copies) && continue
        rp,rj = first(copies)
        for (p,j) in Iterators.drop(copies,1)
            check()
            push!(equalities, (p,j,rp,rj))
        end
    end
    check()
    return (; blocks, occurrences, linear, quadratic, equalities, linear_owners, quadratic_owners)
end

function consensus_surrogates(opt, ctx, snap, plan, multipliers)
    return phase!(ctx, "coordination") do
        linear = deepcopy(plan.linear)
        for ((p,j,rp,rj), lambda) in zip(plan.equalities, multipliers)
            check_time(opt, ctx, :consensus_surrogate)
            isfinite(lambda) || error("non-finite stored consensus multiplier")
            exact = Rational{BigInt}(lambda)
            linear[p][j] += exact
            linear[rp][rj] -= exact
        end
        problems = Any[]
        residuals = Rational{BigInt}[]
        faithful = Bool[]
        for p in eachindex(plan.blocks)
            check_time(opt, ctx, :consensus_surrogate)
            l = Pair{Int,Float64}[]
            q = Pair{Tuple{Int,Int},Float64}[]
            residual = big(0)//1
            preserved = true
            for (i,c) in enumerate(linear[p])
                check_time(opt, ctx, :consensus_surrogate)
                rounded = Float64(c)
                isfinite(rounded) || error("non-finite dispatched consensus coefficient")
                push!(l, i=>rounded)
                delta = c - Rational{BigInt}(rounded)
                residual += snap.domain === QUBOTools.BoolDomain ? min(0,delta) : -abs(delta)
                preserved &= iszero(delta)
            end
            for (ij,c) in plan.quadratic[p]
                check_time(opt, ctx, :consensus_surrogate)
                rounded = Float64(c)
                isfinite(rounded) || error("non-finite dispatched consensus coefficient")
                push!(q, ij=>rounded)
                delta = c - Rational{BigInt}(rounded)
                residual += snap.domain === QUBOTools.BoolDomain ? min(0,delta) : -abs(delta)
                preserved &= iszero(delta)
            end
            push!(problems, (; n=length(plan.blocks[p]), domain=snap.domain,
                sense=QUBOTools.Min, linear=l, quadratic=q, scale=1.0, offset=0.0))
            push!(residuals, residual)
            push!(faithful, preserved)
        end
        return problems, residuals, faithful
    end
end

function consensus_dispatched_energy(opt, ctx, problem, state)
    # Independently evaluate the actual Float64 coefficients as exact rationals;
    # returned ObjectiveValue is validated for finiteness but never used as a bound.
    value = big(0)//1
    for (i,c) in problem.linear
        check_time(opt, ctx, :consensus_block_energy)
        value += Rational{BigInt}(c) * state[i]
    end
    for ((i,j),c) in problem.quadratic
        check_time(opt, ctx, :consensus_block_energy)
        value += Rational{BigInt}(c) * state[i] * state[j]
    end
    return value
end

function consensus_child!(opt, ctx, problem, selected, iteration, block)
    check_work(opt, ctx, :consensus_before_factory)
    attempt = ctx.data["attempted_calls"] + 1
    call = Dict{String,Any}("attempt"=>attempt, "kind"=>"consensus_block",
        "iteration"=>iteration, "block"=>block, "selected_indices"=>copy(selected),
        "original_to_reduced"=>Dict(i=>j for (j,i) in enumerate(selected)),
        "phase_sec"=>Dict(k=>0.0 for k in keys(ctx.data["phase_sec"])),
        "public_status"=>nothing, "valid_results"=>0, "invalid_results"=>0,
        "seed"=>nothing, "exact"=>false, "certificate_available"=>false,
        "physical_reads"=>nothing, "physical_reads_meaning"=>"unknown; enumeration is not hardware reads")
    push!(ctx.data["calls"], call)
    ctx.data["attempted_calls"] = attempt
    child, mapped = copy_child!(opt, ctx, problem, call)
    check_time(opt, ctx, :dispatch)
    phase!(ctx, "execution", call) do
        MOI.optimize!(child)
    end
    status = MOI.get(child, MOI.TerminationStatus())
    call["public_status"] = string(status)
    status === MOI.INTERRUPTED || status in ACCEPTED_CHILD_STATUSES || error("failure-class child status: $status")
    count = MOI.get(child, MOI.ResultCount())
    count isa Integer && !(count isa Bool) && count >= 0 || error("invalid child result count")
    call["reported_results"] = count
    check_time(opt, ctx, :after_child)
    best, value = nothing, nothing
    for row in 1:count
        check_time(opt, ctx, :before_row)
        reserve_evaluation!(opt, ctx)
        state, energy = phase!(ctx, "validation_reconstruction", call) do
            MOI.get(child, MOI.PrimalStatus(row)) === MOI.FEASIBLE_POINT || error("infeasible consensus row")
            raw = [MOI.get(child, MOI.VariablePrimal(row), v) for v in mapped]
            all(x -> valid_value(x, problem.domain), raw) || error("invalid consensus copy values")
            reported = MOI.get(child, MOI.ObjectiveValue(row))
            reported isa Real && isfinite(reported) || error("non-finite consensus child energy")
            state = Int.(raw)
            return state, consensus_dispatched_energy(opt, ctx, problem, state)
        end
        check_time(opt, ctx, :after_row)
        call["valid_results"] += 1
        if value === nothing || energy < value || (energy == value && isless(Tuple(state), Tuple(best)))
            best, value = state, energy
        end
    end
    status === MOI.INTERRUPTED && throw(StopSolve(MOI.INTERRUPTED, "child_interrupted"))
    best !== nothing || error("child returned no valid consensus results")
    check_time(opt, ctx, :consensus_block_commit)
    call["exact"] = status === MOI.OPTIMAL
    call["surrogate_energy_without_constant"] = value
    ctx.data["completed_calls"] += 1
    return best, value, status, call
end

function consensus_update(opt, ctx, multipliers, disagreement, iteration)
    return phase!(ctx, "coordination") do
        step = Float64(opt.options[:consensus_step]) / sqrt(Float64(iteration))
        limit = Float64(opt.options[:consensus_multiplier_limit])
        next = copy(multipliers)
        for i in eachindex(next)
            check_time(opt, ctx, :consensus_update)
            # Reject overflow before projection; clamping Inf would conceal it.
            proposal = multipliers[i] + step * disagreement[i]
            isfinite(proposal) || throw(StopSolve(MOI.NORM_LIMIT, "nonfinite_consensus_update"))
            next[i] = clamp(proposal, -limit, limit)
        end
        check_time(opt, ctx, :consensus_update_complete)
        return next
    end
end

function consensus_decomposition!(opt, ctx, snap)
    data = Dict{String,Any}("started_iterations"=>0, "completed_iterations"=>0,
        "history"=>Any[], "history_dropped"=>0, "best_lower_bound"=>nothing,
        "best_bound_iteration"=>nothing, "incumbent_normalized"=>nothing,
        "absolute_gap"=>nothing, "stagnation"=>0,
        "certificate_method"=>"exact_rational_dispatch_residual_v1")
    ctx.data["consensus"] = data
    ctx.data["phase_sec"]["bound"] = 0.0
    ctx.data["phase_sec"]["coordination"] = 0.0
    cert = prepare_pruning(opt, ctx, snap)
    cert === nothing && error("finite original coefficients required for consensus")
    plan = phase!(ctx, "preparation") do
        consensus_plan(opt, ctx, snap, cert)
    end
    data["blocks"] = deepcopy(plan.blocks)
    data["linear_owners"] = plan.linear_owners
    data["quadratic_owners"] = plan.quadratic_owners
    data["equalities"] = plan.equalities
    upper = pruning_energy(opt, ctx, cert, ctx.state)
    data["incumbent_normalized"] = upper
    if snap.constant
        data["best_lower_bound"] = cert.constant
        data["absolute_gap"] = big(0)//1
        opt.termination = MOI.OPTIMAL
        ctx.data["stop_reason"] = "constant_objective"
        return nothing
    end
    multipliers = zeros(Float64, length(plan.equalities))
    for iteration in 1:opt.options[:consensus_iterations]
        check_work(opt, ctx, :consensus_iteration)
        data["started_iterations"] += 1
        problems, residuals, faithful = consensus_surrogates(opt, ctx, snap, plan, multipliers)
        copies = Vector{Int}[]
        lower = cert.constant
        certified = true
        calls = Any[]
        for p in eachindex(plan.blocks)
            state, value, status, call = consensus_child!(opt, ctx, problems[p], plan.blocks[p], iteration, p)
            push!(copies, state)
            push!(calls, call)
            certified &= status === MOI.OPTIMAL
            lower += value + residuals[p]
        end
        candidate, disagreement = phase!(ctx, "coordination") do
            check_time(opt, ctx, :consensus_reconcile)
            candidate = Int[]
            for occurrences in plan.occurrences
                check_time(opt, ctx, :consensus_reconcile)
                p,j = first(occurrences)
                push!(candidate, copies[p][j])
            end
            disagreement = Int[]
            for (p,j,rp,rj) in plan.equalities
                check_time(opt, ctx, :consensus_reconcile)
                push!(disagreement, copies[p][j] - copies[rp][rj])
            end
            return candidate, disagreement
        end
        reserve_evaluation!(opt, ctx)
        energy = phase!(ctx, "full_energy") do
            full_energy(candidate, snap.linear, snap.quadratic, snap.scale, snap.offset)
        end
        exact = pruning_energy(opt, ctx, cert, candidate)
        certified && lower > min(upper, exact) && error("consensus certificate contradicts original incumbent")
        data["best_lower_bound"] !== nothing && data["best_lower_bound"] > min(upper,exact) &&
            error("previous consensus certificate contradicts original incumbent")
        check_time(opt, ctx, :consensus_iteration_commit)
        improved = exact < upper
        bound_improved = certified && (data["best_lower_bound"] === nothing || lower > data["best_lower_bound"])
        if improved
            upper = exact
            ctx.state, ctx.energy = candidate, energy
            ctx.improvements += 1
        end
        if bound_improved
            data["best_lower_bound"] = lower
            data["best_bound_iteration"] = iteration
        end
        data["incumbent_normalized"] = upper
        data["absolute_gap"] = data["best_lower_bound"] === nothing ? nothing : upper - data["best_lower_bound"]
        for (p, call) in enumerate(calls)
            call["certificate_available"] = certified
            call["transfer_preserved"] = faithful[p]
            call["residual_lower_bound"] = residuals[p]
        end
        history = Dict{String,Any}("iteration"=>iteration, "multipliers"=>copy(multipliers),
            "copy_solutions"=>copies, "disagreement"=>disagreement,
            "lower_bound"=>certified ? lower : nothing,
            "supergradient_certified"=>certified && all(faithful),
            "candidate"=>candidate, "candidate_energy"=>energy, "candidate_normalized"=>exact)
        length(data["history"]) == opt.options[:consensus_history_limit] && begin
            popfirst!(data["history"])
            data["history_dropped"] += 1
        end
        push!(data["history"], history)
        push!(ctx.data["incumbent_energy_trace"], ctx.energy)
        data["completed_iterations"] += 1
        data["stagnation"] = improved || bound_improved ? 0 : data["stagnation"] + 1
        reason = all(iszero, disagreement) ? "consensus_copy_agreement" :
            data["stagnation"] >= opt.options[:consensus_stagnation] ? "consensus_stagnation" :
            iteration == opt.options[:consensus_iterations] ? "consensus_iteration_cap" : nothing
        if reason !== nothing
            opt.termination = MOI.LOCALLY_SOLVED
            ctx.data["stop_reason"] = reason
            return nothing
        end
        multipliers = consensus_update(opt, ctx, multipliers, disagreement, iteration)
    end
    return nothing
end

# SPDX-License-Identifier: MPL-2.0
function validate_coarse_configuration(opt)
    opt.options[:strategy] === :coarse || return nothing
    opt.options[:coarse_groups] !== nothing ||
        throw(UnsupportedChild("coarse requires explicit coarse_groups"))
    opt.options[:component_executor] === nothing && opt.options[:selection] === :strongest_edge &&
        opt.options[:partition_plan] === nothing && opt.options[:consensus_plan] === nothing &&
        opt.options[:separator] == Int[] && !opt.options[:separator_pruning] ||
        throw(UnsupportedChild("coarse requires serial execution, default selection, no partition/consensus plan, separator or pruning"))
    return nothing
end

function coarse_plan(opt, ctx, snap)
    raw = opt.options[:coarse_groups]
    (snap.n == 0 ? isempty(raw) : 1 <= length(raw) <= opt.options[:max_variables]) ||
        throw(UnsupportedChild("coarse group count must be in 1:max_variables; empty models require an empty plan"))
    groups = Vector{Int}[]
    seen = falses(snap.n)
    for group in raw
        check_time(opt, ctx, :coarse_plan)
        isempty(group) && throw(UnsupportedChild("coarse groups must be nonempty"))
        owned = sort(copy(group))
        for i in owned
            check_time(opt, ctx, :coarse_plan)
            1 <= i <= snap.n && !seen[i] ||
                throw(UnsupportedChild("coarse groups must be disjoint unique indices in the original free-variable range"))
            seen[i] = true
        end
        push!(groups, owned)
    end
    return groups
end

# Substitute x_i = c_i + d_i*m_g into every stored term. An uncovered index
# has d_i=0. Within-group products normalize using y^2=y or z^2=1.
function coarse_problem(opt, ctx, snap, groups, frozen)
    membership = zeros(Int, snap.n)
    c = copy(frozen)
    d = zeros(Int, snap.n)
    binary = snap.domain === QUBOTools.BoolDomain
    for (g, group) in enumerate(groups), i in group
        check_time(opt, ctx, :coarse_construction)
        membership[i] = g
        c[i] = binary ? frozen[i] : 0
        d[i] = binary ? 1 - 2*frozen[i] : frozen[i]
    end
    linear = zeros(Float64, length(groups))
    quadratic = Dict{Tuple{Int,Int},Float64}()
    offset = snap.offset
    for (i, a) in snap.linear
        check_time(opt, ctx, :coarse_construction)
        offset += a*c[i]
        d[i] != 0 && (linear[membership[i]] += a*d[i])
    end
    for ((i,j), b) in snap.quadratic
        check_time(opt, ctx, :coarse_construction)
        offset += b*c[i]*c[j]
        gi, gj = membership[i], membership[j]
        gi != 0 && (linear[gi] += b*d[i]*c[j])
        gj != 0 && (linear[gj] += b*d[j]*c[i])
        if gi != 0 && gj != 0
            value = b*d[i]*d[j]
            if gi == gj
                if binary
                    linear[gi] += value
                else
                    offset += value
                end
            else
                pair = minmax(gi, gj)
                quadratic[pair] = get(quadratic, pair, 0.0) + value
            end
        end
    end
    all(isfinite, linear) && all(isfinite, values(quadratic)) && isfinite(offset) ||
        error("non-finite coarse objective")
    problem = (; n=length(groups), domain=snap.domain, sense=snap.sense,
        linear=collect(enumerate(linear)), quadratic=sort!(collect(quadratic); by=first),
        scale=snap.scale, offset)
    check_time(opt, ctx, :coarse_construction)
    return problem, membership, c, d
end

function coarse_lift(opt, ctx, frozen, groups, macrostate, domain)
    candidate = copy(frozen)
    binary = domain === QUBOTools.BoolDomain
    for (g, group) in enumerate(groups), i in group
        check_time(opt, ctx, :coarse_lift)
        candidate[i] = binary ? frozen[i] + (1 - 2*frozen[i])*macrostate[g] : frozen[i]*macrostate[g]
    end
    return candidate
end

# Interpret the Float64 coefficients actually exported by child_model, after
# coefficient-wise scaling. Exact summation avoids confusing dispatch roundoff
# with original-objective ranking or with a contradictory child certificate.
function coarse_dispatched_energy(opt, ctx, problem, macrostate)
    check_time(opt,ctx,:coarse_optimal_consistency)
    value = Rational{BigInt}(problem.scale * problem.offset)
    for (i,c) in problem.linear
        check_time(opt,ctx,:coarse_optimal_consistency)
        value += Rational{BigInt}(problem.scale * c) * macrostate[i]
    end
    for ((i,j),c) in problem.quadratic
        check_time(opt,ctx,:coarse_optimal_consistency)
        value += Rational{BigInt}(problem.scale * c) * macrostate[i] * macrostate[j]
    end
    check_time(opt,ctx,:coarse_optimal_consistency)
    return value
end

function coarse_decomposition!(opt, ctx, snap, groups)
    frozen = copy(ctx.state)
    info = Dict{String,Any}("macro_groups"=>deepcopy(groups), "macro_count"=>length(groups),
        "represented_original_count"=>sum(length, groups; init=0),
        "frozen_incumbent"=>frozen, "frozen_incumbent_version"=>ctx.improvements,
        "invocation"=>opt.invocation, "complete"=>false, "accepted"=>false,
        "original_proof"=>false, "child_status"=>nothing)
    ctx.data["coarse"] = info
    if snap.constant
        info["complete"] = true
        opt.termination = MOI.OPTIMAL
        ctx.data["stop_reason"] = "constant_objective"
        return nothing
    end
    check_work(opt, ctx, :before_coarse)
    call = Dict{String,Any}("attempt"=>ctx.data["attempted_calls"] + 1, "kind"=>"coarse",
        "macro_groups"=>deepcopy(groups), "macro_count"=>length(groups),
        "represented_original_count"=>info["represented_original_count"],
        "frozen_incumbent_version"=>ctx.improvements,
        "phase_sec"=>Dict(k=>0.0 for k in keys(ctx.data["phase_sec"])),
        "seed"=>nothing, "seed_supported"=>nothing, "public_status"=>nothing,
        "valid_results"=>0, "invalid_results"=>0, "reported_multiplicities"=>Any[],
        "physical_reads"=>nothing, "physical_reads_meaning"=>"unknown; enumeration is not hardware reads",
        "exact"=>false, "original_proof"=>false,
        "time_limit_supported"=>nothing, "time_limit_enforced"=>false)
    problem, membership, c, d = phase!(ctx, "conditioning", call) do
        coarse_problem(opt, ctx, snap, groups, frozen)
    end
    info["original_to_macro"] = membership
    info["orientation_constant"], info["orientation_coefficient"] = c, d
    check_work(opt, ctx, :before_factory)
    push!(ctx.data["calls"], call)
    ctx.data["attempted_calls"] = call["attempt"]
    child, mapped = copy_child!(opt, ctx, problem, call)
    check_time(opt, ctx, :dispatch)
    phase!(ctx, "execution", call) do
        MOI.optimize!(child)
    end
    status, count = phase!(ctx, "validation_reconstruction", call) do
        status = MOI.get(child, MOI.TerminationStatus())
        call["public_status"] = info["child_status"] = string(status)
        status === MOI.INTERRUPTED || status in ACCEPTED_CHILD_STATUSES ||
            error("failure-class child status: $status")
        count = MOI.get(child, MOI.ResultCount())
        count isa Integer && !(count isa Bool) && count >= 0 || error("invalid child result count")
        count > 0 || status === MOI.INTERRUPTED || error("child returned no valid results")
        call["reported_results"] = count
        return status, count
    end
    check_time(opt, ctx, :after_child)
    best_state, best_energy = nothing, nothing
    best_dispatched = nothing
    for row in 1:count
        check_time(opt, ctx, :before_row)
        ctx.evaluations < opt.options[:max_candidate_evaluations] ||
            throw(StopSolve(MOI.ITERATION_LIMIT, "max_candidate_evaluations"))
        try
            candidate, dispatched = phase!(ctx, "validation_reconstruction", call) do
                MOI.get(child, MOI.PrimalStatus(row)) === MOI.FEASIBLE_POINT || error("child row $row is not a feasible point")
                raw = [MOI.get(child, MOI.VariablePrimal(row), v) for v in mapped]
                all(valid_value(x, snap.domain) for x in raw) || error("malformed coarse child row $row")
                reported = MOI.get(child, MOI.ObjectiveValue(row))
                reported isa Real && isfinite(reported) || error("non-finite coarse child energy")
                macrostate = Int.(raw)
                dispatched = status === MOI.OPTIMAL ? coarse_dispatched_energy(opt,ctx,problem,macrostate) : nothing
                return coarse_lift(opt, ctx, frozen, groups, macrostate, snap.domain), dispatched
            end
            reserve_evaluation!(opt, ctx)
            energy = phase!(ctx, "full_energy", call) do
                full_energy(candidate, snap.linear, snap.quadratic, snap.scale, snap.offset)
            end
            opt.checkpoint(:reconstruct)
            check_time(opt, ctx, :after_row)
            call["valid_results"] += 1
            if dispatched !== nothing && (best_dispatched === nothing || better(dispatched,best_dispatched,snap.sense))
                best_dispatched = dispatched
            end
            push!(call["reported_multiplicities"], child isa QUBODrivers.AbstractSampler ? QUBOTools.reads(child, row) : nothing)
            if best_energy === nothing || better(energy, best_energy, snap.sense) ||
                (energy == best_energy && isless(Tuple(candidate), Tuple(best_state)))
                best_state, best_energy = candidate, energy
            end
        catch err
            !(err isa InterruptException || err isa StopSolve) && (call["invalid_results"] += 1)
            rethrow()
        end
    end
    if status === MOI.OPTIMAL
        phase!(ctx,"validation_reconstruction",call) do
            no_flip = fill(snap.domain === QUBOTools.BoolDomain ? 0 : 1,problem.n)
            incumbent = coarse_dispatched_energy(opt,ctx,problem,no_flip)
            # This is the documented atol/rtol inequality, evaluated exactly on
            # exported coefficients rather than rounding its comparison again.
            tolerance = Rational{BigInt}(1e-12)
            close = abs(incumbent-best_dispatched) <=
                max(tolerance,tolerance*max(abs(incumbent),abs(best_dispatched)))
            better(incumbent,best_dispatched,snap.sense) && !close &&
                error("child OPTIMAL contradicts feasible no-flip point in dispatched coarse objective")
        end
    end
    check_time(opt, ctx, :before_commit)
    if best_energy !== nothing && better(best_energy, ctx.energy, snap.sense)
        ctx.state, ctx.energy = best_state, best_energy
        ctx.improvements += 1
        info["accepted"] = true
    end
    ctx.data["completed_calls"] += 1
    info["complete"] = true
    call["exact"] = status === MOI.OPTIMAL # child certificate only
    call["proposal_energy"], call["committed_energy"] = best_energy, ctx.energy
    call["accepted_to_working"] = true
    push!(ctx.data["incumbent_energy_trace"], ctx.energy)
    status === MOI.INTERRUPTED && throw(StopSolve(MOI.INTERRUPTED, "child_interrupted"))
    check_work(opt, ctx, :heuristic_completion)
    limited = !(status in (MOI.OPTIMAL, MOI.LOCALLY_SOLVED, MOI.ALMOST_OPTIMAL, MOI.ALMOST_LOCALLY_SOLVED))
    opt.termination = limited ? status : MOI.LOCALLY_SOLVED
    ctx.data["stop_reason"] = limited ? "coarse_child_limit" : "coarse_proposal_complete"
    return nothing
end

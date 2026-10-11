# SPDX-License-Identifier: MPL-2.0
# Independently authored narrow policy informed by QSplit's aggregation/repair
# design, pinned in issue #15. No upstream implementation code is copied.

# Vote only on each selected neighborhood, never on the lifted complement.
function batch_votes(frozen, neighborhoods, proposals; checkpoint=()->nothing)
    votes = Dict{Int,Tuple{Int,Int}}() # (lower-domain value, upper-domain value)
    for (selected, proposal) in zip(neighborhoods, proposals), i in selected
        checkpoint()
        lower, upper = get(votes, i, (0, 0))
        votes[i] = proposal.state[i] == 1 ? (lower, upper + 1) : (lower + 1, upper)
    end
    consensus = copy(frozen)
    disagreement, ties = Int[], Int[]
    for i in sort!(collect(keys(votes)))
        checkpoint()
        lower, upper = votes[i]
        lower > 0 && upper > 0 && push!(disagreement, i)
        if lower == upper
            push!(ties, i)
        elseif upper > lower
            consensus[i] = 1
        else
            # A lower value only comes from a validated proposal in this domain.
            consensus[i] = minimum(p.state[i] for (s, p) in zip(neighborhoods, proposals) if i in s)
        end
    end
    checkpoint()
    return consensus, disagreement, ties, votes
end

function batch_energy!(opt, ctx, snap, state, phase)
    check_time(opt, ctx, phase)
    length(state) == snap.n && all(valid_value(x, snap.domain) for x in state) ||
        error("invalid complete batch assignment")
    reserve_evaluation!(opt, ctx)
    energy = phase!(ctx, "full_energy") do
        full_energy(state, snap.linear, snap.quadratic, snap.scale, snap.offset)
    end
    check_time(opt, ctx, phase)
    return energy
end

# Limited child statuses are usable on existing serial routes; an unfinished
# child is not a completed electorate/repair transaction on this route.
function completed_batch_child(proposal)
    proposal.status in (MOI.OPTIMAL, MOI.LOCALLY_SOLVED, MOI.ALMOST_OPTIMAL, MOI.ALMOST_LOCALLY_SOLVED) ||
        throw(StopSolve(proposal.status, "batch_child_unfinished"))
    return proposal
end

function frozen_batch!(opt, ctx, snap, neighborhoods; sweep=nothing)
    # Bounded overlapping batches deliberately bypass disjoint-partition rules.
    1 <= length(neighborhoods) <= opt.options[:batch_size] || error("invalid batch size")
    frozen = SolveState(copy(ctx.state), ctx.energy, 0, ctx.improvements, ctx.deadline, ctx.data)
    record = Dict{String,Any}("batch"=>length(ctx.data["batches"]) + 1, "sweep"=>sweep,
        "frozen_invocation"=>ctx.data["invocation"], "frozen_incumbent_version"=>ctx.improvements,
        "frozen_energy"=>ctx.energy, "neighborhoods"=>deepcopy(neighborhoods),
        "proposal_energies"=>Float64[], "consensus_energy"=>nothing, "repaired_energy"=>nothing,
        "votes"=>nothing, "tie_indices"=>Int[], "uncovered_count"=>snap.n,
        "disagreement"=>Int[], "repair_blocks"=>Vector{Int}[],
        "repair_completed_blocks"=>0, "repair_enabled"=>opt.options[:repair],
        "tie_rule"=>"retain frozen value; proposal ties lexicographic; incumbent retained on energy ties",
        "complete"=>false, "accepted"=>false, "reason"=>"unfinished",
        "child_calls"=>0, "candidate_evaluations"=>0, "elapsed_sec"=>0.0)
    push!(ctx.data["batches"], record)
    start, calls, evaluations = time_ns(), ctx.data["attempted_calls"], ctx.evaluations
    try
        proposals = Any[]
        for selected in neighborhoods
            check_time(opt, ctx, :batch_generation)
            proposal = completed_batch_child(child_call!(opt, ctx, snap, selected;
                kind="batch_proposal", working=frozen, accept=false, sweep, batch=record["batch"]))
            push!(proposals, proposal)
            push!(record["proposal_energies"], proposal.energy)
        end
        consensus, disagreement, ties, votes = phase!(ctx, "aggregation") do
            batch_votes(frozen.state, neighborhoods, proposals;
                checkpoint=()->check_time(opt, ctx, :batch_voting))
        end
        record["votes"], record["disagreement"], record["tie_indices"] = votes, disagreement, ties
        record["uncovered_count"] = snap.n - length(votes)
        energy = batch_energy!(opt, ctx, snap, consensus, :batch_consensus)
        record["consensus_energy"] = energy
        # The scratch incumbent may be worse than the committed incumbent. Finish
        # all ordered repair blocks before comparing any batch candidate globally.
        scratch = SolveState(copy(consensus), energy, 0, 0, ctx.deadline, ctx.data)
        blocks = opt.options[:repair] ?
            [disagreement[first:min(first + opt.options[:max_variables] - 1, length(disagreement))]
                for first in 1:opt.options[:max_variables]:length(disagreement)] : Vector{Int}[]
        record["repair_blocks"] = blocks
        for block in blocks
            check_time(opt, ctx, :batch_repair)
            proposal = completed_batch_child(child_call!(opt, ctx, snap, block;
                kind="batch_repair", working=scratch, accept=false, sweep, batch=record["batch"]))
            # Retain scratch on ties and on worse proposals, as in serial children.
            if better(proposal.energy, scratch.energy, snap.sense)
                scratch.state, scratch.energy = proposal.state, proposal.energy
                scratch.improvements += 1
            end
            record["repair_completed_blocks"] += 1
        end
        repaired_energy = batch_energy!(opt, ctx, snap, scratch.state, :batch_repaired)
        record["repaired_energy"] = repaired_energy
        best_state, best_energy = frozen.state, frozen.energy
        for candidate in [proposals; [(; state=consensus, energy), (; state=scratch.state, energy=repaired_energy)]]
            check_time(opt, ctx, :batch_acceptance)
            if better(candidate.energy, best_energy, snap.sense) ||
                (candidate.energy == best_energy && better(best_energy, frozen.energy, snap.sense) &&
                 isless(Tuple(candidate.state), Tuple(best_state)))
                best_state, best_energy = candidate.state, candidate.energy
            end
        end
        check_time(opt, ctx, :before_batch_commit)
        if better(best_energy, frozen.energy, snap.sense)
            ctx.state, ctx.energy = best_state, best_energy
            ctx.improvements += 1
            record["accepted"] = true
        end
        record["complete"], record["reason"] = true, "batch_complete"
        push!(ctx.data["incumbent_energy_trace"], ctx.energy)
    catch err
        record["reason"] = err isa StopSolve ? err.reason : err isa InterruptException ?
            "interrupt_exception" : err isa UnsupportedChild ? "invalid_option" : "execution_failure"
        rethrow()
    finally
        record["child_calls"] = ctx.data["attempted_calls"] - calls
        record["candidate_evaluations"] = ctx.evaluations - evaluations
        record["elapsed_sec"] = (time_ns() - start) / 1e9
    end
    return nothing
end

function frozen_sweep!(opt, ctx, snap, adjacency, components, oversized, neighbors, seen, sweep)
    pending = Vector{Int}[]
    for component in oversized, anchor in components[component]
        check_work(opt, ctx, :batch_selection)
        selected = selection!(ctx) do
            opt.options[:selection] === :bfs ?
                sort!(bfs_neighborhood(neighbors, seen, anchor, opt.options[:max_variables])) :
                neighborhood(adjacency, anchor, opt.options[:max_variables])
        end
        push!(pending, selected)
        if length(pending) == opt.options[:batch_size]
            frozen_batch!(opt, ctx, snap, pending; sweep)
            empty!(pending)
        end
    end
    isempty(pending) || frozen_batch!(opt, ctx, snap, pending; sweep)
    return nothing
end

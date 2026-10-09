# SPDX-License-Identifier: MPL-2.0
# This state deliberately has no budget or global proof fields. Child validation
# uses it as a working incumbent; only a complete branch can update SolveState.
mutable struct SeparatorBranch
    state::Vector{Int}
    energy::Float64
    improvements::Int
end

function separator_plan(opt, ctx, snap)
    selected = opt.options[:separator]
    adjacency = nothing
    if selected === :articulation
        selected, adjacency = articulation_separator(opt, ctx, snap)
    end
    # Check before exponentiation, assignment allocation, or topology building.
    length(selected) <= opt.options[:max_separator_size] <= 16 ||
        throw(UnsupportedChild("separator exceeds max_separator_size ($(opt.options[:max_separator_size]); hard ceiling 16)"))
    all(i -> 1 <= i <= snap.n, selected) ||
        throw(UnsupportedChild("separator indices must be in 1:$(snap.n) of the original free-variable order"))
    selected = sort(copy(selected))
    checkpoint = ()->check_time(opt, ctx, :separator_plan_validation)
    components = if adjacency === nothing
        last(interaction_graph(snap, selected; checkpoint))
    else
        graph_components(adjacency, selected; checkpoint)
    end
    for (i, component) in enumerate(components)
        length(component) <= opt.options[:max_variables] ||
            throw(UnsupportedChild("residual component $i has $(length(component)) variables, exceeding max_variables $(opt.options[:max_variables]) in :separator mode"))
    end
    # Topology and original/reduced mappings are invariant across assignments.
    maps = Dict{Int,Int}[]
    for c in components
        map = Dict{Int,Int}()
        for (j, v) in enumerate(c)
            checkpoint()
            map[v] = j
        end
        push!(maps, map)
    end
    checkpoint()
    return selected, components, maps, 1 << length(selected)
end

function separator_energy!(opt, ctx, snap, state, phase)
    check_time(opt, ctx, phase)
    reserve_evaluation!(opt, ctx)
    energy = phase!(ctx, "full_energy") do
        full_energy(state, snap.linear, snap.quadratic, snap.scale, snap.offset)
    end
    check_time(opt, ctx, :separator_after_evaluation)
    return energy
end

function separator_decomposition!(opt, ctx, snap)
    proof = Dict{String,Any}(
        "indices"=>Int[], "residual_components"=>Vector{Int}[],
        "required_branches"=>nothing, "started_branches"=>0, "completed_branches"=>0,
        "certified_branches"=>0, "component_certificates"=>Int[], "constant_components"=>Int[],
        "current_branch"=>nothing, "completed_components"=>0,
        "proof_complete"=>false, "incomplete_reason"=>nothing,
        "discovery"=>nothing)
    ctx.data["separator"] = proof
    selected, components, maps, required = phase!(ctx, "preparation") do
        check_time(opt, ctx, :separator_plan)
        separator_plan(opt, ctx, snap)
    end
    proof["indices"], proof["residual_components"] = selected, components
    proof["required_branches"] = required
    proof["component_certificates"] = zeros(Int, length(components))
    proof["constant_components"] = zeros(Int, length(components))
    low = snap.domain === QUBOTools.BoolDomain ? 0 : -1
    # Streaming bit order: smallest original separator index changes fastest.
    # Restart every branch from the input start, never an unfinished branch.
    for mask in 0:required-1
        check_time(opt, ctx, :separator_branch)
        proof["current_branch"] = mask + 1
        proof["started_branches"] += 1
        proof["completed_components"] = 0
        state = copy(snap.state)
        for (bit, i) in enumerate(selected)
            state[i] = iszero((mask >> (bit-1)) & 1) ? low : 1
        end
        energy = separator_energy!(opt, ctx, snap, state, :separator_initial)
        working = SeparatorBranch(state, energy, 0)
        certified = true
        for (i, component) in enumerate(components)
            prepared = phase!(ctx, "conditioning") do
                check_time(opt, ctx, :separator_conditioning)
                conditioned_problem(snap, working.state, component)
            end
            problem, _, map, _ = prepared
            map == maps[i] || error("separator residual mapping changed")
            constant = iszero(problem.scale) ||
                (all(iszero(last(t)) for t in problem.linear) && all(iszero(last(t)) for t in problem.quadratic))
            if constant
                # No factory/call allowance needed. Direct work still consumes
                # the shared evaluation and deadline allowances.
                working.energy = separator_energy!(opt, ctx, snap, working.state, :separator_constant)
                proof["constant_components"][i] += 1
            else
                status = child_call!(opt, ctx, snap, component; kind="separator_component",
                    component=i, working, prepared, branch=mask+1)
                if status === MOI.OPTIMAL
                    proof["component_certificates"][i] += 1
                else
                    certified = false
                end
            end
            proof["completed_components"] += 1
        end
        # Count constants and separator-only terms exactly once in the original
        # objective. Never combine the conditioned children's energies.
        energy = separator_energy!(opt, ctx, snap, working.state, :separator_candidate)
        check_time(opt, ctx, :separator_commit)
        if better(energy, ctx.energy, snap.sense)
            ctx.state, ctx.energy = working.state, energy
            ctx.improvements += 1
        end
        push!(ctx.data["incumbent_energy_trace"], ctx.energy)
        proof["completed_branches"] += 1
        proof["certified_branches"] += certified
    end
    if proof["certified_branches"] == required
        # Consuming the final allowance is completion, not interruption. No later
        # work/counter check may erase a proof completed before the deadline.
        proof["proof_complete"] = true
        ctx.data["stop_reason"] = "separator_complete"
        opt.termination = MOI.OPTIMAL
    else
        # Uncertified completion necessarily used a child. Reuse serial limit
        # precedence; fully certified no-child routes take the certified path above.
        check_work(opt, ctx, :separator_heuristic_completion)
        ctx.data["stop_reason"] = "separator_heuristic_complete"
        opt.termination = MOI.LOCALLY_SOLVED
    end
    return nothing
end

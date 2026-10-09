# SPDX-License-Identifier: MPL-2.0
# Public normalized terms supply the graph; explicit vertices retain isolates.
function interaction_graph(snap)
    adjacency = [Dict{Int,Float64}() for _ in 1:snap.n]
    for ((i, j), coefficient) in snap.quadratic
        iszero(coefficient) && continue
        adjacency[i][j] = abs(coefficient)
        adjacency[j][i] = abs(coefficient)
    end
    seen = falses(snap.n)
    components = Vector{Int}[]
    for root in 1:snap.n
        seen[root] && continue
        component, queue = Int[], [root]
        seen[root] = true
        while !isempty(queue)
            i = pop!(queue)
            push!(component, i)
            for j in sort!(collect(keys(adjacency[i])))
                if !seen[j]
                    seen[j] = true
                    push!(queue, j)
                end
            end
        end
        push!(components, sort!(component))
    end
    return adjacency, components
end

function neighborhood(adjacency, anchor, budget)
    budget == 1 && return [anchor]
    neighbors = sort!(collect(keys(adjacency[anchor]));
        by=j -> (-adjacency[anchor][j], j))
    return sort!([anchor; neighbors[1:min(budget-1, length(neighbors))]])
end

# Signed normal-form coefficients, not the absolute interaction graph. The
# offset cancels in a flip; scale and objective sense both affect its gain.
function single_flip_gains(snap, state)
    fields = zeros(Float64, snap.n)
    iszero(snap.scale) && return fields
    for (i, coefficient) in snap.linear
        fields[i] += coefficient
    end
    for ((i, j), coefficient) in snap.quadratic
        fields[i] += coefficient * state[j]
        fields[j] += coefficient * state[i]
    end
    direction = snap.sense === QUBOTools.Min ? -1 : 1
    for i in eachindex(fields)
        step = snap.domain === QUBOTools.BoolDomain ? 1 - 2state[i] : -2state[i]
        fields[i] = direction * snap.scale * step * fields[i]
    end
    all(isfinite, fields) || error("non-finite single-flip gain")
    return fields
end

function gain_neighborhood(snap, state, unvisited, budget)
    gains = single_flip_gains(snap, state)
    # Julia's total ordering distinguishes signed zeros; mathematical ties do not.
    ranked = sort!(collect(unvisited); by=i -> (iszero(gains[i]) ? 0.0 : -gains[i], i))
    # Keep nonpositive gains: a block can improve jointly without a good flip.
    selected = sort!(ranked[1:min(budget, length(ranked))])
    return selected, gains[selected]
end

function serial_decomposition!(opt, ctx, snap)
    adjacency, components = phase!(ctx, "preparation") do
        check_time(opt, ctx, :graph)
        interaction_graph(snap)
    end
    data, budget = ctx.data, opt.options[:max_variables]
    data["components"] = deepcopy(components)
    data["component_exact"] = falses(length(components))
    oversized = findall(c -> length(c) > budget, components)
    if opt.options[:strategy] === :components && !isempty(oversized)
        i = first(oversized)
        throw(UnsupportedChild("component $i has $(length(components[i])) free logical variables, exceeding budget $budget in :components mode"))
    end
    check_time(opt, ctx, :after_graph)
    # One call per fitting component, even when several could be packed together.
    for (i, component) in enumerate(components)
        length(component) > budget && continue
        status = child_call!(opt, ctx, snap, component; kind="component", component=i)
        data["component_exact"][i] = status === MOI.OPTIMAL
    end
    if isempty(oversized) && all(data["component_exact"])
        # No later budget check can erase a fully assembled separable proof.
        data["separable_proof"] = true
        data["stop_reason"] = "components_complete"
        opt.termination = MOI.OPTIMAL
        return nothing
    end
    if isempty(oversized)
        check_work(opt, ctx, :heuristic_completion)
        data["stop_reason"] = "components_heuristic_complete"
        opt.termination = MOI.LOCALLY_SOLVED
        return nothing
    end
    # Coverage is solve/sweep-local. Only a completed child transaction advances it.
    while true
        check_work(opt, ctx, :before_sweep)
        data["started_sweeps"] < opt.options[:max_sweeps] ||
            throw(StopSolve(MOI.ITERATION_LIMIT, "max_sweeps"))
        data["started_sweeps"] += 1
        sweep = data["started_sweeps"]
        improvements = ctx.improvements
        for i in oversized
            if opt.options[:selection] === :single_flip_gain
                unvisited = Set(components[i])
                while !isempty(unvisited)
                    check_work(opt, ctx, :selection)
                    selected, gains = phase!(ctx, "preparation") do
                        gain_neighborhood(snap, ctx.state, unvisited, budget)
                    end
                    child_call!(opt, ctx, snap, selected; kind="neighborhood",
                        component=i, sweep, gains)
                    setdiff!(unvisited, selected)
                end
            else
                for anchor in components[i]
                    selected = phase!(ctx, "preparation") do
                        neighborhood(adjacency, anchor, budget)
                    end
                    child_call!(opt, ctx, snap, selected; kind="neighborhood", component=i, sweep, anchor)
                end
            end
        end
        data["completed_sweeps"] += 1
        data["stagnation"] = ctx.improvements == improvements ? data["stagnation"] + 1 : 0
        check_work(opt, ctx, :after_sweep)
        data["completed_sweeps"] < opt.options[:max_sweeps] ||
            throw(StopSolve(MOI.ITERATION_LIMIT, "max_sweeps"))
        if data["stagnation"] >= opt.options[:stagnation_sweeps]
            opt.termination = MOI.LOCALLY_SOLVED
            data["stop_reason"] = "stagnation_sweeps"
            return nothing
        end
    end
end

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
    # A sweep visits every queued anchor once in component/minimum-index order.
    while true
        check_work(opt, ctx, :before_sweep)
        data["started_sweeps"] < opt.options[:max_sweeps] ||
            throw(StopSolve(MOI.ITERATION_LIMIT, "max_sweeps"))
        data["started_sweeps"] += 1
        sweep = data["started_sweeps"]
        improvements = ctx.improvements
        for i in oversized, anchor in components[i]
            selected = neighborhood(adjacency, anchor, budget)
            child_call!(opt, ctx, snap, selected; kind="neighborhood", component=i, sweep, anchor)
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

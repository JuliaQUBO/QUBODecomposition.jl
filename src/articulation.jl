# SPDX-License-Identifier: MPL-2.0
# Independently implemented iterative low-link traversal. Each DFS child whose
# low-link cannot reach above its parent detaches its whole subtree on deletion.
# Keep only their sum/max; the remaining vertices form the parent-side residual.
function articulation_separator(opt, ctx, snap)
    work = Dict{String,Any}("mode"=>"articulation", "complete"=>false,
        "elapsed_sec"=>0.0, "visited_vertices"=>0, "examined_adjacencies"=>0,
        "articulation_vertices"=>0, "qualifying_vertices"=>0,
        "component_count"=>nothing, "largest_initial_component"=>nothing,
        "selected_largest_residual"=>nothing, "reason"=>nothing)
    ctx.data["separator"]["discovery"] = work
    started = time_ns()
    try
        return discover_articulation(opt, ctx, snap, work)
    finally
        # A subset of separator_plan's preparation timer, never an extra phase.
        work["elapsed_sec"] = (time_ns() - started) / 1e9
    end
end

function discover_articulation(opt, ctx, snap, work)
    checkpoint = ()->check_time(opt, ctx, :articulation_graph)
    adjacency, components = interaction_graph(snap; checkpoint)
    sizes = length.(components)
    largest, second = 0, 0
    component_id = zeros(Int, snap.n)
    for (id, c) in enumerate(components)
        checkpoint()
        size = length(c)
        if size >= largest
            second, largest = largest, size
        else
            second = max(second, size)
        end
        for v in c
            checkpoint()
            component_id[v] = id
        end
    end
    work["component_count"] = length(components)
    work["largest_initial_component"] = largest
    capacity = opt.options[:max_variables]
    if largest <= capacity
        work["selected_largest_residual"] = largest
        work["complete"], work["reason"] = true, "already_fitting"
        return Int[], adjacency
    end
    if opt.options[:max_separator_size] < 1
        work["complete"], work["reason"] = true, "separator_cap_zero"
        throw(UnsupportedChild("articulation discovery requires max_separator_size >= 1 for an oversized component"))
    end

    neighbors = Vector{Int}[]
    for a in adjacency
        check_time(opt, ctx, :articulation_ordering)
        push!(neighbors, sort!(collect(keys(a))))
        check_time(opt, ctx, :articulation_ordering)
    end
    pre, low, parent = zeros(Int, snap.n), zeros(Int, snap.n), zeros(Int, snap.n)
    subtree, next_neighbor = ones(Int, snap.n), ones(Int, snap.n)
    children, cut_children = zeros(Int, snap.n), zeros(Int, snap.n)
    detached_sum, detached_max = zeros(Int, snap.n), zeros(Int, snap.n)
    stack = Int[]
    visited, examined = 0, 0
    for root in 1:snap.n
        check_time(opt, ctx, :articulation_traversal)
        pre[root] == 0 || continue
        visited += 1
        pre[root] = low[root] = visited
        work["visited_vertices"] = visited
        push!(stack, root)
        while !isempty(stack)
            check_time(opt, ctx, :articulation_traversal)
            v = last(stack)
            if next_neighbor[v] <= length(neighbors[v])
                w = neighbors[v][next_neighbor[v]]
                next_neighbor[v] += 1
                examined += 1
                work["examined_adjacencies"] = examined
                if pre[w] == 0
                    parent[w] = v
                    children[v] += 1
                    visited += 1
                    pre[w] = low[w] = visited
                    work["visited_vertices"] = visited
                    push!(stack, w)
                elseif w != parent[v]
                    low[v] = min(low[v], pre[w])
                end
            else
                pop!(stack)
                p = parent[v]
                if p != 0
                    subtree[p] += subtree[v]
                    low[p] = min(low[p], low[v])
                    if low[v] >= pre[p]
                        cut_children[p] += 1
                        detached_sum[p] += subtree[v]
                        detached_max[p] = max(detached_max[p], subtree[v])
                    end
                end
            end
        end
    end

    selected, best = 0, typemax(Int)
    for v in 1:snap.n
        check_time(opt, ctx, :articulation_scoring)
        articulation = parent[v] == 0 ? children[v] > 1 : cut_children[v] > 0
        articulation || continue
        work["articulation_vertices"] += 1
        size = sizes[component_id[v]]
        outside = size == largest ? second : largest
        residual = max(outside, detached_max[v], size - 1 - detached_sum[v])
        residual <= capacity || continue
        work["qualifying_vertices"] += 1
        # Ascending original free indices settle equal residual maxima.
        if residual < best
            selected, best = v, residual
        end
    end
    check_time(opt, ctx, :articulation_complete)
    work["complete"] = true
    if selected == 0
        work["reason"] = "no_supported_articulation"
        throw(UnsupportedChild("no supported articulation separator leaves every residual component within max_variables $capacity; this does not establish infeasibility or absence of other separators"))
    end
    work["selected_largest_residual"], work["reason"] = best, "selected"
    return [selected], adjacency
end

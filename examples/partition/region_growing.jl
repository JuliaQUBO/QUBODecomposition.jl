# SPDX-License-Identifier: MPL-2.0
module PartitionExample

"""
    region_growing(indices, adjacency, capacity)

A deterministic, flat callback for `partition_plan`. Seed each region with the
smallest unused original index, then add the unused neighbor with greatest total
absolute weight to the region (index breaks ties). End a disconnected region
early; every isolate therefore gets a block. No recursion or METIS is required.
"""
function region_growing(indices, adjacency, capacity)
    capacity > 0 || throw(ArgumentError("capacity must be positive"))
    unused = Set(indices)
    blocks = Vector{Int}[]
    while !isempty(unused)
        block = [minimum(unused)]
        delete!(unused, only(block))
        while length(block) < capacity
            frontier = Dict{Int,Float64}()
            for i in block, (j,w) in adjacency[i]
                j in unused || continue
                frontier[j] = get(frontier,j,0.0) + w
            end
            isempty(frontier) && break
            next = first(sort!(collect(keys(frontier)); by=j -> (-frontier[j],j)))
            push!(block, next)
            delete!(unused, next)
        end
        push!(blocks, sort!(block))
    end
    return blocks
end

end

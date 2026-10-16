# SPDX-License-Identifier: MPL-2.0
const SAMPLE_POOL_ROWS_LIMIT = 256
const SAMPLE_POOL_CELLS_LIMIT = 65_536
const SAMPLE_POOL_PROVENANCE_BYTES = 1024

function validate_sample_pool_option(pool)
    pool === nothing && return nothing
    pool isa NamedTuple && all(k -> k in keys(pool), (:labels,:domain,:assignments,:provenance)) &&
        all(k -> k in (:labels,:domain,:assignments,:provenance,:generation_sec), keys(pool)) ||
        throw(ArgumentError("sample_pool must be a NamedTuple with labels, domain, assignments, provenance and optional generation_sec"))
    pool.labels isa AbstractVector && length(pool.labels) <= SAMPLE_POOL_CELLS_LIMIT ||
        throw(ArgumentError("sample_pool labels must be a vector with at most 65536 entries"))
    (pool.domain === :bool || pool.domain === :spin) || throw(ArgumentError("sample_pool domain must be :bool or :spin"))
    pool.provenance isa AbstractString && ncodeunits(pool.provenance) <= SAMPLE_POOL_PROVENANCE_BYTES ||
        throw(ArgumentError("sample_pool provenance must be a string of at most 1024 bytes"))
    pool.assignments isa AbstractVector && length(pool.assignments) <= SAMPLE_POOL_ROWS_LIMIT ||
        throw(ArgumentError("sample_pool assignments must be a vector with at most 256 rows"))
    cells = 0
    for row in pool.assignments
        row isa AbstractVector || throw(ArgumentError("sample_pool assignments must be vectors"))
        length(row) <= SAMPLE_POOL_CELLS_LIMIT - cells ||
            throw(ArgumentError("sample_pool exceeds 65536 assignment cells"))
        cells += length(row)
    end
    generation = get(pool,:generation_sec,nothing)
    generation === nothing || (generation isa Real && !(generation isa Bool) &&
        isfinite(generation) && generation >= 0 && isfinite(Float64(generation))) ||
        throw(ArgumentError("sample_pool generation_sec must be nothing or finite nonnegative seconds"))
    return nothing
end
function own_sample_pool(pool)
    pool === nothing && return nothing
    return (; labels=deepcopy(collect(pool.labels)), domain=pool.domain,
        assignments=[deepcopy(collect(row)) for row in pool.assignments], provenance=String(pool.provenance),
        generation_sec=get(pool,:generation_sec,nothing) === nothing ? nothing : Float64(pool.generation_sec))
end

function validate_sample_fixing_configuration(opt)
    opt.options[:strategy] === :sample_fixing || return nothing
    opt.options[:sample_pool] !== nothing || throw(UnsupportedChild("sample_fixing requires an explicit sample_pool"))
    opt.options[:component_executor] === nothing && opt.options[:selection] === :strongest_edge &&
        opt.options[:partition_plan] === nothing && opt.options[:consensus_plan] === nothing &&
        opt.options[:coarse_groups] === nothing && opt.options[:separator] == Int[] &&
        !opt.options[:separator_pruning] ||
        throw(UnsupportedChild("sample_fixing requires serial execution, default selection, no partition/consensus/coarse plan, separator or pruning"))
    return nothing
end

function sample_pool_labels(opt, ctx, snap, pool)
    length(pool.assignments) <= opt.options[:max_pool_size] ||
        throw(UnsupportedChild("sample_pool exceeds max_pool_size"))
    length(pool.labels) == snap.n && length(unique(pool.labels)) == snap.n ||
        throw(UnsupportedChild("sample_pool labels must be unique and cover the current original free variables"))
    expected = snap.domain === QUBOTools.BoolDomain ? :bool : :spin
    pool.domain === expected || throw(UnsupportedChild("sample_pool domain differs from the original domain"))
    positions = Dict(label=>i for (i,label) in enumerate(pool.labels))
    map = Int[]
    for label in snap.labels
        check_time(opt, ctx, :sample_pool_labels)
        haskey(positions,label) || throw(UnsupportedChild("sample_pool labels differ from the original free-variable labels"))
        push!(map,positions[label])
    end
    return map
end

function sample_pool_scan!(opt, ctx, snap, pool, info)
    map = phase!(ctx, "preparation") do
        sample_pool_labels(opt,ctx,snap,pool)
    end
    info["original_to_pool"] = map
    rows = Vector{Int}[]
    energies = Float64[]
    ids = Int[]
    seen = Set{Tuple}()
    best_state, best_energy = nothing, nothing
    for (row_id, raw) in enumerate(pool.assignments)
        check_time(opt,ctx,:sample_pool_row)
        row = phase!(ctx, "validation_reconstruction") do
            length(raw) == snap.n && all(x -> valid_value(x,snap.domain),raw) ||
                throw(UnsupportedChild("sample_pool row $row_id is incomplete or outside the original domain"))
            Int[raw[i] for i in map]
        end
        reserve_evaluation!(opt,ctx) # duplicate supplied rows are evaluated and charged
        energy = phase!(ctx,"full_energy") do
            full_energy(row,snap.linear,snap.quadratic,snap.scale,snap.offset)
        end
        check_time(opt,ctx,:sample_pool_after_row)
        info["validated_rows"] += 1
        if !(Tuple(row) in seen)
            push!(seen,Tuple(row)); push!(rows,row); push!(energies,energy); push!(ids,row_id)
        end
        if best_energy === nothing || better(energy,best_energy,snap.sense) ||
            (energy == best_energy && isless(Tuple(row),Tuple(best_state)))
            best_state,best_energy = row,energy
        end
    end
    check_time(opt,ctx,:sample_pool_commit)
    if best_energy !== nothing && better(best_energy,ctx.energy,snap.sense)
        ctx.state,ctx.energy = copy(best_state),best_energy
        ctx.improvements += 1
        info["pool_improved_incumbent"] = true
        push!(ctx.data["incumbent_energy_trace"],ctx.energy)
    end
    info["pool_complete"] = true
    info["distinct_rows"] = length(rows)
    info["duplicate_rows"] = length(pool.assignments)-length(rows)
    info["distinct_source_row_ids"] = ids
    return rows,energies,ids
end

function sample_fixing_choice(opt, ctx, snap, rows, support, fixed)
    threshold = Rational{BigInt}(opt.options[:fixing_threshold])
    choice, votes = nothing, 0
    for i in 1:snap.n
        check_time(opt,ctx,:sample_fixing_selection)
        haskey(fixed,i) && continue
        plus = 0
        for row in support
            check_time(opt,ctx,:sample_fixing_score)
            plus += rows[row][i] == 1
        end
        high = max(plus,length(support)-plus)
        2*high > length(support) &&
            high*denominator(threshold) >= length(support)*numerator(threshold) || continue
        if high > votes # ascending original index wins equal support
            value = plus == high ? 1 : (snap.domain === QUBOTools.BoolDomain ? 0 : -1)
            choice,votes = (i,value),high
        end
    end
    return choice,votes
end

function sample_fixing_publish!(opt, ctx, snap, working, info)
    check_time(opt,ctx,:sample_fixing_global_commit)
    if better(working.energy,ctx.energy,snap.sense)
        ctx.state,ctx.energy = copy(working.state),working.energy
        ctx.improvements += 1
        info["terminal_improved_incumbent"] = true
    end
    push!(ctx.data["incumbent_energy_trace"],ctx.energy)
    return nothing
end

function sample_fixing_terminal!(opt, ctx, snap, rows, energies, support, prepared, info)
    problem,fixed,map,delta = prepared
    best = first(support)
    for id in support
        check_time(opt,ctx,:sample_fixing_working)
        if better(energies[id],energies[best],snap.sense) ||
            (energies[id] == energies[best] && isless(Tuple(rows[id]),Tuple(rows[best])))
            best = id
        end
    end
    state,energy = copy(rows[best]),energies[best]
    # A better global incumbent is also a consistency witness when compatible.
    if all(ctx.state[i] == value for (i,value) in fixed) && better(ctx.energy,energy,snap.sense)
        state,energy = copy(ctx.state),ctx.energy
    end
    working = SolveState(state,energy,0,0,ctx.deadline,ctx.data)
    info["restricted_initial_state"],info["restricted_initial_energy"] = copy(state),energy
    info["global_incumbent_compatible"] = all(ctx.state[i] == value for (i,value) in fixed)
    if problem.n == 0
        reserve_evaluation!(opt,ctx)
        candidate = phase!(ctx,"validation_reconstruction") do
            QUBOTools.lift_state(Int[],fixed,map,snap.n)
        end
        working.energy = phase!(ctx,"full_energy") do
            full_energy(candidate,snap.linear,snap.quadratic,snap.scale,snap.offset)
        end
        working.state = candidate
        sample_fixing_publish!(opt,ctx,snap,working,info)
        info["terminal_complete"] = true
        return MOI.LOCALLY_SOLVED
    end
    selected = sort!(collect(keys(map)))
    attempts_before = ctx.data["attempted_calls"]
    status = try
        child_call!(opt,ctx,snap,selected; kind="sample_fixing",working,prepared,
            allow_interrupted_commit=true)
    catch err
        if err isa StopSolve && err.status === MOI.INTERRUPTED && err.reason == "child_interrupted"
            info["child_status"] = "INTERRUPTED"
            info["terminal_complete"] = true
            sample_fixing_publish!(opt,ctx,snap,working,info)
        end
        rethrow()
    finally
        if ctx.data["attempted_calls"] > attempts_before
            call = last(ctx.data["calls"])
            call["original_proof"] = false
            info["child_status"] = call["public_status"]
        end
    end
    info["child_status"] = string(status)
    info["terminal_complete"] = true
    last(ctx.data["calls"])["original_proof"] = false
    sample_fixing_publish!(opt,ctx,snap,working,info)
    return status
end

function sample_fixing_decomposition!(opt, ctx, snap)
    pool = opt.options[:sample_pool]
    info = Dict{String,Any}("provenance"=>pool.provenance,"reported_generation_sec"=>pool.generation_sec,
        "generation_cost_measured_by_parent"=>false,"supplied_rows"=>length(pool.assignments),
        "validated_rows"=>0,"pool_complete"=>false,"pool_improved_incumbent"=>false,
        "threshold"=>opt.options[:fixing_threshold],"weight_policy"=>"one equal vote per distinct assignment",
        "steps"=>Any[],"started_fixings"=>0,"completed_fixings"=>0,
        "fixed_variables"=>Dict{Int,Int}(),"terminal_complete"=>false,
        "terminal_improved_incumbent"=>false,"child_status"=>nothing,"original_proof"=>false,
        "invocation"=>opt.invocation,"complete"=>false)
    ctx.data["sample_fixing"] = info
    rows,energies,ids = sample_pool_scan!(opt,ctx,snap,pool,info)
    if snap.constant
        info["complete"] = true
        info["stop_reason"] = "constant_objective"
        opt.termination = MOI.OPTIMAL
        ctx.data["stop_reason"] = "constant_objective"
        return nothing
    end
    check_work(opt,ctx,:sample_fixing_before_reduction)
    fixed = Dict{Int,Int}()
    support = collect(eachindex(rows))
    remaining = collect(1:snap.n)
    prepared = nothing
    reason = isempty(support) ? "sample_fixing_empty_pool" : "sample_fixing_capacity"
    while !isempty(support) && length(remaining) > opt.options[:max_variables]
        check_work(opt,ctx,:sample_fixing_before_step)
        if length(fixed) >= opt.options[:max_fixings]
            reason = "sample_fixing_cap"
            break
        end
        choice,votes = phase!(ctx,"selection") do
            sample_fixing_choice(opt,ctx,snap,rows,support,fixed)
        end
        if choice === nothing
            reason = "sample_fixing_abstained"
            break
        end
        info["started_fixings"] += 1
        i,value = choice
        next_support = Int[]
        for id in support
            check_time(opt,ctx,:sample_fixing_filter)
            rows[id][i] == value && push!(next_support,id)
        end
        isempty(next_support) && error("majority fixing removed every distinct pool assignment")
        next_remaining = filter(!=(i),remaining)
        next_prepared = phase!(ctx,"conditioning") do
            check_time(opt,ctx,:sample_fixing_conditioning)
            result = conditioned_problem(snap,rows[first(next_support)],next_remaining)
            check_time(opt,ctx,:sample_fixing_after_conditioning)
            return result
        end
        check_time(opt,ctx,:sample_fixing_step_commit)
        push!(info["steps"],Dict{String,Any}("step"=>length(fixed)+1,"original_index"=>i,
            "label"=>snap.labels[i],"current_index_before"=>findfirst(==(i),remaining),"value"=>value,
            "score_numerator"=>votes,"score_denominator"=>length(support),
            "support_before"=>length(support),"support_after"=>length(next_support),
            "retained_source_row_ids"=>ids[next_support],"remaining_original_indices"=>copy(next_remaining),
            "original_to_reduced"=>copy(next_prepared[3]),"fixed_variables"=>copy(next_prepared[2]),
            "offset_delta"=>next_prepared[4],"restricted_offset"=>next_prepared[1].offset))
        fixed = next_prepared[2]
        remaining,support,prepared = next_remaining,next_support,next_prepared
        info["fixed_variables"] = copy(fixed)
        info["completed_fixings"] += 1
    end
    info["remaining_original_indices"] = remaining
    info["remaining_labels"] = snap.labels[remaining]
    info["support_source_row_ids"] = ids[support]
    if !isempty(support) && length(remaining) <= opt.options[:max_variables]
        if prepared === nothing
            prepared = phase!(ctx,"conditioning") do
                check_time(opt,ctx,:sample_fixing_conditioning)
                result = conditioned_problem(snap,rows[first(support)],remaining)
                check_time(opt,ctx,:sample_fixing_after_conditioning)
                return result
            end
        end
        status = sample_fixing_terminal!(opt,ctx,snap,rows,energies,support,prepared,info)
        limited = !(status in (MOI.OPTIMAL,MOI.LOCALLY_SOLVED,MOI.ALMOST_OPTIMAL,MOI.ALMOST_LOCALLY_SOLVED))
        check_work(opt,ctx,:heuristic_completion)
        opt.termination = limited ? status : MOI.LOCALLY_SOLVED
        reason = limited ? "sample_fixing_child_limit" : "sample_fixing_complete"
    else
        check_work(opt,ctx,:heuristic_completion)
        opt.termination = MOI.LOCALLY_SOLVED
    end
    info["complete"] = true
    info["stop_reason"] = reason
    ctx.data["stop_reason"] = reason
    return nothing
end

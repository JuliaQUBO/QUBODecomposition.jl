# SPDX-License-Identifier: MPL-2.0
struct StopSolve <: Exception
    status::MOI.TerminationStatusCode
    reason::String
end
struct UnsupportedChild <: Exception
    reason::String
end
Base.showerror(io::IO, e::UnsupportedChild) = print(io, e.reason)

const ACCEPTED_CHILD_STATUSES = Set((MOI.OPTIMAL, MOI.LOCALLY_SOLVED,
    MOI.ALMOST_OPTIMAL, MOI.ALMOST_LOCALLY_SOLVED, MOI.TIME_LIMIT,
    MOI.ITERATION_LIMIT, MOI.NODE_LIMIT, MOI.SOLUTION_LIMIT, MOI.MEMORY_LIMIT,
    MOI.OBJECTIVE_LIMIT, MOI.NORM_LIMIT, MOI.OTHER_LIMIT, MOI.SLOW_PROGRESS))

mutable struct SolveState
    state::Union{Vector{Int},Nothing}
    energy::Union{Float64,Nothing}
    evaluations::Int
    improvements::Int
    deadline::Union{Float64,Nothing}
    data::Dict{String,Any}
end

function check_time(opt, ctx, phase)
    opt.checkpoint(phase)
    if ctx.deadline !== nothing && opt.clock() >= ctx.deadline
        ctx.data["parent_overrun_sec"] = max(0.0, opt.clock() - ctx.deadline)
        throw(StopSolve(MOI.TIME_LIMIT, "parent_time_limit"))
    end
    return nothing
end
function reserve_evaluation!(opt, ctx)
    ctx.evaluations < opt.options[:max_candidate_evaluations] ||
        throw(StopSolve(MOI.ITERATION_LIMIT, "max_candidate_evaluations"))
    ctx.evaluations += 1
end
valid_value(x, domain) = x isa Real && isfinite(x) &&
    (domain === QUBOTools.BoolDomain ? x == 0 || x == 1 : x == -1 || x == 1)
better(x, y, sense) = sense === QUBOTools.Min ? x < y : x > y

# Independent of the child energy and of fixing/lifting helpers. Sorted scalar
# accumulation gives a stable summation order for all normal-form storage types.
function full_energy(state, linear, quadratic, scale, offset)
    scale == 0 && return 0.0 # finite input validation precedes this shortcut
    value = offset
    for (i, coefficient) in linear
        value += coefficient * state[i]
    end
    for ((i, j), coefficient) in quadratic
        value += coefficient * state[i] * state[j]
    end
    value *= scale
    isfinite(value) || error("non-finite full objective energy")
    return value
end

function snapshot(model)
    n = QUBOTools.dimension(model)
    labels = [QUBOTools.variable(model, i) for i in 1:n]
    length(unique(labels)) == n || error("duplicate model labels")
    all(QUBOTools.index(model, label) == i for (i, label) in enumerate(labels)) || error("inconsistent label/index map")
    domain, sense = QUBOTools.domain(model), QUBOTools.sense(model)
    domain in (QUBOTools.BoolDomain, QUBOTools.SpinDomain) || error("unsupported model domain")
    linear = sort!(collect(QUBOTools.linear_terms(model)); by=first)
    quadratic = sort!(collect(QUBOTools.quadratic_terms(model)); by=first)
    scale, offset = Float64(QUBOTools.scale(model)), Float64(QUBOTools.offset(model))
    isfinite(scale) && isfinite(offset) || error("non-finite scale or offset")
    all(isfinite(last(t)) && 1 <= first(t) <= n for t in linear) || error("invalid linear coefficients/indices")
    all(isfinite(last(t)) && 1 <= first(t)[1] < first(t)[2] <= n for t in quadratic) || error("invalid quadratic coefficients/indices")
    # QUBOTools normal forms have already normalized diagonals into their domain.
    starts = [QUBOTools.start(model, i) for i in 1:n]
    state = [x === nothing ? (domain === QUBOTools.BoolDomain ? 0 : -1) : x for x in starts]
    all(valid_value(x, domain) for x in state) || error("invalid specified initial assignment")
    constant = scale == 0 || (all(iszero(last(t)) for t in linear) && all(iszero(last(t)) for t in quadratic))
    return (; n, labels, domain, sense, linear, quadratic, scale, offset, state=Int.(state), constant)
end

function child_model(snap)
    source = MOI.Utilities.UniversalFallback(MOI.Utilities.Model{Float64}())
    variables = MOI.add_variables(source, snap.n)
    for v in variables
        MOI.add_constraint(source, v, snap.domain === QUBOTools.BoolDomain ? MOI.ZeroOne() : QUBODrivers.Spin())
    end
    affine = [MOI.ScalarAffineTerm(snap.scale * c, variables[i]) for (i,c) in snap.linear]
    quadratic = [MOI.ScalarQuadraticTerm(snap.scale * c, variables[i], variables[j]) for ((i,j),c) in snap.quadratic]
    constant = snap.scale * snap.offset
    all(isfinite(t.coefficient) for t in affine) && all(isfinite(t.coefficient) for t in quadratic) && isfinite(constant) ||
        error("non-finite scaled child coefficients")
    MOI.set(source, MOI.ObjectiveSense(), snap.sense === QUBOTools.Min ? MOI.MIN_SENSE : MOI.MAX_SENSE)
    MOI.set(source, MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{Float64}}(),
        MOI.ScalarQuadraticFunction(quadratic, affine, constant))
    return source, variables
end

function whole_model!(opt, ctx, snap)
    check_time(opt, ctx, :before_factory)
    opt.options[:max_child_calls] > 0 || throw(StopSolve(MOI.ITERATION_LIMIT, "max_child_calls"))
    ctx.evaluations < opt.options[:max_candidate_evaluations] ||
        throw(StopSolve(MOI.ITERATION_LIMIT, "max_candidate_evaluations"))
    call = Dict{String,Any}("attempt"=>1, "selected_indices"=>collect(1:snap.n),
        "seed"=>nothing, "seed_supported"=>nothing, "public_status"=>nothing,
        "valid_results"=>0, "invalid_results"=>0, "reported_multiplicities"=>Any[],
        "physical_reads"=>nothing, "physical_reads_meaning"=>"unknown; enumeration is not hardware reads",
        "exact"=>false, "time_limit_supported"=>nothing, "time_limit_enforced"=>false)
    push!(ctx.data["calls"], call)
    ctx.data["attempted_calls"] = 1 # reserve before the factory, including failures
    child = opt.options[:child_optimizer]()
    child isa MOI.AbstractOptimizer || throw(UnsupportedChild("factory must return an MOI optimizer"))
    MOI.is_empty(child) || throw(UnsupportedChild("factory must return an empty optimizer"))
    haskey(opt.used_children, child) && throw(UnsupportedChild("factory reused a live child optimizer"))
    opt.used_children[child] = nothing
    domain_set = snap.domain === QUBOTools.BoolDomain ? MOI.ZeroOne : QUBODrivers.Spin
    MOI.supports_constraint(child, VI, domain_set) &&
        MOI.supports(child, MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{Float64}}()) &&
        MOI.supports(child, MOI.ObjectiveSense()) || throw(UnsupportedChild("child must support the original domain, sense and Float64 quadratic objective"))
    source, variables = child_model(snap)
    map = MOI.copy_to(child, source)
    mapped = [map[v] for v in variables]
    length(unique(mapped)) == snap.n && Set(mapped) == Set(MOI.get(child, MOI.ListOfVariableIndices())) || error("inconsistent copied child index map")
    call["source_to_child"] = [v.value for v in mapped]
    seed = opt.options[:seed]
    supported = MOI.supports(child, QUBODrivers.RandomSeed())
    call["seed_supported"] = supported
    if seed !== nothing
        call["seed"] = Int(mod(big(seed), big(2)^31-1))
        supported && MOI.set(child, QUBODrivers.RandomSeed(), call["seed"])
    end
    check_time(opt, ctx, :before_child)
    time_supported = MOI.supports(child, MOI.TimeLimitSec())
    call["time_limit_supported"] = time_supported
    call["time_limit_enforced"] = child isa QUBODrivers.AbstractSampler && QUBODrivers.enforces_time_limit(child)
    limits = Any[opt.options[:child_time_limit_sec]]
    ctx.deadline !== nothing && push!(limits, max(0.0, ctx.deadline - opt.clock()))
    time_supported && push!(limits, MOI.get(child, MOI.TimeLimitSec()))
    filter!(!isnothing, limits)
    all(x isa Real && isfinite(x) && x >= 0 for x in limits) || throw(UnsupportedChild("invalid factory-configured child time limit"))
    effective_limit = isempty(limits) ? nothing : minimum(limits)
    call["effective_time_limit_sec"] = effective_limit
    if time_supported && effective_limit !== nothing
        MOI.set(child, MOI.TimeLimitSec(), effective_limit)
    end
    check_time(opt, ctx, :dispatch)
    execution_start = time_ns()
    try
        MOI.optimize!(child)
    finally
        ctx.data["child_execution_sec"] += (time_ns() - execution_start) / 1e9
    end
    status = MOI.get(child, MOI.TerminationStatus())
    call["public_status"] = string(status)
    status === MOI.INTERRUPTED && throw(StopSolve(MOI.INTERRUPTED, "child_interrupted"))
    status in ACCEPTED_CHILD_STATUSES || error("failure-class child status: $status")
    count = MOI.get(child, MOI.ResultCount())
    count isa Integer && !(count isa Bool) && count > 0 || error("child returned no valid results")
    call["reported_results"] = count
    check_time(opt, ctx, :after_child)
    best_state, best_energy = nothing, nothing
    for row in 1:count
        check_time(opt, ctx, :before_row)
        ctx.evaluations < opt.options[:max_candidate_evaluations] || begin
            ctx.data["incomplete_scan"] = true
            throw(StopSolve(MOI.ITERATION_LIMIT, "max_candidate_evaluations"))
        end
        try
            MOI.get(child, MOI.PrimalStatus(row)) === MOI.FEASIBLE_POINT || error("child row $row is not a feasible point")
            raw = [MOI.get(child, MOI.VariablePrimal(row), v) for v in mapped]
            all(valid_value(x, snap.domain) for x in raw) || error("child row $row has malformed/non-finite/wrong-domain values")
            reported = MOI.get(child, MOI.ObjectiveValue(row))
            reported isa Real && isfinite(reported) || error("child row $row reports non-finite energy")
            candidate = Int.(raw)
            reserve_evaluation!(opt, ctx)
            energy = full_energy(candidate, snap.linear, snap.quadratic, snap.scale, snap.offset)
            opt.checkpoint(:reconstruct)
            check_time(opt, ctx, :after_row)
            call["valid_results"] += 1
            multiplicity = child isa QUBODrivers.AbstractSampler ? QUBOTools.reads(child, row) : nothing
            push!(call["reported_multiplicities"], multiplicity)
            if best_energy === nothing || better(energy, best_energy, snap.sense) || (energy == best_energy && isless(Tuple(candidate), Tuple(best_state)))
                best_state, best_energy = candidate, energy
            end
        catch err
            if !(err isa InterruptException || err isa StopSolve)
                call["invalid_results"] += 1
            end
            rethrow()
        end
    end
    # Allow scalar summation roundoff in the certificate consistency check.
    # Incumbent replacement below remains strictly improving.
    if status === MOI.OPTIMAL && better(ctx.energy, best_energy, snap.sense) &&
        !isapprox(ctx.energy, best_energy; atol=1e-12, rtol=1e-12)
        error("child OPTIMAL contradicts independently evaluated initial incumbent")
    end
    # Commit only after the complete call is validated; interrupted/malformed scans
    # never attach a partial candidate or an incomplete optimality certificate.
    check_time(opt, ctx, :before_commit)
    if better(best_energy, ctx.energy, snap.sense)
        ctx.state, ctx.energy = best_state, best_energy
        ctx.improvements += 1
    end
    ctx.data["completed_calls"] = 1
    call["exact"] = status === MOI.OPTIMAL
    opt.termination = status
    ctx.data["stop_reason"] = "whole_model_complete"
    return nothing
end

function QUBODrivers.sample(opt::Optimizer)
    wall_start, start = time_ns(), opt.clock()
    invalidate!(opt)
    opt.invocation += 1
    data = Dict{String,Any}("schema_version"=>1, "strategy"=>"whole_model",
        "invocation"=>opt.invocation, "attempted_calls"=>0, "completed_calls"=>0,
        "started_sweeps"=>0, "completed_sweeps"=>0, "stagnation"=>0,
        "calls"=>Any[], "incomplete_scan"=>false, "parent_overrun_sec"=>0.0,
        "child_execution_sec"=>0.0, "time_limit_enforced"=>false,
        "configured_caps"=>Dict(String(k)=>v for (k,v) in opt.options if k !== :child_optimizer))
    limit = MOI.get(opt, MOI.TimeLimitSec())
    ctx = SolveState(nothing, nothing, 0, 0, limit === nothing ? nothing : start + limit, data)
    try
        for (key, value) in opt.options
            try
                validate_option(key, value)
            catch err
                err isa ArgumentError || rethrow()
                throw(UnsupportedChild(sprint(showerror, err)))
            end
        end
        opt.options[:child_optimizer] !== nothing && opt.options[:max_variables] !== nothing ||
            throw(UnsupportedChild("child_optimizer and max_variables are required before solving"))
        check_time(opt, ctx, :prepare)
        snap = snapshot(QUBOTools.backend(opt))
        data["dimension"] = snap.n
        data["labels"] = copy(snap.labels)
        data["label_to_original"] = Dict(label=>i for (i,label) in enumerate(snap.labels))
        data["original_to_reduced"] = collect(1:snap.n)
        data["domain"], data["sense"] = string(snap.domain), string(snap.sense)
        data["scale"], data["offset"] = snap.scale, snap.offset
        check_time(opt, ctx, :initial)
        reserve_evaluation!(opt, ctx)
        energy = full_energy(snap.state, snap.linear, snap.quadratic, snap.scale, snap.offset)
        check_time(opt, ctx, :initial_commit)
        ctx.state, ctx.energy = snap.state, energy
        if snap.constant
            opt.termination = MOI.OPTIMAL
            data["stop_reason"] = "constant_objective"
        elseif snap.n > opt.options[:max_variables]
            throw(UnsupportedChild("nonconstant model has $(snap.n) free logical variables, exceeding budget $(opt.options[:max_variables]); components and sweeps are not implemented"))
        else
            whole_model!(opt, ctx, snap)
        end
    catch err
        if err isa InterruptException
            opt.termination = MOI.INTERRUPTED
            data["stop_reason"] = "interrupt_exception"
        elseif err isa StopSolve
            opt.termination = err.status
            data["stop_reason"] = err.reason
        elseif err isa UnsupportedChild
            opt.termination = MOI.INVALID_OPTION
            data["stop_reason"] = "invalid_option"
            data["diagnostic"] = sprint(showerror, err)
        else
            opt.termination = MOI.OTHER_ERROR
            data["stop_reason"] = "execution_failure"
            data["diagnostic"] = sprint(showerror, err)
        end
    end
    data["candidate_evaluations"] = ctx.evaluations
    data["accepted_improvements"] = ctx.improvements
    data["emitted_multiplicity"] = ctx.state === nothing ? 0 : 1
    data["incumbent_energy"] = ctx.energy
    if data["attempted_calls"] > data["completed_calls"]
        data["incomplete_scan"] = true
    end
    effective = (time_ns() - wall_start) / 1e9
    data["parent_processing_sec"] = max(0.0, effective - data["child_execution_sec"])
    metadata = Dict{String,Any}("origin"=>"QUBODecomposition.jl",
        "algorithm"=>Dict{String,Any}("name"=>"whole_model"),
        "backend"=>Dict{String,Any}("name"=>"QUBODecomposition", "version"=>PACKAGE_VERSION),
        "status"=>string(opt.termination), "termination_status"=>opt.termination,
        "reads"=>Dict{String,Any}("number_of_reads"=>ctx.evaluations,
            "final_number_of_reads"=>ctx.state === nothing ? 0 : 1,
            "meaning"=>"independently evaluated full candidates; constructed output multiplicity one"),
        "seeds"=>Dict{String,Any}("sampler"=>opt.options[:seed]),
        "time"=>Dict{String,Any}("effective"=>effective), "decomposition"=>data)
    samples = ctx.state === nothing ? QUBOTools.Sample{Float64,Int}[] :
        [QUBOTools.Sample{Float64,Int}(ctx.state, ctx.energy, 1)]
    result = QUBOTools.SampleSet{Float64,Int}(samples; metadata,
        sense=QUBOTools.sense(opt), domain=QUBOTools.domain(opt))
    effective = (time_ns() - wall_start) / 1e9
    metadata["time"]["effective"] = effective
    data["parent_processing_sec"] = max(0.0, effective - data["child_execution_sec"])
    return result
end

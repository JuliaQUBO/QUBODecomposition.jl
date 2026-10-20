# SPDX-License-Identifier: MPL-2.0
const DEFAULTS = Dict{Symbol,Any}(
    :child_optimizer => nothing, :max_variables => nothing,
    :strategy => :components_then_sweeps, :selection => :strongest_edge,
    :partition_plan => nothing, :coarse_groups => nothing, :component_executor => nothing,
    :sample_pool => nothing, :fixing_threshold => 1.0, :max_fixings => 256, :max_pool_size => 256,
    :batch_size => 8, :repair => true,
    :consensus_plan => nothing, :consensus_iterations => 16,
    :consensus_step => 1.0, :consensus_multiplier_limit => 1.0e6,
    :consensus_stagnation => 4, :consensus_history_limit => 16,
    :separator => Int[], :max_separator_size => 8, :separator_pruning => false,
    :max_sweeps => 20, :max_child_calls => 1000,
    :max_candidate_evaluations => 100_000, :stagnation_sweeps => 2,
    :child_time_limit_sec => nothing, :absolute_deadline_sec => nothing, :seed => nothing,
    :preprocessing => :off, :max_work => typemax(Int), :child_work_bound => nothing,
    :preprocessing_max_work => typemax(Int), :preprocessing_max_deductions => typemax(Int),
    :preprocessing_max_exact_work => typemax(Int),
)

"""
    Optimizer(; child_optimizer=nothing, max_variables=nothing, kwargs...)

A composite sampler with serial defaults, whole-model dispatch for fitting inputs,
independent-component solves and bounded conditioned neighborhood sweeps.
The default strategy is `:components_then_sweeps`; `:components` rejects oversized
components and `:whole_model` rejects oversized nonconstant inputs.
Opt into exhaustive conditioning with `strategy=:separator`, `separator=[...]`
in original free-variable indices, or `separator=:articulation` for automatic
single-articulation discovery, and `max_separator_size=8` (hard ceiling 16).
Neighborhood selection defaults to `:strongest_edge`; opt into state-aware
blocks with `:single_flip_gain`, multi-hop neighborhoods with `:bfs`, or
seeded permutation blocks with `:random_blocks` via the `selection` option.
Use `selection=:partition` with `partition_plan` as an owned vector of blocks
or a callback `(indices, adjacency, max_variables) -> blocks`.
Use `strategy=:frozen_batch` with `selection=:strongest_edge` or `:bfs`,
`batch_size=8` (1:64) and `repair=true` for transactional unweighted voting.
Use `strategy=:sample_fixing` with an explicit labelled `sample_pool` for bounded
unary majority fixing and original-space incumbent retention; see the sample-fixing manual.
Use `strategy=:coarse` with `coarse_groups=[[1,2],[3,4]]` for one bounded
block-orientation proposal from the frozen complete incumbent.
Use `strategy=:consensus` with `consensus_plan=[[1,2],[2,3]]` for bounded
serial overlapping-block Lagrangian coordination; see the consensus manual.
Use `component_executor=SequentialComponentExecutor()` or
`ProcessComponentExecutor(pool; max_inflight=2)` with `strategy=:components` for
the frozen independent-component job path, bypassing the whole-model shortcut.
Use `preprocessing=:dominance` for opt-in root certification with QUBOPreprocessing.
It supports the serial whole-model/components/sweeps routes with automatic
selection; explicit index plans and advanced strategies require separate mappings.
`max_work` bounds structural passes plus declared child reservations, separately
from candidate and call caps; see the certified root preprocessing manual.
The zero-argument constructor permits configuration with raw MOI attributes.
See the package manual's Construction and configuration, Results and statuses,
and Budgets, timing, seeds and reads pages for validation and metadata contracts.
"""
mutable struct Optimizer <: QUBODrivers.AbstractSampler{Float64}
    storage::ModelStorage{Float64}
    input::Any
    options::Dict{Symbol,Any}
    termination::MOI.TerminationStatusCode
    clock::Function
    checkpoint::Function
    used_children::WeakKeyDict{Any,Nothing}
    invocation::Int
    preprocessing_result::Any
end

function Optimizer(; kwargs...)
    storage = ModelStorage()
    opt = Optimizer(storage, QUBOTools.backend(storage), deepcopy(DEFAULTS),
        MOI.OPTIMIZE_NOT_CALLED, () -> time_ns() / 1e9, _ -> nothing,
        WeakKeyDict{Any,Nothing}(), 0, nothing)
    for (key, value) in kwargs
        MOI.set(opt, MOI.RawOptimizerAttribute(String(key)), value)
    end
    return opt
end

QUBOTools.backend(opt::Optimizer) = opt.input
MOI.get(::Optimizer, ::MOI.SolverName) = "QUBODecomposition"
MOI.get(::Optimizer, ::MOI.SolverVersion) = PACKAGE_VERSION
function MOI.get(opt::Optimizer, ::MOI.TerminationStatus)
    # The framework attaches only after callback validation. A failed callback
    # must not expose sample()'s provisional status from an unattached invocation.
    data = get(QUBOTools.metadata(QUBOTools.solution(opt)), "decomposition", nothing)
    attached = data isa AbstractDict && get(data, "invocation", nothing) == opt.invocation
    return attached ? opt.termination : MOI.OPTIMIZE_NOT_CALLED
end
MOI.get(opt::Optimizer, ::MOI.RawSolver) = opt
QUBODrivers.supports_seed(::Type{Optimizer}) = true
QUBODrivers.honors_final_reads(::Type{Optimizer}) = false
QUBODrivers.enforces_time_limit(::Type{Optimizer}) = false

function invalidate!(opt::Optimizer)
    opt.preprocessing_result = nothing
    opt.termination = MOI.OPTIMIZE_NOT_CALLED
    QUBOTools.attach!(opt, QUBOTools.SampleSet{Float64,Int}(;
        sense=QUBOTools.sense(opt), domain=QUBOTools.domain(opt)))
    return nothing
end

function QUBODrivers.set_model!(opt::Optimizer, model::QUBOTools.Model{V,Float64,Int}) where {V}
    MOI.empty!(opt.storage)
    opt.input = copy(model)
    if V === VI
        QUBODrivers.set_model!(opt.storage, opt.input)
    end
    invalidate!(opt)
    return opt.input
end

function MOI.empty!(opt::Optimizer)
    MOI.empty!(opt.storage)
    opt.input = QUBOTools.backend(opt.storage)
    invalidate!(opt)
    return opt
end
MOI.is_empty(opt::Optimizer) = isempty(QUBOTools.backend(opt)) && MOI.is_empty(opt.storage)

function MOI.copy_to(opt::Optimizer, src::MOI.ModelLike)
    MOI.empty!(opt)
    try
        map = MOI.copy_to(opt.storage, src)
        opt.input = QUBOTools.backend(opt.storage)
        invalidate!(opt)
        return map
    catch
        MOI.empty!(opt)
        rethrow()
    end
end

# Forward public MOI model queries to generated storage, including fixed variables.
for A in (MOI.NumberOfVariables, MOI.ListOfVariableIndices, MOI.ListOfConstraintTypesPresent)
    @eval MOI.get(opt::Optimizer, attr::$A) = MOI.get(opt.storage, attr)
end
for S in (MOI.ZeroOne, QUBODrivers.Spin)
    @eval begin
        MOI.get(opt::Optimizer, attr::MOI.NumberOfConstraints{VI,$S}) = MOI.get(opt.storage, attr)
        MOI.get(opt::Optimizer, attr::MOI.ListOfConstraintIndices{VI,$S}) = MOI.get(opt.storage, attr)
        MOI.get(opt::Optimizer, attr::MOI.ConstraintFunction, ci::MOI.ConstraintIndex{VI,$S}) = MOI.get(opt.storage, attr, ci)
        MOI.get(opt::Optimizer, attr::MOI.ConstraintSet, ci::MOI.ConstraintIndex{VI,$S}) = MOI.get(opt.storage, attr, ci)
        MOI.is_valid(opt::Optimizer, ci::MOI.ConstraintIndex{VI,$S}) = MOI.is_valid(opt.storage, ci)
    end
end
MOI.get(opt::Optimizer, attr::MOI.NumberOfConstraints{VI,MOI.EqualTo{T}}) where {T<:Real} = MOI.get(opt.storage, attr)
MOI.get(opt::Optimizer, attr::MOI.ListOfConstraintIndices{VI,MOI.EqualTo{T}}) where {T<:Real} = MOI.get(opt.storage, attr)
MOI.get(opt::Optimizer, attr::MOI.ConstraintFunction, ci::MOI.ConstraintIndex{VI,MOI.EqualTo{T}}) where {T<:Real} = MOI.get(opt.storage, attr, ci)
MOI.get(opt::Optimizer, attr::MOI.ConstraintSet, ci::MOI.ConstraintIndex{VI,MOI.EqualTo{T}}) where {T<:Real} = MOI.get(opt.storage, attr, ci)
MOI.is_valid(opt::Optimizer, ci::MOI.ConstraintIndex{VI,MOI.EqualTo{T}}) where {T<:Real} = MOI.is_valid(opt.storage, ci)
MOI.get(opt::Optimizer, a::MOI.VariablePrimal, v::VI) = MOI.get(opt.storage, a, v)
MOI.get(opt::Optimizer, a::MOI.VariablePrimalStart, v::VI) = MOI.get(opt.storage, a, v)
function MOI.set(opt::Optimizer, a::MOI.VariablePrimalStart, v::VI, value)
    invalidate!(opt)
    return MOI.set(opt.storage, a, v, value)
end
MOI.supports(::Optimizer, ::MOI.VariablePrimalStart, ::Type{VI}) = true

function validate_option(key::Symbol, value)
    if key === :preprocessing
        value in (:off, :dominance) || throw(ArgumentError("preprocessing must be :off or :dominance"))
    elseif key in (:max_work, :preprocessing_max_work, :preprocessing_max_deductions, :preprocessing_max_exact_work)
        value isa Integer && !(value isa Bool) && 0 <= value <= typemax(Int) ||
            throw(ArgumentError("$key must be a nonnegative Int-sized integer, excluding Bool"))
    elseif key === :child_work_bound
        value === nothing || value isa Function || throw(ArgumentError("child_work_bound must be a function or nothing"))
    elseif key === :sample_pool
        validate_sample_pool_option(value)
    elseif key === :fixing_threshold
        value isa Real && !(value isa Bool) && isfinite(value) && 0.5 < value <= 1 &&
            isfinite(Float64(value)) && 0.5 < Float64(value) <= 1 ||
            throw(ArgumentError("fixing_threshold must be finite in (1/2,1] in Float64"))
    elseif key in (:max_fixings, :max_pool_size)
        minimum = key === :max_fixings ? 0 : 1
        value isa Integer && !(value isa Bool) && minimum <= value <= 256 ||
            throw(ArgumentError("$key must be an integer in $minimum:256, excluding Bool"))
    elseif key === :component_executor
        value === nothing || value isa AbstractComponentExecutor ||
            throw(ArgumentError("component_executor must be nothing or an AbstractComponentExecutor"))
    elseif key === :child_optimizer
        value === nothing || applicable(value) || applicable(value, ComponentJob((UInt128(0), 1, 1), (), (), (;), (), nothing, nothing, nothing, 0)) || throw(ArgumentError("child_optimizer must accept a ComponentJob or no arguments"))
    elseif key === :max_variables
        value === nothing || (value isa Integer && !(value isa Bool) && 0 < value <= typemax(Int)) ||
            throw(ArgumentError("max_variables must be a positive Int-sized integer, excluding Bool"))
    elseif key in (:max_sweeps, :max_child_calls, :max_candidate_evaluations, :stagnation_sweeps)
        minimum = key === :stagnation_sweeps ? 1 : 0
        value isa Integer && !(value isa Bool) && minimum <= value <= typemax(Int) ||
            throw(ArgumentError("$key must be an Int-sized integer >= $minimum, excluding Bool"))
    elseif key in (:consensus_iterations, :consensus_stagnation, :consensus_history_limit)
        value isa Integer && !(value isa Bool) && 1 <= value <= 10_000 ||
            throw(ArgumentError("$key must be an integer in 1:10000, excluding Bool"))
    elseif key in (:consensus_step, :consensus_multiplier_limit)
        value isa Real && !(value isa Bool) && isfinite(value) && value > 0 &&
            isfinite(Float64(value)) && Float64(value) > 0 ||
            throw(ArgumentError("$key must be finite and positive in Float64"))
    elseif key in (:consensus_plan, :coarse_groups)
        value === nothing || (value isa AbstractVector && all(b -> b isa AbstractVector &&
            all(i -> i isa Integer && !(i isa Bool) && 1 <= i <= typemax(Int), b), value)) ||
            throw(ArgumentError("$key must be nothing or a vector of index vectors"))
    elseif key === :batch_size
        value isa Integer && !(value isa Bool) && 1 <= value <= 64 ||
            throw(ArgumentError("batch_size must be an integer in 1:64, excluding Bool"))
    elseif key in (:repair, :separator_pruning)
        value isa Bool || throw(ArgumentError("$key must be Bool"))
    elseif key === :separator
        value === :articulation && return nothing
        value isa AbstractVector && all(i -> i isa Integer && !(i isa Bool) && 1 <= i <= typemax(Int), value) ||
            throw(ArgumentError("separator must be :articulation or a vector of positive Int-sized indices, excluding Bool"))
        length(unique(value)) == length(value) || throw(ArgumentError("separator indices must be unique"))
    elseif key === :partition_plan
        value === nothing || value isa AbstractVector ||
            applicable(value, Int[], Dict{Int,Float64}[], 1) ||
            throw(ArgumentError("partition_plan must be nothing, a vector of blocks or a three-argument callback"))
        if value isa AbstractVector
            all(b -> b isa AbstractVector && all(i -> i isa Integer && !(i isa Bool) && 1 <= i <= typemax(Int), b), value) ||
                throw(ArgumentError("partition blocks must be vectors of positive Int-sized indices, excluding Bool"))
        end
    elseif key === :max_separator_size
        value isa Integer && !(value isa Bool) && 0 <= value <= 16 ||
            throw(ArgumentError("max_separator_size must be an integer in 0:16, excluding Bool"))
    elseif key === :strategy
        value in (:whole_model, :components, :components_then_sweeps, :separator, :frozen_batch, :consensus, :coarse, :sample_fixing) ||
            throw(ArgumentError("strategy must be :whole_model, :components, :components_then_sweeps or :separator or :frozen_batch or :consensus or :coarse or :sample_fixing"))
    elseif key === :selection
        value in (:strongest_edge, :single_flip_gain, :bfs, :random_blocks, :partition) ||
            throw(ArgumentError("selection must be :strongest_edge, :single_flip_gain, :bfs, :random_blocks or :partition"))
    elseif key in (:child_time_limit_sec, :time_limit_sec, :absolute_deadline_sec)
        value === nothing || (value isa Real && !(value isa Bool) && isfinite(value) && value >= 0 && isfinite(Float64(value))) ||
            throw(ArgumentError("$key must be nothing or finite nonnegative seconds"))
    elseif key === :seed
        value === nothing || (value isa Integer && !(value isa Bool) && 0 <= value <= 2^31-2) ||
            throw(ArgumentError("seed must be nothing or an integer in 0:2^31-2, excluding Bool"))
    else
        throw(MOI.UnsupportedAttribute(MOI.RawOptimizerAttribute(String(key))))
    end
    return nothing
end

function MOI.set(opt::Optimizer, attr::MOI.RawOptimizerAttribute, value)
    invalidate!(opt)
    key = Symbol(attr.name)
    if haskey(DEFAULTS, key)
        validate_option(key, value)
        opt.options[key] = key === :sample_pool ? own_sample_pool(value) :
            key === :fixing_threshold ? Float64(value) :
            key in (:partition_plan, :consensus_plan, :coarse_groups) && value isa AbstractVector ? [Int.(b) for b in value] :
            key === :separator && value isa AbstractVector ? Int.(value) :
            key === :absolute_deadline_sec && value !== nothing ? Float64(value) : value
    elseif attr.name in ("moi/name", "moi/silent", "moi/numberofthreads", "final_num_reads", "post_sample_callback", "post_sample_transform", "fixed_variables", "moi_variables")
        if attr.name === "post_sample_transform" && value !== false
            throw(ArgumentError("post-sample transformations are deferred; PostSampleTransform must be false"))
        end
        MOI.set(opt.storage, attr, value)
    elseif attr.name === "moi/timelimitsec"
        validate_option(:time_limit_sec, value)
        opt.options[:time_limit_sec] = value === nothing ? nothing : Float64(value)
    else
        throw(MOI.UnsupportedAttribute(attr))
    end
    return nothing
end
function MOI.get(opt::Optimizer, attr::MOI.RawOptimizerAttribute)
    attr.name === "preprocessing_result" && return opt.preprocessing_result
    key = Symbol(attr.name)
    haskey(DEFAULTS, key) && return key in (:separator, :partition_plan, :consensus_plan, :coarse_groups, :sample_pool) && opt.options[key] !== nothing && (opt.options[key] isa AbstractVector || key === :sample_pool) ? deepcopy(opt.options[key]) : opt.options[key]
    attr.name === "moi/timelimitsec" && return get(opt.options, :time_limit_sec, nothing)
    attr.name in ("fixed_variables", "moi_variables") && return MOI.get(opt.storage, attr)
    MOI.supports(opt.storage, attr) && return MOI.get(opt.storage, attr)
    throw(MOI.UnsupportedAttribute(attr))
end
MOI.supports(opt::Optimizer, a::MOI.RawOptimizerAttribute) = a.name == "preprocessing_result" ? false :
    haskey(DEFAULTS, Symbol(a.name)) || a.name in ("moi/timelimitsec", "fixed_variables", "moi_variables") || MOI.supports(opt.storage, a)
MOI.get(opt::Optimizer, ::QUBODrivers.RawSamplerAttribute{K}) where {K} = MOI.get(opt, MOI.RawOptimizerAttribute(String(K)))
MOI.set(opt::Optimizer, ::QUBODrivers.RawSamplerAttribute{K}, value) where {K} = MOI.set(opt, MOI.RawOptimizerAttribute(String(K)), value)
MOI.supports(opt::Optimizer, ::QUBODrivers.RawSamplerAttribute{K}) where {K} = MOI.supports(opt, MOI.RawOptimizerAttribute(String(K)))
for (A, key) in ((MOI.TimeLimitSec, "moi/timelimitsec"), (MOI.Name, "moi/name"),
    (MOI.Silent, "moi/silent"), (MOI.NumberOfThreads, "moi/numberofthreads"),
    (QUBODrivers.RandomSeed, "seed"), (QUBODrivers.FinalNumberOfReads, "final_num_reads"),
    (QUBODrivers.PostSampleCallback, "post_sample_callback"), (QUBODrivers.PostSampleTransform, "post_sample_transform"))
    @eval begin
        MOI.get(opt::Optimizer, ::$A) = MOI.get(opt, MOI.RawOptimizerAttribute($key))
        MOI.set(opt::Optimizer, ::$A, value) = MOI.set(opt, MOI.RawOptimizerAttribute($key), value)
        MOI.supports(::Optimizer, ::$A) = true
    end
end

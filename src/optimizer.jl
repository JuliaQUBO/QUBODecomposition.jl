# SPDX-License-Identifier: MPL-2.0
const DEFAULTS = Dict{Symbol,Any}(
    :child_optimizer => nothing, :max_variables => nothing,
    :strategy => :components_then_sweeps, :selection => :strongest_edge,
    :separator => Int[], :max_separator_size => 8,
    :max_sweeps => 20, :max_child_calls => 1000,
    :max_candidate_evaluations => 100_000, :stagnation_sweeps => 2,
    :child_time_limit_sec => nothing, :seed => nothing,
)

"""
    Optimizer(; child_optimizer=nothing, max_variables=nothing, kwargs...)

A serial composite sampler with whole-model dispatch for fitting inputs,
independent-component solves and bounded conditioned neighborhood sweeps.
The default strategy is `:components_then_sweeps`; `:components` rejects oversized
components and `:whole_model` rejects oversized nonconstant inputs.
Opt into exhaustive conditioning with `strategy=:separator`, `separator=[...]`
in original free-variable indices, or `separator=:articulation` for automatic
single-articulation discovery, and `max_separator_size=8` (hard ceiling 16).
Neighborhood selection defaults to `:strongest_edge`; opt into state-aware
blocks with `:single_flip_gain`, multi-hop neighborhoods with `:bfs`, or
seeded permutation blocks with `:random_blocks` via the `selection` option.
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
end

function Optimizer(; kwargs...)
    storage = ModelStorage()
    opt = Optimizer(storage, QUBOTools.backend(storage), copy(DEFAULTS),
        MOI.OPTIMIZE_NOT_CALLED, () -> time_ns() / 1e9, _ -> nothing,
        WeakKeyDict{Any,Nothing}(), 0)
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
    if key === :child_optimizer
        value === nothing || applicable(value) || throw(ArgumentError("child_optimizer must be a zero-argument factory"))
    elseif key === :max_variables
        value === nothing || (value isa Integer && !(value isa Bool) && 0 < value <= typemax(Int)) ||
            throw(ArgumentError("max_variables must be a positive Int-sized integer, excluding Bool"))
    elseif key in (:max_sweeps, :max_child_calls, :max_candidate_evaluations, :stagnation_sweeps)
        minimum = key === :stagnation_sweeps ? 1 : 0
        value isa Integer && !(value isa Bool) && minimum <= value <= typemax(Int) ||
            throw(ArgumentError("$key must be an Int-sized integer >= $minimum, excluding Bool"))
    elseif key === :separator
        value === :articulation && return nothing
        value isa AbstractVector && all(i -> i isa Integer && !(i isa Bool) && 1 <= i <= typemax(Int), value) ||
            throw(ArgumentError("separator must be :articulation or a vector of positive Int-sized indices, excluding Bool"))
        length(unique(value)) == length(value) || throw(ArgumentError("separator indices must be unique"))
    elseif key === :max_separator_size
        value isa Integer && !(value isa Bool) && 0 <= value <= 16 ||
            throw(ArgumentError("max_separator_size must be an integer in 0:16, excluding Bool"))
    elseif key === :strategy
        value in (:whole_model, :components, :components_then_sweeps, :separator) ||
            throw(ArgumentError("strategy must be :whole_model, :components, :components_then_sweeps or :separator"))
    elseif key === :selection
        value in (:strongest_edge, :single_flip_gain, :bfs, :random_blocks) ||
            throw(ArgumentError("selection must be :strongest_edge, :single_flip_gain, :bfs or :random_blocks"))
    elseif key in (:child_time_limit_sec, :time_limit_sec)
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
        opt.options[key] = key === :separator && value isa AbstractVector ? Int.(value) : value
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
    key = Symbol(attr.name)
    haskey(DEFAULTS, key) && return key === :separator && opt.options[key] isa AbstractVector ? copy(opt.options[key]) : opt.options[key]
    attr.name === "moi/timelimitsec" && return get(opt.options, :time_limit_sec, nothing)
    attr.name in ("fixed_variables", "moi_variables") && return MOI.get(opt.storage, attr)
    MOI.supports(opt.storage, attr) && return MOI.get(opt.storage, attr)
    throw(MOI.UnsupportedAttribute(attr))
end
MOI.supports(opt::Optimizer, a::MOI.RawOptimizerAttribute) = haskey(DEFAULTS, Symbol(a.name)) ||
    a.name in ("moi/timelimitsec", "fixed_variables", "moi_variables") || MOI.supports(opt.storage, a)
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

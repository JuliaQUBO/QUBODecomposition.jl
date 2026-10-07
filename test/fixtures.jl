const VI = MOI.VariableIndex
# SPDX-License-Identifier: MPL-2.0
# A controlled public MOI optimizer. Its coefficient evaluator instruments the
# child boundary; expected parent energies are derived separately in each test.
mutable struct FixtureChild <: MOI.AbstractOptimizer
    model::Any
    rows::Vector{Any}
    values::Vector{Float64}
    status::MOI.TerminationStatusCode
    scripted::Bool
    callback::Function
    seed_supported::Bool
    time_supported::Bool
    seed::Any
    limit::Any
    corrupt_map::Bool
    row_status::MOI.ResultStatusCode
    log::Vector{Any}
end
function FixtureChild(; rows=nothing, values=nothing, status=MOI.OPTIMAL,
    callback=_ -> nothing, seed_supported=true, time_supported=true, limit=nothing,
    corrupt_map=false, row_status=MOI.FEASIBLE_POINT, log=Any[])
    return FixtureChild(MOI.Utilities.UniversalFallback(MOI.Utilities.Model{Float64}()),
        rows === nothing ? Any[] : Any[rows...], values === nothing ? Float64[] : Float64[values...],
        status, rows !== nothing, callback, seed_supported, time_supported, nothing, limit,
        corrupt_map, row_status, log)
end
MOI.is_empty(c::FixtureChild) = MOI.is_empty(c.model)
MOI.supports_constraint(::FixtureChild, ::Type{VI}, ::Type{S}) where {S<:MOI.AbstractSet} = S in (MOI.ZeroOne, QUBODrivers.Spin)
MOI.supports(::FixtureChild, ::MOI.ObjectiveSense) = true
MOI.supports(::FixtureChild, ::MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{Float64}}) = true
MOI.supports(c::FixtureChild, ::MOI.TimeLimitSec) = c.time_supported
MOI.supports(c::FixtureChild, ::QUBODrivers.RandomSeed) = c.seed_supported
MOI.set(c::FixtureChild, ::MOI.TimeLimitSec, x) = (c.limit=x; nothing)
MOI.get(c::FixtureChild, ::MOI.TimeLimitSec) = c.limit
MOI.set(c::FixtureChild, ::QUBODrivers.RandomSeed, x) = (c.seed=x; nothing)
MOI.get(c::FixtureChild, ::MOI.ListOfVariableIndices) = MOI.get(c.model, MOI.ListOfVariableIndices())
MOI.get(c::FixtureChild, ::MOI.TerminationStatus) = c.status
MOI.get(c::FixtureChild, ::MOI.ResultCount) = length(c.rows)
MOI.get(c::FixtureChild, ::MOI.PrimalStatus) = c.row_status
MOI.get(c::FixtureChild, a::MOI.ObjectiveValue) = c.values[a.result_index]
MOI.get(c::FixtureChild, a::MOI.VariablePrimal, v::VI) = c.rows[a.result_index][v]

function MOI.copy_to(c::FixtureChild, src::MOI.ModelLike)
    map = MOI.Utilities.IndexMap()
    # Shift indices away from the source and deliberately reverse insertion order.
    unused = MOI.add_variables(c.model, 7)
    MOI.delete(c.model, unused)
    variables = MOI.get(src, MOI.ListOfVariableIndices())
    for v in reverse(variables)
        map[v] = MOI.add_variable(c.model)
    end
    for (F,S) in MOI.get(src, MOI.ListOfConstraintTypesPresent())
        for ci in MOI.get(src, MOI.ListOfConstraintIndices{F,S}())
            f = MOI.Utilities.map_indices(map, MOI.get(src, MOI.ConstraintFunction(), ci))
            map[ci] = MOI.add_constraint(c.model, f, MOI.get(src, MOI.ConstraintSet(), ci))
        end
    end
    f = MOI.get(src, MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{Float64}}())
    MOI.set(c.model, MOI.ObjectiveFunction{typeof(f)}(), MOI.Utilities.map_indices(map, f))
    MOI.set(c.model, MOI.ObjectiveSense(), MOI.get(src, MOI.ObjectiveSense()))
    if c.corrupt_map && length(variables) > 1
        map[variables[1]] = map[variables[2]]
    end
    push!(c.log, (; variables=[map[v].value for v in variables], objective=f))
    return map
end

function MOI.optimize!(c::FixtureChild)
    push!(c.log, (; seed=c.seed, limit=c.limit))
    c.callback(c)
    if c.scripted
        vars = sort(MOI.get(c.model, MOI.ListOfVariableIndices()); by=v -> -v.value)
        c.rows = Any[Dict(v=>row[i] for (i,v) in enumerate(vars) if i <= length(row)) for row in c.rows]
        isempty(c.values) && (c.values=fill(0.0, length(c.rows)))
        return nothing
    end
    vars = MOI.get(c.model, MOI.ListOfVariableIndices())
    spin = !isempty(MOI.get(c.model, MOI.ListOfConstraintIndices{VI,QUBODrivers.Spin}()))
    states = Iterators.product(fill(spin ? (-1,1) : (0,1), length(vars))...)
    f = MOI.get(c.model, MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{Float64}}())
    best, value = nothing, nothing
    sense = MOI.get(c.model, MOI.ObjectiveSense())
    for state in states
        x = Dict(v=>state[i] for (i,v) in enumerate(vars))
        energy = f.constant
        for t in f.affine_terms
            energy += t.coefficient*x[t.variable]
        end
        for t in f.quadratic_terms
            energy += t.coefficient*x[t.variable_1]*x[t.variable_2] / (t.variable_1==t.variable_2 ? 2 : 1)
        end
        if value === nothing || (sense===MOI.MIN_SENSE ? energy < value : energy > value)
            best,value=x,energy
        end
    end
    c.rows, c.values = Any[best], [value]
    return nothing
end

function direct_model(; labels=[:a,:b,:c,:isolate], domain=:bool, sense=:min, scale=2.0, offset=5.0)
    return QUBOTools.Model{eltype(labels),Float64,Int}(labels,
        [1,2,3], [-3.0,2.0,-1.0], [1,2], [2,3], [4.0,-2.0]; domain, sense, scale, offset)
end
function solve_model(model; child=() -> FixtureChild(), budget=QUBOTools.dimension(model)+1, kwargs...)
    opt=QUBODecomposition.Optimizer(; child_optimizer=child, max_variables=budget, kwargs...)
    QUBODrivers.set_model!(opt, model)
    MOI.optimize!(opt)
    return opt
end
const decomposition = opt -> QUBOTools.metadata(QUBOTools.solution(opt))["decomposition"]

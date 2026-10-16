# SPDX-License-Identifier: MPL-2.0
# Guard the actual public ExactSampler before dispatch; preserve every public
# backend status. This adapter neither enumerates nor upgrades certificates.
mutable struct SampleFixingExactChild <: MOI.AbstractOptimizer
    child::Any
    assignments::Base.RefValue{Int}
    dimensions::Vector{Int}
end
SampleFixingExactChild(work, dimensions) = SampleFixingExactChild(QUBODrivers.ExactSampler.Optimizer(),work,dimensions)
MOI.is_empty(c::SampleFixingExactChild) = MOI.is_empty(c.child)
MOI.supports_constraint(c::SampleFixingExactChild,::Type{MOI.VariableIndex},::Type{S}) where {S<:MOI.AbstractSet} =
    MOI.supports_constraint(c.child,MOI.VariableIndex,S)
for A in (MOI.ObjectiveSense,MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{Float64}},
    MOI.TimeLimitSec,QUBODrivers.RandomSeed)
    @eval MOI.supports(c::SampleFixingExactChild,a::$A) = MOI.supports(c.child,a)
end
for A in (MOI.ListOfVariableIndices,MOI.NumberOfVariables,MOI.TerminationStatus,
    MOI.ResultCount,MOI.PrimalStatus,MOI.ObjectiveValue,MOI.TimeLimitSec)
    @eval MOI.get(c::SampleFixingExactChild,a::$A) = MOI.get(c.child,a)
end
MOI.get(c::SampleFixingExactChild,a::MOI.VariablePrimal,v::MOI.VariableIndex) = MOI.get(c.child,a,v)
for A in (MOI.TimeLimitSec,QUBODrivers.RandomSeed)
    @eval MOI.set(c::SampleFixingExactChild,a::$A,v) = MOI.set(c.child,a,v)
end
MOI.copy_to(c::SampleFixingExactChild,source::MOI.ModelLike) = MOI.copy_to(c.child,source)
function MOI.optimize!(c::SampleFixingExactChild)
    n = MOI.get(c.child,MOI.NumberOfVariables())
    1 <= n <= 4 || error("sample-fixing comparison child must have one to four free variables")
    work = 1 << n
    c.assignments[] + work <= 512 || error("shared arm child-assignment allowance")
    c.assignments[] += work # failed calls remain charged
    push!(c.dimensions,n)
    MOI.optimize!(c.child)
    return nothing
end

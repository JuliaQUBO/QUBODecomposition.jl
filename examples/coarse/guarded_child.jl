# SPDX-License-Identifier: MPL-2.0
# Guard the actual public ExactSampler before dispatch; preserve every public
# backend status. This adapter neither enumerates nor upgrades certificates.
mutable struct GuardedExactChild <: MOI.AbstractOptimizer
    child::Any
    assignments::Base.RefValue{Int}
    dimensions::Vector{Int}
end
GuardedExactChild(work, dimensions) = GuardedExactChild(QUBODrivers.ExactSampler.Optimizer(),work,dimensions)
MOI.is_empty(c::GuardedExactChild) = MOI.is_empty(c.child)
MOI.supports_constraint(c::GuardedExactChild,F::Type,S::Type) = MOI.supports_constraint(c.child,F,S)
MOI.supports(c::GuardedExactChild,a::MOI.AbstractOptimizerAttribute) = MOI.supports(c.child,a)
MOI.supports(c::GuardedExactChild,a::MOI.AbstractModelAttribute) = MOI.supports(c.child,a)
MOI.get(c::GuardedExactChild,a::MOI.AbstractOptimizerAttribute) = MOI.get(c.child,a)
MOI.get(c::GuardedExactChild,a::MOI.AbstractModelAttribute) = MOI.get(c.child,a)
MOI.get(c::GuardedExactChild,a::MOI.AbstractVariableAttribute,v::MOI.VariableIndex) = MOI.get(c.child,a,v)
MOI.set(c::GuardedExactChild,a::MOI.AbstractOptimizerAttribute,v) = MOI.set(c.child,a,v)
MOI.set(c::GuardedExactChild,a::MOI.AbstractModelAttribute,v) = MOI.set(c.child,a,v)
MOI.copy_to(c::GuardedExactChild,source::MOI.ModelLike) = MOI.copy_to(c.child,source)
function MOI.optimize!(c::GuardedExactChild)
    n = MOI.get(c.child,MOI.NumberOfVariables())
    1 <= n <= 4 || error("comparison child must have one to four free variables")
    work = 1 << n
    c.assignments[] + work <= 512 || error("shared arm child-assignment allowance")
    c.assignments[] += work # failed calls remain charged
    push!(c.dimensions,n)
    MOI.optimize!(c.child)
    return nothing
end

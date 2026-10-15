# SPDX-License-Identifier: MPL-2.0
# A deliberately small, offline MOI child with an honest global status. It
# evaluates the dispatched Float64 coefficients exactly; this is not a status
# override for released ExactSampler. No new package dependency is required.
mutable struct BoundedExactChild <: MOI.AbstractOptimizer
    model::MOI.Utilities.UniversalFallback{MOI.Utilities.Model{Float64}}
    row::Dict{MOI.VariableIndex,Int}
    energy::Float64
    work::Base.RefValue{Int}
end
BoundedExactChild(work) = BoundedExactChild(
    MOI.Utilities.UniversalFallback(MOI.Utilities.Model{Float64}()),
    Dict{MOI.VariableIndex,Int}(),0.,work)
MOI.is_empty(c::BoundedExactChild)=MOI.is_empty(c.model)
MOI.supports_constraint(::BoundedExactChild,::Type{MOI.VariableIndex},::Type{S}) where {S<:MOI.AbstractSet}=S in (MOI.ZeroOne,QUBODrivers.Spin)
MOI.supports(::BoundedExactChild,::MOI.ObjectiveSense)=true
MOI.supports(::BoundedExactChild,::MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{Float64}})=true
MOI.supports(::BoundedExactChild,::MOI.TimeLimitSec)=false
MOI.supports(::BoundedExactChild,::QUBODrivers.RandomSeed)=false
MOI.copy_to(c::BoundedExactChild,source::MOI.ModelLike)=MOI.copy_to(c.model,source)
MOI.get(c::BoundedExactChild,::MOI.ListOfVariableIndices)=MOI.get(c.model,MOI.ListOfVariableIndices())
MOI.get(c::BoundedExactChild,::MOI.TerminationStatus)=isempty(c.row) ? MOI.OPTIMIZE_NOT_CALLED : MOI.OPTIMAL
MOI.get(c::BoundedExactChild,::MOI.ResultCount)=isempty(c.row) ? 0 : 1
MOI.get(::BoundedExactChild,::MOI.PrimalStatus)=MOI.FEASIBLE_POINT
MOI.get(c::BoundedExactChild,::MOI.VariablePrimal,v::MOI.VariableIndex)=c.row[v]
MOI.get(c::BoundedExactChild,::MOI.ObjectiveValue)=c.energy
function MOI.optimize!(c::BoundedExactChild)
    vars=MOI.get(c.model,MOI.ListOfVariableIndices())
    n=length(vars)
    1<=n<=4 || error("offline child requires one to four variables")
    c.work[]+(1<<n)<=1024 || error("aggregate child enumeration ceiling")
    c.work[]+=1<<n # reserve before enumeration
    f=MOI.get(c.model,MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{Float64}}())
    spin=!isempty(MOI.get(c.model,MOI.ListOfConstraintIndices{MOI.VariableIndex,QUBODrivers.Spin}()))
    minimize=MOI.get(c.model,MOI.ObjectiveSense())===MOI.MIN_SENSE
    best=nothing
    for state in Iterators.product(fill(spin ? (-1,1) : (0,1),n)...)
        x=Dict(v=>state[i] for (i,v) in enumerate(vars))
        value=Rational{BigInt}(f.constant)
        for t in f.affine_terms
            value+=Rational{BigInt}(t.coefficient)*x[t.variable]
        end
        for t in f.quadratic_terms
            value+=Rational{BigInt}(t.coefficient)*x[t.variable_1]*x[t.variable_2]/
                (t.variable_1==t.variable_2 ? 2 : 1)
        end
        if best===nothing || (minimize ? value<best : value>best)
            best=value
            c.row=x
        end
    end
    c.energy=Float64(best)
    return nothing
end

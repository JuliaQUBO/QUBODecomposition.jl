# SPDX-License-Identifier: MPL-2.0
import ToQUBO
const TA = ToQUBO.Attributes

# Public MOI wrapper at the compiler/composite boundary. It copies the actual
# dispatched objective before solving and retains each invocation's diagnostics.
mutable struct CapturingComposite <: MOI.AbstractOptimizer
    inner::QUBODecomposition.Optimizer
    log::Vector{Any}
    pending::Any
    metadata::Function
    before_solve::Function
end
CapturingComposite(inner) = CapturingComposite(inner, Any[], nothing, ()->nothing, ()->nothing)
MOI.is_empty(c::CapturingComposite) = MOI.is_empty(c.inner)
MOI.empty!(c::CapturingComposite) = MOI.empty!(c.inner)
MOI.supports_incremental_interface(::CapturingComposite) = false
MOI.supports(c::CapturingComposite, a::MOI.AbstractOptimizerAttribute) = MOI.supports(c.inner,a)
MOI.get(c::CapturingComposite, a::MOI.AbstractOptimizerAttribute) = MOI.get(c.inner,a)
MOI.set(c::CapturingComposite, a::MOI.AbstractOptimizerAttribute, v) = MOI.set(c.inner,a,v)
MOI.get(c::CapturingComposite, a::MOI.AbstractModelAttribute) = MOI.get(c.inner,a)
MOI.get(c::CapturingComposite, a::MOI.AbstractVariableAttribute, v::VI) = MOI.get(c.inner,a,v)
function MOI.copy_to(c::CapturingComposite, src::MOI.ModelLike)
    vars=copy(MOI.get(src,MOI.ListOfVariableIndices()))
    f=deepcopy(MOI.get(src,MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{Float64}}()))
    c.pending=(; vars, f, sense=MOI.get(src,MOI.ObjectiveSense()))
    return MOI.copy_to(c.inner,src)
end
function MOI.optimize!(c::CapturingComposite)
    c.before_solve()
    meta=deepcopy(c.metadata())
    MOI.optimize!(c.inner)
    n=MOI.get(c.inner,MOI.ResultCount())
    push!(c.log,(; c.pending..., meta, data=deepcopy(decomposition(c.inner)),
        status=MOI.get(c.inner,MOI.TerminationStatus()),
        state=n>0 ? copy(QUBOTools.state(c.inner,1)) : nothing,
        energy=n>0 ? MOI.get(c.inner,MOI.ObjectiveValue()) : nothing))
    return nothing
end

function compiler_fixture(; budget=32, child=()->FixtureChild(), kwargs...)
    composite=QUBODecomposition.Optimizer(;child_optimizer=child,max_variables=budget,kwargs...)
    capture=CapturingComposite(composite)
    compiler=ToQUBO.Optimizer(()->capture)
    MOI.set(compiler,TA.StableCompilation(),true)
    capture.metadata=()->ToQUBO.reformulation_metadata(compiler)
    return (; model=JuMP.Model(()->compiler), compiler, composite, capture)
end
function binary_fixture(; kwargs...)
    f=compiler_fixture(;kwargs...); m=f.model
    JuMP.@variable(m,x[1:2],Bin)
    JuMP.@objective(m,Max,5+3*x[1]+3*x[2])
    c=JuMP.@constraint(m,x[1]+x[2]<=1)
    JuMP.set_attribute(c,TA.ConstraintEncodingPenaltyHint(),-0.1)
    return (;f..., x, c)
end
function integer_fixture(; sense=MOI.MIN_SENSE, encoding=ToQUBO.Encoding.Binary(), kwargs...)
    f=compiler_fixture(;kwargs...); m=f.model
    JuMP.@variable(m,0<=z<=3,Int)
    JuMP.@variable(m,b,Bin)
    JuMP.set_attribute(z,TA.VariableEncodingMethod(),encoding)
    JuMP.@objective(m,Min,7+2*z+b)
    JuMP.set_objective_sense(m,sense)
    c=JuMP.@constraint(m,z+2*b<=3)
    return (;f..., z, b, c)
end

binary_states(n)=Iterators.product(fill((0,1),n)...)
# No production conditioning, energy or polynomial evaluators are used here.
function scalar_quadratic(f, values)
    v=f.constant
    for t in f.affine_terms
        v+=t.coefficient*values[t.variable]
    end
    for t in f.quadratic_terms
        v+=t.coefficient*values[t.variable_1]*values[t.variable_2]/(t.variable_1==t.variable_2 ? 2 : 1)
    end
    return v
end
compiled_energy(call,state)=scalar_quadratic(call.f,Dict(zip(call.vars,state)))
function scalar_terms(terms,state)
    return sum(t["coefficient"]*prod(state[i] for i in t["variables"];init=1) for t in terms;init=0.0)
end
function decoded(call,state)
    return Dict(e["id"]=>scalar_terms(e["expansion_terms"],state) for e in call.meta["original_variables"])
end
function assert_bit_inventory(call)
    n=length(call.vars)
    @test [v.value for v in call.vars]==collect(1:n)
    @test [v["id"] for v in call.meta["target_variables"]]==collect(1:n)
    @test all(t.variable in call.vars for t in call.f.affine_terms)
    @test all(t.variable_1 in call.vars && t.variable_2 in call.vars for t in call.f.quadratic_terms)
    if call.state!==nothing
        @test length(call.state)==n
        @test all(x in (0,1) for x in call.state)
        @test compiled_energy(call,call.state)≈call.energy
    end
end
function assert_source_result(f,source_value,residual)
    @test JuMP.result_count(f.model)==1
    @test ToQUBO.source_objective_value(f.model)≈source_value
    @test ToQUBO.is_feasible(f.model)==(residual<=1e-6)
    violations=ToQUBO.violations(f.model)
    @test isempty(violations)==(residual<=1e-6)
    if residual>1e-6
        @test only(violations).raw_residual≈residual
        @test only(violations).violation≈residual
    end
    @test JuMP.primal_status(f.model)==(residual<=1e-6 ? MOI.FEASIBLE_POINT : MOI.INFEASIBLE_POINT)
end

# Compare the whole compiled model, ownership and complete result. Enumeration
# catches a changed coefficient even when it leaves the winning energy equal.
function assert_fresh_compilation(call,fresh)
    assert_bit_inventory(call)
    assert_bit_inventory(fresh)
    @test call.vars==fresh.vars
    @test call.sense==fresh.sense
    @test isapprox(call.f,fresh.f)
    @test call.meta==fresh.meta
    @test call.state==fresh.state
    @test call.energy≈fresh.energy
    @test !isempty(call.meta["original_variables"])
    for bits in binary_states(length(call.vars))
        @test compiled_energy(call,bits)≈compiled_energy(fresh,bits)
        @test decoded(call,bits)==decoded(fresh,bits)
    end
end

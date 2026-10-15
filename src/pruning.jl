# SPDX-License-Identifier: MPL-2.0
# Exact rationals of the stored original Float64 normal form, including signed
# scale and sense. No conditioned Float64 coefficient enters a pruning proof.
struct SeparatorCertificate
    n::Int
    domain::Any
    linear::Vector{Rational{BigInt}}
    quadratic::Vector{Pair{Tuple{Int,Int},Rational{BigInt}}}
    constant::Rational{BigInt}
end

function prepare_pruning(opt, ctx, snap)
    return phase!(ctx, "bound") do
        check_time(opt, ctx, :bound_prepare)
        # Unavailable evidence is an abstention, never an exclusion certificate.
        all(isfinite, (snap.scale, snap.offset)) &&
            all(isfinite(last(t)) for t in snap.linear) &&
            all(isfinite(last(t)) for t in snap.quadratic) || return nothing
        q(x) = Rational{BigInt}(x)
        factor = (snap.sense === QUBOTools.Min ? 1 : -1) * q(snap.scale)
        linear = zeros(Rational{BigInt}, snap.n)
        for (i, c) in snap.linear
            check_time(opt, ctx, :bound_prepare)
            linear[i] = factor * q(c)
        end
        quadratic = Pair{Tuple{Int,Int},Rational{BigInt}}[]
        for (ij, c) in snap.quadratic
            check_time(opt, ctx, :bound_prepare)
            push!(quadratic, ij => factor * q(c))
        end
        result = SeparatorCertificate(snap.n, snap.domain, linear, quadratic, factor * q(snap.offset))
        check_time(opt, ctx, :bound_prepare_complete)
        return result
    end
end

function pruning_energy(opt, ctx, cert, state)
    return phase!(ctx, "bound") do
        check_time(opt, ctx, :bound_incumbent)
        length(state) == cert.n && all(valid_value(x, cert.domain) for x in state) ||
            error("pruning incumbent must be a complete valid original-domain assignment")
        value = cert.constant
        for i in 1:cert.n
            check_time(opt, ctx, :bound_incumbent)
            value += cert.linear[i] * state[i]
        end
        for ((i,j), c) in cert.quadratic
            check_time(opt, ctx, :bound_incumbent)
            value += c * state[i] * state[j]
        end
        check_time(opt, ctx, :bound_incumbent_complete)
        return value
    end
end

# Substitute the assigned set in exact arithmetic. Aggregate boundary terms into
# each residual linear coefficient before taking independent term minima.
function exact_restriction(opt, ctx, cert, state, assigned)
    fixed = falses(cert.n)
    fixed[assigned] .= true
    constant = cert.constant
    linear = copy(cert.linear)
    quadratic = Pair{Tuple{Int,Int},Rational{BigInt}}[]
    for i in assigned
        check_time(opt, ctx, :bound_terms)
        constant += linear[i] * state[i]
        linear[i] = 0
    end
    for ((i,j), c) in cert.quadratic
        check_time(opt, ctx, :bound_terms)
        if fixed[i] && fixed[j]
            constant += c * state[i] * state[j]
        elseif fixed[i]
            linear[j] += c * state[i]
        elseif fixed[j]
            linear[i] += c * state[j]
        else
            push!(quadratic, (i,j)=>c)
        end
    end
    return constant, linear, quadratic
end

function separator_lower_bound(opt, ctx, cert, state, selected)
    return phase!(ctx, "bound") do
        check_time(opt, ctx, :bound_branch)
        constant, linear, quadratic = exact_restriction(opt, ctx, cert, state, selected)
        value = constant
        for c in linear
            check_time(opt, ctx, :bound_terms)
            value += cert.domain === QUBOTools.BoolDomain ? min(0, c) : -abs(c)
        end
        for (_, c) in quadratic
            check_time(opt, ctx, :bound_terms)
            value += cert.domain === QUBOTools.BoolDomain ? min(0, c) : -abs(c)
        end
        check_time(opt, ctx, :bound_branch_complete)
        return value
    end
end

# An OPTIMAL child certifies its dispatched objective. Transfer that certificate
# only if its variable-dependent coefficients equal the exact original restriction.
# The offset may differ: an assignment-independent constant cannot change argmin.
function restriction_preserved(opt, ctx, cert, snap, state, component, problem)
    return phase!(ctx, "bound") do
        check_time(opt, ctx, :bound_transfer)
        _, linear, quadratic = exact_restriction(opt, ctx, cert, state,
            setdiff(1:cert.n, component))
        factor = snap.sense === QUBOTools.Min ? 1 : -1
        actual_linear = zeros(Rational{BigInt}, length(component))
        for (i,c) in problem.linear
            check_time(opt, ctx, :bound_transfer)
            scaled = problem.scale * c # exactly the Float64 operation in child_model
            isfinite(scaled) || return false
            actual_linear[i] = factor * Rational{BigInt}(scaled)
        end
        linear[component] == actual_linear || return false
        map = Dict(v=>i for (i,v) in enumerate(component))
        expected = Dict((map[i],map[j])=>c for ((i,j),c) in quadratic if !iszero(c))
        actual = Dict{Tuple{Int,Int},Rational{BigInt}}()
        for (ij,c) in problem.quadratic
            check_time(opt, ctx, :bound_transfer)
            scaled = problem.scale * c
            isfinite(scaled) || return false
            iszero(scaled) || (actual[ij] = factor * Rational{BigInt}(scaled))
        end
        check_time(opt, ctx, :bound_transfer_complete)
        return expected == actual
    end
end

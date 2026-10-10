# SPDX-License-Identifier: MPL-2.0
module CompactChildExperiment
using QUBODrivers, QUBOTools
import MathOptInterface as MOI
const VI = MOI.VariableIndex

function exact_size(n)
    n isa Integer && !(n isa Bool) && 0 <= n <= 8 ||
        throw(ArgumentError("exhaustive child requires at most 8 variables"))
    return 1 << n # at most 256, checked before exponentiation or allocation
end
mutable struct Ledger
    limit::Int
    reserved::Int
    calls::Vector{Dict{String,Any}}
end
function Ledger(limit::Int=1024)
    0 <= limit <= 100000 || throw(ArgumentError("invalid experiment allowance"))
    return Ledger(limit, 0, Dict{String,Any}[])
end

QUBODrivers.@setup CertifiedChild begin
    name = "Test/example certified exhaustive result adapter"
    attributes = begin
        WorkLedger["ledger"]::Any = nothing
        ResultMode["result_mode"]::Symbol = :all
        SourceHook["source_hook"]::Any = identity
    end
end
# Expose only a certificate installed AFTER validation, never the source flag.
function MOI.get(c::CertifiedChild, ::MOI.TerminationStatus)
    return get(QUBOTools.metadata(QUBOTools.solution(c)), "termination_status", MOI.OPTIMIZE_NOT_CALLED)
end
QUBODrivers.honors_final_reads(::Type{<:CertifiedChild}) = false

function child(ledger; mode=:all, source_hook=identity)
    mode in (:all, :compact) || throw(ArgumentError("mode must be :all or :compact"))
    c = CertifiedChild()
    MOI.set(c, MOI.RawOptimizerAttribute("ledger"), ledger)
    MOI.set(c, MOI.RawOptimizerAttribute("result_mode"), mode)
    MOI.set(c, MOI.RawOptimizerAttribute("source_hook"), source_hook)
    return c
end

# The checked source is the released ExactSampler, after its normal frame cast.
# Verify exhaustive completion AND every assignment before discarding any row.
# This is deliberately stronger than counts alone; it is not a production trait.
function validate_source(source, model, count)
    ss = QUBOTools.solution(source)
    md = QUBOTools.metadata(ss)
    get(md, "termination_status", nothing) === MOI.OPTIMAL &&
        get(md, "status", nothing) == "optimal" &&
        get(get(md, "execution", Dict()), "mode", nothing) == "exhaustive_search" &&
        get(get(md, "optimizer", Dict()), "evaluations", nothing) == count ||
        error("missing or inconsistent exhaustive-completion certificate")
    MOI.get(source, MOI.ResultCount()) == length(ss) == count || error("incomplete exhaustive rows")
    QUBOTools.domain(ss) === QUBOTools.domain(model) && QUBOTools.sense(ss) === QUBOTools.sense(model) ||
        error("source frame mismatch")
    vars = QUBOTools.variables(model)
    QUBOTools.variables(QUBOTools.backend(source)) == vars || error("source variable mapping mismatch")
    low = QUBOTools.domain(model) === QUBOTools.BoolDomain ? 0 : -1
    seen = falses(count)
    best_state, best_energy = nothing, nothing
    for row in 1:count
        MOI.get(source, MOI.PrimalStatus(row)) === MOI.FEASIBLE_POINT || error("infeasible source row")
        raw = [MOI.get(source, MOI.VariablePrimal(row), v) for v in vars]
        length(raw) == QUBOTools.dimension(model) && all(x -> x isa Real && isfinite(x) && x in (low, 1), raw) ||
            error("malformed source assignment")
        state = Int.(raw)
        mask = sum((state[i] == 1 ? 1 << (i-1) : 0 for i in eachindex(state)); init=0)
        seen[mask+1] && error("duplicate source assignment")
        seen[mask+1] = true
        QUBOTools.reads(ss, row) == 1 || error("unexpected exhaustive multiplicity")
        reported = MOI.get(source, MOI.ObjectiveValue(row))
        energy = QUBOTools.value(model, state)
        reported isa Real && isfinite(reported) && isfinite(energy) &&
            isapprox(reported, energy; atol=1e-12, rtol=1e-12) || error("source objective mismatch")
        better = best_energy === nothing || (QUBOTools.sense(model) === QUBOTools.Min ? energy < best_energy : energy > best_energy)
        if better || (energy == best_energy && isless(Tuple(state), Tuple(best_state)))
            best_state, best_energy = state, energy
        end
    end
    all(seen) && QUBOTools.reads(ss) == count || error("incomplete exhaustive coverage")
    return best_state, best_energy
end

function QUBODrivers.sample(c::CertifiedChild)
    sample_started = time_ns()
    # Generic samplers retain their last attached solution on exceptions. Clear it
    # before any failing guard; keep the exhaustive source's attachment private.
    model = QUBOTools.backend(c)
    QUBOTools.attach!(c, QUBOTools.SampleSet{Float64,Int}(;
        sense=QUBOTools.sense(model), domain=QUBOTools.domain(model)))
    ledger = MOI.get(c, MOI.RawOptimizerAttribute("ledger"))::Ledger
    mode = MOI.get(c, MOI.RawOptimizerAttribute("result_mode"))
    mode in (:all, :compact) || error("invalid result mode")
    model = QUBOTools.backend(c)
    count = exact_size(QUBOTools.dimension(model))
    record = Dict{String,Any}("variables"=>QUBOTools.dimension(model),
        "reserved_assignments"=>0, "actual_assignments"=>0, "rows_emitted"=>0,
        "certificate_checked"=>false, "dispatched"=>false, "failed"=>true,
        "certificate_selection_sec"=>0.0, "result_build_sec"=>0.0)
    push!(ledger.calls, record)
    count <= ledger.limit - ledger.reserved || error("assignment allowance exhausted before dispatch")
    ledger.reserved += count
    record["reserved_assignments"] = count
    record["dispatched"] = true
    source = QUBODrivers.ExactSampler.Optimizer()
    QUBODrivers.set_model!(source, copy(model))
    MOI.optimize!(source) # identical exhaustive search/full result creation in both modes
    # The bounded released loop has completed. Keep actual work even if checks fail.
    record["actual_assignments"] = count
    hook = MOI.get(c, MOI.RawOptimizerAttribute("source_hook"))
    hook(source) # identity in measured runs; fault injection in deterministic tests
    started = time_ns()
    state, energy = validate_source(source, model, count)
    record["certificate_selection_sec"] = (time_ns()-started)/1e9
    record["certificate_checked"] = true
    started = time_ns()
    result = if mode === :all
        copy(QUBOTools.solution(source))
    else
        QUBOTools.SampleSet{Float64,Int}([QUBOTools.Sample{Float64,Int}(state, energy, 1)];
            metadata=deepcopy(QUBOTools.metadata(QUBOTools.solution(source))),
            sense=QUBOTools.sense(model), domain=QUBOTools.domain(model))
    end
    md = QUBOTools.metadata(result)
    md["termination_status"] = MOI.OPTIMAL
    md["experiment"] = Dict("mode"=>String(mode), "source_assignments"=>count,
        "emitted_rows"=>length(result), "source_time"=>deepcopy(md["time"]), "tie_choice"=>"lexicographically smallest original child state")
    # Full search work remains optimizer evaluations; reads describe output rows.
    md["reads"] = Dict{String,Any}("number_of_reads"=>count,
        "final_number_of_reads"=>length(result),
        "meaning"=>"exhaustive assignments and emitted rows; not physical reads")
    record["result_build_sec"] = (time_ns()-started)/1e9
    record["rows_emitted"] = length(result)
    record["failed"] = false
    # Replace inherited source timing; framework stamps total adapter sample time.
    md["time"] = Dict{String,Any}("effective"=>(time_ns()-sample_started)/1e9)
    return result
end
end

# SPDX-License-Identifier: MPL-2.0
const QP = QUBOPreprocessing

# Structural reservations are distinct from child calls and candidate evaluations.
# They count storage/term passes; arithmetic bit complexity and sorting are extra.
mutable struct StructuralWork
    remaining::Int
    used::Int
    phases::Dict{String,Int}
end
work_passes(n,k) = Base.checked_mul(n,k)
stored_positions(x::Union{QUBOTools.SparseLinearForm,QUBOTools.SparseQuadraticForm}) = length(QUBOTools.data(x).nzval)
stored_positions(x) = length(QUBOTools.data(x))
function form_work(form)
    return Base.checked_add(QUBOTools.dimension(form)+1,
        Base.checked_add(stored_positions(QUBOTools.linear_form(form)),
                         stored_positions(QUBOTools.quadratic_form(form))))
end
model_work(model) = form_work(QUBOTools.form(model))
snapshot_work(snap) = Base.checked_add(snap.n+1,Base.checked_add(length(snap.linear),length(snap.quadratic)))
snapshot_storage_work(snap) = form_work(snap.form)
function charge_work!(opt,ctx,units,phase;check_deadline=true)
    budget = get(ctx.data,"_work_budget",nothing)
    budget === nothing && return nothing
    ctx.data["work_phase"] = phase
    check_deadline && check_time(opt,ctx,Symbol(phase))
    units <= budget.remaining || throw(StopSolve(MOI.ITERATION_LIMIT,"max_work"))
    budget.remaining -= units
    budget.used += units
    budget.phases[phase] = get(budget.phases,phase,0)+units
    return nothing
end
evaluation_cap(opt,ctx) = opt.options[:max_candidate_evaluations]-get(ctx.data,"_reserved_original_evaluations",0)

function validate_preprocessing_configuration(opt)
    opt.options[:preprocessing] === :off && opt.options[:max_work] == typemax(Int) && return nothing
    opt.options[:strategy] in (:whole_model,:components,:components_then_sweeps) &&
        opt.options[:selection] in (:strongest_edge,:bfs,:random_blocks,:single_flip_gain) &&
        opt.options[:component_executor] === nothing && opt.options[:partition_plan] === nothing &&
        opt.options[:coarse_groups] === nothing && opt.options[:consensus_plan] === nothing &&
        opt.options[:sample_pool] === nothing && opt.options[:separator] == Int[] ||
        throw(UnsupportedChild("root preprocessing supports serial whole_model/components/components_then_sweeps with automatic selection; explicit index plans, advanced strategies and component executors require separate projection contracts"))
    return nothing
end

function qp_deadline(opt,ctx)
    ctx.deadline === nothing && return nothing
    check_time(opt,ctx,:preprocessing_deadline)
    remaining = max(0.0,ctx.deadline-opt.clock())
    seconds = min(remaining,Float64(typemax(UInt64)÷4)/1e9)
    now = time_ns()
    duration = min(typemax(UInt64)-now,UInt64(floor(seconds*1e9)))
    return now+duration
end

function reserve_child_work!(opt,ctx,child,problem,call)
    budget = get(ctx.data,"_work_budget",nothing)
    budget === nothing && return nothing
    builtin = child isa QUBODrivers.ExactSampler.Optimizer
    builtin && problem.n > 20 && throw(UnsupportedChild("built-in ExactSampler exceeds the 20-variable hard work guard"))
    # Callbacks receive owned immutable numerical input, never the live snapshot.
    description = (; n=problem.n,domain=problem.domain,sense=problem.sense,
        linear=Tuple(problem.linear),quadratic=Tuple(problem.quadratic),
        scale=problem.scale,offset=problem.offset)
    callback = opt.options[:child_work_bound]
    bound = callback !== nothing ? callback(child,description,budget.remaining,ctx.deadline) :
        builtin ? Base.checked_add(work_passes(snapshot_work(problem),8),
                                   work_passes(1<<problem.n,work_passes(snapshot_work(problem),4))) : nothing
    bound === nothing && opt.options[:max_work] != typemax(Int) &&
        throw(UnsupportedChild("finite max_work requires child_work_bound for an unknown child"))
    bound === nothing || (bound isa Integer && !(bound isa Bool) && 0 <= bound <= typemax(Int)) ||
        throw(UnsupportedChild("child_work_bound must return a nonnegative Int-sized integer"))
    call["child_work_reserved"] = bound
    charge_work!(opt,ctx,something(bound,0),"child_reservation")
    return nothing
end

function exact_original_energy(snap,state)
    value = Rational{BigInt}(snap.offset)
    for (i,c) in snap.linear;value += Rational{BigInt}(c)*state[i];end
    for ((i,j),c) in snap.quadratic;value += Rational{BigInt}(c)*state[i]*state[j];end
    return Rational{BigInt}(snap.scale)*value
end

function root_phase!(f,opt,ctx,diagnostics,name)
    check_time(opt,ctx,Symbol(name))
    start = time_ns()
    try
        return f()
    finally
        elapsed = (time_ns()-start)/1e9
        diagnostics["phase_sec"][name] = get(diagnostics["phase_sec"],name,0.0)+elapsed
        ctx.data["phase_sec"]["preprocessing"] += elapsed
    end
end

function project_call(call,free_to_original,original_n)
    projected = copy(call)
    projected["residual_selected_indices"] = call["selected_indices"]
    projected["selected_indices"] = free_to_original[call["selected_indices"]]
    projected["original_to_reduced"] = Dict(free_to_original[i]=>j for (i,j) in call["original_to_reduced"])
    projected["boundary_fixed_variables"] = Dict(free_to_original[i]=>v for (i,v) in call["boundary_fixed_variables"])
    projected["preprocessing_fixed_variable_count"] = original_n-length(free_to_original)
    projected["fixed_variable_count"] = original_n-length(call["selected_indices"])
    projected["conditioning_incumbent_space"] = "residual"
    if call["anchor"] !== nothing
        projected["residual_anchor"] = call["anchor"]
        projected["anchor"] = free_to_original[call["anchor"]]
    end
    return projected
end

function preprocessed_solve!(opt,ctx,original)
    diagnostics = Dict{String,Any}("enabled"=>true,"applied"=>false,"scope"=>"original",
        "phase_sec"=>Dict{String,Float64}(),"reason"=>"preparing","proof_verified"=>false,
        "original_dimension"=>original.n,"residual_dimension"=>nothing,
        "original_to_residual"=>nothing,"generation"=>nothing,"residual"=>nothing,
        "original_candidate_committed"=>false)
    ctx.data["preprocessing"] = diagnostics
    budget = ctx.data["_work_budget"]
    # Fund both the original audit and one final evaluation before residual work.
    ctx.evaluations < opt.options[:max_candidate_evaluations] ||
        throw(StopSolve(MOI.ITERATION_LIMIT,"max_candidate_evaluations"))
    charge_work!(opt,ctx,work_passes(model_work(QUBOTools.backend(opt)),8),"reserved_original_lift")
    ws = root_phase!(opt,ctx,diagnostics,"workspace") do
        charge_work!(opt,ctx,work_passes(model_work(QUBOTools.backend(opt)),8),"workspace")
        QP.Workspace(QUBOTools.backend(opt);rules=:dominance)
    end
    diagnostics["generation"] = string(QP.generation(ws))
    opt.preprocessing_result = (;workspace=ws,exported=nothing,verification=nothing,
        generation=QP.generation(ws),invocation=opt.invocation)
    deadline = qp_deadline(opt,ctx)
    report = root_phase!(opt,ctx,diagnostics,"propagation") do
        cap = min(Int(opt.options[:preprocessing_max_work]),budget.remaining÷4)
        reservation = work_passes(cap,4)
        charge_work!(opt,ctx,reservation,"propagation")
        result = QP.propagate!(ws;max_work=cap,
            max_deductions=Int(opt.options[:preprocessing_max_deductions]),
            max_exact_work=min(Int(opt.options[:preprocessing_max_exact_work]),work_passes(cap,3)),
            deadline_ns=deadline)
        actual = result.candidates+result.edge_visits+result.exact_work
        actual <= reservation || error("preprocessing exceeded its structural reservation")
        unused = reservation-actual
        budget.remaining += unused;budget.used -= unused;budget.phases["propagation"] -= unused
        return result
    end
    diagnostics["propagation"] = Dict("stop_reason"=>string(report.stop_reason),
        "candidates"=>report.candidates,"edge_visits"=>report.edge_visits,
        "deductions"=>report.deductions,"exact_work"=>report.exact_work,"pending"=>report.pending)
    check_time(opt,ctx,:after_preprocessing)
    report.stop_reason === :deadline && throw(StopSolve(MOI.TIME_LIMIT,"preprocessing_deadline"))
    exported = try
        root_phase!(opt,ctx,diagnostics,"materialization") do
            charge_work!(opt,ctx,work_passes(model_work(QUBOTools.backend(opt))+report.deductions,8),"materialization")
            QP.materialize(ws)
        end
    catch err
        err isa ArgumentError || rethrow()
        diagnostics["reason"] = "unsafe_export"
        diagnostics["fallback"] = "original_objective"
        opt.preprocessing_result = (;workspace=ws,exported=nothing,verification=nothing,
            generation=QP.generation(ws),invocation=opt.invocation)
        prepare_work_certificate!(opt,ctx,original)
        return run_strategy!(opt,ctx,original)
    end
    proof = exported isa QP.ConditionedExport ? exported.certificate.proof : nothing
    verified = if proof === nothing
        nothing
    else
        root_phase!(opt,ctx,diagnostics,"verification") do
            result = QP.verify_certificate(ws,proof;max_work=budget.remaining,deadline_ns=qp_deadline(opt,ctx))
            charge_work!(opt,ctx,result.term_visits,"verification";check_deadline=false)
            return result
        end
    end
    opt.preprocessing_result = (;workspace=ws,exported,verification=verified,
        generation=QP.generation(ws),invocation=opt.invocation)
    if verified !== nothing && !verified.valid
        diagnostics["reason"] = string(verified.stop_reason)
        verified.stop_reason === :deadline && throw(StopSolve(MOI.TIME_LIMIT,"preprocessing_deadline"))
        verified.stop_reason === :work_limit && throw(StopSolve(MOI.ITERATION_LIMIT,"preprocessing_verification_work"))
        error("root preprocessing certificate rejected: $(verified.stop_reason)")
    end
    exported.certificate.scope === :original || error("root preprocessing must not introduce caller assumptions")
    diagnostics["proof_verified"] = true
    diagnostics["applied"] = true
    diagnostics["reason"] = "accepted"
    charge_work!(opt,ctx,work_passes(model_work(QUBOTools.backend(opt)),4),"residual_snapshot")
    map = QP.index_map(exported)
    free = findall(!iszero,map)
    residual = snapshot(QP.export_model(exported))
    residual = merge(residual,(state=original.state[free],))
    diagnostics["residual_dimension"] = residual.n
    diagnostics["original_to_residual"] = map
    ctx.data["original_to_reduced"] = map
    # Original and residual incumbents never share a coordinate system. Only
    # execution counters and the work ledger are shared. Residual phase timers
    # are aggregated once, after that transaction completes.
    residual_data = copy(ctx.data)
    residual_data["phase_sec"] = Dict(k=>0.0 for k in keys(ctx.data["phase_sec"]))
    residual_data["dimension"] = residual.n
    residual_data["labels"] = copy(residual.labels)
    residual_data["label_to_original"] = Dict(label=>i for (i,label) in enumerate(residual.labels))
    residual_data["original_to_reduced"] = collect(1:residual.n)
    residual_data["scale"],residual_data["offset"] = residual.scale,residual.offset
    residual_data["calls"] = Any[]
    residual_data["components"] = Any[]
    residual_data["component_exact"] = Bool[]
    residual_data["incumbent_energy_trace"] = Float64[]
    residual_data["stop_reason"] = "residual_preparing"
    delete!(residual_data,"preprocessing")
    residual_data["_reserved_original_evaluations"] = 1
    working = SolveState(nothing,nothing,ctx.evaluations,0,ctx.deadline,residual_data)
    pending = nothing
    try
        reserve_evaluation!(opt,working)
        charge_work!(opt,working,snapshot_work(residual),"residual_initial_energy")
        energy = phase!(working,"full_energy") do
            full_energy(residual.state,residual.linear,residual.quadratic,residual.scale,residual.offset)
        end
        check_time(opt,working,:residual_initial_commit)
        working.state,working.energy = residual.state,energy
        push!(residual_data["incumbent_energy_trace"],energy)
        prepare_work_certificate!(opt,working,residual)
        run_strategy!(opt,working,residual)
    catch err
        pending = err
    end
    ctx.evaluations = working.evaluations
    for (phase,elapsed) in residual_data["phase_sec"]
        ctx.data["phase_sec"][phase] += elapsed
    end
    for key in ("attempted_calls","completed_calls","started_sweeps","completed_sweeps","stagnation",
                "incomplete_scan","separable_proof","selection_sec","selection_seed","selection_rng","stop_reason")
        ctx.data[key] = residual_data[key]
    end
    ctx.data["calls"] = [project_call(call,free,original.n) for call in residual_data["calls"]]
    ctx.data["components"] = [free[component] for component in residual_data["components"]]
    ctx.data["component_exact"] = copy(residual_data["component_exact"])
    delete!(residual_data,"_work_budget")
    delete!(residual_data,"_root_certificate")
    delete!(residual_data,"_reserved_original_evaluations")
    diagnostics["residual"] = residual_data
    if working.state !== nothing && !(pending isa InterruptException)
        try
            check_time(opt,ctx,:before_original_lift)
            reserve_evaluation!(opt,ctx)
            candidate,energy,exact,prior = phase!(ctx,"original_reconstruction") do
                restored = QP.reconstruct(exported,working.state)
                restored.energy.finite || error("non-finite reconstructed original energy")
                state = restored.state
                all(valid_value(x,original.domain) for x in state) && length(state)==original.n ||
                    error("malformed original reconstruction")
                energy = full_energy(state,original.linear,original.quadratic,original.scale,original.offset)
                state,energy,exact_original_energy(original,state),exact_original_energy(original,ctx.state)
            end
            check_time(opt,ctx,:before_original_commit)
            certified = pending === nothing && opt.termination === MOI.OPTIMAL
            certified && better(prior,exact,original.sense) && error("residual optimum contradicts original incumbent")
            if better(exact,prior,original.sense) || certified
                ctx.state,ctx.energy = candidate,energy
                ctx.improvements += exact != prior
                push!(ctx.data["incumbent_energy_trace"],energy)
                diagnostics["original_candidate_committed"] = true
            end
        catch err
            pending = err
        end
    end
    if pending !== nothing || !diagnostics["original_candidate_committed"]
        ctx.data["separable_proof"] = false
    end
    pending === nothing || throw(pending)
    return nothing
end

function prepare_work_certificate!(opt,ctx,snap)
    haskey(ctx.data,"_work_budget") || return nothing
    charge_work!(opt,ctx,work_passes(snapshot_work(snap),2),"exact_objective_capture")
    ctx.data["_root_certificate"] = prepare_pruning(opt,ctx,snap)
    return nothing
end

function finish_work_metadata!(ctx)
    budget = pop!(ctx.data,"_work_budget",nothing)
    pop!(ctx.data,"_root_certificate",nothing)
    if budget !== nothing
        ctx.data["work"] = Dict("used"=>budget.used,"remaining"=>budget.remaining,
            "phases"=>copy(budget.phases),"meaning"=>"reserved structural storage/term units, including child reservations")
    end
    return nothing
end

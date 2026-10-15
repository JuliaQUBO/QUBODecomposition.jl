# SPDX-License-Identifier: MPL-2.0
# Explicit component executors and absolute_deadline_sec require version >=0.1.2.
using Distributed
import MathOptInterface as MOI
import QUBODecomposition, QUBODrivers, QUBOTools

function run_process_components()
    # Workers inherit the active environment containing this package revision.
    project = dirname(Base.active_project())
    pids = addprocs(2; exeflags=`--project=$project --threads=1 --startup-file=no`,
        env=["OPENBLAS_NUM_THREADS"=>"1", "OMP_NUM_THREADS"=>"1"])
    local state, energy
    identities = Any[]
    try
        for pid in pids
            remotecall_wait(Core.eval, pid, Main, :(import QUBODecomposition, QUBODrivers))
            identity = remotecall_fetch(Core.eval, pid, Main, :((;
                source=realpath(pkgdir(QUBODecomposition)),
                version=pkgversion(QUBODecomposition), project=realpath(Base.active_project()))))
            @assert identity.source == realpath(pkgdir(QUBODecomposition))
            @assert identity.version == pkgversion(QUBODecomposition)
            @assert identity.project == realpath(Base.active_project())
            push!(identities, identity)
        end
        model = QUBOTools.Model{Symbol,Float64,Int}([:a,:b,:isolate],
            [1,2,3], [-2.,1.,-3.], [1], [2], [-1.]; offset=4.)
        executor = QUBODecomposition.ProcessComponentExecutor(WorkerPool(pids); max_inflight=2)
        optimizer = QUBODecomposition.Optimizer(child_optimizer=QUBODrivers.ExactSampler.Optimizer,
            max_variables=3, strategy=:components, component_executor=executor, seed=17,
            absolute_deadline_sec=time_ns()/1e9 + 3600.) # Cooperative allowance, not hard cancellation.
        QUBODrivers.set_model!(optimizer, model)
        MOI.optimize!(optimizer)
        state, energy = QUBOTools.state(optimizer,1), QUBOTools.value(optimizer,1)
        @assert state == [1,0,1] && energy == -1.
        @assert QUBOTools.value(model, state) == energy
        @assert MOI.get(optimizer, MOI.TerminationStatus()) == MOI.LOCALLY_SOLVED
        # The optimizer returns workers to the caller's pool for reuse.
        MOI.optimize!(optimizer)
        @assert QUBOTools.state(optimizer,1) == state && QUBOTools.value(optimizer,1) == energy
        @assert all(pid in workers() for pid in pids) && isready(executor.pool)
        # An expired absolute deadline must stop before invoking any child factory.
        MOI.set(optimizer, MOI.RawOptimizerAttribute("child_optimizer"),
            () -> error("expired deadline dispatched a child"))
        MOI.set(optimizer, MOI.RawOptimizerAttribute("absolute_deadline_sec"), 0.)
        MOI.optimize!(optimizer)
        @assert MOI.get(optimizer, MOI.TerminationStatus()) == MOI.TIME_LIMIT
        @assert MOI.get(optimizer, MOI.ResultCount()) == 0
        data = QUBOTools.metadata(QUBOTools.solution(optimizer))["decomposition"]
        @assert data["attempted_calls"] == 0 && isempty(data["calls"])
        @assert all(pid in workers() for pid in pids) && isready(executor.pool)
    finally
        rmprocs(pids) # Caller owns workers; the optimizer never terminates them.
    end
    @assert all(!(pid in workers()) for pid in pids)
    return (; state, energy, status=MOI.LOCALLY_SOLVED, worker_identities=identities,
        expired_deadline_status=MOI.TIME_LIMIT)
end

if abspath(PROGRAM_FILE) == @__FILE__
    @show run_process_components()
end

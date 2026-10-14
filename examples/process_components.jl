# SPDX-License-Identifier: MPL-2.0
using Distributed
import MathOptInterface as MOI
import QUBODecomposition, QUBODrivers, QUBOTools

function run_process_components()
    # Workers inherit the active environment containing this package revision.
    project = dirname(Base.active_project())
    pids = addprocs(2; exeflags=`--project=$project --threads=1 --startup-file=no`,
        env=["OPENBLAS_NUM_THREADS"=>"1", "OMP_NUM_THREADS"=>"1"])
    try
        for pid in pids
            remotecall_wait(Core.eval, pid, Main, :(import QUBODecomposition, QUBODrivers))
        end
        model = QUBOTools.Model{Symbol,Float64,Int}([:a,:b,:isolate],
            [1,2,3], [-2.,1.,-3.], [1], [2], [-1.]; offset=4.)
        executor = QUBODecomposition.ProcessComponentExecutor(WorkerPool(pids); max_inflight=2)
        optimizer = QUBODecomposition.Optimizer(child_optimizer=QUBODrivers.ExactSampler.Optimizer,
            max_variables=3, strategy=:components, component_executor=executor, seed=17)
        QUBODrivers.set_model!(optimizer, model)
        MOI.optimize!(optimizer)
        state, energy = QUBOTools.state(optimizer,1), QUBOTools.value(optimizer,1)
        @assert state == [1,0,1] && energy == -1.
        @assert QUBOTools.value(model, state) == energy
        @assert MOI.get(optimizer, MOI.TerminationStatus()) == MOI.LOCALLY_SOLVED
        # This same executor/pool can be reused before caller cleanup.
        return (; state, energy, status=MOI.get(optimizer, MOI.TerminationStatus()))
    finally
        rmprocs(pids) # Caller owns workers; the optimizer never terminates them.
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    @show run_process_components()
end

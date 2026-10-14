# SPDX-License-Identifier: MPL-2.0
@testset "Two real processes: overlap, isolation, reuse and ownership" begin
    # Pkg.test and runtime-floor environments must propagate to worker imports.
    project = dirname(Base.active_project())
    pids = addprocs(2; exeflags=`--project=$project --threads=1 --startup-file=no`,
        env=["OPENBLAS_NUM_THREADS"=>"1","OMP_NUM_THREADS"=>"1","MKL_NUM_THREADS"=>"1"])
    releases = (RemoteChannel(()->Channel{Nothing}(1)),RemoteChannel(()->Channel{Nothing}(1)))
    try
        fixture = joinpath(dirname(@__DIR__),"process_fixture.jl")
        for pid in pids
            remotecall_wait(Base.include,pid,Main,fixture)
        end
        include("../process_fixture.jl")
        pool = WorkerPool(pids)
        executor = QD.ProcessComponentExecutor(pool;max_inflight=2)
        @test_throws ArgumentError QD.ProcessComponentExecutor(pool;max_inflight=3)
        started = RemoteChannel(()->Channel{Any}(2))
        factory = ProcessComponentFixture.Factory(started,releases,true,0)
        model = disconnected_fixture()
        opt = QD.Optimizer(child_optimizer=factory,max_variables=2,strategy=:components,
            component_executor=executor,seed=101)
        QUBODrivers.set_model!(opt,model)
        task = @async MOI.optimize!(opt)
        # Both callbacks must have started and remain blocked before either can
        # finish. This demonstrates overlap without a speedup threshold.
        @test timedwait(()->isready(started) || istaskdone(task),120.) == :ok
        istaskdone(task) && error("Solve ended before overlap barrier: $(MOI.get(opt,MOI.TerminationStatus()))")
        first_start = take!(started)
        @test timedwait(()->isready(started) || istaskdone(task),120.) == :ok
        istaskdone(task) && error("Solve ended before overlap barrier: $(MOI.get(opt,MOI.TerminationStatus()))")
        second_start = take!(started)
        @test Set((first_start.component,second_start.component)) == Set((1,2))
        @test Set((first_start.worker,second_start.worker)) == Set(pids)
        @test first_start.local_count == second_start.local_count == 1
        @test sort([first_start.seed,second_start.seed]) == [101,102]
        @test sort([first_start.n,second_start.n]) == [1,2]
        put!(releases[2],nothing)
        put!(releases[1],nothing)
        fetch(task)
        @test MOI.get(opt,MOI.TerminationStatus()) == MOI.OPTIMAL
        @test QUBOTools.value(opt,1) == oracle(model)
        @test decomposition(opt)["execution"]["max_observed_inflight"] == 2
        @test all(c["executor_diagnostics"].worker in pids for c in decomposition(opt)["calls"])
        @test all(remotecall_fetch(()->Threads.nthreads(),pid)==1 for pid in pids)
        @test decomposition(opt)["child_execution_sec"] == sum(c["executor_diagnostics"].execution_sec for c in decomposition(opt)["calls"])
        @test decomposition(opt)["parent_processing_sec"] === nothing
        # Reuse exactly the same pool for another invocation and a changed model.
        old_id = decomposition(opt)["calls"][1]["job_id"]
        MOI.set(opt,MOI.RawOptimizerAttribute("child_optimizer"),ProcessComponentFixture.Factory(started,releases,false,0))
        MOI.optimize!(opt)
        @test decomposition(opt)["invocation"] == 2
        @test decomposition(opt)["calls"][1]["job_id"][1] != old_id[1]
        @test QUBOTools.value(opt,1) == oracle(model)
        changed = QUBOTools.Model{Int,Float64,Int}([37,81], [1,2], [3.,-7.],Int[],Int[],Float64[];offset=-8.,scale=-2.,sense=:max)
        QUBODrivers.set_model!(opt,changed)
        MOI.optimize!(opt)
        @test QUBOTools.state(opt,1) == [0,1]
        @test QUBOTools.value(opt,1) == 30.
        @test decomposition(opt)["labels"] == [37,81]
        @test decomposition(opt)["attempted_calls"] == 2
        # A worker-side exception is drained, charged and never retried. Workers
        # remain alive and the same executor is immediately usable again.
        MOI.set(opt,MOI.RawOptimizerAttribute("child_optimizer"),ProcessComponentFixture.Factory(started,releases,false,1))
        MOI.optimize!(opt)
        @test MOI.get(opt,MOI.TerminationStatus()) == MOI.OTHER_ERROR
        @test !decomposition(opt)["separable_proof"]
        @test decomposition(opt)["attempted_calls"] <= 2
        @test all(c["job_state"] in ("failed_or_unknown","drained_uncommitted") for c in decomposition(opt)["calls"])
        @test all(pid in workers() for pid in pids)
        MOI.set(opt,MOI.RawOptimizerAttribute("child_optimizer"),ProcessComponentFixture.Factory(started,releases,false,0))
        MOI.optimize!(opt)
        @test MOI.get(opt,MOI.TerminationStatus()) == MOI.OPTIMAL
        @test QUBOTools.value(opt,1) == 30.
        @test isready(pool)
        # Actual process loss also propagates without retry or fabricated proof.
        MOI.set(opt,MOI.RawOptimizerAttribute("child_optimizer"),ProcessComponentFixture.Factory(started,releases,false,-1))
        MOI.optimize!(opt)
        @test MOI.get(opt,MOI.TerminationStatus()) == MOI.OTHER_ERROR
        @test !decomposition(opt)["separable_proof"]
        @test decomposition(opt)["attempted_calls"] <= 2
        @test count(pid->pid in workers(),pids) == 1
        @test any(c["job_state"]=="failed_or_unknown" for c in decomposition(opt)["calls"])
    finally
        # Release barriers even on failed assertions so cleanup cannot hang.
        for release in releases
            !isready(release) && put!(release,nothing)
        end
        # Only the caller/test owns cleanup, including on assertion failure.
        rmprocs([pid for pid in pids if pid in workers()])
    end
    @test all(!(pid in workers()) for pid in pids)
end

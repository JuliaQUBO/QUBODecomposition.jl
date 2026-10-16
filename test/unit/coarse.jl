# SPDX-License-Identifier: MPL-2.0
# All enumeration introduced here reserves work before constructing state spaces.
const COARSE_TEST_CHILD_WORK = Ref(0)
const COARSE_TEST_ORACLE_WORK = Ref(0)
function coarse_states(domain, n)
    0 <= n <= 8 || error("coarse oracle dimension ceiling")
    work = 1 << n
    COARSE_TEST_ORACLE_WORK[] + work <= 16_384 || error("coarse oracle aggregate ceiling")
    COARSE_TEST_ORACLE_WORK[] += work
    return Iterators.product(fill(domain === :bool ? (0,1) : (-1,1), n)...)
end
function coarse_test_child(; callback=_->nothing, kwargs...)
    child = FixtureChild(; kwargs...)
    child.callback = c -> begin
        n = length(MOI.get(c.model, MOI.ListOfVariableIndices()))
        n <= 8 || error("coarse test child dimension ceiling")
        if !c.scripted
            work = 1 << n
            COARSE_TEST_CHILD_WORK[] + work <= 65_536 || error("coarse test child aggregate ceiling")
            COARSE_TEST_CHILD_WORK[] += work
        end
        callback(c)
    end
    return child
end
coarse_solve(model, groups; child=()->coarse_test_child(), budget=groups === nothing ? 1 : length(groups), kwargs...) =
    solve_model(model; strategy=:coarse, coarse_groups=groups, child, budget=max(1,budget), kwargs...)

function coarse_fixture(; domain=:bool, sense=:min, scale=1.0, reversed=false)
    labels = reversed ? [:unused,:p,:q,:c,:a,:z] : [:z,:a,:c,:q,:p,:unused]
    low = domain === :bool ? 0 : -1
    r = reversed ? [1,low,1,low,1,low] : [low,1,low,1,1,low]
    model = QUBOTools.Model{Symbol,Float64,Int}(labels,
        collect(1:6),[-3.,2.,-1.,4.,.5,0.],
        [1,3,1,2,3,4],[2,4,3,4,5,5],[3.,-1.,-2.,5.,-4.,1.];
        domain,sense,scale,offset=7.,start=Dict(zip(labels,r)))
    scalar(x) = scale*(7 - 3x[1] + 2x[2] - x[3] + 4x[4] + .5x[5] +
        3x[1]*x[2] - x[3]*x[4] - 2x[1]*x[3] + 5x[2]*x[4] -
        4x[3]*x[5] + x[4]*x[5])
    return model, r, scalar
end

@testset "Coarse full-objective substitution and independent scalar identity" begin
    for domain in (:bool,:spin), sense in (:min,:max), scale in (-2.5,0.,.75), reversed in (false,true)
        model, r, scalar = coarse_fixture(; domain,sense,scale,reversed)
        groups = [[4,3],[2,1]] # caller macro order is significant
        values = domain === :bool ? (0,1) : (-1,1)
        function independent_lift(m)
            x = copy(r)
            for (g,indices) in enumerate(groups), i in indices
                x[i] = domain === :bool ? (m[g] == 0 ? r[i] : 1-r[i]) : r[i]*m[g]
            end
            return x
        end
        rows = [independent_lift(m) for m in coarse_states(domain,2)]
        seen = Ref(0)
        child = () -> coarse_test_child(callback=c -> begin
            seen[] += 1
            vars = sort(MOI.get(c.model,MOI.ListOfVariableIndices()); by=v->-v.value)
            @test length(vars) == 2
            f = MOI.get(c.model,MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{Float64}}())
            for m in coarse_states(domain,2)
                x = Dict(v=>m[i] for (i,v) in enumerate(vars))
                dispatched = f.constant + sum(t.coefficient*x[t.variable] for t in f.affine_terms; init=0.) +
                    sum(t.coefficient*x[t.variable_1]*x[t.variable_2]/(t.variable_1==t.variable_2 ? 2 : 1) for t in f.quadratic_terms; init=0.)
                @test dispatched == scalar(independent_lift(m))
            end
        end)
        opt = coarse_solve(model,groups; child)
        data = decomposition(opt); info = data["coarse"]
        @test info["macro_groups"] == [[3,4],[1,2]]
        @test info["macro_count"] == 2 && info["represented_original_count"] == 4
        @test info["frozen_incumbent"] == r
        @test info["frozen_incumbent_version"] == 0 && !info["original_proof"]
        @test info["invocation"] == 1 && info["complete"]
        @test QUBOTools.value(opt,1) == scalar(QUBOTools.state(opt,1))
        @test data["labels"] == QUBOTools.variables(model)
        @test !data["separable_proof"]
        @test QUBOTools.state(opt,1)[5:6] == r[5:6]
        optimum = sense === :min ? minimum(scalar,rows) : maximum(scalar,rows)
        @test QUBOTools.value(opt,1) == optimum
        if scale == 0
            @test seen[] == data["attempted_calls"] == 0
            @test MOI.get(opt,MOI.TerminationStatus()) === MOI.OPTIMAL
        else
            call = only(data["calls"])
            @test seen[] == data["attempted_calls"] == data["completed_calls"] == 1
            @test call["source_to_child"] == [9,8]
            @test !haskey(call,"original_to_reduced") && !haskey(call,"selected_indices")
            @test call["exact"] && !call["original_proof"]
            @test MOI.get(opt,MOI.TerminationStatus()) === MOI.LOCALLY_SOLVED
        end
    end
end

@testset "Joint orientation crosses an exact partition barrier" begin
    for domain in (:bool,:spin)
        binary = domain === :bool
        model = QUBOTools.Model{Symbol,Float64,Int}([:d,:b,:a,:c], collect(1:4),
            fill(binary ? 1. : -.5,4), [1,1,2,2],[3,4,3,4],fill(binary ? -2. : -.5,4);domain)
        scalar(x) = binary ? sum(x)-2*(x[1]+x[2])*(x[3]+x[4]) :
            -.5sum(x)-.5*(x[1]+x[2])*(x[3]+x[4])
        partition = solve_model(model; budget=2, selection=:partition, partition_plan=[[1,2],[3,4]],
            child=()->coarse_test_child(), max_sweeps=3)
        coarse = coarse_solve(model,[[1,2],[3,4]])
        @test QUBOTools.value(partition,1) == 0.
        @test QUBOTools.value(coarse,1) == -4.
        @test QUBOTools.value(coarse,1) == minimum(scalar(x) for x in coarse_states(domain,4))
        @test QUBOTools.state(coarse,1) == ones(Int,4)
        @test MOI.get(coarse,MOI.TerminationStatus()) === MOI.LOCALLY_SOLVED
    end
    # Capacity counts groups, including a group containing an original isolate.
    model = QUBOTools.Model{Int,Float64,Int}(collect(1:8),[1],[-1.],[1],[7],[-1.])
    opt = coarse_solve(model,[collect(1:4),collect(5:8)])
    @test only(decomposition(opt)["calls"])["macro_count"] == 2
    @test decomposition(opt)["coarse"]["represented_original_count"] == 8
    @test length(only(decomposition(opt)["calls"])["source_to_child"]) == 2
    @test QUBOTools.state(opt,1) == ones(Int,8)
    # Non-surjective exact coarse solution misses the original global optimum.
    model = QUBOTools.Model{Symbol,Float64,Int}([:a,:b],[1,2],[-2.,1.],Int[],Int[],Float64[])
    opt = coarse_solve(model,[[1,2]])
    @test QUBOTools.value(opt,1) == -1.
    @test minimum(-2x[1]+x[2] for x in coarse_states(:bool,2)) == -2.
    @test MOI.get(opt,MOI.TerminationStatus()) === MOI.LOCALLY_SOLVED
    @test !decomposition(opt)["coarse"]["original_proof"]
    # Even a surjective map remains conservative in this first implementation.
    opt = coarse_solve(model,[[1],[2]])
    @test QUBOTools.value(opt,1) == -2.
    @test MOI.get(opt,MOI.TerminationStatus()) === MOI.LOCALLY_SOLVED
end

@testset "Coarse plan ownership and validation before shortcuts" begin
    groups = [[2,1],[3,4]]
    opt = coarse_solve(direct_model(),groups)
    groups[1][1] = 4
    getter = MOI.get(opt,MOI.RawOptimizerAttribute("coarse_groups"))
    getter[1][1] = 4
    @test MOI.get(opt,MOI.RawOptimizerAttribute("coarse_groups")) == [[2,1],[3,4]]
    for plan in (nothing, [[1,1]], [[1],[1,2]], [Int[]], [[5]], Vector{Int}[], [[1],[2],[3]])
        for model in (direct_model(), direct_model(;scale=0.))
            calls = Ref(0)
            opt = coarse_solve(model,plan; budget=2, child=()->(calls[]+=1; coarse_test_child()))
            @test MOI.get(opt,MOI.TerminationStatus()) === MOI.INVALID_OPTION
            @test calls[] == decomposition(opt)["attempted_calls"] == 0
        end
    end
    for plan in ([[true]], [[0]], [[1.]], "invalid")
        @test_throws ArgumentError QUBODecomposition.Optimizer(coarse_groups=plan)
    end
    for options in ((selection=:partition,), (partition_plan=[[1]],), (consensus_plan=[[1]],),
        (separator=[1],), (separator_pruning=true,), (component_executor=QUBODecomposition.SequentialComponentExecutor(),))
        opt = coarse_solve(direct_model(),[[1,2]]; options...)
        @test MOI.get(opt,MOI.TerminationStatus()) === MOI.INVALID_OPTION
        @test decomposition(opt)["attempted_calls"] == 0
    end
    empty = QUBOTools.Model{Int,Float64,Int}(Int[],Int[],Float64[],Int[],Int[],Float64[];offset=9.)
    opt = coarse_solve(empty,Vector{Int}[])
    @test MOI.get(opt,MOI.TerminationStatus()) === MOI.OPTIMAL
    @test QUBOTools.value(opt,1) == 9.
    @test decomposition(opt)["attempted_calls"] == 0
    @test isempty(decomposition(opt)["coarse"]["macro_groups"])
    @test MOI.get(coarse_solve(empty,[[1]]),MOI.TerminationStatus()) === MOI.INVALID_OPTION
end

@testset "Coarse row transaction, caps, interruption and child provenance" begin
    # Flipping both macrovariables strictly improves this start to [1,0,1,1].
    model = direct_model()
    groups = [[1],[3,4]]
    for status in (MOI.OPTIMAL,MOI.LOCALLY_SOLVED,MOI.INTERRUPTED,MOI.TIME_LIMIT)
        opt = coarse_solve(model,groups; seed=17, child=()->coarse_test_child(
            rows=[[0,0],[1,1],[1,0],[1,1]],values=[-1000.,500.,900.,0.],status))
        @test QUBOTools.state(opt,1) == [1,0,1,1] # best original row, independently ranked
        @test QUBOTools.value(opt,1) == 2.
        @test decomposition(opt)["candidate_evaluations"] == 5
        @test decomposition(opt)["accepted_improvements"] == 1
        @test only(decomposition(opt)["calls"])["seed"] == 17
        @test only(decomposition(opt)["calls"])["public_status"] == string(status)
        @test MOI.get(opt,MOI.TerminationStatus()) ===
            (status in (MOI.INTERRUPTED,MOI.TIME_LIMIT) ? status : MOI.LOCALLY_SOLVED)
    end
    for child in (
        ()->coarse_test_child(rows=[[1,1],[2,0]]),
        ()->coarse_test_child(rows=[[1,1],[1]]),
        ()->coarse_test_child(rows=[[1,1],[NaN,0]]),
        ()->coarse_test_child(rows=[[1,1],[1,0]],values=[0.,Inf]),
        ()->coarse_test_child(rows=[[1,1]],row_status=MOI.NO_SOLUTION),
        ()->coarse_test_child(rows=[[1,1]],status=MOI.OTHER_ERROR),
        ()->coarse_test_child(rows=[]),
        ()->coarse_test_child(corrupt_map=true))
        opt = coarse_solve(model,groups;child)
        @test MOI.get(opt,MOI.TerminationStatus()) === MOI.OTHER_ERROR
        @test QUBOTools.state(opt,1) == zeros(Int,4)
        @test decomposition(opt)["completed_calls"] == 0 && decomposition(opt)["incomplete_scan"]
    end
    for count in (-1,true,1.0,NaN)
        opt = coarse_solve(model,groups;child=()->coarse_test_child(result_count=count))
        @test MOI.get(opt,MOI.TerminationStatus()) === MOI.OTHER_ERROR
        @test QUBOTools.state(opt,1) == zeros(Int,4)
    end
    for status in (MOI.INTERRUPTED,MOI.LOCALLY_SOLVED)
        rows = status === MOI.INTERRUPTED ? [] : [[0,0]]
        opt = coarse_solve(model,groups;child=()->coarse_test_child(;rows,status))
        @test QUBOTools.state(opt,1) == zeros(Int,4)
        @test decomposition(opt)["completed_calls"] == 1
        @test decomposition(opt)["accepted_improvements"] == 0
    end
    for failure in (InterruptException(),ErrorException("child failed"))
        opt = coarse_solve(model,groups;child=()->coarse_test_child(callback=_->throw(failure)))
        @test QUBOTools.state(opt,1) == zeros(Int,4)
        @test decomposition(opt)["attempted_calls"] == 1 && decomposition(opt)["completed_calls"] == 0
        @test MOI.get(opt,MOI.TerminationStatus()) === (failure isa InterruptException ? MOI.INTERRUPTED : MOI.OTHER_ERROR)
    end
    for child in (() -> error("factory failed"), () -> 42)
        opt = coarse_solve(model,groups;child)
        @test decomposition(opt)["attempted_calls"] == 1
        @test QUBOTools.state(opt,1) == zeros(Int,4)
    end
    for cap in (2,3)
        opt = coarse_solve(model,groups;max_candidate_evaluations=cap,
            child=()->coarse_test_child(rows=[[1,0],[1,1]],status=MOI.INTERRUPTED))
        @test QUBOTools.state(opt,1) == (cap == 2 ? zeros(Int,4) : [1,0,1,1])
        @test decomposition(opt)["candidate_evaluations"] == cap
        @test decomposition(opt)["incomplete_scan"] == (cap == 2)
        @test MOI.get(opt,MOI.TerminationStatus()) === (cap == 2 ? MOI.ITERATION_LIMIT : MOI.INTERRUPTED)
    end
    for caps in ((max_child_calls=0,), (max_candidate_evaluations=1,))
        opt = coarse_solve(model,groups;caps...)
        @test decomposition(opt)["attempted_calls"] == 0
        @test MOI.get(opt,MOI.TerminationStatus()) === MOI.ITERATION_LIMIT
    end
    for caps in ((max_child_calls=1,), (max_candidate_evaluations=2,))
        opt = coarse_solve(model,groups;caps...)
        @test decomposition(opt)["completed_calls"] == 1
        @test MOI.get(opt,MOI.TerminationStatus()) === MOI.ITERATION_LIMIT
    end
end

@testset "Coarse cooperative deadlines cover construction, lifting and commit" begin
    for phase in (:coarse_plan,:coarse_construction,:before_factory,:before_child,:dispatch,
        :after_child,:before_row,:coarse_lift,:reconstruct,:before_commit)
        now = Ref(0.)
        opt = QUBODecomposition.Optimizer(strategy=:coarse,coarse_groups=[[1],[3,4]],
            max_variables=2,child_optimizer=()->coarse_test_child(rows=[[1,1]],status=MOI.INTERRUPTED))
        QUBODrivers.set_model!(opt,direct_model())
        opt.clock = ()->now[]
        opt.checkpoint = p -> (p === phase && (now[]=1.); nothing)
        MOI.set(opt,MOI.TimeLimitSec(),1.)
        MOI.optimize!(opt)
        @test MOI.get(opt,MOI.TerminationStatus()) === MOI.TIME_LIMIT
        @test QUBOTools.state(opt,1) == zeros(Int,4)
        @test decomposition(opt)["accepted_improvements"] == 0
    end
    seen = Ref{Any}(nothing)
    opt = QUBODecomposition.Optimizer(strategy=:coarse,coarse_groups=[[1],[3,4]],
        max_variables=2,child_time_limit_sec=3.,child_optimizer=()->coarse_test_child(callback=c->(seen[]=c.limit)))
    QUBODrivers.set_model!(opt,direct_model()); opt.clock=()->4.
    MOI.set(opt,MOI.TimeLimitSec(),5.)
    MOI.set(opt,MOI.RawOptimizerAttribute("absolute_deadline_sec"),6.)
    MOI.optimize!(opt)
    @test seen[] == 2.
    @test decomposition(opt)["effective_deadline_sec"] == 6.
end

@testset "Coarse maps rebuild with changed input and fixed-variable reconstruction" begin
    opt = QUBODecomposition.Optimizer(strategy=:coarse,coarse_groups=[[2,1],[3,4]],
        max_variables=2,child_optimizer=()->coarse_test_child())
    for (invocation,(domain,sense,scale,reversed)) in enumerate(((:bool,:min,1.,false),(:spin,:max,-2.,true),(:bool,:max,.75,true)))
        model, r, scalar = coarse_fixture(;domain,sense,scale,reversed)
        QUBODrivers.set_model!(opt,model)
        @test MOI.get(opt,MOI.ResultCount()) == 0
        MOI.optimize!(opt)
        info = decomposition(opt)["coarse"]
        @test info["invocation"] == invocation && info["frozen_incumbent"] == r
        @test info["frozen_incumbent_version"] == 0
        @test QUBOTools.value(opt,1) == scalar(QUBOTools.state(opt,1))
        @test decomposition(opt)["attempted_calls"] == 1
    end
    previous = deepcopy(decomposition(opt))
    QUBOTools.data(QUBOTools.linear_form(QUBOTools.form(QUBOTools.backend(opt))))[1] = 7.
    MOI.optimize!(opt)
    @test decomposition(opt)["invocation"] == 4
    @test previous["invocation"] == 3
    @test decomposition(opt)["coarse"]["frozen_incumbent"] == previous["coarse"]["frozen_incumbent"]
    MOI.set(opt,MOI.RawOptimizerAttribute("coarse_groups"),[[1]])
    @test MOI.get(opt,MOI.ResultCount()) == 0
    MOI.optimize!(opt)
    @test decomposition(opt)["coarse"]["macro_count"] == 1
    @test decomposition(opt)["coarse"]["original_to_macro"] == [1,0,0,0,0,0]
    for spin in (false,true), maximize in (false,true)
        source = MOI.Utilities.UniversalFallback(MOI.Utilities.Model{Float64}())
        vars = MOI.add_variables(source,4)
        for v in vars
            MOI.add_constraint(source,v,spin ? QUBODrivers.Spin() : MOI.ZeroOne())
        end
        fixed = spin ? -1. : 1.
        MOI.add_constraint(source,vars[1],MOI.EqualTo(fixed))
        f = MOI.ScalarQuadraticFunction(
            [MOI.ScalarQuadraticTerm(3.,vars[1],vars[2]),MOI.ScalarQuadraticTerm(-4.,vars[2],vars[3])],
            [MOI.ScalarAffineTerm(c,v) for (c,v) in zip([2.,2.,1.,1.],vars)],5.)
        MOI.set(source,MOI.ObjectiveFunction{typeof(f)}(),f)
        MOI.set(source,MOI.ObjectiveSense(),maximize ? MOI.MAX_SENSE : MOI.MIN_SENSE)
        opt = QUBODecomposition.Optimizer(strategy=:coarse,coarse_groups=[[1,2],[3]],
            max_variables=2,child_optimizer=()->coarse_test_child())
        map = MOI.copy_to(opt,source); MOI.optimize!(opt)
        x = [MOI.get(opt,MOI.VariablePrimal(),map[v]) for v in vars]
        @test x[1] == fixed
        @test 5+2x[1]+2x[2]+x[3]+x[4]+3x[1]*x[2]-4x[2]*x[3] == MOI.get(opt,MOI.ObjectiveValue())
        @test decomposition(opt)["coarse"]["represented_original_count"] == 3
        @test QUBOTools.state(opt,1) == x[2:4]
        @test MOI.get(opt,MOI.TerminationStatus()) === MOI.LOCALLY_SOLVED
    end
    @test COARSE_TEST_ORACLE_WORK[] <= 16_384
    @test COARSE_TEST_CHILD_WORK[] <= 65_536
end

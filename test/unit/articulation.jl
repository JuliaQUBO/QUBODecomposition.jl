# SPDX-License-Identifier: MPL-2.0
import Random
@testset "Automatic articulation separator" begin
    # Deliberately slow, independent oracle: a Boolean matrix and fresh BFS for
    # every vertex deletion. Never calls the planner or its connectivity helper.
    function deletion_components(n, edges, removed=0)
        graph = falses(n,n)
        for (i,j) in edges
            graph[i,j] = graph[j,i] = true
        end
        seen = falses(n)
        removed > 0 && (seen[removed] = true)
        components = Vector{Int}[]
        for root in 1:n
            seen[root] && continue
            queue = [root]; seen[root] = true
            cursor = 1
            while cursor <= length(queue)
                v = queue[cursor]; cursor += 1
                for w in 1:n
                    if graph[v,w] && !seen[w]
                        seen[w] = true; push!(queue,w)
                    end
                end
            end
            push!(components,sort(queue))
        end
        return components
    end
    function deletion_oracle(n, edges, capacity, cap=1)
        n <= 10 || error("connectivity oracle size guard")
        original = deletion_components(n,edges)
        maximum(length.(original);init=0) <= capacity && return Int[]
        cap >= 1 || return nothing
        candidates = Tuple{Int,Int}[]
        for v in 1:n
            residual = deletion_components(n,edges,v)
            length(residual) > length(original) || continue # genuine articulation
            score = maximum(length.(residual);init=0)
            score <= capacity && push!(candidates,(score,v))
        end
        return isempty(candidates) ? nothing : [last(minimum(candidates))]
    end
    # Planning-only graph inputs avoid model construction and child execution.
    function planning(n,edges,capacity;cap=1,checkpoint=_->nothing)
        opt = QUBODecomposition.Optimizer(max_variables=capacity,
            strategy=:separator,separator=:articulation,max_separator_size=cap)
        opt.checkpoint = checkpoint
        ctx = QUBODecomposition.SolveState(nothing,nothing,0,0,nothing,
            Dict{String,Any}("separator"=>Dict{String,Any}("discovery"=>nothing)))
        snap = (;n,quadratic=[((i,j),(-1.)^k) for (k,(i,j)) in enumerate(edges)])
        selected = try
            first(QUBODecomposition.separator_plan(opt,ctx,snap))
        catch err
            err isa QUBODecomposition.UnsupportedChild || rethrow()
            nothing
        end
        return selected,ctx.data["separator"]["discovery"]
    end
    @testset "Independent deletion oracle on every simple graph through five vertices" begin
        for n in 0:5
            possible = [(i,j) for i in 1:n for j in i+1:n]
            for mask in 0:(1<<length(possible))-1
                edges = [edge for (k,edge) in enumerate(possible) if !iszero(mask & (1<<(k-1)))]
                for capacity in 1:max(1,n)
                    selected,work = planning(n,edges,capacity)
                    @test selected == deletion_oracle(n,edges,capacity)
                    @test work["complete"]
                    if work["reason"] != "already_fitting"
                        @test work["visited_vertices"] == n
                        @test work["examined_adjacencies"] == 2length(edges)
                    end
                end
            end
        end
        rng = Random.Xoshiro(22)
        for n in 6:9, repetition in 1:40
            edges = [(i,j) for i in 1:n for j in i+1:n if Random.rand(rng)<0.3]
            capacity = Random.rand(rng,1:n)
            @test first(planning(n,edges,capacity)) == deletion_oracle(n,edges,capacity)
        end
    end
    @testset "Capacity, scoring, ties and whole-model refusal" begin
        fixtures = [
            (6,[(i,i+1) for i in 1:5],3,[3]), # 3/4 score tie, ascending index
            (7,[(i,i+1) for i in 1:6],5,[4]), # score minimizes, not first qualifying
            (5,[(1,i) for i in 2:5],1,[1]), # DFS root articulation
            (7,[(1,2),(1,3),(2,3),(1,4),(1,5),(4,5),(5,6)],3,[1]),
            (8,[(i,i+1) for i in 1:5],3,[3]), # retained isolates
            (9,[(i,i+1) for i in 1:4] ∪ [(6,7),(7,8),(8,9)],2,nothing),
            (5,[(i,i+1) for i in 1:4],1,nothing), # articulations cannot fit
            (4,[(1,2),(2,3),(3,4),(1,4)],3,nothing), # valid deletion, no articulation
            (4,[(i,j) for i in 1:4 for j in i+1:4],3,nothing),
            (6,[(1,2),(2,3),(4,5)],3,Int[])]
        for (n,edges,capacity,expected) in fixtures
            actual,work = planning(n,edges,capacity)
            @test actual == expected == deletion_oracle(n,edges,capacity)
            if actual !== nothing
                residual = deletion_components(n,edges,isempty(actual) ? 0 : only(actual))
                @test work["selected_largest_residual"] == maximum(length.(residual);init=0)
            end
        end
        @test first(planning(5,[(1,i) for i in 2:5],1;cap=0)) === nothing
        @test first(planning(5,[(1,2)],2;cap=0)) == Int[]
        # A fitting outside component can dominate scores and change a tie.
        edges = [(i,i+1) for i in 1:4] ∪ [(6,7),(7,8)]
        @test first(planning(8,edges,3)) == [2]
    end
    @testset "Long path without recursion or exponential children" begin
        n = 30_000
        edges = [(i,i+1) for i in 1:n-1]
        selected,work = planning(n,edges,n÷2)
        @test selected == [n÷2]
        @test work["visited_vertices"] == n
        @test work["examined_adjacencies"] == 2(n-1)
        @test work["articulation_vertices"] == n-2
        @test work["qualifying_vertices"] == 2
    end
    @testset "Independent original energy, matching manual plan and public certificates" begin
        for (n,edges,capacity) in ((6,[(i,i+1) for i in 1:5],3),
            (5,[(1,i) for i in 2:5],1),
            (7,[(1,2),(1,3),(2,3),(1,4),(1,5),(4,5),(5,6)],3),
            (4,[(1,2)],2)), domain in (:bool,:spin), sense in (:min,:max), scale in (-2.5,0.75)
            n <= 10 || error("energy oracle size guard")
            linear = [(-1.)^i*(i+1)/2 for i in 1:n]
            weights = [(-1.)^k*(k+2)/4 for k in eachindex(edges)]
            labels = [Symbol("label",11i) for i in 1:n]
            model = QUBOTools.Model{Symbol,Float64,Int}(labels,collect(1:n),linear,
                first.(edges),last.(edges),weights;domain,sense,scale,offset=3.25)
            scalar(x) = scale*(3.25+sum(linear[i]*x[i] for i in 1:n)+
                sum(weights[k]*x[i]*x[j] for (k,(i,j)) in enumerate(edges)))
            values = [scalar(x) for x in Iterators.product(fill(domain===:bool ? (0,1) : (-1,1),n)...)]
            expected = (sense===:min ? minimum : maximum)(values)
            selected = deletion_oracle(n,edges,capacity)
            for child in (() -> FixtureChild(), () -> FixtureChild(status=MOI.LOCALLY_SOLVED),
                () -> QUBODrivers.ExactSampler.Optimizer())
                automatic = solve_model(model;budget=capacity,child,strategy=:separator,separator=:articulation)
                manual = solve_model(model;budget=capacity,child,strategy=:separator,separator=selected)
                d,p = decomposition(automatic),decomposition(automatic)["separator"]
                @test QUBOTools.value(automatic,1) == QUBOTools.value(manual,1) == expected
                @test scalar(QUBOTools.state(automatic,1)) == expected
                @test QUBOTools.state(automatic,1) == QUBOTools.state(manual,1)
                @test MOI.get(automatic,MOI.TerminationStatus()) === MOI.get(manual,MOI.TerminationStatus())
                @test p["indices"] == selected
                @test p["proof_complete"] == decomposition(manual)["separator"]["proof_complete"]
                @test d["attempted_calls"] == decomposition(manual)["attempted_calls"]
                @test d["candidate_evaluations"] == decomposition(manual)["candidate_evaluations"]
                @test d["configured_caps"]["separator"] === :articulation
                @test d["labels"] == labels
                @test 0 <= p["discovery"]["elapsed_sec"] <= d["phase_sec"]["preparation"]
                @test all(c["selected_indices"]==p["residual_components"][c["component"]] for c in d["calls"])
            end
        end
    end
    @testset "Refusal, small coefficients and validation precedence" begin
        for scale in (0.,1.), edges in ([(1,2),(2,3),(3,4),(1,4)],
            [(i,j) for i in 1:4 for j in i+1:4])
            model = QUBOTools.Model{Int,Float64,Int}(collect(1:4),[1],[-1.],
                first.(edges),last.(edges),fill(1e-100,length(edges));scale)
            count=Ref(0); child=()->(count[]+=1;FixtureChild())
            auto = solve_model(model;child,budget=3,strategy=:separator,separator=:articulation)
            @test MOI.get(auto,MOI.TerminationStatus()) === MOI.INVALID_OPTION
            @test count[] == decomposition(auto)["attempted_calls"] == 0
            @test occursin("no supported articulation",decomposition(auto)["diagnostic"])
            manual = solve_model(model;budget=3,strategy=:separator,separator=[1])
            @test MOI.get(manual,MOI.TerminationStatus()) === MOI.OPTIMAL
            invalid = solve_model(model;budget=3,strategy=:separator,separator=[5])
            @test MOI.get(invalid,MOI.TerminationStatus()) === MOI.INVALID_OPTION
        end
        for n in (0,3), scale in (0.,1.)
            m = QUBOTools.Model{Int,Float64,Int}(collect(1:n),Int[],Float64[],Int[],Int[],Float64[];scale)
            o=solve_model(m;budget=1,strategy=:separator,separator=:articulation,max_separator_size=0,max_child_calls=0)
            @test MOI.get(o,MOI.TerminationStatus()) === MOI.OPTIMAL
            @test decomposition(o)["separator"]["indices"] == Int[]
        end
    end
    @testset "Raw options, ownership, invalidation and rebuilding" begin
        for value in (:automatic,:unknown,"articulation",nothing,1,[:articulation],[true])
            @test_throws ArgumentError QUBODecomposition.Optimizer(separator=value)
        end
        m = QUBOTools.Model(Dict(:z=>2.,:a=>1.,:m=>1.),Dict((:z,:a)=>-4.,(:z,:m)=>-4.))
        o = solve_model(m;budget=1,strategy=:separator,separator=:articulation)
        @test decomposition(o)["separator"]["indices"] == [3]
        @test MOI.get(o,MOI.RawOptimizerAttribute("separator")) === :articulation
        for (key,value,expected) in (("max_variables",3,Int[]),("max_variables",1,[3]),
            ("separator",[3],[3]),("separator",:articulation,[3]))
            MOI.set(o,MOI.RawOptimizerAttribute(key),value)
            @test MOI.get(o,MOI.ResultCount()) == 0
            MOI.optimize!(o)
            @test decomposition(o)["separator"]["indices"] == expected
        end
        MOI.set(o,MOI.RawOptimizerAttribute("max_separator_size"),0)
        MOI.optimize!(o)
        @test MOI.get(o,MOI.TerminationStatus()) === MOI.INVALID_OPTION
        @test decomposition(o)["separator"]["discovery"]["reason"] == "separator_cap_zero"
        # Mutating result metadata cannot affect subsequent discovery or options.
        decomposition(o)["separator"]["indices"] = [1]
        MOI.set(o,MOI.RawOptimizerAttribute("max_separator_size"),1)
        MOI.optimize!(o)
        @test decomposition(o)["separator"]["indices"] == [3]
        changed = QUBOTools.Model(Dict(:a=>1.,:m=>2.,:z=>1.),Dict((:a,:m)=>-4.,(:m,:z)=>-4.))
        QUBODrivers.set_model!(o,changed); MOI.optimize!(o)
        @test decomposition(o)["separator"]["indices"] == [2]
        QUBODrivers.set_model!(o,QUBOTools.Model(Dict(:new=>-1.),Dict{Tuple{Symbol,Symbol},Float64}()))
        MOI.optimize!(o)
        @test decomposition(o)["labels"] == [:new]
        @test decomposition(o)["separator"]["indices"] == Int[]
        for strategy in (:whole_model,:components,:components_then_sweeps)
            MOI.set(o,MOI.RawOptimizerAttribute("strategy"),strategy); MOI.optimize!(o)
            @test MOI.get(o,MOI.TerminationStatus()) === MOI.OPTIMAL
            @test decomposition(o)["separator"] === nothing
        end
        @test_throws ArgumentError MOI.set(o,MOI.RawOptimizerAttribute("separator"),:unknown)
        @test MOI.get(o,MOI.ResultCount()) == 0
    end
    @testset "Cooperative deadlines and interruptions before child dispatch" begin
        m = QUBOTools.Model{Int,Float64,Int}(collect(1:7),collect(1:7),ones(7),
            collect(1:6),collect(2:7),fill(-2.,6))
        for phase in (:articulation_graph,:articulation_ordering,:articulation_traversal,
            :articulation_scoring,:articulation_complete,:separator_plan_validation), timeout in (false,true)
            calls=Ref(0); clock=Ref(0.); visits=Ref(0)
            o=QUBODecomposition.Optimizer(child_optimizer=()->(calls[]+=1;FixtureChild()),
                max_variables=3,strategy=:separator,separator=:articulation)
            QUBODrivers.set_model!(o,m)
            o.clock=()->clock[]; MOI.set(o,MOI.TimeLimitSec(),1.)
            o.checkpoint=p->(if p===phase
                visits[]+=1
                if visits[] == (phase===:articulation_complete ? 1 : 2)
                    timeout ? (clock[]=2.) : throw(InterruptException())
                end
            end)
            MOI.optimize!(o)
            d=decomposition(o); proof=d["separator"]; work=proof["discovery"]
            @test MOI.get(o,MOI.TerminationStatus()) === (timeout ? MOI.TIME_LIMIT : MOI.INTERRUPTED)
            @test calls[] == d["attempted_calls"] == 0
            @test proof["required_branches"] === nothing
            @test !proof["proof_complete"] && proof["indices"] == Int[]
            @test work["complete"] == (phase===:separator_plan_validation)
            @test work["complete"] || work["reason"] == d["stop_reason"]
            @test work["elapsed_sec"] <= d["phase_sec"]["preparation"]
            @test QUBOTools.state(o,1) == zeros(Int,7)
        end
        # Interruption during enumeration retains the same branch transaction as
        # an identical supplied plan; discovery does not confer a certificate.
        for selected in (:articulation,[4])
            o=QUBODecomposition.Optimizer(child_optimizer=()->FixtureChild(),max_variables=3,
                strategy=:separator,separator=selected)
            QUBODrivers.set_model!(o,m)
            visits=Ref(0)
            o.checkpoint=p->(p===:separator_commit && (visits[]+=1)==2 && throw(InterruptException()))
            MOI.optimize!(o)
            @test MOI.get(o,MOI.TerminationStatus()) === MOI.INTERRUPTED
            @test decomposition(o)["separator"]["completed_branches"] == 1
            @test !decomposition(o)["separator"]["proof_complete"]
            # The first completed branch improves both three-vertex paths;
            # interruption of branch two must retain that complete incumbent.
            scalar(x) = sum(x) - 2sum(x[i]*x[i+1] for i in 1:6)
            branch_values = [scalar(collect(x)) for x in Iterators.product(fill((0,1),7)...) if x[4]==0]
            @test QUBOTools.value(o,1) == minimum(branch_values)
            @test QUBOTools.state(o,1) == [1,1,1,0,1,1,1]
        end
    end
end

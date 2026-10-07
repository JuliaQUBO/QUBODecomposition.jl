# SPDX-License-Identifier: MPL-2.0
@testset "Scalar oracle, frames, forms, labels and isolates" begin
    for domain in (:bool,:spin), sense in (:min,:max), scale in (2.0,-3.0,0.0),
        labels in ([:z,:a,:q,:isolate], [91,3,47,2]), storage in (:sparse,:dense,:dict)
        base = direct_model(; labels, domain, sense, scale)
        form = QUBOTools.form(base, storage, Float64)
        model = QUBOTools.Model{eltype(labels),Float64,Int}(QUBOTools.VariableMap{eltype(labels)}(Dict(i=>label for (i,label) in enumerate(labels))), form)
        log=Any[]
        opt=solve_model(model; child=() -> FixtureChild(;log))
        states=Iterators.product(fill(domain===:bool ? (0,1) : (-1,1),4)...)
        # Original scalar expression: no QUBOTools energy or child objective oracle.
        oracle(x)=scale*(5-3*x[1]+2*x[2]-x[3]+4*x[1]*x[2]-2*x[2]*x[3])
        expected=(sense===:min ? minimum : maximum)(oracle(x) for x in states)
        state=QUBOTools.state(opt,1)
        @test oracle(state)==expected==MOI.get(opt,MOI.ObjectiveValue())
        @test MOI.get(opt,MOI.TerminationStatus())===MOI.OPTIMAL
        @test QUBOTools.variables(opt)==QUBOTools.variables(model)
        @test length(state)==4
        @test QUBOTools.domain(opt)===QUBOTools.domain(model)
        @test QUBOTools.sense(opt)===QUBOTools.sense(model)
        @test decomposition(opt)["attempted_calls"]==(scale==0 ? 0 : 1)
        @test isempty(QUBODrivers.validate_metadata(QUBOTools.solution(opt)))
        @test QUBOTools.reads(opt,1)==1
        @test decomposition(opt)["labels"]==labels
        scale!=0 && @test only(decomposition(opt)["calls"])["source_to_child"]==[11,10,9,8]
    end
end
@testset "Empty, constant and singleton" begin
    for domain in (:bool,:spin), sense in (:min,:max), n in (0,1,4)
        labels=collect(1:n)
        model=QUBOTools.Model{Int,Float64,Int}(Set(labels),Dict(i=>0.0 for i in labels),Dict{Tuple{Int,Int},Float64}(); domain,sense,scale=-2.0,offset=7.0)
        opt=solve_model(model; budget=1,child=() -> error("constant model called child"))
        @test MOI.get(opt,MOI.TerminationStatus())===MOI.OPTIMAL
        @test QUBOTools.value(opt,1)==-14.0
        @test length(QUBOTools.state(opt,1))==n
        @test decomposition(opt)["attempted_calls"]==0
    end
    for domain in (:bool,:spin), sense in (:min,:max)
        model=QUBOTools.Model(Dict(:only=>-4.0),Dict{Tuple{Symbol,Symbol},Float64}();domain,sense,offset=3.0)
        opt=solve_model(model;budget=1)
        vals=domain===:bool ? (3.0,-1.0) : (7.0,-1.0)
        @test QUBOTools.value(opt,1)==(sense===:min ? minimum(vals) : maximum(vals))
        @test decomposition(opt)["attempted_calls"]==1
    end
end
@testset "Configuration and unsupported capacity" begin
    opt=QUBODecomposition.Optimizer()
    @test MOI.get(opt,MOI.TerminationStatus())===MOI.OPTIMIZE_NOT_CALLED
    MOI.optimize!(opt)
    @test MOI.get(opt,MOI.TerminationStatus())===MOI.INVALID_OPTION
    @test MOI.get(opt,MOI.ResultCount())==0
    for value in (0,-1,1.5,true,"2")
        @test_throws ArgumentError QUBODecomposition.Optimizer(;max_variables=value)
    end
    for key in (:max_sweeps,:max_child_calls,:max_candidate_evaluations,:stagnation_sweeps)
        for value in (-1,1.5,true)
            @test_throws ArgumentError QUBODecomposition.Optimizer(;Dict(key=>value)...)
        end
    end
    for key in (:child_time_limit_sec,), value in (-1,Inf,NaN,true)
        @test_throws ArgumentError QUBODecomposition.Optimizer(;Dict(key=>value)...)
    end
    for value in (-1,2^31-1,true,0.5)
        @test_throws ArgumentError QUBODecomposition.Optimizer(;seed=value)
    end
    @test_throws ArgumentError QUBODecomposition.Optimizer(;strategy=:unsupported)
    @test_throws MOI.UnsupportedAttribute QUBODecomposition.Optimizer(;unknown=1)
    opt=solve_model(direct_model(); budget=1,strategy=:whole_model)
    @test MOI.get(opt,MOI.TerminationStatus())===MOI.INVALID_OPTION
    @test MOI.get(opt,MOI.ResultCount())==1
    @test decomposition(opt)["attempted_calls"]==0
    @test occursin("4 free logical variables",decomposition(opt)["diagnostic"])
    MOI.set(opt,MOI.RawOptimizerAttribute("max_variables"),4)
    MOI.optimize!(opt)
    @test MOI.get(opt,MOI.ResultCount())==1
    @test_throws ArgumentError MOI.set(opt,MOI.RawOptimizerAttribute("seed"),true)
    @test MOI.get(opt,MOI.ResultCount())==0
    @test MOI.get(opt,MOI.TerminationStatus())===MOI.OPTIMIZE_NOT_CALLED
end

@testset "Starts and normalized constant spin diagonals" begin
    model=direct_model(;domain=:spin)
    QUBOTools.attach!(model,:b=>1)
    opt=solve_model(model;max_child_calls=0)
    @test QUBOTools.state(opt,1)==[-1,1,-1,-1]
    @test QUBOTools.value(opt,1)==18.0
    huge=floatmax(Float64)
    model=QUBOTools.Model(Dict(:a=>huge,:b=>huge),Dict{Tuple{Symbol,Symbol},Float64}();scale=0.0,domain=:spin)
    opt=solve_model(model;budget=1)
    @test MOI.get(opt,MOI.TerminationStatus())===MOI.OPTIMAL
    @test QUBOTools.value(opt,1)==0.0
    form=QUBOTools.DenseForm{Float64}(2,zeros(2),[3.0 0.0;0.0 4.0],-2.0,5.0;domain=:spin)
    model=QUBOTools.Model{Symbol,Float64,Int}(QUBOTools.VariableMap{Symbol}(Dict(1=>:u,2=>:v)),form)
    opt=solve_model(model;budget=1)
    @test MOI.get(opt,MOI.TerminationStatus())===MOI.OPTIMAL
    @test QUBOTools.value(opt,1)==-24.0
    @test decomposition(opt)["attempted_calls"]==0
end

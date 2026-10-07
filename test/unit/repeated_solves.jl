# SPDX-License-Identifier: MPL-2.0
@testset "Fresh snapshots and invalidation" begin
    opt=QUBODecomposition.Optimizer(;child_optimizer=() -> FixtureChild(),max_variables=8)
    models=[direct_model(),direct_model(;domain=:spin,sense=:max,scale=-2.0,offset=8.0),
        direct_model(;labels=[:isolate,:c,:b,:a]),
        QUBOTools.Model(Dict(:single=>-2.0),Dict{Tuple{Symbol,Symbol},Float64}();offset=3.0)]
    for model in models
        QUBODrivers.set_model!(opt,model)
        @test MOI.get(opt,MOI.ResultCount())==0
        @test MOI.get(opt,MOI.TerminationStatus())===MOI.OPTIMIZE_NOT_CALLED
        MOI.optimize!(opt)
        fresh=solve_model(model)
        @test QUBOTools.state(opt,1)==QUBOTools.state(fresh,1)
        @test QUBOTools.value(opt,1)==QUBOTools.value(fresh,1)
        @test decomposition(opt)["labels"]==QUBOTools.variables(model)
    end
    # Mutation of the live backend must arrive at the next invocation.
    model=QUBOTools.backend(opt)
    QUBOTools.data(QUBOTools.linear_form(QUBOTools.form(model)))[1]=2.0
    MOI.optimize!(opt)
    @test QUBOTools.value(opt,1)==3.0
    MOI.empty!(opt)
    @test MOI.is_empty(opt)
    @test MOI.get(opt,MOI.ResultCount())==0
    @test MOI.get(opt,MOI.TerminationStatus())===MOI.OPTIMIZE_NOT_CALLED
    child=FixtureChild()
    opt=solve_model(direct_model();child=()->child)
    MOI.empty!(child.model)
    MOI.optimize!(opt)
    @test MOI.get(opt,MOI.TerminationStatus())===MOI.INVALID_OPTION
    @test occursin("reused",decomposition(opt)["diagnostic"])
end

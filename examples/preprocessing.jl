# SPDX-License-Identifier: MPL-2.0
module RootPreprocessingExample
import QUBODecomposition, QUBODrivers, QUBOTools
import MathOptInterface as MOI

function run()
    labels=[11,7,30,9,4]
    model=QUBOTools.Model{Int,Float64,Int}(labels,[2],[6.0],
        [2,2,2,2,1,4],[1,3,4,5,3,5],fill(-1.0,6))
    scalar(x)=6*x[2]-x[2]*(x[1]+x[3]+x[4]+x[5])-x[1]*x[3]-x[4]*x[5]
    n=QUBOTools.dimension(model)
    n<=8 || error("tiny reference guard precedes exponentiation")
    optimum=minimum(scalar([isodd(mask>>(i-1)) ? 1 : 0 for i in 1:n]) for mask in 0:(1<<n)-1)
    outcomes=Dict{Symbol,Any}()
    for mode in (:off,:dominance)
        opt=QUBODecomposition.Optimizer(child_optimizer=QUBODrivers.ExactSampler.Optimizer,
            max_variables=2,strategy=:components,preprocessing=mode,max_work=100_000)
        QUBODrivers.set_model!(opt,model);MOI.optimize!(opt)
        data=QUBOTools.metadata(QUBOTools.solution(opt))["decomposition"]
        outcomes[mode]=(;opt,data,status=MOI.get(opt,MOI.TerminationStatus()))
    end
    on,off=outcomes[:dominance],outcomes[:off]
    @assert off.status===MOI.INVALID_OPTION # one connected five-variable component
    @assert on.status in (MOI.OPTIMAL,MOI.LOCALLY_SOLVED) # actual installed child status
    @assert on.data["preprocessing"]["residual_dimension"]==4
    @assert on.data["components"]==[[1,3],[4,5]]
    @assert on.data["attempted_calls"]==2
    @assert all(length(c["selected_indices"])<=2 for c in on.data["calls"])
    state=QUBOTools.state(on.opt,1)
    @assert length(state)==5 && scalar(state)==QUBOTools.value(on.opt,1)==optimum==-2
    return (;status=on.status,original_variables=n,residual_variables=4,child_calls=2,
        original_energy=optimum,work_reserved=on.data["work"]["used"],off_status=off.status)
end
end

if abspath(PROGRAM_FILE)==@__FILE__
    println(RootPreprocessingExample.run())
end

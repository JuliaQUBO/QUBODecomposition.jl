using Test, SparseArrays
import MathOptInterface as MOI
import QUBODrivers, QUBOTools, QUBODecomposition
const ROOT = "/tmp/qubo-finalize-DrOmiT/astra-coarse45/repo"
@assert realpath(pkgdir(QUBODecomposition)) == realpath(ROOT)
@assert readchomp(`git -C $ROOT rev-parse HEAD`) == "deea226fea4ecc6dfaf67f1c2780a06d144a96db"
include(joinpath(ROOT,"test/fixtures.jl"))
println((source=pathof(QUBODecomposition),julia=VERSION,driver=pkgversion(QUBODrivers),moi=pkgversion(MOI)))
# Exactly three scripted one-variable child calls. No child enumeration.
for (strategy,sense,start,macro_row) in ((:whole_model,:min,0,1),(:coarse,:min,0,1),(:coarse,:max,1,1))
    model=QUBOTools.Model{Symbol,Float64,Int}([:x],[1],[1.],Int[],Int[],Float64[];
        sense,start=Dict(:x=>start))
    captured=Ref{Any}(nothing)
    factory=()->FixtureChild(rows=[[macro_row]],status=MOI.OPTIMAL,callback=c->begin
        @assert c.scripted
        f=MOI.get(c.model,MOI.ObjectiveFunction{MOI.ScalarQuadraticFunction{Float64}}())
        @assert isempty(f.quadratic_terms) && length(f.affine_terms)==1
        captured[]=(constant=f.constant,coefficient=only(f.affine_terms).coefficient,
            no_flip=f.constant,returned=f.constant+only(f.affine_terms).coefficient*macro_row)
    end)
    opt=solve_model(model;strategy,coarse_groups=strategy===:coarse ? [[1]] : nothing,child=factory,budget=1)
    data=decomposition(opt);call=only(data["calls"])
    println((strategy,sense,initial=start,dispatched=captured[],status=MOI.get(opt,MOI.TerminationStatus()),
        state=QUBOTools.state(opt,1),energy=QUBOTools.value(opt,1),
        exact=call["exact"],completed_calls=data["completed_calls"],
        diagnostic=get(data,"diagnostic",nothing)))
    @assert data["attempted_calls"]==1
    @assert MOI.get(opt,MOI.TerminationStatus()) === (strategy===:coarse ? MOI.LOCALLY_SOLVED : MOI.OTHER_ERROR)
end
println("Confirmed: ordinary route rejects the contradictory exact child; both coarse senses accept it. Three scripted child calls, zero enumeration.")

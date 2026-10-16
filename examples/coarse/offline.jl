# SPDX-License-Identifier: MPL-2.0
using QUBODecomposition, QUBODrivers, QUBOTools
import MathOptInterface as MOI

# Each separate original block change costs +2 from the all-zero start. Reversing
# both blocks together costs -4; the full coarse objective is 2y1+2y2-8y1*y2.
model = QUBOTools.Model{Symbol,Float64,Int}([:a,:b,:c,:d], collect(1:4),ones(4),
    [1,1,2,2],[3,4,3,4],fill(-2.,4))
optimizer = QUBODecomposition.Optimizer(
    strategy=:coarse, coarse_groups=[[1,2],[3,4]], max_variables=2,
    child_optimizer=()->QUBODrivers.ExactSampler.Optimizer())
QUBODrivers.set_model!(optimizer,model)
MOI.optimize!(optimizer)
x = QUBOTools.state(optimizer,1)
@assert x == ones(Int,4)
@assert QUBOTools.value(optimizer,1) == sum(x)-2*(x[1]+x[2])*(x[3]+x[4]) == -4.
@assert MOI.get(optimizer,MOI.TerminationStatus()) === MOI.LOCALLY_SOLVED
info = QUBOTools.metadata(QUBOTools.solution(optimizer))["decomposition"]
@assert only(info["calls"])["macro_count"] == 2
@assert info["coarse"]["represented_original_count"] == 4
@assert !info["coarse"]["original_proof"]
println("One two-variable coarse proposal improved four original variables to -4; parent status is heuristic.")

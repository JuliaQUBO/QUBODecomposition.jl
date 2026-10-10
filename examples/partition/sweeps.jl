# SPDX-License-Identifier: MPL-2.0
import MathOptInterface as MOI
import QUBODrivers, QUBOTools, QUBODecomposition
include(joinpath(@__DIR__, "region_growing.jl"))

edges = [(1,2),(1,3),(2,3),(3,4),(4,5),(4,6),(5,6)]
model = QUBOTools.Model{Int,Float64,Int}(collect(1:7),collect(1:7),
    [1.,1.,1.,1.,1.,1.,-0.5],first.(edges),last.(edges),[-2.,-2.,-2.,4.,-2.,-2.,-2.];offset=7.25)
# Capacity three bounds every exhaustive child to eight binary assignments.
optimizer = QUBODecomposition.Optimizer(child_optimizer=QUBODrivers.ExactSampler.Optimizer,
    max_variables=3,selection=:partition,partition_plan=PartitionExample.region_growing,
    max_child_calls=16,max_candidate_evaluations=129,max_sweeps=3,stagnation_sweeps=1,seed=41)
QUBODrivers.set_model!(optimizer,model)
MOI.optimize!(optimizer)
full_state = QUBOTools.state(optimizer,1)
energy = QUBOTools.value(optimizer,1)
partition = QUBOTools.metadata(QUBOTools.solution(optimizer))["decomposition"]["partition"]
@assert sort(vcat(partition["blocks"]...)) == collect(1:7)
@assert all(length(b) <= 3 for b in partition["blocks"])
@assert energy == QUBOTools.value(model,full_state)
@assert MOI.get(optimizer,MOI.TerminationStatus()) !== MOI.OPTIMAL

# SPDX-License-Identifier: MPL-2.0
using Test, SparseArrays
import MathOptInterface as MOI
import QUBODrivers, QUBOTools, QUBODecomposition
include("fixtures.jl")
@testset "QUBODecomposition serial decomposition" begin
    include("unit/whole_model.jl")
    include("unit/results.jl")
    include("unit/budgets.jl")
    include("unit/repeated_solves.jl")
    include("unit/review_regressions.jl")
    include("unit/serial.jl")
    include("unit/selection.jl")
    include("unit/bfs_random.jl")
    include("unit/separator.jl")
    include("unit/articulation.jl")
    include("conformance.jl")
end

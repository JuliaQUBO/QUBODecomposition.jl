# SPDX-License-Identifier: MPL-2.0
using Test, SparseArrays
import MathOptInterface as MOI
import QUBODrivers, QUBOTools, QUBODecomposition
include("fixtures.jl")
@testset "QUBODecomposition whole-model slice" begin
    include("unit/whole_model.jl")
    include("unit/results.jl")
    include("unit/budgets.jl")
    include("unit/repeated_solves.jl")
    include("unit/review_regressions.jl")
    include("conformance.jl")
end

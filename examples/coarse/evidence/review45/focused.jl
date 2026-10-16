using Test, SparseArrays
import MathOptInterface as MOI
import QUBODrivers, QUBOTools, QUBODecomposition
@assert realpath(pkgdir(QUBODecomposition)) == realpath("/tmp/qubo-finalize-DrOmiT/coarse17/repo")
include("/tmp/qubo-finalize-DrOmiT/coarse17/repo/test/fixtures.jl")
include("/tmp/qubo-finalize-DrOmiT/coarse17/repo/test/unit/coarse.jl")
println((oracle_assignments=COARSE_TEST_ORACLE_WORK[],child_assignments=COARSE_TEST_CHILD_WORK[]))

using Test, SparseArrays
import MathOptInterface as MOI
import QUBODrivers, QUBOTools, QUBODecomposition
@assert pkgdir(QUBODecomposition) == "/tmp/qubo-finalize-DrOmiT/sample18/repo"
println((source=pathof(QUBODecomposition),julia=VERSION,driver=pkgversion(QUBODrivers),tools=pkgversion(QUBOTools),moi=pkgversion(MOI)))
include("/tmp/qubo-finalize-DrOmiT/sample18/repo/test/fixtures.jl")
include("/tmp/qubo-finalize-DrOmiT/sample18/repo/test/unit/sample_fixing.jl")
println((oracle_assignments=SAMPLE18_ORACLE_WORK[],child_assignments=SAMPLE18_CHILD_WORK[]))

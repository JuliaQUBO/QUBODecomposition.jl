# SPDX-License-Identifier: MPL-2.0
# Run in the installation project; locate every exercised script in the distribution.
using Pkg, QUBODecomposition
import MathOptInterface as MOI
import QUBOTools
expected_version = VersionNumber(ENV["QUBODECOMPOSITION_EXPECTED_VERSION"])
const PACKAGE_UUID = Base.UUID("142f39e9-ef93-42e3-b199-458fb82151e7")
installed = Pkg.dependencies()[PACKAGE_UUID]
@assert installed.name == "QUBODecomposition" && installed.version == expected_version
root = pkgdir(QUBODecomposition)
@assert realpath(root) == realpath(installed.source)
@assert !installed.is_tracking_path
@assert pkgversion(QUBODecomposition) == expected_version
@assert MOI.get(QUBODecomposition.Optimizer(), MOI.SolverVersion()) == expected_version
@assert MOI.get(QUBODecomposition.ModelStorage(), MOI.SolverVersion()) == expected_version
expected = get(ENV, "QUBODECOMPOSITION_EXPECTED_REV", "")
if !isempty(expected)
    @assert installed.git_revision == expected
end
for (uuid, dependency) in Pkg.dependencies()
    @assert !dependency.is_tracking_path "unexpected development override: $(dependency.name)"
end
@assert isfile(joinpath(root, "LICENSE")) && isfile(joinpath(root, "NOTICE"))
for script in ("whole_model.jl", "serial_sweeps.jl", "process_components.jl")
    sandbox = Module(gensym(:InstalledExample))
    Base.include(sandbox, joinpath(root, "examples", script))
    if script == "process_components.jl"
        result = Base.invokelatest(getfield(sandbox, :run_process_components))
        @assert result.expired_deadline_status == MOI.TIME_LIMIT
        println((; installed_process_example=result))
    else
        optimizer = getfield(sandbox, :optimizer)
        @assert QUBOTools.metadata(QUBOTools.solution(optimizer))["backend"]["version"] == expected_version
    end
end
# Use the installed examples' bounded offline entry points, never comparison runners.
pruning_sandbox = Module(gensym(:InstalledPruning))
Base.include(pruning_sandbox, joinpath(root, "examples", "separator_pruning.jl"))
pruning = Base.invokelatest(getfield(getfield(pruning_sandbox, :SeparatorPruningExample), :run))
pruning_state = QUBOTools.state(pruning.optimizer, 1)
@assert length(pruning_state) == 3 && all(x -> x in (0, 1), pruning_state)
x = Dict(zip(pruning.data["labels"], pruning_state))
# Independent scalar evaluation of the example's stored original objective.
pruning_energy = 4 + 10x[:center] - 2x[:left] - x[:right] +
    x[:center]*x[:left] + x[:center]*x[:right]
@assert QUBOTools.value(pruning.optimizer, 1) == pruning_energy == 1
@assert QUBOTools.metadata(QUBOTools.solution(pruning.optimizer))["backend"]["version"] == expected_version
proof = pruning.data["separator"]
@assert proof["pruning_enabled"] && !proof["bound_unavailable"]
@assert proof["bound_method"] == "exact_rational_original_termwise_v1"
@assert proof["certified_pruned_branches"] == 1 && proof["certified_branches"] == 0
@assert proof["completed_branches"] + proof["certified_pruned_branches"] == proof["required_branches"] == 2
@assert proof["unfinished_branches"] == 0 && !proof["proof_complete"]
@assert MOI.get(pruning.optimizer, MOI.TerminationStatus()) == MOI.LOCALLY_SOLVED
println((; installed_pruning_example=(state=pruning_state, energy=pruning_energy, proof)))

consensus_sandbox = Module(gensym(:InstalledConsensus))
Base.include(consensus_sandbox, joinpath(root, "examples", "consensus", "offline.jl"))
# run() also asserts LOCALLY_SOLVED despite its honest exact child certificates.
consensus = Base.invokelatest(getfield(getfield(consensus_sandbox, :ConsensusExample), :run))
@assert length(consensus.state) == 3 && all(x -> x in (-1, 1), consensus.state)
a, b, c = consensus.state
consensus_energy = 2 + a*b + b*c + a*c
@assert consensus.energy == consensus_energy
@assert consensus.lower isa Rational{BigInt} && consensus.gap isa Rational{BigInt}
# This fixture is minimization with unit scale: normalized and original units agree.
@assert consensus.lower <= 1 <= consensus_energy
@assert consensus.gap == Rational{BigInt}(consensus_energy) - consensus.lower >= 0
@assert 0 < consensus.child_assignments <= 1024
println((; installed_consensus_example=consensus))
println((; name=installed.name, uuid=PACKAGE_UUID, version=installed.version,
    revision=installed.git_revision, tree=installed.tree_hash, source=root,
    entrypoint=pathof(QUBODecomposition), julia=VERSION))
Pkg.status(;mode=Pkg.PKGMODE_MANIFEST)

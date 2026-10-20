# SPDX-License-Identifier: MPL-2.0
# Run in the installation project; locate every exercised script in the distribution.
using Pkg, QUBODecomposition
import MathOptInterface as MOI
import QUBOTools, QUBODrivers
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
certified_exact = pkgversion(QUBODrivers) >= v"0.6.6"
@assert proof["certified_pruned_branches"] == 1
@assert proof["certified_branches"] == (certified_exact ? 1 : 0)
@assert proof["completed_branches"] + proof["certified_pruned_branches"] == proof["required_branches"] == 2
@assert proof["unfinished_branches"] == 0 && proof["proof_complete"] == certified_exact
@assert MOI.get(pruning.optimizer, MOI.TerminationStatus()) == (certified_exact ? MOI.OPTIMAL : MOI.LOCALLY_SOLVED)
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
# Coarse proposals use two macrovariables for four complete original variables.
coarse_sandbox = Module(gensym(:InstalledCoarse))
Base.include(coarse_sandbox, joinpath(root, "examples", "coarse", "offline.jl"))
coarse_optimizer = getfield(coarse_sandbox, :optimizer)
coarse_state = QUBOTools.state(coarse_optimizer, 1)
@assert length(coarse_state) == 4 && all(x -> x in (0, 1), coarse_state)
coarse_metadata = QUBOTools.metadata(QUBOTools.solution(coarse_optimizer))
coarse_data = coarse_metadata["decomposition"]
cx = Dict(zip(coarse_data["labels"], coarse_state))
# Independently score the stored original polynomial, without production lifting.
coarse_energy = cx[:a] + cx[:b] + cx[:c] + cx[:d] -
    2*(cx[:a] + cx[:b])*(cx[:c] + cx[:d])
@assert QUBOTools.value(coarse_optimizer, 1) == coarse_energy == -4
@assert MOI.get(coarse_optimizer, MOI.TerminationStatus()) == MOI.LOCALLY_SOLVED
@assert coarse_metadata["backend"]["version"] == expected_version
coarse_info = coarse_data["coarse"]
coarse_call = only(coarse_data["calls"])
@assert coarse_data["configured_caps"]["max_variables"] == 2
@assert coarse_info["macro_groups"] == [[1,2],[3,4]]
@assert coarse_info["original_to_macro"] == [1,1,2,2]
@assert coarse_info["represented_original_count"] == 4
@assert coarse_info["frozen_incumbent"] == zeros(Int, 4)
@assert coarse_info["complete"] && !coarse_info["original_proof"]
@assert coarse_call["kind"] == "coarse" && coarse_call["macro_count"] == 2
@assert length(coarse_call["source_to_child"]) == 2
@assert !haskey(coarse_call, "original_to_reduced") && !coarse_call["original_proof"]
@assert coarse_call["exact"] == certified_exact
@assert coarse_call["public_status"] == (certified_exact ? "OPTIMAL" : "LOCALLY_SOLVED")
println((; installed_coarse_example=(state=coarse_state, energy=coarse_energy,
    macro_groups=coarse_info["macro_groups"], child_status=coarse_call["public_status"])))

# A biased unary restriction must preserve the better complete global incumbent.
sample_sandbox = Module(gensym(:InstalledSampleFixing))
Base.include(sample_sandbox, joinpath(root, "examples", "sample_fixing", "offline.jl"))
sample_fixing = Base.invokelatest(getfield(getfield(sample_sandbox, :SampleFixingExample), :run))
sample_state = QUBOTools.state(sample_fixing.optimizer, 1)
@assert sample_fixing.state == sample_state
@assert length(sample_state) == 4 && all(x -> x in (0, 1), sample_state)
sample_data = sample_fixing.metadata["decomposition"]
sx = Dict(zip(sample_data["labels"], sample_state))
sample_energy = 4sx[:a] - 2sx[:b] - sx[:c]
@assert QUBOTools.value(sample_fixing.optimizer, 1) == sample_fixing.energy == sample_energy == -3
@assert MOI.get(sample_fixing.optimizer, MOI.TerminationStatus()) == MOI.LOCALLY_SOLVED
@assert sample_fixing.metadata["backend"]["version"] == expected_version
sample_info = sample_data["sample_fixing"]
sample_call = only(sample_data["calls"])
@assert sample_data["configured_caps"]["max_variables"] == 2
@assert sample_info["pool_complete"] && sample_info["terminal_complete"]
@assert sample_info["supplied_rows"] == sample_info["validated_rows"] == sample_info["distinct_rows"] == 3
@assert sample_info["provenance"] == "explicit biased demonstration pool; not generated samples"
@assert sample_info["reported_generation_sec"] === nothing
@assert sample_info["original_to_pool"] == collect(1:4)
@assert sample_info["fixed_variables"] == Dict(1=>1, 4=>0)
@assert !sample_info["global_incumbent_compatible"] && !sample_info["original_proof"]
@assert sample_call["kind"] == "sample_fixing" && sample_call["selected_indices"] == [2,3]
@assert length(sample_call["source_to_child"]) == 2 && !sample_call["original_proof"]
@assert sample_call["original_to_reduced"] == Dict(2=>1, 3=>2)
@assert sample_fixing.child_dimensions == [2] && sample_fixing.child_assignments == 4
@assert sample_call["exact"] == certified_exact
@assert sample_call["public_status"] == (certified_exact ? "OPTIMAL" : "LOCALLY_SOLVED")
println((; installed_sample_fixing_example=(state=sample_state, energy=sample_energy,
    fixed=sample_info["fixed_variables"], provenance=sample_info["provenance"],
    child_status=sample_call["public_status"])))
# The installed root example compares disabled/enabled capacity handling and
# independently enumerates the original five-variable objective.
root_sandbox = Module(gensym(:InstalledRootPreprocessing))
Base.include(root_sandbox, joinpath(root, "examples", "preprocessing.jl"))
root_result = Base.invokelatest(getfield(getfield(root_sandbox, :RootPreprocessingExample), :run))
@assert root_result.status == (certified_exact ? MOI.OPTIMAL : MOI.LOCALLY_SOLVED)
@assert root_result.off_status == MOI.INVALID_OPTION
@assert root_result.original_variables == 5 && root_result.residual_variables == 4
@assert root_result.child_calls == 2 && root_result.original_energy == -2
@assert 0 < root_result.work_reserved <= 100_000
println((; installed_root_preprocessing_example=root_result))

println((; name=installed.name, uuid=PACKAGE_UUID, version=installed.version,
    revision=installed.git_revision, tree=installed.tree_hash, source=root,
    entrypoint=pathof(QUBODecomposition), julia=VERSION))
Pkg.status(;mode=Pkg.PKGMODE_MANIFEST)

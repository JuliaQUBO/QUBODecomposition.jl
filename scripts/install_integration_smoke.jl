# SPDX-License-Identifier: MPL-2.0
# Invoke in the installed package's project, in a fresh process. No checkout paths.
using Pkg, QUBODecomposition
length(ARGS) == 1 && only(ARGS) in ("candidate", "registry") ||
    error("choose candidate or registry installation mode")
mode = only(ARGS)
expected_version = VersionNumber(ENV["QUBODECOMPOSITION_EXPECTED_VERSION"])
revision = get(ENV, "QUBODECOMPOSITION_EXPECTED_REV", "")
mode == "candidate" && !occursin(r"^[0-9a-f]{40}$", revision) &&
    error("candidate mode requires full QUBODECOMPOSITION_EXPECTED_REV")
uuid = Base.UUID("142f39e9-ef93-42e3-b199-458fb82151e7")
original = Pkg.dependencies()[uuid]
@assert original.version == expected_version && !original.is_tracking_path
@assert mode == "candidate" ? original.git_revision == revision : !original.is_tracking_repo
root = pkgdir(QUBODecomposition)
project = mktempdir(;cleanup=false) # retain the manifest for maintainer evidence
cp(joinpath(root, "examples/toqubo/Project.toml"), joinpath(project, "Project.toml"))
Pkg.activate(project)
if mode == "candidate"
    Pkg.add(url="https://github.com/JuliaQUBO/QUBODecomposition.jl.git", rev=revision)
else
    Pkg.Registry.update()
    Pkg.add("QUBODecomposition")
end
Pkg.instantiate()
installed = Pkg.dependencies()[uuid]
@assert installed.version == expected_version && installed.tree_hash == original.tree_hash
@assert realpath(installed.source) == realpath(root)
@assert !installed.is_tracking_path
@assert mode == "candidate" ? installed.git_revision == revision : !installed.is_tracking_repo
@assert all(!d.is_tracking_path for d in values(Pkg.dependencies()))
@assert Pkg.dependencies()[Base.UUID("9a412ddf-83fa-43b6-9748-7843c851aa65")].version >= v"0.7.1"
include(joinpath(root, "examples/toqubo/refinement.jl"))
@assert RefinementExample.run(;budget=2).source_feasible
@assert RefinementExample.run(;budget=8).source_feasible
include(joinpath(root, "examples/toqubo/deadline.jl"))
@assert DeadlineExample.run().reason == :feasible
println((; mode, version=installed.version, revision=installed.git_revision,
    tree=installed.tree_hash, source=root, project, julia=VERSION))
Pkg.status(;mode=Pkg.PKGMODE_MANIFEST)
println("INSTALLED INTEGRATION SMOKE PASSED")

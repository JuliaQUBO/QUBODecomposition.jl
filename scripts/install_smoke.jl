# SPDX-License-Identifier: MPL-2.0
# Run in the installation project; locate every exercised script in the distribution.
using Pkg, QUBODecomposition
expected_version = VersionNumber(ENV["QUBODECOMPOSITION_EXPECTED_VERSION"])
const PACKAGE_UUID = Base.UUID("142f39e9-ef93-42e3-b199-458fb82151e7")
installed = Pkg.dependencies()[PACKAGE_UUID]
@assert installed.name == "QUBODecomposition" && installed.version == expected_version
root = pkgdir(QUBODecomposition)
@assert realpath(root) == realpath(installed.source)
@assert !installed.is_tracking_path
expected = get(ENV, "QUBODECOMPOSITION_EXPECTED_REV", "")
if !isempty(expected)
    @assert installed.git_revision == expected
end
for (uuid, dependency) in Pkg.dependencies()
    @assert !dependency.is_tracking_path "unexpected development override: $(dependency.name)"
end
@assert isfile(joinpath(root, "LICENSE")) && isfile(joinpath(root, "NOTICE"))
for script in ("whole_model.jl", "serial_sweeps.jl")
    sandbox = Module(gensym(:InstalledExample))
    Base.include(sandbox, joinpath(root, "examples", script))
end
println((; name=installed.name, uuid=PACKAGE_UUID, version=installed.version,
    revision=installed.git_revision, tree=installed.tree_hash, source=root,
    entrypoint=pathof(QUBODecomposition), julia=VERSION))
Pkg.status(;mode=Pkg.PKGMODE_MANIFEST)

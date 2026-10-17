# SPDX-License-Identifier: MPL-2.0
# Temporary integration-development pin. Remove this bootstrap from every CI
# environment before production merge, after the declared normal floor resolves.
using Pkg
Pkg.add(PackageSpec(
    url="https://github.com/JuliaQUBO/QUBOPreprocessing.jl.git",
    rev="3aa2923a4b5fe6cda21fbb4e331e9198b603029f"))

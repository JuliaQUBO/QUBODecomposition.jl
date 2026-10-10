# SPDX-License-Identifier: MPL-2.0
using Pkg
length(ARGS)==2 || error("usage: run.jl NEW_OUTPUT_DIRECTORY CUMULATIVE_LEDGER_FILE")
output,ledger=abspath.(ARGS)
root=normpath(joinpath(@__DIR__,"../.."))
ENV["JULIA_PKG_PRECOMPILE_AUTO"]="0"
Pkg.activate(mktempdir(;prefix="compact-child-env-"))
Pkg.develop(path=root)
Pkg.add([PackageSpec(name="QUBOTools",version=v"0.16.2"),PackageSpec(name="QUBODrivers",version=v"0.6.5"),PackageSpec(name="MathOptInterface")])
Pkg.pin(["QUBOTools","QUBODrivers"])
include("adapter.jl")
include("comparison.jl")
CompactComparison.run(output,ledger)

# SPDX-License-Identifier: MPL-2.0
# Reuse the merged pilot in an isolated environment, with THIS candidate checkout.
using Pkg
length(ARGS) == 2 || error("usage: run.jl PILOT_CHECKOUT NEW_OUTPUT_DIRECTORY")
pilot, output = abspath.(ARGS)
root = normpath(joinpath(@__DIR__, "../.."))
const PILOT_SHA = "7dbe623c30fb674cef5ede6bdc46b7b99e07736b"
readchomp(`git -C $pilot rev-parse HEAD`) == PILOT_SHA || error("wrong pilot revision")
isempty(readchomp(`git -C $pilot status --porcelain`)) || error("pilot must be clean")
isempty(readchomp(`git -C $root status --porcelain`)) || error("candidate must be committed and clean")
ispath(output) && error("choose a new output directory")
ENV["JULIA_NUM_PRECOMPILE_TASKS"] = "1"
ENV["JULIA_PKG_PRECOMPILE_AUTO"] = "0"
Pkg.activate(mktempdir(; prefix="selection-comparison-"))
Pkg.develop([PackageSpec(path=root), PackageSpec(path=pilot)])
Pkg.add([PackageSpec(name="ToQUBO", version="0.7.1"),
    PackageSpec(name="QUBODrivers", version="0.6.5"),
    PackageSpec(name="QUBOTools", version="0.16.2"),
    PackageSpec(name="JuMP"), PackageSpec(name="MathOptInterface"),
    PackageSpec(name="QUBOLib"), PackageSpec(name="DBInterface"), PackageSpec(name="DataFrames")])
Pkg.pin(["ToQUBO", "QUBODrivers", "QUBOTools"])
include(joinpath(pilot, "examples/decomposition/pilot.jl"))
include("compare.jl")
SelectionComparison.run(root, pilot, output)

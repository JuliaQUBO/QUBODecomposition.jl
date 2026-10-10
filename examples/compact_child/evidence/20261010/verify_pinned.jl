# SPDX-License-Identifier: MPL-2.0
# Run in an environment containing the pinned benchmark's example dependencies
# and this QUBODecomposition checkout; this checks identities, not timed solves.
length(ARGS)==1 || error("usage: verify_pinned.jl PINNED_BENCHMARK_CHECKOUT")
benchmark=abspath(only(ARGS))
root=normpath(joinpath(@__DIR__,"../../../.."))
const PINNED_SHA="684a96b8e757b400964d062c4229aacc12a523e1"
readchomp(`git -C $benchmark rev-parse HEAD`)==PINNED_SHA || error("wrong benchmark checkout")
isempty(readchomp(`git -C $benchmark status --porcelain`)) || error("benchmark must be clean")
include(joinpath(benchmark,"examples/decomposition/pilot.jl"))
include(joinpath(benchmark,"examples/decomposition/exact-scaling/scaling.jl"))
include(joinpath(root,"examples/compact_child/adapter.jl"))
include(joinpath(root,"examples/compact_child/comparison.jl"))
using Test,QUBOTools,SHA
@test readchomp(`git -C $benchmark rev-parse HEAD`)==CompactComparison.BENCHMARK_SHA
for name in ("path15","star33")
 a=ExactScaling.fixture(name); b=CompactComparison.fixture(name)
 @test DecompositionPilot.description(a)["linear"]==CompactComparison.description(b)["linear"]
 @test DecompositionPilot.description(a)["quadratic"]==CompactComparison.description(b)["quadratic"]
 @test QUBOTools.variables(a.model)==QUBOTools.variables(b.model)
 @test QUBOTools.scale(a.model)==QUBOTools.scale(b.model)==1.5
 @test QUBOTools.offset(a.model)==QUBOTools.offset(b.model)==3.
 @test QUBOTools.sense(a.model)===QUBOTools.sense(b.model)===QUBOTools.Min
 @test QUBOTools.domain(a.model)===QUBOTools.domain(b.model)===QUBOTools.BoolDomain
 @test ExactScaling.supplied(name,b.n)==b.separator
 @test ExactScaling.reference(a,name)["energy"]==CompactComparison.bound(b)
 println(name," pinned benchmark fixture hash ",DecompositionPilot.fixture_hash(a))
end
@test CompactComparison.preflight()[2]["assignments"]==7680
CompactComparison.audit_small_families()
println("Pinned fixture identities, preflight and small-family scalar oracles passed")

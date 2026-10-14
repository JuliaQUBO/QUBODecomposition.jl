# SPDX-License-Identifier: MPL-2.0
module ProcessComponentFixture
import MathOptInterface as MOI
import QUBODrivers, QUBOTools, QUBODecomposition
using Distributed
include("fixtures.jl")
const calls = Ref(0)
struct Factory
    started::RemoteChannel
    releases::Tuple
    synchronize::Bool
    fail_component::Int
end
function (f::Factory)(job)
    calls[] += 1
    local_count = calls[]
    f.fail_component == -1 && job.id[3] == 1 && exit(0)
    job.id[3] == f.fail_component && error("deliberate worker factory failure")
    FixtureChild(callback=child -> begin
        n = MOI.get(child.model, MOI.NumberOfVariables())
        @assert n == job.problem.n
        if f.synchronize && job.id[3] <= 2
            put!(f.started,(;component=job.id[3],worker=myid(),local_count,seed=child.seed,n,problem=job.problem))
            take!(f.releases[job.id[3]])
        end
    end)
end
end

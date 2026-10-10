# SPDX-License-Identifier: MPL-2.0
include("../../examples/compact_child/comparison.jl")
@testset "Bounded compact comparison preflight and independent fixture identities" begin
    plans,totals=CompactComparison.preflight()
    @test totals==Dict("attempts"=>24,"assignments"=>7680,"parent_bound"=>7800,"oracle_assignments"=>512)
    for (name,n,edges,separator,capacity,optimum) in (
        ("path15",15,[(i,i+1) for i in 1:14],[8],7,-60.),
        ("star33",33,[(1,j) for j in 2:33],[1],1,-141.))
        f=CompactComparison.fixture(name)
        @test (f.n,f.edges,f.separator,f.capacity)==(n,edges,separator,capacity)
        @test QUBOTools.value(f.model,ones(Int,n))==optimum==CompactComparison.scalar(f,ones(Int,n))
        @test CompactComparison.bound(f)==optimum
        @test CompactComparison.scalar(f,zeros(Int,n))==4.5
    end
    CompactComparison.audit_small_families() # separately capped independent scalar work
    @test_throws ErrorException CompactComparison.fixture("path1000000000")
    mktempdir() do dir
        p=joinpath(dir,"checkpoint.toml")
        CompactComparison.checkpoint(p,Dict("reserved"=>7680,"missing"=>nothing))
        @test CompactComparison.TOML.parsefile(p)["reserved"]==7680
        prior=read(p)
        @test_throws Exception CompactComparison.checkpoint(p,Dict("invalid"=>Ref(1)))
        @test read(p)==prior
        # Fail after temporary creation and a partial write, before replacement.
        broken_writer=(io,payload)->(write(io,first(payload,3));error("injected write failure"))
        @test_throws ErrorException CompactComparison.checkpoint(p,Dict("reserved"=>15360);writer=broken_writer)
        @test read(p)==prior
        @test length(readdir(dir))==1
    end
end

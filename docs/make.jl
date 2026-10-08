# SPDX-License-Identifier: MPL-2.0
using Documenter, QUBODecomposition

all(arg -> arg in ("--skip-deploy", "--deploy"), ARGS) || error("unknown documentation argument")
("--skip-deploy" in ARGS && "--deploy" in ARGS) && error("choose build-only or deploy")
deploy = "--deploy" in ARGS
if deploy
    get(ENV, "GITHUB_ACTIONS", "") == "true" || error("publication requires GitHub Actions")
    isempty(get(ENV, "GITHUB_TOKEN", "")) && error("missing publication token")
    # Defense in depth: only this repository's reviewed main can publish.
    get(ENV, "GITHUB_REPOSITORY", "") == "JuliaQUBO/QUBODecomposition.jl" || error("wrong publisher repository")
    get(ENV, "GITHUB_REF", "") == "refs/heads/main" || error("publication requires main")
    get(ENV, "GITHUB_EVENT_NAME", "") in ("push", "workflow_dispatch") || error("untrusted publication event")
end

DocMeta.setdocmeta!(QUBODecomposition, :DocTestSetup, :(using QUBODecomposition); recursive=true)
include("check.jl")
makedocs(;
    root=@__DIR__, modules=[QUBODecomposition], sitename="QUBODecomposition.jl",
    authors="QUBODecomposition contributors", doctest=true, checkdocs=:all,
    repo=Documenter.Remotes.GitHub("JuliaQUBO", "QUBODecomposition.jl"),
    format=Documenter.HTML(;
        prettyurls=true, inventory_version="",
        canonical="https://juliaqubo.github.io/QUBODecomposition.jl/dev/",
        edit_link="main",
    ),
    pages=[
        "Overview" => "index.md",
        "Installation and quick start" => "start.md",
        "Manual" => [
            "Construction and configuration" => "configuration.md",
            "Strategies" => "strategies.md",
            "Results and statuses" => "results.md",
            "Budgets, timing, seeds and reads" => "budgets.md",
            "JuMP and ToQUBO" => "integration.md",
        ],
        "Executable examples" => "examples.md",
        "Public API" => "api.md",
        "Acceptance coverage" => "acceptance.md",
        "Publication and ecosystem handoff" => "deployment.md",
    ],
)

if deploy
    deploydocs(;
        root=@__DIR__, repo="github.com/JuliaQUBO/QUBODecomposition.jl.git",
        branch="gh-pages", devbranch="main", devurl="dev",
        versions=["dev" => "dev"], push_preview=false,
        forcepush=false,
    )
else
    @info "Build only: no deployment attempted"
end

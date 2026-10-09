# SPDX-License-Identifier: MPL-2.0
using Documenter, QUBODecomposition, TOML

release_tag = get(ENV, "QUBODECOMPOSITION_RELEASE_TAG", "")
release_commit = get(ENV, "QUBODECOMPOSITION_RELEASE_COMMIT", "")
if !isempty(release_tag) || !isempty(release_commit)
    occursin(r"^v[0-9]+\.[0-9]+\.[0-9]+$", release_tag) || error("invalid release tag")
    occursin(r"^[0-9a-f]{40}$", release_commit) || error("full release SHA required")
    readchomp(`git -C $(dirname(@__DIR__)) rev-parse HEAD`) == release_commit || error("release checkout mismatch")
    TOML.parsefile(joinpath(dirname(@__DIR__), "Project.toml"))["version"] == release_tag[2:end] || error("release version mismatch")
end
channel = isempty(release_tag) ? "dev" : release_tag

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
    isempty(release_tag) || get(ENV, "GITHUB_EVENT_NAME", "") == "workflow_dispatch" || error("release refresh requires manual dispatch")
end

DocMeta.setdocmeta!(QUBODecomposition, :DocTestSetup, :(using QUBODecomposition); recursive=true)
include("check.jl")
makedocs(;
    root=@__DIR__, modules=[QUBODecomposition], sitename="QUBODecomposition.jl",
    authors="QUBODecomposition contributors", doctest=true, checkdocs=:all,
    repo=Documenter.Remotes.GitHub("JuliaQUBO", "QUBODecomposition.jl"),
    format=Documenter.HTML(;
        prettyurls=true, inventory_version="",
        canonical="https://juliaqubo.github.io/QUBODecomposition.jl/$channel/",
        edit_link=isempty(release_tag) ? "main" : nothing,
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
    # The Actions job/environment remains on main. Only Documenter's supported
    # tag routing sees the already-validated release ref during this call.
    withenv("GITHUB_REF" => isempty(release_tag) ? "refs/heads/main" : "refs/tags/$release_tag") do
        deploydocs(;
            root=@__DIR__, repo="github.com/JuliaQUBO/QUBODecomposition.jl.git",
            branch="gh-pages", devbranch="main", devurl="dev",
            versions=["stable" => "v^", "v#.#", "dev" => "dev"], push_preview=false,
            forcepush=false,
        )
    end
else
    @info "Build only: no deployment attempted"
end

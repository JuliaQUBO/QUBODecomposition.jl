# Publication and ecosystem handoff

## Ownership and published destination

Package documentation is owned by [JuliaQUBO/QUBODecomposition.jl](https://github.com/JuliaQUBO/QUBODecomposition.jl),
with maintainer/release authority [@bernalde](https://github.com/bernalde).
The canonical development manual is
[https://juliaqubo.github.io/QUBODecomposition.jl/dev/](https://juliaqubo.github.io/QUBODecomposition.jl/dev/).
**Development documentation is published and served-content checks pass.**
README links include the hosted manual and preserve useful source references.

The separate [Documentation workflow](https://github.com/JuliaQUBO/QUBODecomposition.jl/blob/main/.github/workflows/documentation.yml)
builds on pull requests and main pushes. Manual refresh uses that workflow's
**Run workflow** action on `main`, or after merge:

```sh
gh workflow run documentation.yml --repo JuliaQUBO/QUBODecomposition.jl --ref main
```

[Local setup/build commands](start.md#Build-this-manual) work without deployment
credentials. `docs/make.jl` defaults to build only; `--skip-deploy` is explicit.
Only the trusted publisher passes `--deploy`.

## Publisher and trust boundaries

Pull requests have `contents: read`, checkout without persisted credentials, and
no deployment token or Pages environment. Their HTML artifact supports review;
there is no published PR preview. No `pull_request_target` code execution is used.

Publication requires the exact upstream repository, `refs/heads/main`, and a
`push` or `workflow_dispatch` event. The publisher rebuilds that trusted source;
it never consumes a PR build artifact. It appends through Documenter's
`deploydocs` to `gh-pages` with `devbranch="main"`, `devurl="dev"`,
`versions=["dev" => "dev"]`, `push_preview=false` and `forcepush=false`.
The publication content is archived with symlinks dereferenced, excluding only
checkout internals (`.git`/`.github`), then uploaded and deployed through Actions
Pages. `upload-pages-artifact@v5` uses `include-hidden-files: true` to preserve
`.documenter-siteinfo.json` and the other Documenter metadata.
This explicit Pages deployment avoids relying on a `GITHUB_TOKEN` branch push
to trigger a separate branch-based Pages build.

Only the publishing job has `contents: write`, `pages: write`, `id-token: write`
and the `github-pages` environment. Its built-in `GITHUB_TOKEN` is exposed as an
environment variable only to the Documenter publication step. Official actions
use the job token through their default inputs; checkout does not persist credentials.
No deploy key or personal token is assumed. Pages must use **GitHub Actions**
before a trusted publication can succeed.

All publication steps share the destination lock
`documentation-JuliaQUBO-QUBODecomposition-gh-pages`, with `cancel-in-progress: false`
and `queue: max` to retain queued writers. Any future preview, cleanup or other
`gh-pages` writer must use this same lock and preserve existing history/content.
This workflow adds no force push or cleanup of existing previews/releases.

## Layout and future releases

Documenter creates `gh-pages/dev/`, root redirect/version metadata (`versions.js`),
and `dev/.documenter-siteinfo.json`, `dev/siteinfo.js`, search index and API inventory.
The current selector contains **dev only**. There is no fabricated `stable`,
release tag or registration. Tag publication is deliberately not triggered.
At an actual release, maintainers must review tag trust/authentication and add
tag triggers/version selection/canonical release URLs as a separate release action.
The root redirect must continue to resolve to a real channel.

## Verified publication and refresh checks

The repository Pages source is **GitHub Actions**. The existing `github-pages`
environment permits only the `main` branch; its protection requirements are preserved.
The previous legacy `main`/root Pages setting was corrected without recreating the site,
adding credentials or changing publication history.

[Documentation run 37874067202](https://github.com/JuliaQUBO/QUBODecomposition.jl/actions/runs/37874067202)
built trusted source [`5e3f4cd`](https://github.com/JuliaQUBO/QUBODecomposition.jl/commit/5e3f4cdaced8b34d30de6fad4de2c6dc3fb2bf67),
appended publication [`d026a53`](https://github.com/JuliaQUBO/QUBODecomposition.jl/commit/d026a5313cefce12f613b1044ac9fea68e96b883)
to `gh-pages`, and successfully deployed it through Actions Pages. The Actions deployment
completed after the separate legacy branch-based publisher. No duplicate dispatch was needed.

All 26 files in that Pages artifact matched the publicly served bytes. Checks covered
all eleven manual pages, 408 internal navigation/anchor/asset references, the root
redirect to `dev/`, API and example source targets, CSS/JavaScript/search data,
equation-support configuration, site metadata, the inventory and the dev-only version
layout. These are served HTML and asset checks; browser rendering and interactive
search, equations and version selection were not exercised. There is no stable release
channel or registered-package installation claim.

For subsequent main pushes or an authorized manual refresh:

1. Confirm Pages still uses **GitHub Actions** and inspect the actual `github-pages`
   deployment-branch entries and any approval requirements; preserve protections.
2. Observe the Documentation run for the intended main commit. Confirm both the
   Documenter append to `gh-pages` and the explicit Pages deployment succeed.
   If setup or deployment failed, inspect the cause before dispatching a refresh.
3. Verify the served canonical manual against the corresponding publication/artifact:
   pages/navigation, examples/API/source links, base paths/assets, search data,
   `versions.js`, `siteinfo.js`, `.documenter-siteinfo.json` and `objects.inv`.
   Check the dev-only selector and root redirect; use browser checks for interaction
   or rendering questions. A build alone does not prove the public site is current.

Package issue [#3](https://github.com/JuliaQUBO/QUBODecomposition.jl/issues/3) owns
this package-local publication and hosted-link handoff. Its completion assessment is
separate from the full MVP/release criteria and the ecosystem work below.

## QUBO.jl aggregation dependency

[QUBO.jl#82](https://github.com/JuliaQUBO/QUBO.jl/issues/82) owns overview,
MultiDocumenter navigation/search and aggregate hosted verification. Its future
`MultiDocRef` should use repository
`https://github.com/JuliaQUBO/QUBODecomposition.jl.git`, publication branch `gh-pages`,
path/name `QUBODecomposition.jl`, and the verified dev channel. The planned aggregate
route is `https://juliaqubo.github.io/QUBO.jl/QUBODecomposition.jl/dev/`;
it is not currently advertised as a working site.

The inspected [pinned aggregate builder](https://github.com/JuliaQUBO/QUBO.jl/blob/a41353173d84e7e13d6763ac5a0d17a23a61568e/docs/multimake.jl)
indexes only `stable` versions. #82 must handle **dev-only search** before claiming
this package is searchable, and refresh the aggregate after the package publication
branch is usable. Do not invent stable docs to satisfy that search configuration.
The inspected [ToQUBO builder](https://github.com/JuliaQUBO/ToQUBO.jl/blob/69ac52592f4c47ed2168bf480c9947d1fcbbfc2c/docs/make.jl)
and [workflow](https://github.com/JuliaQUBO/ToQUBO.jl/blob/69ac52592f4c47ed2168bf480c9947d1fcbbfc2c/.github/workflows/documentation.yml)
are ecosystem examples, not this package's publication policy.

[QUBODrivers#87](https://github.com/JuliaQUBO/QUBODrivers.jl/issues/87) owns the
external sampler catalog. No cross-repository changes are included here.

Deployment APIs and authentication follow the official
[Documenter hosting guide](https://documenter.juliadocs.org/stable/man/hosting/),
[deploydocs reference](https://documenter.juliadocs.org/stable/lib/public/#Documenter.deploydocs),
[GitHub Actions Pages guide](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)
and [concurrency documentation](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency).

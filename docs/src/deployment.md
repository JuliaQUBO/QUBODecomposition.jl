# Publication and ecosystem handoff

## Ownership and planned destination

Package documentation is owned by [JuliaQUBO/QUBODecomposition.jl](https://github.com/JuliaQUBO/QUBODecomposition.jl),
with maintainer/release authority [@bernalde](https://github.com/bernalde).
The planned development URL is `https://juliaqubo.github.io/QUBODecomposition.jl/dev/`.
**Hosted publication is not yet verified.** README links stay on existing source
files until the canonical pages have been served and checked.

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

## Remaining maintainer setup and hosted verification

Merging triggers the Documentation workflow immediately. If Pages setup is still
pending, the first publisher is expected to fail at `configure-pages`, before the
Documenter branch push. Complete setup below, then dispatch the workflow on `main`
to publish. Repository settings are a separate administrator action.

After human review and merge, @bernalde (or a repository administrator) must:

1. Confirm/enable repository Pages with source **GitHub Actions**, and confirm
   the `github-pages` environment has a deployment-branch policy allowing only `main`.
   Review existing environment protection/approval requirements rather than bypassing them.
2. Confirm repository/org policy permits the publisher's scoped built-in token
   writes and the referenced Actions. No new repository secret is required by this method.
3. Observe the merge-triggered Documentation run. If it failed or was gated while
   setup was pending, run the manual refresh command above on `main` after setup.
   Confirm the Documenter branch push and Pages deployment both succeed.
4. Use `gh-pages-deployment` to confirm the publisher run/commit and Actions Pages
   state, `gh-pages/dev` content, served canonical pages, navigation, all four examples,
   API/source links, relative assets/base path, `versions.js`, `siteinfo.js` and
   `.documenter-siteinfo.json`. Verify the dev-only selector and root redirect.
5. Only after served-content verification, add verified README hosted links and
   assess the remaining publication criteria of package issue #3. Keep #3 open meanwhile.

A local HTML build proves buildability; it does not prove public-site success.

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

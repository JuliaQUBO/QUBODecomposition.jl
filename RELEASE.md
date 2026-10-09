# Release procedure

Maintained by @bernalde. Update this procedure when publication behavior changes.
The first planned version is **0.1.0 through General**, UUID
`142f39e9-ef93-42e3-b199-458fb82151e7`. `Project.toml` reserves that version;
preparation is not registration, a tag, a stable manual or a published release.
This preparation PR uses Refs #1 and stops for human review before all publication.

## Preparation gate

1. Refresh main, open work, tags/releases and General records/PRs. Wait for applicable
   main checks after a human merge. Keep base, candidate full SHA and Git tree SHA
   in the PR evidence; do not bump a reserved 0.1.0 to 0.1.1.
2. Review [acceptance rows 1–21](docs/src/acceptance.md), examples, CI and maintained
   limitations. Production remains QUBOTools >=0.16.2, QUBODrivers >=0.6.5 and MOI 1;
   JuMP/ToQUBO stay in tests/examples, with ToQUBO >=0.7.1 on the 0.7 patch line.
   Julia support starts at 1.10. Run `Pkg.test()`, the docs build and current-head CI,
   including runtime floors and pinned ToQUBO. Do not repeat unchanged exhaustive
   experiments beyond required checks without a changed input or unresolved concern.
3. Check the distributed tree includes LICENSE (MPL-2.0), NOTICE, source, examples,
   docs and smoke script. Compare any future citation/archive license metadata to
   LICENSE. No CFF, DOI, archival deposit or author identity is fabricated here.
   Repository/organization policies inspected for preparation impose no additional
   citation/archive gate; reassess before an archive integration is authorized.
4. Push the candidate, then install its exact SHA in a fresh project **and fresh
   single depot**, using the default package server and released upstream packages:

   ```sh
   candidate_dir=$(mktemp -d)
   export JULIA_DEPOT_PATH="$candidate_dir/depot"
   export QUBODECOMPOSITION_EXPECTED_REV=FULL_CANDIDATE_SHA
   julia --startup-file=no --project="$candidate_dir/project" -e '
     using Pkg
     Pkg.Registry.update()
     Pkg.add(url="https://github.com/JuliaQUBO/QUBODecomposition.jl.git",
             rev=ENV["QUBODECOMPOSITION_EXPECTED_REV"])
     # The examples import these public interfaces directly.
     Pkg.add(["QUBODrivers", "QUBOTools", "MathOptInterface"])
     using QUBODecomposition
     include(joinpath(pkgdir(QUBODecomposition), "scripts/install_smoke.jl"))'
   ```

   Leave `JULIA_PKG_SERVER` unset to use its default. Save Project/Manifest and log.
   The smoke runs the distribution's own fitting and serial examples, with scalar
   objective, complete reconstruction and conservative status assertions. It checks
   identity/version/revision/path and rejects every development override. This is
   candidate-install evidence, **not** normal General installation evidence.
   In a second temporary project in that depot, install the same SHA, then add
   released JuMP, ToQUBO, QUBODrivers and QUBOTools under the compat bounds in the
   installed `examples/toqubo/Project.toml`. Run the installed refinement/deadline
   scripts; assert both capacities are source-feasible and the deadline reason is
   `:feasible`. Keep its manifest separately. Never execute examples from a checkout
   while claiming installed-distribution verification.
5. Require independent automated review, address actionable feedback and verify it.
   Automated review is not human maintainer approval. Keep the preparation PR draft.
   Assess head changes: refresh installed files/smoke/build evidence when relevant
   inputs change; verify live CI at every new head.

Full benchmark campaigns, advanced strategies, external execution and the registry
canary are later gates; an unregistered package cannot pass registry-based adoption.

## Human acceptance and registration (future authorized actions)

1. @bernalde reviews and accepts the preparation PR, then merges under normal gates.
   Record the exact resulting release commit and tree and verify applicable checks
   on that commit. A merge SHA differs from the PR SHA: repeat exact-SHA candidate
   installation or explicitly validate unchanged tree evidence before registration.
2. Confirm the **JuliaRegistrator** app includes this repository at
   [organization installations](https://github.com/organizations/JuliaQUBO/settings/installations)
   or [app installation](https://github.com/apps/juliateam-registrator/installations/new).
   Inspection on 2026-10-09 showed `juliateam-registrator` installed for **all**
   organization repositories. No installation change is needed on that evidence;
   recheck scope before invoking it. The requester must have collaborator/public-org
   member authority. No custom credential is required for the prepared workflows.
3. On the **exact verified release commit**, request registration with this comment
   (copy the maintained notes from [CHANGELOG.md](CHANGELOG.md)):

   ```text
   @JuliaRegistrator register

   Release notes:
   First 0.1.0 local QUBO/Ising decomposition optimizer: whole-model dispatch,
   independent components and bounded serial conditioned sweeps; conservative
   statuses, complete reconstruction and released JuMP/ToQUBO composition.
   ```

   A commit comment pins the source; avoid an issue trigger that silently follows
   a moving branch. Read back Registrator's response and General PR. Check package
   name/UUID/repository/version/tree, registry checks and the new-package waiting
   period (currently three days for a new package). Wait for General merge; ordinary blocking comments affect AutoMerge.
4. Let [TagBot](.github/workflows/tagbot.yml) create the tag and non-draft GitHub
   release after registration. The standard organization template grants
   `contents: write`, `issues: write`, `pull-requests: read` and uses `GITHUB_TOKEN`.
   JuliaTagBot's comment or an explicit maintainer workflow dispatch triggers it.
   If necessary, dispatch on main with an appropriate lookback and inspect its run.
   Tags/releases created by `GITHUB_TOKEN` do **not** trigger downstream workflows.
   Documentation is deliberately refreshed manually from main, without SSH/PAT.

   **Workflow-changing commit caveat:** official TagBot guidance warns that GitHub
   can reject tagging/releasing a commit which changes workflow files using this
   token. This preparation changes workflows. Before choosing the release SHA,
   inspect its workflow diff to its parent. Prefer a separately reviewed release
   verification-record commit with no workflow changes (retain 0.1.0), then verify
   that exact source; do not create an empty version bump. If TagBot still fails,
   inspect its manual-intervention issue. A human with separately authorized release
   authority may create only missing artifacts on the verified SHA. Never silently
   retarget or recreate an existing tag/release, or add a new credential.

## Publication verification (after real General merge/tag/release)

1. Require General's `Package.toml` name/UUID/repo and `Versions.toml` 0.1.0 tree to
   match the release source. Fetch the real tag and assert
   `git rev-parse 'v0.1.0^{commit}'` equals the full verified release commit;
   an annotated tag-object SHA and a branch-valued release `targetCommitish` are
   not evidence of the tag target. Verify a non-draft/non-prerelease GitHub release
   and relevant successful workflows. Do not repair existing artifacts implicitly.
2. Use another fresh project **and fresh depot**, default package server, no version
   selector, repository override or development path:

   ```sh
   published_dir=$(mktemp -d)
   JULIA_DEPOT_PATH="$published_dir/depot" julia --startup-file=no \
     --project="$published_dir/project" -e '
       using Pkg
       Pkg.Registry.update()
       Pkg.add("QUBODecomposition")
       Pkg.add(["QUBODrivers", "QUBOTools", "MathOptInterface"])
       using QUBODecomposition
       info = Pkg.dependencies()[Base.UUID("142f39e9-ef93-42e3-b199-458fb82151e7")]
       @assert info.version == v"0.1.0" && !info.is_tracking_repo && !info.is_tracking_path
       include(joinpath(pkgdir(QUBODecomposition), "scripts/install_smoke.jl"))'
   ```

   Unset the candidate revision assertion and `JULIA_PKG_SERVER` first. Compare
   installed tree to General; retain manifests/versions/log. Bound propagation
   retries with new depots; unresolved package-server propagation remains pending.
   Also repeat the separate released JuMP/ToQUBO installed examples.
3. After tag/release verification, publish release documentation explicitly:

   ```sh
   gh workflow run documentation.yml --repo JuliaQUBO/QUBODecomposition.jl \
     --ref main -f release_tag=v0.1.0 -f release_commit=FULL_RELEASE_COMMIT_SHA
   ```

   This runs the reviewed main workflow with the existing main-only Pages
   environment. Its read-only provenance gate rejects wrong tag/commit/version,
   non-main ancestry, unmatched General tree or an unpublished GitHub release.
   It checks out that exact release SHA, builds with released dependencies and then
   appends Documenter publication under the shared gh-pages lock. Documenter's tag
   routing is set only for its deployment call; the Actions job and OIDC environment
   remain on main. No tag event, PR artifact or environment bypass is used.
   Existing dev docs, metadata and history survive. Stable/version aliases appear
   only when a real release tree is published. Observe both append and Pages deploy.
4. Verify served `v0.1.0/` and `stable/`, source links/canonical URLs, root/version
   routing, search/inventory/site metadata and the retained dev channel against
   the artifact/gh-pages tree. Check actual browser navigation/search separately
   from HTML assertions. Then dispatch QUBO.jl's existing Documentation workflow
   on main, observe aggregation, and verify the aggregate overview, five-package
   navigation, stable-first routing and real “stagnation” search results. Package
   publication does not automatically update that separate repository.
5. Adopt the **registered** package in the ecosystem canary afterward under its
   owner, then assess tracker #1 and QUBO.jl #73/#76 complete delivery criteria.
   Preparation readiness never closes those trackers or resolves human reviews.

Sources: [organization TagBot policy](https://github.com/JuliaQUBO/.github/blob/3cb779e5ee351345a8da3182603cef951bdde82e/.github/TAGBOT.md),
[official TagBot guidance](https://github.com/JuliaRegistries/TagBot#readme),
[Registrator](https://github.com/JuliaRegistries/Registrator.jl#readme),
[General requirements](https://github.com/JuliaRegistries/General#readme), and
[Documenter hosting/version layout](https://documenter.juliadocs.org/stable/man/hosting/).

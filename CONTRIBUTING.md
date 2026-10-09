# Contributing

Keep pull requests focused on the accepted design and link the implementation tracker with `Refs` until its entire MVP is delivered.
Functional work belongs on a feature branch and draft PR. Include tests, user documentation, and verification evidence.
Human maintainer review is required before merging AI-assisted contributions; disclose assistance in the PR.
New decomposition methods must follow the [global-guarantee design decision](docs/src/guarantees.md):
declare the method's class, assumptions, exact special cases, proof/completion and fallback rules,
and provide independent global-oracle tests or an exact-child counterexample as appropriate.
Preserve upstream notices when adapting code. Do not assign a dependency's copyright ownership to newly authored files.

Once the runtime is available, run `julia --project=. -e 'using Pkg; Pkg.test()'`.
Runtime dependencies are QUBOTools, QUBODrivers, MathOptInterface and used Julia standard libraries.
JuMP and ToQUBO belong in test/example environments.

Maintainer and release authority: @bernalde. Tagging, registration and releases are separate maintainer actions.

## Dependency maintenance and merged branches

Dependabot updates the root, docs and ToQUBO example environments weekly, and
GitHub Actions monthly. Julia updates are grouped by environment. The trusted-main
Dependabot Auto-merge workflow squashes same-repository, non-draft Dependabot PRs
into main only after all five Julia lanes, Documentation build and all other
reported current-head checks are successful (optional neutral/skipped checks
are allowed). Major and grouped updates follow the same gates. Human PRs and
forks remain for maintainers. Changed heads, missing checks, outdated branches,
conflicts and unresolved merge gates block automatic merging; no admin bypass
or deferred auto-merge is used. Maintainer commits on a Dependabot PR still
require checks at the resulting head.

Main uses strict required checks for the five Julia lanes and conversation
resolution, following QUBO.jl's policy. Human maintainer review of AI-assisted
contributions remains required by this contribution policy. GitHub's native
post-merge branch deletion covers human and Dependabot PRs while retaining
protected branches. This setting does not remove existing unmerged branches.

The Actions token suppresses ordinary post-merge push workflows. Automation
therefore dispatches the existing main-only Documentation workflow to refresh
`gh-pages` and Actions Pages, with a per-PR run marker for idempotent seven-day
reconciliation. This package has no PR documentation previews to clean up.
The existing publisher queue, environment and trust gates stay intact. Failed
publication requires inspection and a manual rerun; reconciliation does not
hide failures with replacement runs. Ordinary main CI is also suppressed by a
token merge, so badges remain at the last ordinary main run; passing up-to-date
PR CI is the merge evidence. Publication to this package does not refresh the
QUBO.jl aggregate: its existing documentation workflow must run subsequently.

# General registration review disposition

Source: [goerz's review](https://github.com/JuliaRegistries/General/pull/171137#issuecomment-6104133572).
The complete comment, author and UTC timestamps are retained in [review.md](review.md);
[inventory.json](inventory.json) records stable IDs and every mapped request.

Inspected package main: `33b6cb39e7423d65056e884a7ae9a7530e1492b8`.
Submitted 0.1.0 source: `c760d09594adf2dcfc6884523e908d8076af6b4c`.
General registration remains open, with no package tags/releases or General package
record at inspection. This PR does not change the submitted source.

## Dispositions

| ID | Disposition | Verification and result |
| --- | --- | --- |
| R1 | Author action | At @bernalde's explicit follow-up request, the README now has a concise AI-assisted narrative in the maintainer's tone, with purpose, installation, construction, a brief exact/heuristic distinction, badges and manual links. @bernalde must review and certify the wording. The reviewer's explicit request for writing by hand is not automatically satisfied by an AI-assisted rewrite; maintainer authorship and registry acceptance remain human actions. [readme-outline.md](readme-outline.md) retains the factual checklist. |
| R2 | Done | Verified the cited bookkeeping in all three named files. Removed acceptance rows, authority/status and repeated publication-process text from README and the two user-entry pages. Installation remains a development URL install while registration is pending. Manual-build instructions now live in CONTRIBUTING.md; RELEASE.md remains the release procedure. |
| R3 | Done | Repository integration and visible tracked coverage are verified at OIDC head `c9780a49b61efa6e6e1be93d66639af57c0dcce8`: seven files, 922/928 lines, 99.35% on Codecov. The final PR handoff records verification of the subsequent upload-job isolation. The existing Julia 1.10/Linux/latest lane collects full-suite coverage via julia-runtest, runs julia-processcoverage with `directories: src`, validates a nonempty report with executed package lines, retains `lcov.info`, and supplies it to a separate Codecov v7 upload job after all five lanes pass. All five test lanes and documentation checks remain. Upload failure fails the separate coverage check rather than reporting false success. Service activation/authentication and visible results must be assessed separately; see the evidence and remaining actions below. |
| R4 | Done | Added CI, Documentation, dev manual and Codecov badges with repository-specific targets. No percentage or claim of active service configuration was inserted. The default-branch coverage badge needs a successful main upload before it can show coverage. |
| R5 | Done, differently | CONTRIBUTING.md already required human review and PR disclosure. Added a short README assistance/responsibility disclosure based on the user's explicit statement; kept this PR draft for human certification. A new acknowledgment on General was explicitly requested separately; it is not a claim that the fixes or human-authored README are complete. |

## Validation evidence

Local verification uses Julia 1.10.11 and released QUBOTools 0.16.2,
QUBODrivers 0.6.5, MOI 1.54.0, JuMP 1.32.1 and ToQUBO 0.7.1:

- `Pkg.test(coverage="user")` passed, including driver conformance and ToQUBO.
- `docs/make.jl --skip-deploy` passed with Documenter 1.19.0, doctests and offline
  examples; `docs/check.jl` passed for 26 Markdown files.
- Inspected rendered overview and quick-start HTML, including installation,
  strategy output and links; contributor build steps no longer appear there.
- Tested the documented URL install at main in a new project and the README
  constructor. Quick-start now explicitly installs MathOptInterface, which its
  doctest imports directly; relying on a transitive dependency is insufficient.
- Ran the inspected julia-processcoverage v1 implementation with
  `INPUT_DIRECTORIES=src`; generated LCOV for all seven package source files. The upload guard passed
  with 922 executed out of 928 measured source lines (local report, not a
  service coverage result).
- `actionlint .github/workflows/ci.yml` and `git diff --check` passed.

The final PR handoff records current-head CI and upload evidence. The README
narrative was subsequently rewritten at the maintainer's explicit request; its
installation commands and construction example are unchanged, and its claims
are checked against the same source and guarantees manual. No numerical
comparison campaign is repeated and no prose-pinning test is added.

## Coverage integration and remaining service action

Choice follows the existing QUBOTools integration and the official
[julia-processcoverage guidance](https://github.com/julia-actions/julia-processcoverage),
[julia-runtest coverage default](https://github.com/julia-actions/julia-runtest/blob/v1/action.yml),
and [Codecov action inputs](https://github.com/codecov/codecov-action).
The uploader uses `files: lcov.info` and `disable_search: true`.
The workflow retains `pull_request` and `contents: read`. The separate coverage upload job requests
`id-token: write` to obtain a short-lived Codecov audience identity; repository
write permissions are not granted. It does not use `pull_request_target` or
execute fork code with repository secrets. The Codecov v7 action skips OIDC
requests for fork PRs and uses its supported public-fork tokenless flow.
Same-repository uploads use OIDC; a stored token is not needed for normal PRs.
Dependabot OIDC is expected but must be verified on its first upload. If it cannot
authenticate, the uploader supports CODECOV_TOKEN as a Dependabot-secret fallback.
All Julia test jobs retain only `contents: read`; the upload job downloads the
report after all five lanes pass and never runs Julia or repository scripts.

At initial inspection neither repository nor available organization secret names
included CODECOV_TOKEN. The public Codecov API returned `active: false`,
`activated: false`, and `totals: null`. The original unauthenticated uploader
failed; the follow-up now uses Codecov's supported GitHub OIDC authentication
instead of requiring a stored upload token. At `c9780a49`, the OIDC upload succeeded,
the public API reports `active: true` and `activated: true`, and the commit is
`complete` with seven files, 922/928 executed lines and 99.35% coverage.
The final PR handoff records the
new-head upload and observable service result. Local LCOV generation alone is
not upload success. A PR upload alone does not establish main's baseline.

## CI upload evidence and independent review

At initial head `b7bf54471e59ddd3f7478e2010406e6a7a3c6ed2`,
[coverage job 114379999531](https://github.com/JuliaQUBO/QUBODecomposition.jl/actions/runs/38108851313/job/114379999531)
passed package tests, source report processing/validation, and artifact retention.
The uploader command used `--disable-search --file lcov.info`, found exactly that
report, and failed with `Token required because branch is protected`.
The retained `source-coverage` artifact was downloaded and inspected separately.
This is an authentication failure, not a successful upload or visible service result.
The same authentication failure recurred at heads `a12e1215` and `7cafc555`;
all tests and report checks passed. The follow-up switches to the official
Codecov action's GitHub OIDC authentication and preserves strict upload failure.
No stored service credential or Codecov setting was changed by this task.
The first OIDC upload at `c9780a49` succeeded and its visible service result was
verified. The follow-up isolates identity permission to the report uploader,
qualifies Dependabot expectations, and adds a Dependabot-secret fallback. Source
coverage is an explicit required check in the repository's merge automation.
Verify the final-head upload and the first Dependabot upload separately.

The independent initial review used Claude Code 2.1.292. Requested model/effort:
`claude-opus-5-5` / high. Client JSON reported canonical model
`claude-opus-5-5`, exposed no effort metadata, and reported zero nested helpers.
Implementer requested: GPT-6.1 Sol / high; this session exposes no verifiable
implementer model/effort metadata. The review found no Blocking source issue and
two Nonblocking corrections: update the manual-build link after moving its target,
and explain the Dependabot coverage credential. The first follow-up updated the
link, removed the obsolete source-reference claim, and documented the original
credential requirement in CONTRIBUTING.md. The later OIDC fix removes that
stored-token dependency. The append-only PR handoff records current-head CI and
service results. Local runtime/coverage evidence remains reusable because source,
tests and dependency inputs are unchanged; CI validates the changed authentication.
The affected docs were rebuilt after the link fix.

## Source and release handoff

Merging this PR later will change main, not the source already submitted for 0.1.0.
@bernalde and the registry reviewer must decide whether to replace the pending
submission with a verified source that includes these changes, or handle the
fixes in a subsequent version. The intervening main contains runtime features
absent from the submitted source, so rebasing the submission onto main is a
release-scope decision, not an automatic documentation fix. No tag, release,
registration retrigger, submission edit, merge or thread resolution is performed.

## Eventual reviewer response — draft, not posted

After reviewing the README and confirming coverage, write a short response in
your own words that links the merged fix, accurately describes README authorship
and your certification, and points to coverage for the agreed release source. Confirm the
source decision with the reviewer before any release or registration action.

Possible structure (fill only after verification):

> The README now focuses on installation and use, and I've reviewed the final
> wording [describe AI assistance accurately]. The release bookkeeping is out of
> the user docs. Coverage is uploaded to Codecov: [verified report].
> The package changes are in [merged PR]. The source we plan to register is
> [agreed full SHA]. Please take another look when you have a chance.

The separate acknowledgment requested by the user is posted at
https://github.com/JuliaRegistries/General/pull/171137#issuecomment-6105025644 .
The detailed technical response above remains unposted.

Targeted review of the OIDC head found no Blocking issue, one Nonblocking request
to isolate identity permission, and one Question about unverified Dependabot
claims. Both are addressed by the separate upload job and qualified contributor
guidance/fallback. The existing 17 automation tests pass, including the required
coverage check in the workflow/merge-check inventory. Only the uploader receives
identity permission; all five Julia test lanes and report validation stay intact.

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
| R1 | Author action | @bernalde must write the final README narrative by hand and review it from a user's perspective. The existing construction example and manual links remain; [readme-outline.md](readme-outline.md) supplies the outline and factual checklist. Mechanical deletions and badges in this PR do not satisfy human authorship. |
| R2 | Done | Verified the cited bookkeeping in all three named files. Removed acceptance rows, authority/status and repeated publication-process text from README and the two user-entry pages. Installation remains a development URL install while registration is pending. Manual-build instructions now live in CONTRIBUTING.md; RELEASE.md remains the release procedure. |
| R3 | Author action | Repository integration is implemented; @bernalde must activate Codecov and verify visible tracking. The existing Julia 1.10/Linux/latest lane collects full-suite coverage via julia-runtest, runs julia-processcoverage with `directories: src`, validates a nonempty report with executed package lines, retains `lcov.info`, and passes exactly that report to Codecov v7. All five test lanes and documentation checks remain. Upload failure fails the lane rather than reporting false success. Service activation/authentication and visible results must be assessed separately; see the evidence and remaining actions below. |
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

The final PR handoff records current-head CI and upload evidence. No numerical
comparison campaign is repeated and no prose-pinning test is added.

## Coverage integration and remaining service action

Choice follows the existing QUBOTools integration and the official
[julia-processcoverage guidance](https://github.com/julia-actions/julia-processcoverage),
[julia-runtest coverage default](https://github.com/julia-actions/julia-runtest/blob/v1/action.yml),
and [Codecov action inputs](https://github.com/codecov/codecov-action).
The uploader uses `files: lcov.info` and `disable_search: true`.
The workflow retains `pull_request` with `contents: read`; it does not use
`pull_request_target`, privileged execution, or OIDC write permissions.
Fork PRs receive no repository token and use Codecov's supported public-fork flow.

Neither repository nor available organization secret names included CODECOV_TOKEN.
The public Codecov API returned `active: false`, `activated: false`, and
`totals: null`; its badge currently reports unknown coverage. Authenticated
Codecov settings were not available. @bernalde must activate this repository
in Codecov and
provide a repository-scoped CODECOV_TOKEN to GitHub Actions (and separately to
Dependabot if needed), or confirm the existing public tokenless configuration.
Do not expose that token to fork PRs. Then rerun the affected CI and verify the
uploaded commit/report and visible service result. Local LCOV generation alone
is not upload success. A PR upload alone does not establish main's baseline.

## CI upload evidence and independent review

At initial head `b7bf54471e59ddd3f7478e2010406e6a7a3c6ed2`,
[coverage job 114379999531](https://github.com/JuliaQUBO/QUBODecomposition.jl/actions/runs/38108851313/job/114379999531)
passed package tests, source report processing/validation, and artifact retention.
The uploader command used `--disable-search --file lcov.info`, found exactly that
report, and failed with `Token required because branch is protected`.
The retained `source-coverage` artifact was downloaded and inspected separately.
This is an authentication failure, not a successful upload or visible service result.
@bernalde must activate Codecov and supply CODECOV_TOKEN as both an Actions and
Dependabot secret, unless an explicitly verified public tokenless configuration
replaces the token requirement. Then rerun the affected check and verify service
coverage. No service setting or credential was changed by this task.

The independent initial review used Claude Code 2.1.292. Requested model/effort:
`claude-opus-5-5` / high. Client JSON reported canonical model
`claude-opus-5-5`, exposed no effort metadata, and reported zero nested helpers.
Implementer requested: GPT-6.1 Sol / high; this session exposes no verifiable
implementer model/effort metadata. The review found no Blocking source issue and
two Nonblocking corrections: update the manual-build link after moving its target,
and explain the Dependabot coverage credential. The follow-up updates that link,
removes the obsolete source-reference claim, and adds the credential requirement
to CONTRIBUTING.md. The PR handoff summary supplies the same explicit action.
Full runtime/coverage evidence remains reusable because these fixes change only
contributor text and a documentation link; the affected docs are rebuilt.

## Source and release handoff

Merging this PR later will change main, not the source already submitted for 0.1.0.
@bernalde and the registry reviewer must decide whether to replace the pending
submission with a verified source that includes these changes, or handle the
fixes in a subsequent version. The intervening main contains runtime features
absent from the submitted source, so rebasing the submission onto main is a
release-scope decision, not an automatic documentation fix. No tag, release,
registration retrigger, submission edit, merge or thread resolution is performed.

## Eventual reviewer response — draft, not posted

After supplying the README and confirming coverage, write a short response in
your own words that links the merged fix, identifies the human-written README,
and points to the uploaded coverage for the agreed release source. Confirm the
source decision with the reviewer before any release or registration action.

Possible structure (fill only after verification):

> I've rewritten the README myself and removed the release bookkeeping from the
> user docs. The coverage report is now uploaded to Codecov: [verified report].
> The package changes are in [merged PR]. The source we plan to register is
> [agreed full SHA]. Please take another look when you have a chance.

The separate acknowledgment requested by the user is posted at
https://github.com/JuliaRegistries/General/pull/171137#issuecomment-6105025644 .
The detailed technical response above remains unposted.

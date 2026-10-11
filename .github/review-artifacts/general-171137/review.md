Source: https://github.com/JuliaRegistries/General/pull/171137#issuecomment-6104133572
Author: @goerz
Created: 2026-10-11T01:19:41Z
Updated: 2026-10-11T01:19:41Z

Thank you for submitting your package! My concerns here are about the visible degree of LLM involvement, so let me point at the [LLM guidelines for registered packages](https://github.com/JuliaRegistries/General#is-there-any-policy-regarding-the-use-of-llms-in-registered-packages) up front. I see that `CONTRIBUTING.md` already requires human review of AI-assisted contributions, so this is mostly about one artifact.

The README is not written for a human reader. A good part of it is internal release bookkeeping ("Acceptance rows 1–20 are delivered, and the development manual is published", "Row 21 requires verified publication and registry installation, followed by ecosystem adoption", "Accepting maintainer and release authority"), which tells a potential user nothing about what the package does or how to use it. The warning that a `Project.toml` version does not establish publication is made three times in the README alone, and then again in `docs/src/index.md` and `docs/src/start.md`. Please make sure that you write your READMEs by hand, based on your own understanding; the README in particular is a document targeted at a human user. The release-process material already has a proper home in `RELEASE.md`, and what should be left is a short description of what the package does, the construction example you already have, badges, and a link into the manual.

The other point is minor: the CI workflow never uploads coverage information, so nothing is tracking it over time. Could you add `julia-actions/julia-processcoverage` and a Codecov or Coveralls upload, along with the usual README badges? You can copy that part of the CI script from most other popular Julia packages. Packages developed mostly through LLMs should meet a slightly higher standard, and decent _tracked_ test coverage is part of that.

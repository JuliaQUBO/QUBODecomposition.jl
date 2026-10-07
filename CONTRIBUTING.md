# Contributing

Keep pull requests focused on the accepted design and link the implementation tracker with `Refs` until its entire MVP is delivered.
Functional work belongs on a feature branch and draft PR. Include tests, user documentation, and verification evidence.
Human maintainer review is required before merging AI-assisted contributions; disclose assistance in the PR.
Preserve upstream notices when adapting code. Do not assign a dependency's copyright ownership to newly authored files.

Once the runtime is available, run `julia --project=. -e 'using Pkg; Pkg.test()'`.
Runtime dependencies are QUBOTools, QUBODrivers, MathOptInterface and used Julia standard libraries.
JuMP and ToQUBO belong in test/example environments.

Maintainer and release authority: @bernalde. Tagging, registration and releases are separate maintainer actions.

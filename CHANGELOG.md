# Release notes

## Unreleased

- Preserve fully validated strict improvements from normally returned interrupted
  children on whole-model and ordinary serial/component routes, then stop with
  truthful interruption status. Keep separator and frozen-batch transactions
  atomic and interrupted results uncertified under the existing shared budgets.

## 0.1.0 — release notes

Release source and publication are verified through [RELEASE.md](RELEASE.md).

### Runtime

- Standalone QUBO/Ising optimizer using public QUBOTools, QUBODrivers and MOI APIs.
  Whole-model dispatch, independent connected components and bounded serial
  conditioned sweeps reconstruct full states and evaluate the original objective.
- Opt-in state-aware `selection=:single_flip_gain`, multi-hop `selection=:bfs`
  and seeded `selection=:random_blocks`. Strongest-edge selection stays the default.
- Opt-in `strategy=:separator` with supplied separators or automatic
  `separator=:articulation` discovery. Shared budgets and private branch transactions
  preserve incumbents; global `OPTIMAL` requires exhaustive branch coverage and
  valid public optimality certificates for every residual child problem.
- Opt-in `selection=:partition`, accepting an owned plan or a flat callback.
  Validate capacity and coverage, condition boundaries exactly and record planning
  costs and cut statistics. Coupled partition sweeps remain heuristic.
- Opt-in `strategy=:frozen_batch` with overlapping frozen-boundary proposals,
  unweighted voting and conditional disagreement repair. Commit only complete,
  strictly improving batch transactions under shared budgets; serial stays the default.
- Invocation/per-child budgets, deterministic seeds, repeated-solve invalidation,
  conservative statuses and separate candidate/physical-read accounting.
- Direct JuMP and released ToQUBO 0.7.1 composition in separate environments;
  integer/slack/quadratization fixtures, penalty refinement and cooperative outer deadlines.

### Documentation and validation

- Executable examples, the development manual, sampler catalog and QUBO aggregate;
  concise installation and README guidance, CI/documentation badges and tracked
  source coverage through a separate Codecov uploader using OIDC for same-repository runs.
- Independent scalar/global-oracle and driver-conformance tests for the public
  strategies, plus retained revision-pinned bounded comparisons.
- A compact certified-child adapter and its comparison live only in tests/examples.
  They are an experiment, not a production API or an adopted optimization.
- TagBot and provenance-gated release documentation are prepared for the publication
  sequence. Registration, tags, stable documentation and registry adoption each
  require their own verification.

Julia >=1.10; QUBOTools >=0.16.2 on 0.16, QUBODrivers >=0.6.5 on 0.6, MOI 1.
JuMP and ToQUBO are test/example dependencies. License: MPL-2.0; see LICENSE/NOTICE.

Exact local children do not prove coupled sweep or frozen-batch global optimality.
Released ExactSampler retains its conservative public status. The voting comparison
found equal quality with mixed costs on its small fixtures; it established no general
quality or speed advantage. Numerical comparisons remain tied to their original
producing revisions and limits.

Opaque synchronous children cannot be forcibly cancelled; automatic ToQUBO
refinement has no shared wall-clock deadline. Parallel children, preprocessing,
external execution and broader benchmark campaigns remain separate work.

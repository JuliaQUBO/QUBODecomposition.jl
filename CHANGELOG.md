# Release notes

## Unreleased

- Add opt-in `strategy=:separator` with bounded user-supplied separators, private
  branch transactions, shared budgets and separate exhaustive proof metadata.
  Global `OPTIMAL` requires all residual public certificates and complete branch
  coverage; released ExactSampler retains its conservative status.

- Add opt-in `selection=:bfs` multi-hop neighborhoods and
  `selection=:random_blocks` solve-local seeded permutations, with complete
  per-sweep component coverage, recorded blocks and independent child seeds.
- Extend the matched-work selector comparison and heuristic guarantee checks.
  Strongest-edge remains the default; coupled exact-child search remains heuristic.

These changes follow the source submitted for 0.1.0 registration and belong in a
subsequent release with the single-flip-gain policy. They do not change that
registration's source revision or publish a release.

## 0.1.0 — release notes

These notes describe the source prepared for the first General release. Publication
is established by the registry/tag/release checks in RELEASE.md, not this entry.

- Standalone local QUBO/Ising optimizer on public QUBOTools, QUBODrivers and MOI APIs.
- Whole-model child dispatch, independent connected components and bounded serial
  conditioned neighborhood sweeps, with full-state reconstruction and independently
  evaluated original objectives.
- Invocation/per-child budgets, deterministic seeds, repeated-solve invalidation,
  conservative statuses and separate candidate/physical-read accounting.
- Direct JuMP and released ToQUBO 0.7.1 composition in separate environments;
  integer/slack/quadratization fixtures, penalty refinement and cooperative outer deadlines.
- Executable examples and a published development manual, sampler catalog and QUBO
  aggregate; prepared TagBot and a provenance-gated main-dispatched release-documentation
  workflow, to be exercised after registration.

Julia >=1.10; QUBOTools >=0.16.2 on 0.16, QUBODrivers >=0.6.5 on 0.6, MOI 1.
JuMP and ToQUBO are test/example dependencies. License: MPL-2.0; see LICENSE/NOTICE.

Exact neighborhoods do not prove coupled global optimality. Opaque synchronous
children cannot be forcibly cancelled; automatic ToQUBO refinement has no shared
wall-clock deadline. Parallel children, advanced strategies, full benchmark
campaigns, external execution and registry-based ecosystem adoption remain later work.

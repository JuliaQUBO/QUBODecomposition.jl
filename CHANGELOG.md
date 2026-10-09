# Release notes

## 0.1.0 — planned first General release

This entry prepares release notes. No registration, tag or release is claimed.

- Standalone local QUBO/Ising optimizer on public QUBOTools, QUBODrivers and MOI APIs.
- Whole-model child dispatch, independent connected components and bounded serial
  conditioned neighborhood sweeps, with full-state reconstruction and independently
  evaluated original objectives.
- Invocation/per-child budgets, deterministic seeds, repeated-solve invalidation,
  conservative statuses and separate candidate/physical-read accounting.
- Direct JuMP and released ToQUBO 0.7.1 composition in separate environments;
  integer/slack/quadratization fixtures, penalty refinement and cooperative outer deadlines.
- Executable examples and a published development manual, sampler catalog and QUBO
  aggregate; prepared TagBot and verified main-dispatched release-documentation path.

Julia >=1.10; QUBOTools >=0.16.2 on 0.16, QUBODrivers >=0.6.5 on 0.6, MOI 1.
JuMP and ToQUBO are test/example dependencies. License: MPL-2.0; see LICENSE/NOTICE.

Exact neighborhoods do not prove coupled global optimality. Opaque synchronous
children cannot be forcibly cancelled; automatic ToQUBO refinement has no shared
wall-clock deadline. Parallel children, advanced strategies, full benchmark
campaigns, external execution and registry-based ecosystem adoption remain later work.

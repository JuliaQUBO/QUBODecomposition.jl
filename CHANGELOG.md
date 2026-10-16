# Release notes

## Unreleased

- Add opt-in `strategy=:sample_fixing` with a bounded owned labelled original-domain
  pool, equal votes per distinct assignment and deterministic strict-majority unary
  fixing. All supplied rows are validated/charged before a pool-best transaction;
  support, public fixing/lifting maps and offsets are retained. Restricted child
  work preserves a separate full incumbent and every nonconstant route remains
  heuristic. External pool generation cost is unknown unless explicitly reported.
  See [sample-guided fixing](docs/src/sample_fixing.md).

- Add opt-in `strategy=:coarse` with explicit disjoint `coarse_groups` for one
  bounded block-orientation proposal. The full original objective is substituted,
  and every lifted child row is ranked using the original objective. Capacity
  counts macrovariables; nonconstant completion remains heuristic. Planning,
  construction, lifting and evaluations share parent caps and deadlines.
  See [coarse proposals](docs/src/coarse.md) for configuration, provenance and
  interrupted-result handling.

## 0.1.3 — release notes

- Add opt-in `separator_pruning=true` for `strategy=:separator`. Exact-rational
  termwise bounds and incumbent comparisons interpret the stored logical
  objective, including sense, signed scale and offset. Certified exclusions skip
  residual dispatch; uncertain evidence abstains. Solved-branch certificate
  transfer is conservative when conditioning or dispatch changes coefficients.
  Global `OPTIMAL` still requires complete certified solved-or-pruned coverage.
  Diagnostics distinguish solved, certified-pruned and unfinished branches; all
  work shares the parent calls, candidate budgets and deadlines.
  ([#40](https://github.com/JuliaQUBO/QUBODecomposition.jl/issues/40),
  [PR #41](https://github.com/JuliaQUBO/QUBODecomposition.jl/pull/41))
- Add experimental opt-in `strategy=:consensus` with explicit overlapping plans
  covering every variable and interaction. Serial bounded multiplier coordination
  produces independently evaluated complete original candidates, with separate
  exact-rational certified bounds/gaps when all child evidence supports them.
  Rounded child-surrogate residuals are bounded conservatively; missing evidence
  stays unavailable. Bounds/gaps use normalized minimization units (negate a bound
  for an original maximization upper bound); scalar candidate energies retain the
  original sense/scale/offset conventions. Completed iterations publish atomically.
  ([#39](https://github.com/JuliaQUBO/QUBODecomposition.jl/issues/39),
  [PR #42](https://github.com/JuliaQUBO/QUBODecomposition.jl/pull/42))
- Consensus remains a heuristic: exact children, copy agreement and zero reported
  gap do not promote completion to global `OPTIMAL`. The independently justified
  constant-objective route keeps its existing proof rule. Reference-copy
  reconciliation, finite iterations, bounded multipliers, possible duality gaps
  and rounding-altered update directions limit quality and convergence claims.
  Both features' certificates begin at the stored logical objective and rely on
  documented child contracts; they do not certify upstream modeling arithmetic
  or ToQUBO source feasibility. Released ExactSampler remains `LOCALLY_SOLVED`.
- Defaults, Julia >=1.10 and all dependency floors remain unchanged. Deadline
  enforcement is cooperative; opaque children and exact certificate work can
  overrun. No general quality or performance advantage is established. The
  historical consensus comparison's conclusion is **revise before wider adoption**:
  mixed quality/work across three tiny fixtures, with 18 attempts measuring
  `d3b778054b6da94668102d76f5716a9181350ff9` before later review fixes. Separator
  timings likewise describe their recorded producing revision. Neither comparison
  is a 0.1.3 measurement; evidence and spent allowances remain historical.
- Extend installed-distribution smoke checks with the existing guarded offline
  pruning and consensus examples, original-energy/reconstruction assertions and
  truthful certificate/status checks. Preserve fitting/serial/version checks,
  caller-owned two-worker lifecycle/deadline coverage and separate ToQUBO smoke.

See [pruning guarantees](docs/src/guarantees.md#certified-separator-exclusions),
[consensus](docs/src/consensus.md) and the historical
[pruning](examples/pruning/README.md) / [consensus](examples/consensus/README.md)
comparisons. These APIs require **0.1.3 or later**. Before publication, install an
exact full candidate SHA; ordinary General installation does not establish that
this version is available. Follow [RELEASE.md](RELEASE.md) for the separate human
acceptance, registration and publication gates. Issues #17/#18, consensus
reconciliation improvements and future QUBOPreprocessing integration are separate
work.

## 0.1.2 — release notes

- Add explicit `SequentialComponentExecutor()` and bounded
  `ProcessComponentExecutor(pool; max_inflight=...)` for independent,
  capacity-fitting components with `strategy=:components`. Both plan separate
  components even when the whole model fits capacity. Existing serial defaults,
  zero-argument child factories and coupled strategy behavior remain unchanged.
  ([PR #36](https://github.com/JuliaQUBO/QUBODecomposition.jl/pull/36))
- Expose owned frozen `ComponentJob` inputs and `ComponentResult` outputs, with
  job-aware factories and a generic executor extension boundary. Callers initialize,
  dedicate, reuse and clean up local worker pools; the package creates or terminates
  no workers and transports no live optimizer. Validation and strictly improving
  commits follow deterministic component order and independently score the full
  original objective. Calls, candidates and deadlines share one parent budget;
  failures remain charged, submitted jobs drain and no job is implicitly retried.
- Preserve truthful partial, interrupted and failure outcomes. Global `OPTIMAL`
  requires complete validated public optimality certificates from every independent
  component (or the existing constant-model rules). Heuristic children, incomplete
  scans and failed/missing results provide no global proof. Child-duration sums
  may overlap and are not parent wall time or overhead.
- Add `absolute_deadline_sec` to the constructor and raw MOI options. It uses
  local-host monotonic seconds (`time_ns()/1e9`), persists across invocations and
  combines with `MOI.TimeLimitSec` by taking the earlier deadline. Expired deadlines
  prevent dispatch and commit; an already expired invocation returns `TIME_LIMIT`
  without an incumbent. Caller and workers must share the monotonic clock origin.
  ([PR #37](https://github.com/JuliaQUBO/QUBODecomposition.jl/pull/37))
- Deadlines are cooperative: input copying, callbacks and opaque children can
  overrun, and every exit drains submitted work. This API provides no hard
  cancellation. Coupled sweeps, separator branches and frozen voting batches
  retain their serial paths; remote hosts, worker restart and replacement are
  outside the supported process executor.
- Document the minimum API version (0.1.2), registered versus exact-source
  installation and the retained, revision-pinned experiment with bounded claims.
  Extend installed-distribution smoke coverage to real local workers, package and
  environment identity, pool reuse/caller cleanup and expired absolute deadlines.

See [component execution](docs/src/components.md) and
[budgets](docs/src/budgets.md) for the supported contract. Runtime dependency floors
and Julia >=1.10 are unchanged. Publication requires the separate verification
gates in [RELEASE.md](RELEASE.md); preparation does not establish registration,
tagging, a GitHub release or stable documentation publication.

## 0.1.1 — release notes

- Preserve fully validated strict improvements from normally returned interrupted
  children on whole-model and ordinary serial/component routes, then stop with
  truthful interruption status. Keep separator and frozen-batch transactions
  atomic and interrupted results uncertified under the existing shared budgets.
  ([PR #31](https://github.com/JuliaQUBO/QUBODecomposition.jl/pull/31))
- Correct the graph-partition section link in the configuration guide.
  ([PR #33](https://github.com/JuliaQUBO/QUBODecomposition.jl/pull/33))
- Track package-version metadata during precompilation so reused caches report
  the current solver version after a version-only change.

Publication of this version requires the verification gates in [RELEASE.md](RELEASE.md).

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

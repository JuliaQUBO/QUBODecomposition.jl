# Independent component execution

The explicit executor API requires QUBODecomposition **0.1.2 or later**. If that
version is not yet registered, use an exact source revision as described in
[installation](start.md).

Serial execution remains the default (`component_executor=nothing`), including
its whole-model shortcut when the input fits `max_variables`. Opt into the
supported component job pipeline with `strategy=:components` and either
`QUBODecomposition.SequentialComponentExecutor()` or
`QUBODecomposition.ProcessComponentExecutor(pool; max_inflight=2)`.
Both explicit executors always plan separate components, even when the entire
model fits capacity. The sequential executor is useful for comparing identical
frozen jobs with process execution.

Only independent, capacity-fitting components are supported. The executor option
requires the default `selection=:strongest_edge`, `partition_plan=nothing` and
`separator=Int[]`. Other strategies/options and any oversized component produce
`INVALID_OPTION` before child dispatch; capacity is checked even for constant
models. Coupled sweeps, separator branches and frozen voting batches remain on
the existing serial paths. Empty/constant models require no child calls.

## Factory and worker setup

Supply a fresh empty MOI optimizer per job. Existing zero-argument factories work;
a factory accepting `ComponentJob` can configure generic allocation and observers
from its supported context. Configure solver-specific attributes in that factory;
the package forwards the job seed and minimum supported time limit. Do not capture
live optimizers, mutable samplers or a shared observer/ledger in transported
closures. Define named factories and their dependencies on every worker first.

Use an explicitly supplied `Distributed.WorkerPool` of local-host processes.
Initialize Julia projects, package imports, factory definitions and thread limits
before solving. Workers must load the same package revision and compatible
Julia/dependencies as the coordinator. Dedicate the pool to these solves; do not
use the same pool/executor concurrently from several parents or unrelated tasks.
The package creates no workers, persists no job/model/result cache and never
terminates caller workers. Pools can be reused across solves and model changes;
the caller owns `addprocs`, initialization and `rmprocs`, including cleanup after
errors. A factory that reuses a still-live optimizer is rejected on its worker.
The executor limits submitted, uncommitted jobs, including out-of-order results
buffered for deterministic commit. It never retries a failed job.

An executable tiny offline example uses two one-thread workers and released
ExactSampler children, with no native SA or service credentials:

```@eval
import Markdown
import QUBODecomposition
Markdown.parse("```julia\n" * read(joinpath(dirname(pathof(QUBODecomposition)), "..", "examples/process_components.jl"), String) * "\n```")
```

```@example processes
import QUBODecomposition # hide
include(joinpath(dirname(pathof(QUBODecomposition)), "..", "examples/process_components.jl")) # hide
run_process_components()
```

## Supported job boundary

`ComponentJob.id` is `(solve_token, invocation, component)`. A fresh opaque solve
token prevents another optimizer, a prior invocation or a changed model from
reusing an identity. Component numbers and original free indices are deterministic;
the solve token is deliberately unique and is never a seed input. `indices` and
`labels` map reduced positions to original free variables. `problem` owns tuples
of normalized coefficients, domain, sense, signed scale and conditioned offset.
`reference` records the frozen component assignment. `seed` is
`(parent_seed + component - 1) mod (2^31-1)`, or `nothing`. `deadline` is the shared
absolute local-host monotonic deadline; `child_time_limit_sec` is the parent child
limit; `candidate_limit` bounds result transfer by the configured candidate cap minus
the initial evaluation, fixed for every job in the invocation. The coordinator
still enforces the shared remaining evaluation allowance. These are generic execution concepts; reads, SA schedules and
scheduled-variable work units belong in a consumer factory/executor.

`execute_component(factory, job)` constructs the optimizer where called, copies
owned model data, sets supported limits, executes and extracts owned result rows.
No private optimizer object or parent solve state is serialized. The worker uses
the minimum of factory time limit, child limit and remaining parent deadline when
the child supports `MOI.TimeLimitSec`. The result carries public termination,
reported result count, tuples of rows and support/worker/timing diagnostics.
Worker exceptions propagate to the coordinator as errors, without replacement.

A custom `AbstractComponentExecutor` implements `executor_width` and
`submit_component(executor, factory, job)`. Return promptly with an `isready`/
`fetch` handle producing exactly one `ComponentResult` or throwing an error.
The handle must remain drainable on every exit. Consumers can attach per-child
allocation and diagnostics using this interface without accessing optimizer
internals. Preserve owned data, isolation and identity; no implicit retry.
The coordinator rejects duplicate, stale, mismatched and malformed envelopes,
invalid/nonfeasible rows, nonfinite reported energies and failure-class statuses.
Additional diagnostic fields are retained but cannot alter acceptance/proof.
This is a trusted local extension interface, not a sandbox for arbitrary code.

## Acceptance, budgets and stops

All component inputs are conditioned on the same frozen reference. No nonzero
edge crosses components, so changing a complement changes only a child's
constant. The coordinator commits in ascending component order, merging only the
component's returned variables into the **current** full incumbent. It evaluates
every candidate in the original objective, including scale and offset; it never
sums child energies with repeated conditioned constants. Within each complete
scan, equal-energy candidates use lexicographic full-state order. Incumbent
replacement is strictly improving, preserving its existing assignment on ties.
Under nonbinding limits and deterministic factories/children, sequential and
process executors have identical job inputs/seeds and final results despite
completion order. Wall-clock-limited runs can complete different work depending
on scheduling; identical partial results are not promised.

The initial original evaluation and every validated row share the existing
candidate cap. The coordinator reserves calls before submission (factory/copy/
worker failures remain charged), and requires room for at least one evaluation
per outstanding job before dispatching another. This minimum reservation is not
a promise that all child rows fit. Extra rows can exhaust the shared scan cap;
partial scans never commit or certify their component. Worker result transfer is
bounded by the fixed invocation `candidate_limit`; that cap does not bound opaque child internals.
A complete public `OPTIMAL` component proof exactly at a call/candidate cap retains
`OPTIMAL`; heuristic completion keeps existing cap precedence.

On a shared deadline, cancellation, invalid result, failure or a normally returned
`INTERRUPTED` status, queued dispatch stops. Readiness is inspected before
refilling the window. Previously submitted jobs stay charged. A completely
validated interrupted component may improve the incumbent and then ends the
parent with `INTERRUPTED`, without a global proof. It must have enough scan/time
allowance to complete its transaction. When interruption arrives out of order,
dispatch stops and the coordinator processes the already-dispatched stable prefix
through that component. A parent deadline takes precedence over a late child
status or result. Failure stops acceptance immediately.

Every exit drains outstanding handles; late rows are recorded as
`drained_uncommitted` and cannot mutate the incumbent. Failed/unavailable results
are `failed_or_unknown`. The built-in executor returns each acquired worker to
the pool once its call returns/errors. Opaque/noninterruptible calls can extend
solve/drain wall time beyond the cooperative deadline. There is no forcible
cancellation and no assumption that a reservation was unspent. Callers needing a
hard wall/memory bound must enforce an OS limit on the process group. Remote hosts,
worker restart and replacing failed jobs are outside this initial executor.
After process loss, the caller must supply a healthy pool before another solve.

## Proof and timing

This is the existing separable method with concurrent isolated children. The
original objective is a constant plus independent component terms over a product
of binary/spin domains, so complete validated public `OPTIMAL` solutions for every
component assemble a global optimum. Signed scale/sense are included in each
child objective and the independent full evaluation. Public `LOCALLY_SOLVED`
(including ExactSampler), missing/failed components and incomplete scans cannot
establish this proof. Fixed variables remain reconstructed by the existing driver
MOI copy hook; optimality is over the supplied logical QUBO, with the existing
ToQUBO source-feasibility qualifications.

`time.effective` / `MOI.SolveTimeSec` measure parent wall time including waiting and
draining. `child_execution_sec` sums child execution durations and can exceed
parent wall time. Failed/missing results have unavailable child durations;
`child_execution_timing_complete=false` flags that the sum contains only available
durations. In explicit executor mode, `parent_processing_sec=nothing`:
subtracting overlapping child durations does not measure overhead. Invocation
`phase_sec` records coordinator preparation/conditioning/validation/full-energy
work; its execution/copying slots do not duplicate worker costs. Per-call
`executor_diagnostics` separates worker copying, execution and extraction, with
worker id and local-host monotonic execution start/end. The invocation `execution`
record includes window width, maximum observed in-flight count, arrival/commit
orders, wait and drain wall durations. These durations overlap and are not
additive. Per-job state/status/support/seeds/maps are retained in the existing
bounded call log; no benchmark-specific storage or mandatory heavy tracing is
added.

The retained [four-arm native SA experiment](https://github.com/JuliaQUBO/QUBOBenchmarks.jl/blob/6e195598461969a89c0d70a40f22a1fa02ef88df/examples/decomposition/sa/four-arm/evidence/native-20261014/REPORT.md)
used package revision `4f39e6eba398d0fa6c9c70c0b5e30e437ceb2c29`, whose tree matches
the 0.1.2 preparation base `44a97d92963726a200b54f6a7c72f6c53e08fb00`.
Its 32 validation controls and 88 comparison slots are complete and spent; all
20 component measurement pairs matched native inputs, output multisets and final
assignments. The n=256 matched four-arm analysis retained nine complete blocks
because one portfolio measurement hit its deadline. These observations establish
neither general speedup nor SA optimality and give no reason to change defaults.
The example and tests make no performance claim; the historical campaign is not
part of package installation or release verification.

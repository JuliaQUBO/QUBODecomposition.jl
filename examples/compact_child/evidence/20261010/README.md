Complete original raw attempt files are losslessly compressed; use gzip -dc ordinary/results.toml.gz > /tmp/compact-ordinary.toml. SHA256SUMS checks the committed archive. Both cohorts retain all four warmups and twenty measured attempts. Source objective checks are a separate validation pass, derived from the checked complete-coverage loop in adapter.jl; optimizer evaluation/search assignment fields exclude this validation pass. Unit tests have separate bounded work and do not spend the timing campaign allowance.

Review corrections preserve the frozen raw cohorts and original logs. In both
original `audit.log` files, the line labeled `paired time ms` actually contains
**seconds**; the corrected retained `audit.py` prints those values in milliseconds
and audits paired allocation medians separately. Reproduce it with Python 3.11+:

```sh
python3 examples/compact_child/evidence/20261010/audit.py examples/compact_child/evidence/20261010/ordinary examples/compact_child/REPORT.md
python3 examples/compact_child/evidence/20261010/audit.py examples/compact_child/evidence/20261010/confounded
```

`verify_pinned.jl` retains the identity-check snippet used to compare equations,
variables, domains, senses, scales, offsets, separators and references with the
pinned benchmark modules. The two historical fixture hashes were **recomputed**
by that pin's `DecompositionPilot.fixture_hash` (canonical JSON description), not
looked up in a historical hash list. The equality checks compare actual fixture
objects; local hard-coded tests are separate corroboration. From an environment
with this checkout, QUBOBenchmarks, QUBOLib, JuMP, ToQUBO, DBInterface and DataFrames:

```sh
julia --startup-file=no --threads=1 --project=EXAMPLE_ENV examples/compact_child/evidence/20261010/verify_pinned.jl PINNED_BENCHMARK_CHECKOUT
```

The original check used `/tmp/qubo-compact-task/env`, with the pinned checkout at
`/tmp/qubo-compact-task/benchmarks`. It ran the retained snippet's checks; the new
script replaces those fixed paths with arguments. This is a deterministic audit,
not another timing campaign. The experiment's `run.jl` remains the standalone
portable comparison bootstrap; the identity audit additionally needs the benchmark
example dependencies in its selected environment.

Exact comparison commands used from `/tmp/qubo-compact-task/repo`:

```sh
JULIA_DEPOT_PATH=/tmp/qubo-compact-task/depot:/tmp/qubo-scaling-depot:/home/bernalde/.julia JULIA_NUM_PRECOMPILE_TASKS=1 timeout 360s julia --startup-file=no --threads=1 examples/compact_child/run.jl /tmp/qubo-compact-task/run01 /tmp/qubo-compact-task/cumulative.toml
JULIA_DEPOT_PATH=/tmp/qubo-compact-task/depot:/tmp/qubo-scaling-depot:/home/bernalde/.julia JULIA_NUM_PRECOMPILE_TASKS=1 timeout 360s julia --startup-file=no --threads=1 examples/compact_child/run.jl /tmp/qubo-compact-task/run02 /tmp/qubo-compact-task/cumulative.toml
JULIA_DEPOT_PATH=/tmp/qubo-compact-task/depot:/tmp/qubo-scaling-depot:/home/bernalde/.julia JULIA_NUM_PRECOMPILE_TASKS=1 timeout 360s julia --startup-file=no --threads=1 examples/compact_child/run.jl /tmp/qubo-compact-task/run03 /tmp/qubo-compact-task/cumulative.toml
```

Stdout/stderr were redirected to the retained bootstrap logs. `run01` failed
before reservation; `run02` is confounded; `run03` is ordinary. These commands
record what happened, not permission to execute again: the cumulative ledger is
exhausted. Any new campaign needs a separately authorized allowance. The default
runner initializes a missing ledger, so a new filename must never be used to reset
this task's spent allowance.

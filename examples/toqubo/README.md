# Offline ToQUBO composition

QUBODecomposition is unregistered. From this repository checkout, create the
example environment with Julia 1.10 or later:

```sh
julia --project=examples/toqubo -e 'using Pkg; Pkg.develop(path=pwd()); Pkg.instantiate(); Pkg.status()'
julia --project=examples/toqubo examples/toqubo/refinement.jl
julia --project=examples/toqubo examples/toqubo/deadline.jl
```

The declared environment uses released ToQUBO `0.7` (minimum 0.7.0), JuMP 1,
QUBODrivers on the 0.6 line (minimum 0.6.5) and QUBOTools on the 0.16 line
(minimum 0.16.2). The ignored local manifest records
exact resolution; no development override for an upstream dependency is needed.
After setup, both examples run offline using the public ExactSampler child.
CI runs them on Julia 1.10/current Linux and current Windows.

`refinement.jl` constructs ExactSampler beneath QUBODecomposition beneath
ToQUBO. The two source variables introduce a third compiled slack bit. Budget
2 therefore exercises coupled serial neighborhoods; budget 8 fits the whole
model. A weak penalty yields source objective 11, compiled objective 10.9 and
`INFEASIBLE_POINT`. Automatic refinement makes the decoded source feasible.
`MOI.ObjectiveValue` remains the penalized compiled objective; evaluate the
source separately with `ToQUBO.source_objective_value` and `ToQUBO.violations`.
ExactSampler reports `LOCALLY_SOLVED`, and exact neighborhoods do not establish
a coupled global optimum. The independent whole-model test oracle establishes
the feasible optimum 8; the serial contract promises feasible behavior for this
fixture, not a general global-optimality guarantee.

ToQUBO 0.7.0 has an ordinary repeated-compilation residual: recompiling an
already populated target can retain encodings and add stale slack variables.
The explicit public `MOI.Utilities.reset_optimizer(model)` empties the attached
compiler before copying the source again. The examples use this workaround;
the tests retain the unreset reproduction for the upstream #244 handoff.
Automatic refinement itself already resets between its penalty updates.
Refined hints/scales persist on the compiler; cached source attributes may
replace them on recopy. Set the desired hint explicitly when restarting.

There are three budget scopes: child factory/per-call time, one composite
invocation's calls/candidates/deadline, and ToQUBO's maximum additional penalty
updates. `MaxPenaltyUpdates=5` permits at most six composite invocations; it
provides no shared wall-clock deadline. ExactSampler returns every compiled
assignment: allow `1 + sum(2^child_dimension)` candidate evaluations to scan
all intended calls transactionally.

`deadline.jl` demonstrates an explicit outer loop. It owns one absolute
deadline, disables automatic updates, compiles with a public compiler-only
optimizer, copies the target, and dispatches the composite with the remaining
time. It projects the full bit assignment and independently evaluates this
fixture's source objective and residual. Compilation, copying, checking and
child work all reduce the allowance before the next dispatch. Checks are
cooperative: an opaque synchronous child can overrun and cannot be forcibly
preempted. A returned incumbent must still be checked for source feasibility.
Composite effective time measures only the last composite invocation;
`CompilationTime` measures only the last compilation. Neither is a cumulative
outer-loop measurement.

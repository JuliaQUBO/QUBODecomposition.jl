# Bounded serial Lagrangian consensus

This API requires **0.1.3 or later**; see [installation](start.md).
The historical comparison concluded **revise before wider adoption**,
with mixed quality/work across three tiny fixtures and no general performance
advantage. Its 18 attempts measured
`d3b778054b6da94668102d76f5716a9181350ff9`, before later review fixes; those
measurements are not 0.1.3 results.

## Mathematical contract

This opt-in prototype is heuristic. Its separate certified bound targets the
complete logical input objective, not constraints of a source compiled by ToQUBO.
Let the stored normal form be
`E(x) = scale * (offset + sum_i l_i*x_i + sum_ij q_ij*x_i*x_j)`.
Set `F = s*E`, where `s=1` for minimization and `s=-1` for maximization.
The signed scale, including zero, and the offset are part of this definition.
The certificate interprets each stored finite Float64 as its exact rational value;
it does not first multiply or aggregate the coefficients in floating point.

An explicit ordered plan `B_1,...,B_P` covers all free indices, including isolates.
Each block is nonempty, has distinct valid indices, and fits `max_variables`.
Every nonzero original interaction must have a block containing both endpoints,
even at zero scale. The first containing block owns each linear term and each
interaction; the global constant belongs to block 1 exactly once. No term is split.
Block indices refer to the input's free-variable order after fixed-variable
elimination, not its labels or its pre-elimination MOI indices.

For every occurrence of index `i` introduce a copy `z_pi` in the original Bool
`{0,1}` or Spin `{-1,1}` domain. Its reference is its first containing block.
For every other occurrence impose `z_pi-z_ref(i),i=0`, one row of `Az=0`.
Every original assignment has a unique equal-copy lift; conversely coverage and
these equalities give exactly one original assignment. Single term ownership and
the single constant imply `sum_p F_p(z_p)=F(x)` on this equal-copy domain.
Thus the equality-constrained copied problem is equivalent to the original.

For arbitrary finite real equality multipliers (no sign restriction), define
`g(lambda)=min_z [sum_p F_p(z_p)+lambda'Az]`.
The domain before enforcing equality is a Cartesian product, so this minimum is
the sum of independent block minima. On every equal-copy lift the multiplier
term vanishes. Minimizing over the larger copied domain therefore gives
`g(lambda) <= min_x F(x)` (weak duality). Maximizing this concave function need
not close the duality gap. Exact block minimizers supply the supergradient `Az`;
heuristic block solutions or rounded surrogate minimizers do not automatically
supply a supergradient for the intended dual.

## Arithmetic and evidence

A block child receives minimization, scale one, and zero constant. Its linear and
quadratic coefficients are rounded to Float64 from the exact intended surrogate.
Let `h` be that dispatched polynomial, `f` the intended block polynomial without
its constant, and `r=f-h`. For each residual term take its minimum over the
original domain independently; their sum `R` satisfies `r(z)>=R`. A completely
scanned public `OPTIMAL` child, under its MOI promise to solve the dispatched
objective globally, supplies a minimizing returned state `z*` and hence
`min f >= h(z*)+R`. Add the exact owned block constant, then sum all blocks.
All these operations use exact rationals. If coefficients cannot be dispatched
finitely, the call fails conservatively. Missing, interrupted, local, approximate
or unsupported certificate evidence never supplies a block lower bound. A
heuristic incumbent energy is an upper bound on a block minimum, not a lower
bound. ExactSampler on QUBODrivers 0.6.5 reports uncertified `LOCALLY_SOLVED`.
Under the corrected 0.6.6 public contract it can supply supported block
certificates, subject to the same validation and rounding corrections. This
does not promote consensus completion to an original global certificate.
No additional solver capability or reported ObjectiveBound is inferred.

When every residual variable coefficient is zero, exact child minima also
minimize the intended surrogate. Otherwise the residual bound remains valid but
copy disagreement is only a heuristic update direction. Constants are restored
exactly even though children never receive them. The certificate assumes the
child honors the mathematical MOI objective it is given; public status cannot
validate an arbitrary dishonest child.

Original candidates are reconciled by taking each variable's reference copy.
This yields a complete domain assignment even when copies disagree. The parent
independently evaluates its original energy and compares exact rational `F`
values to retain the best incumbent, including under cancellation. Scalar output
energies follow the existing original Float64 evaluation contract. Certified
bounds and gaps are kept separately as exact rational values in normalized
minimization units. No tolerance creates validity or closes a gap.

Every completed iteration is a transaction: all block scans, reconciliation,
original evaluation and certificate work finish before publishing its candidate,
bound and history. Partial iterations preserve earlier valid evidence. Completion,
copy agreement, exact children and even a zero bound gap keep heuristic status;
the independently justified constant-objective route remains `OPTIMAL`.

## Configuration, budgets and results

Use `strategy=:consensus`, `consensus_plan=[[1,2],[2,3]]`, and an ordinary
zero-argument `child_optimizer` factory. The ordered plan is copied on set/get;
indices inside each block are sorted, while block order fixes references and
ownership. There is no whole-model shortcut or child-generated starting solution.
The complete input start (default zeros for Bool, minus ones for Spin) is evaluated
before the strategy runs. Invalid plans are rejected before child dispatch,
including when the objective is constant or its scale is zero.

Multipliers start at Float64 zero. After completed iteration `k`, update every
row by `lambda <- clamp(lambda + consensus_step/sqrt(k) * disagreement,
-consensus_multiplier_limit, consensus_multiplier_limit)` in Float64. Defaults are
`consensus_step=1.0`, `consensus_multiplier_limit=1e6`, and
`consensus_iterations=16`. Every finite stored multiplier is interpreted exactly
in the next surrogate. Nonfinite proposals stop with `NORM_LIMIT` and preserve
previous evidence. Projection, bounded work and approximate directions do not
promise convergence. Copy agreement stops immediately. Otherwise stop after
`consensus_stagnation=4` consecutive completed iterations improving neither the
exact original incumbent nor the best certified bound, or the iteration cap.
These normal completion routes return heuristic `LOCALLY_SOLVED`.

This update is projected dual supergradient ascent; see
[Multiplier update references](@ref). With `L(z,lambda)=sum_p F_p(z_p)+lambda'Az`
and an exact intended-Lagrangian minimizer `z_k`,
`g(mu) <= g(lambda_k) + (Az_k)'(mu-lambda_k)` for every `mu`.
Thus `Az_k` is a supergradient of the concave dual, giving the plus sign in
`lambda_next = projection(lambda_k + alpha_k*Az_k)`. Here each row of `Az_k`
is the non-reference copy minus its reference copy. The schedule
`alpha_k=consensus_step/sqrt(k)` is a standard nonsummable diminishing step size.
The symmetric box projection and its default limit are prototype safeguards;
equality multipliers themselves have no sign restriction. The cited exact
supergradient argument applies to discrete block domains as well, but does not
justify heuristic or rounding-altered directions, primal optimality, or
convergence under this prototype's finite budgets and stopping rules.

All iterations share `max_child_calls`, `max_candidate_evaluations`, the relative
parent time limit and optional absolute deadline. Each scanned block row consumes
one parent candidate evaluation, as does each reconciled original candidate;
the initial original evaluation consumes one. This strategy's counter therefore
includes surrogate evaluations. Exhaustion or interruptions retain only completed
iteration transactions. Child calls remain cooperative with the existing time
limit forwarding; an arbitrary child can overrun. Preparation, exact certificate
work and coordination are charged to parent wall time, and measured in the
`preparation`, `bound`, `coordination`, `copying`, `execution`,
`validation_reconstruction` and `full_energy` phase totals.

`metadata(solution)["decomposition"]["consensus"]` exposes the canonical blocks,
term owners, equality rows, iteration counts, best certified `best_lower_bound`,
`incumbent_normalized`, exact `absolute_gap`, certificate method and bounded
`history`. These rational values are in normalized minimization units; for a
maximization input negate the lower bound to obtain an original-objective upper
bound. A missing certificate is `nothing`, never a heuristic surrogate value.
History records evaluated multipliers, copy solutions, disagreement, original
candidate/energy and whether a genuine supergradient was certified. Retain at
most `consensus_history_limit=16` iterations (oldest discarded); best evidence
survives eviction. Calls identify their dispatched block and public child status.
The three integer consensus options accept 1:10000, and the step and multiplier
limit must be finite positive Float64-representable values.

Only serial execution, default selection, and no partition/separator/pruning
options are supported with this strategy; incompatible combinations fail before
dispatch. Conditional repair, automatic overlapping plans, parallel coordination,
preprocessing integration and source network constraints are deferred. Defaults
and existing strategies retain their behavior.

The executable [offline example](https://github.com/JuliaQUBO/QUBODecomposition.jl/blob/main/examples/consensus/offline.jl)
uses a guarded rational exhaustive child with public `OPTIMAL`, without altering
released ExactSampler's status. Run `julia --project=. examples/consensus/offline.jl`.
The [bounded comparison](https://github.com/JuliaQUBO/QUBODecomposition.jl/blob/main/examples/consensus/README.md)
records candidate quality, certificates, complete timing and total work separately.

## Multiplier update references

1. Stephen Boyd, Lin Xiao, Almir Mutapcic, and Jacob Mattingley,
   [*Notes on Decomposition Methods*](https://web.stanford.edu/class/ee364b/lectures/decomposition_notes.pdf#page=7),
   May 11, 2015, section 2, pp. 7–8. Introduces local copies and equality
   consistency constraints, then updates their multipliers using copy
   disagreement. Its update `nu := nu - alpha_k*(y2-y1)` matches our
   `lambda += alpha_k*(copy-reference)` when `y1=copy` and `y2=reference`.
2. Stephen Boyd, with help from Jaehyun Park,
   [*Subgradient Methods*](https://stanford.edu/class/ee364b/lectures/subgrad_method_notes.pdf),
   May 2014, section 2.2, pp. 4–5, and sections 6–6.2, pp. 21–24. Gives
   `alpha_k=a/sqrt(k)` as a nonsummable diminishing schedule and develops
   projected subgradient methods, including ascent on the Lagrangian dual.
   These are references for the update's components; they do not establish
   convergence of this bounded heuristic implementation.

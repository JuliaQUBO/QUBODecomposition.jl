# Design decision: global guarantees

This package supports two classes of decomposition: **globally exact under stated
assumptions** and **heuristic even with exact subproblem solves**. Classify the
complete search and reconstruction procedure, not the child solver's name or the
algebra used to build a subproblem. The single-flip-gain sweeps introduced in
[PR #19](https://github.com/JuliaQUBO/QUBODecomposition.jl/pull/19) belong to the
heuristic class, as do strongest-edge, BFS, random-block and coupled graph-partition sweeps, and frozen-batch voting/repair.

This decision extends the [accepted package design](https://github.com/JuliaQUBO/QUBO.jl/blob/7c3391f9e4ccf369027da858866f6d4b74790313/docs/src/design.md).
It governs documentation, future strategies and their proof/status rules. The
classification itself does not introduce a capability trait or a new certificate;
each implemented method must satisfy its stated proof obligations. Strongest-edge
selection remains the default.

## What the two classes mean

**Globally exact under stated assumptions:** for every input in the method's
supported problem class, exact solution of every required subproblem, together
with completion of the outer algorithm and valid reconstruction, recovers **at
least one** global optimum of the original logical QUBO/Ising model. It need not
recover a particular optimum when there are ties, enumerate all optima, or fit
within a user's finite time/work allowance. Preconditions and potentially
exponential outer work must be explicit.

**Heuristic even with exact subproblem solves:** exact solution of every subproblem
the method generates does not imply global optimality of the original model.
The method may find an optimum, including on every fixture in a small benchmark,
but has no such general guarantee. Finite sweep coverage, monotone improvement,
exact energy evaluation and exhaustive children do not change this classification.

Keep three claims separate:

| Claim | What it establishes |
| --- | --- |
| Exact representation/restriction | A lifted candidate has the same objective as its reduced representation, including scale, offsets and boundary interactions. |
| Global guarantee of a method | Under documented assumptions and complete execution, at least one original optimum is reachable and the outer algorithm finds it. |
| Global certificate for this invocation | The required proof conditions actually completed and were validated for this input and returned state. |

A fixed-boundary subproblem can have exact representation and an exact child
certificate while the outer method remains heuristic. An exact method interrupted
before completing its proof has no global certificate for that invocation.

A child reporting `INTERRUPTED` can supply independently validated feasible
improvements, but never an exact child certificate. Every normally returned
`INTERRUPTED` child stops the invocation; on whole-model or ordinary serial/component
routes a fully validated strict improvement can be committed first. This does not
complete a separable or global proof. Earlier completed
component/branch certificates remain diagnostic evidence; they cannot certify the
unfinished invocation. Separator branches and frozen voting/repair batches discard
interrupted scratch work rather than promoting it into a completed global commit.

## Why a global guarantee transfers

For analysis let `F=E` for minimization and `F=-E` for maximization, incorporating
the original scale, including its sign. Let `X` be all assignments of the original
free logical variables in their declared domain.

For independent components, there are no cross-component terms and

```math
F(x)=c+\sum_k F_k(x_{C_k}),\qquad
\min_{x\in X}F(x)=c+\sum_k\min_{x_{C_k}}F_k(x_{C_k}).
```

The Cartesian product of component domains covers `X`, so combining exact
component optima gives a global optimum. In the implementation, evaluate the
assembled state against the original objective; do not sum conditioned child
energies that each include the same constant.

For exhaustive conditioning, a branch `b` has a residual domain `Y_b` and a lifting
map `L_b`. Exact objective representation and complete coverage give

```math
F_b(y)=F(L_b(y)),\qquad \bigcup_b L_b(Y_b)=X,\qquad
\min_{x\in X}F(x)=\min_b\min_{y\in Y_b}F_b(y).
```

Thus every required branch must be solved and compared, or safely excluded by a
valid global bound. The opt-in `separator_pruning=true` route supplies the exclusion proof below. Branch-local states may initially
worsen the global incumbent. Strict global improvement may govern completed
candidate acceptance, but must not prune unfinished branches.

A certified reduction may replace full coverage with a proof that its image
contains at least one original optimum. Each reduction must preserve this property
under the accumulated reductions. Exact solution of the final residual then
transfers through valid lifting. An energy-preserving map alone does not prove
that its image contains an optimum. The proposed strict dominance rules preserve
every optimum; future weaker persistency rules must establish compatibility of
jointly applied fixings.

These are mathematical guarantees assuming correct objective transformations and
exact subproblem solutions. The current Float64 implementation validates mappings,
states and original energies and trusts the child's public certificate contract;
it is not a formal exact-arithmetic proof checker. New numerical reduction or
bound certificates must conservatively handle rounding and uncertainty rather
than infer proof from a tolerance or observed agreement.

## Certified separator exclusions

`separator_pruning=true` requires **0.1.3 or later**; see [installation](start.md).

For the stored original normal form, normalize sense and signed scale together:
`F(x) = d * scale * (offset + sum(aᵢ xᵢ) + sum(bᵢⱼ xᵢ xⱼ))`, where
`d=1` for minimization and `d=-1` for maximization. Binary variables use `{0,1}`;
spin variables use `{-1,1}`. Every finite stored Float64 is converted to its exact
`Rational{BigInt}` value, with no decimal approximation or tolerance. This contract
starts at the stored free-variable model: previous modeling, MOI fixed-variable
substitution, encoding and input conversion may already have rounded coefficients.

For a fully assigned separator, substitute those values into the original
coefficients using rational operations. Count the resulting constant once and
aggregate boundary contributions into each remaining linear coefficient. For a
remaining binary term of coefficient `c`, its minimum is `min(0,c)`; for a spin
linear or quadratic term it is `-abs(c)`. Summing these minima relaxes consistency
between terms, so the result `L_b` is a lower bound on every completion of branch
`b`. It may be weak. An empty residual gives the exact branch value. Signed and
zero scale are handled by normalization before taking minima.

A complete valid original-domain incumbent supplies the exact upper bound
`U=F(x*)`. Exclude only if `L_b >= U`, retaining the incumbent on equality.
Every later incumbent replacement must satisfy `F(x_new) < U` in rational
arithmetic, both inside a child transaction and at a completed branch commit.
Thus `U` never increases, and every earlier exclusion remains valid for the
assignment eventually returned. Rounded Float64 energy comparisons cannot
replace the incumbent in this mode. Displayed energies and the energy trace
remain Float64 and can tie or increase under cancellation even as exact `F`
improves. An unavailable bound falls back to ordinary solving, contributes no
exclusion certificate, and is recorded as unavailable. Invalid or nonfinite
original inputs and child evidence retain the existing validation failure rules.

A solved branch still needs a valid public `OPTIMAL` certificate for every
nonconstant residual. The pruning route additionally compares every dispatched
variable-dependent coefficient against the exact original restriction, including
the actual Float64 scale multiplication at dispatch. Rounded coefficients that
change this restriction prevent certificate transfer; direct constant residuals
also require that comparison. A differing additive constant does not change
minimizers. These branches may supply validated incumbents but remain
uncertified. A rounded-model optimum that is worse under the original objective
does not contradict that child certificate: retain the better original working
assignment and keep the branch uncertified. No tolerance repairs a failed comparison.

Global `OPTIMAL` requires `certified_branches + certified_pruned_branches ==
required_branches` and completion before interruption. An uncertified solved
branch stays uncertified even if a later incumbent could theoretically dominate
it; no retrospective proof is attempted. The method is globally exact under
faithful objective transformations and truthful globally optimal children. A
particular invocation certifies only its completed coverage. This does **not**
turn the solver into an exact-arithmetic proof checker: child optimality is
trusted, and upstream floating-point modeling/fixing is outside this certificate.
ExactSampler on QUBODrivers 0.6.5 reports uncertified `LOCALLY_SOLVED`;
[the corrected 0.6.6 public contract](results.md#ExactSampler-version-contract)
can supply child certificates after complete validation. No LP, learned bound,
partial-assignment search or parallel separator search is added.

## Classification of current and planned methods

Classify the route actually taken. For example, `:components_then_sweeps` has an
exact route when every component fits and a heuristic route when it enters coupled
sweeps. A heuristic policy option does not invalidate a whole-model dispatch in
which that policy was never used. Planned rows describe issue contracts, not
features already implemented or certified.

| Method or route | Class | Assumptions / reason |
| --- | --- | --- |
| Empty or constant objective (implemented) | Globally exact | Complete valid assignment and original objective evaluation; no search is required. |
| Whole-model dispatch (implemented) | Globally exact with an exact child | Every free logical variable fits; original domain/objective is retained; child solve and parent validation complete. |
| Independent connected components (implemented) | Globally exact with exact children | Every component fits and is solved exactly; no nonzero cross-component interactions; complete assembly. |
| Strongest-edge and single-flip-gain sweeps ([#11](https://github.com/JuliaQUBO/QUBODecomposition.jl/issues/11), implemented) | Heuristic | Exact conditional optima at incumbent boundaries do not cover all assignments or all useful joint moves. |
| BFS / random blocks ([#12](https://github.com/JuliaQUBO/QUBODecomposition.jl/issues/12), implemented) | Heuristic | Multi-hop traversal and per-sweep variable coverage change the search trajectory, not the global proof. Finite random exploration supplies no guarantee. Whole-model and fitting independent-component routes retain their exact special cases. |
| Graph-partition sweeps ([#13](https://github.com/JuliaQUBO/QUBODecomposition.jl/issues/13), implemented) | Heuristic on coupled blocks | Preserving cut-edge terms by conditioning is algebraically correct but fixes the other blocks. The existing fitting whole-model and independent-component routes retain their certificates. A zero-cut plan alone does not create a new certificate. |
| Exhaustive separator conditioning ([#14](https://github.com/JuliaQUBO/QUBODecomposition.jl/issues/14), automatic articulation selection [#22](https://github.com/JuliaQUBO/QUBODecomposition.jl/issues/22), implemented) | Globally exact with exact residual solves | Every separator assignment is solved and certified or safely excluded; all required residual components fit; complete branches are assembled and compared. Work is exponential in separator size. |
| Frozen-batch voting and conditional repair ([#15](https://github.com/JuliaQUBO/QUBODecomposition.jl/issues/15), implemented) | Heuristic | Neither votes nor exact repair over a restricted disagreement set establish global coverage. |
| Serial Lagrangian consensus ([#39](https://github.com/JuliaQUBO/QUBODecomposition.jl/issues/39), implemented) | Heuristic, with separate certified normalized lower bounds when supported | See the [decomposition and weak-duality contract](consensus.md). Exact children or copy agreement do not certify global completion. |
| [Certified root dominance preprocessing](preprocessing.md) ([#16](https://github.com/JuliaQUBO/QUBODecomposition.jl/issues/16), implemented; 0.1.5 or later) | Guarantee-preserving reduction; globally exact only with an exact residual procedure | Every fixing/export and the actual dispatched child objective must preserve the accepted original polynomial. Full lifting/evaluation and complete residual proof are required. Coupled heuristic sweeps remain heuristic. |
| [Block-orientation coarse proposals](coarse.md) ([#17](https://github.com/JuliaQUBO/QUBODecomposition.jl/issues/17), implemented; 0.1.4 or later) | Heuristic for nonconstant originals | Exact lifting preserves energies only on represented assignments. Current singleton surjections also remain conservatively heuristic; arithmetic-preserving original certificate transfer is not implemented. Original constants retain their direct proof. |
| [Sample-guided variable fixing](sample_fixing.md) ([#18](https://github.com/JuliaQUBO/QUBODecomposition.jl/issues/18), implemented; 0.1.4 or later) | Heuristic for nonconstant originals | Even unanimous samples may fix a variable away from every optimum; exact solution of that restricted residual cannot repair the exclusion. |

An exact preprocessing stage followed by a heuristic search remains heuristic.
Likewise an exact terminal child cannot restore a guarantee lost through an
uncertified fixing or coarse restriction. A heuristic can supply an incumbent to
a separate complete exact algorithm, but any eventual global certificate must
come from that algorithm's proof, not from the heuristic's child statuses.

## Why coupled sweeps are heuristic

A call solves `min F(x_S, x_complement_current)`, then the parent accepts only
strict improvement. Gains rank individual flips; visiting every index does not
enumerate every useful block. Increasing the number of identical stagnant sweeps
does not supply the missing proof.

The [recorded comparison](https://github.com/JuliaQUBO/QUBODecomposition.jl/blob/7b891df244d0317eb9e9b825e21508ecd6cc19ed/examples/selection/README.md)
contains two distinct failure mechanisms with exact children:

- **Selection misses an improving pair.** In the constrained fixture the gain
  policy stops at `[0,1,1,0,0]`, energy 12. Its repeated blocks `{2,3}`, `{1,4}`
  and `{5}` cannot improve that state. Block `{1,3}` would reach `[1,1,0,0,0]`,
  energy 1, but is not selected. Changing index 1 or 3 alone gives energy 40 or
  13, respectively. The result is not even optimal over all two-variable moves.
- **Capacity and strict acceptance prevent escape.** For six bits with
  `E(x)=sum(x)-2sum(x[i]*x[j], i<j)`, a state with `k` ones has energy `2k-k^2`.
  From all zeros, one flip gives 1 and two flips give 0; neither strictly improves.
  Three simultaneous flips give -3 and all six give the global minimum -24.
  Even trying every pair would not escape under the current acceptance rule.
  `test/unit/bfs_random.jl` checks this failure with exact children for both BFS
  and random blocks, as well as truthful heuristic status. Their coverage is not
  assignment-space coverage; caps or incomplete sweeps provide no additional
  proof, and no fallback promotes these policies to an exact method.

Neither example is evidence of incorrect conditioning. Different blocks, larger
blocks or exploration may improve a heuristic's results, but require a separate
argument to claim a global guarantee.

## Certificates, limits and source feasibility

The method class is a conditional design property; `MOI.TerminationStatus()` is
the outcome of one invocation. Keep the existing [result/status contract](results.md):

- `OPTIMAL` currently requires a validated constant evaluation, a completely
  processed whole-model public `OPTIMAL` result, or complete certified independent
  components, or all certified separator branches. ExactSampler 0.6.5's public `LOCALLY_SOLVED`
  cannot be upgraded from metadata; corrected 0.6.6 public `OPTIMAL` is usable only
  after complete validation and the route's required proof work.
- A call's `exact` flag concerns that subproblem. `component_exact` records
  individual component certificates; `separable_proof` is the current global
  component-composition evidence. `separator.proof_complete` separately records
  exhaustive separator proof completion. `separable_proof` is not a universal flag for
  separator/reduction methods, nor is it needed for whole-model/constant proofs.
- Coupled sweep completion/stagnation reports `LOCALLY_SOLVED` as heuristic
  completion, without a certified global bound or a certified local minimum.
  Equality with an independently known benchmark optimum is observed quality,
  not a certificate produced by the decomposition.
- If a cap, timeout, invalid result or missing certificate prevents required
  proof work, retain only the validated incumbent and the appropriate limit/failure
  status. A previously completed valid global proof is distinct from incomplete
  work; preserve the existing precedence rules in [strategies](strategies.md).
  Fallback from an exact method to coupled sweeps must explicitly lose the global
  proof claim. Future methods must record the specific incomplete proof obligations.

The guarantee's target is the original **logical QUBO/Ising model supplied to this
optimizer**. For a ToQUBO-compiled model, recovering an optimum of the source
constrained problem additionally requires a valid encoding, sufficient penalties
and correct decoding. Independently check original constraints and source objective.
A valid binary/spin sample is not necessarily source feasible: the constrained
gain result above violates the source constraint despite every child being exact.

## Requirements for future strategy PRs

Each new method must declare its class and supported exact special cases here,
state the assumptions and completion conditions, and explain whether its maps
cover all original assignments or have a certified optimum-preservation argument.
Document how composition, caps, fallbacks and numerical uncertainty affect proof.
Do not expose an exact/global capability solely from child capabilities.

For an exact method, supply the mathematical argument and independent exhaustive
small-instance tests of the original optimum and full reconstruction, including
both domains/senses, signed scales/offsets and interrupted proof work. Tests support
the implementation; passing fixtures alone is not the mathematical guarantee.
For a heuristic, retain a counterexample with exact children, test truthful status
and complete valid incumbents, and report quality separately from full work/runtime.
Any new certificate representation or public API is part of that method's own
reviewed implementation; this classification does not claim it already exists.

Automatic articulation discovery changes only the selected plan. An articulation
point is a graph property, not an optimality certificate. A supported plan must
still enumerate every required assignment and validate every nonconstant residual
public `OPTIMAL` certificate and complete reconstruction. ExactSampler 0.6.5's
`LOCALLY_SOLVED` remains uncertified; the corrected 0.6.6 contract supplies child
certificates, subject to the same complete coverage and reconstruction checks. Refusal to discover an articulation plan
establishes no claim about other separators or QUBO infeasibility. Separator-plan
validation still precedes constant/zero-scale shortcuts.

The opt-in [component execution interface](components.md) preserves the separable
proof by validating/committing in the coordinator. Every required component must
complete with a fully scanned public `OPTIMAL` result. Completion order, worker
count and internal enumeration supply no additional certificate.


The opt-in [coarse proposal](coarse.md) is heuristic: disjoint groups restrict the
represented assignments to simultaneous whole-group orientations about a frozen
incumbent. Exact children certify that restricted model only. Original constant
objectives retain their direct proof; singleton surjective maps conservatively
remain heuristic because arithmetic-preserving certificate transfer is not implemented.
The exact-child two-variable counterexample in `test/unit/coarse.jl` attains -1
over a group while the independent original optimum is -2.

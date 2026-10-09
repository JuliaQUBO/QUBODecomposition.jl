# Design decision: global guarantees

This package supports two classes of decomposition: **globally exact under stated
assumptions** and **heuristic even with exact subproblem solves**. Classify the
complete search and reconstruction procedure, not the child solver's name or the
algebra used to build a subproblem. The single-flip-gain sweeps introduced in
[PR #19](https://github.com/JuliaQUBO/QUBODecomposition.jl/pull/19) belong to the
heuristic class, as do strongest-edge, BFS and random-block sweeps.

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
valid global bound. A bound-based exclusion needs its own proof; it is not part
of the separator implementation. Branch-local states may initially
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
| Graph-partition sweeps ([#13](https://github.com/JuliaQUBO/QUBODecomposition.jl/issues/13), planned) | Heuristic on coupled blocks | Preserving cut-edge terms by conditioning is algebraically correct but fixes the other blocks. A verified zero-cut independent partition is the component special case. |
| Exhaustive separator conditioning ([#14](https://github.com/JuliaQUBO/QUBODecomposition.jl/issues/14), implemented) | Globally exact with exact residual solves | Every separator assignment is explored; all independent residual components fit and are certified; complete branches are assembled and compared. Work is exponential in separator size. |
| Frozen-batch voting and conditional repair ([#15](https://github.com/JuliaQUBO/QUBODecomposition.jl/issues/15), planned) | Heuristic | Neither votes nor exact repair over a restricted disagreement set establish global coverage. |
| Certified dominance preprocessing ([#16](https://github.com/JuliaQUBO/QUBODecomposition.jl/issues/16), planned) | Guarantee-preserving reduction; globally exact only with an exact residual procedure | Every fixing needs valid bound evidence. A fully fixed residual needs direct evaluation; a residual handled by heuristic sweeps leaves the overall pipeline heuristic. |
| Block-orientation coarse proposals ([#17](https://github.com/JuliaQUBO/QUBODecomposition.jl/issues/17), planned) | Heuristic in general | Exact lifting preserves energies only on represented assignments. Singleton groups covering every variable give a surjective whole-model special case, requiring explicit verification before transferring a certificate. |
| Sample-guided variable fixing ([#18](https://github.com/JuliaQUBO/QUBODecomposition.jl/issues/18), planned) | Heuristic | Even unanimous samples may fix a variable away from every optimum; exact solution of that restricted residual cannot repair the exclusion. |

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
  components, or all certified separator branches. The existing ExactSampler's conservative public `LOCALLY_SOLVED`
  does not become a certificate merely because its internal algorithm enumerates.
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

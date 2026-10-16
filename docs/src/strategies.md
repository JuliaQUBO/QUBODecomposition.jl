# Strategies

The [global-guarantee design decision](guarantees.md) classifies whole-model and
independent-component solving as globally exact with certified exact children.
Coupled neighborhood sweeps under all supported selection policies are heuristic even
when every child is exact. The default strategy can take either route depending
on component sizes; completion of the appropriate proof determines run status.

For an original objective

```math
E(x) = \alpha\left(\beta + \sum_i a_i x_i + \sum_{i<j} b_{ij} x_i x_j\right),
```

the committed complete assignment is evaluated using the original scale
`α`, offset `β`, coefficients and objective sense.

Explicit [component executors](components.md) also plan separate components when
the entire model fits capacity; the old shortcut remains the serial default.

For a larger nonconstant model, adjacency uses public nonzero quadratic terms over every declared
free index, including isolates. Components are ordered by minimum original index. Each fitting
component gets exactly one call; disjoint components are not packed. Thus four nonconstant isolates
with B=2 and call cap 3 produce three singleton calls, a complete partial incumbent and
`ITERATION_LIMIT`, without a separable proof.

`:components` preflights all sizes before dispatch; an oversized component returns `INVALID_OPTION`
with its size and B and retains the initial incumbent. `:whole_model` similarly rejects n>B.
The default `:components_then_sweeps` with `selection=:strongest_edge` processes fitting components once, then sweeps oversized
components in their component order, visiting anchors in ascending index. Each neighborhood contains
the anchor and at most B-1 distinct adjacent indices, ranked by descending absolute interaction
coefficient then ascending index. B=1 selects exactly the anchor. No unrelated variables are added.

Opt into state-aware blocks with `selection=:single_flip_gain`. For each original index,
the signed snapshot coefficients give the actual flip change

```math
\Delta_i = \alpha (x'_i-x_i)\left(a_i+\sum_{j\ne i} b_{ij}x_j\right),
```

where `x′ᵢ=1-xᵢ` for binary variables and `x′ᵢ=-xᵢ` for spins. The offset cancels;
negative scale still affects the result. Rank by descending improvement gain (`-Δᵢ`
for minimization, `+Δᵢ` for maximization), breaking ties by original index. Absolute
graph weights do not supply these signed gains.

For this policy, each oversized component starts a sweep with all its indices unvisited.
Before every block, recompute gains from the latest committed complete incumbent. Select
up to B unvisited indices and remove them only after the child call completes. Include
nonpositive gains to fill the block: a joint move can improve even when no single flip
does. Blocks need not be connected, but stay within one component. Each variable occurs
once per completed sweep, so a component of size n needs `ceil(n/B)` calls, including a
possibly shorter final block. Coverage resets on the next sweep, with no state retained
between optimization invocations. Fitting components and whole-model dispatch are unchanged.

The invocation metadata records `selection`; gain-selected calls record `selected_gains`
aligned with ascending `selected_indices`, evaluated before conditioning at
`conditioning_incumbent_version`. Their `anchor` is `nothing`. Gains are selection scores,
not promises about the child result or certificates. Non-finite computed gains report an
execution failure while retaining the last complete incumbent.

The [bounded selector comparison](https://github.com/JuliaQUBO/QUBODecomposition.jl/blob/main/examples/selection/README.md)
records lower child work but worse source feasibility on its constrained fixture.
The additional policies are opt-in; neither quality nor runtime improvement is guaranteed.

`selection=:bfs` retains the default per-component, per-anchor sweep, but grows
each neighborhood through multiple hops. A FIFO traversal starts at the anchor,
visits each expanded index's neighbors in ascending original-index order and
includes each index only once. It stops at B variables or component exhaustion,
without filling from unrelated components. B=1 selects only the anchor; on a path
an endpoint can select four consecutive variables at B=4, while the default
one-hop control still selects two. Adjacency order is cached once per solve and
the traversal's visited bitmap is reused, resetting only selected entries.
Child metadata canonicalizes the selected set to ascending index order and keeps
the original `anchor`.

`selection=:random_blocks` shuffles each oversized component once per sweep and
partitions that permutation into blocks of at most B variables. The final block
may be shorter. Every component variable occurs exactly once per completed
sweep; blocks need not be connected, but never mix components. Each block uses
the latest committed incumbent when conditioning. A new permutation is drawn on
the next sweep, even if the last sweep made no improvement, until stagnation or
work limits stop the solve. Its `anchor` is `nothing`. See the [seed and replay
contract](budgets.md) for the private solve-local RNG and recorded blocks.

Both policies preserve fitting-component and whole-model dispatch, work limits,
failure handling and strict acceptance. All selector state is rebuilt on every
invocation, including after changed coefficients, topology, labels or starts.
Coverage is a work-accounting property: neither visiting every anchor nor every
variable proves neighborhood optimality, parent global optimality or feasibility
of a constrained source problem. At capacity two, the six-bit exact-child trap in
the [guarantee decision](guarantees.md) also defeats BFS and random blocks.

Each call fixes the complement to the latest committed incumbent with released `fix_variables`,
validates its original-index to reduced-index map, copies the reduced objective to a fresh child,
validates all results, and uses released `lift_state` to reconstruct every original free index.
The conditioned form already includes its offset delta; it is not added again. Independent original
scalar evaluation is the acceptance authority. Only a strictly better complete scan commits a state;
equal energy preserves the incumbent. Constants from conditioned child objectives are never summed.

`component_exact` records only complete valid public OPTIMAL certificates. `separable_proof` becomes
true only after every independent component fits and is certified. Exact neighborhood solves cannot
certify the coupled model. Heuristic completion/stagnation reports `LOCALLY_SOLVED`, without a
certified global bound or a certified local minimum. Valid child early-stop statuses are recorded
and decomposition continues while parent allowances remain, except that a normally
returned `INTERRUPTED` always stops the parent after complete result validation.
Whole-model dispatch preserves valid child statuses.

A default or BFS sweep visits all queued anchors once; a gain or random-block sweep covers each oversized component's
indices once as described above. Interruptions/failures/caps leave it started but incomplete.
`stagnation` counts consecutive complete sweeps with no strict improvements. Parent call/candidate/
sweep caps produce `ITERATION_LIMIT`; a reached parent cap or deadline precedes heuristic completion.
Exactly equaling a parent cap counts as reaching it, including after every heuristic component
is processed or when the last allowed sweep also satisfies stagnation. Those cases return
`ITERATION_LIMIT` and name the reached counter; completed-call/sweep metadata still records the
complete work. A fully assembled separable proof survives a later work check. Failures detected on child return
precede parent limits. Thrown interruptions, failures and scans stopped before
completion discard in-flight results. A normally returned `INTERRUPTED` can commit
a fully validated strict improvement before stopping; see [results and statuses](results.md).
Prior validated calls remain committed. `incumbent_energy_trace` contains the initial
energy and energy after each completed call.
Per-call diagnostics retain the original/reduced/child maps, `fixed_variable_count`,
`boundary_fixed_variables` (only fixed neighbors coupled to the selected set), and
`conditioning_incumbent_version` (the number of strict commits before conditioning).
The full complement exists only during the live fixing/lifting transaction; unrelated fixed
variables are not duplicated into every call log. All graph, plans, maps, counters, incumbent
and proof state rebuild on every invocation.

See [the runnable larger-than-budget example](https://github.com/JuliaQUBO/QUBODecomposition.jl/blob/main/examples/serial_sweeps.jl) for full MOI primal
reconstruction including a fixed variable and truthful coupled heuristic status.

The implementation was written from the accepted contract, without adapting upstream source.
The pinned [QSplit neighborhood reference](https://github.com/alpha-unito/QSplit/blob/4da64b072e702953038addd51cdf54f97f0f9516/qsplit/splitting/split_k_interactions.py)
uses a NumPy negative slice that selects everything for zero neighbors and may select unrelated zero
interactions; this implementation explicitly handles B=1 and adjacency. The pinned
[D-Wave conditioning reference](https://github.com/dwavesystems/dwave-hybrid/blob/ec17a700b0250123da9909ec82db4ecb2516993d/hybrid/utils.py)
sets the induced model offset to zero. Here fixing preserves the offset, and full original energy
is independently recomputed. These are references only; no Python runtime dependency is added.
The pinned [BFS helper](https://github.com/dwavesystems/dwave-hybrid/blob/ec17a700b0250123da9909ec82db4ecb2516993d/hybrid/decomposers.py#L216)
and [random decomposer](https://github.com/dwavesystems/dwave-hybrid/blob/ec17a700b0250123da9909ec82db4ecb2516993d/hybrid/decomposers.py#L397)
were inspected as implementation references. Our random policy uses a complete
permutation and chunking per component/sweep; D-Wave independently selects random
subproblems. It is not a port of that sampling policy. This implementation uses
only the additional Julia `Random` standard library and adapts no upstream code.

## Bounded separator conditioning

Use `strategy=:separator, separator=[i, ...]` to enumerate user-supplied original
**free-variable indices**. These are positions in `decomposition.labels`, not
arbitrary labels or MOI indices before fixed-variable removal. `max_separator_size`
defaults to 8 and cannot exceed 16. The plan rejects invalid or duplicate indices,
cap violations and any component of `G−S` larger than `max_variables` before child
dispatch. There is no pruning or sweep fallback.
The strategy takes precedence over the usual whole-model and constant shortcuts,
so its plan and completion accounting apply even to fitting or constant inputs.
Other strategies retain their existing dispatch and defaults.

Sort separator indices ascending and enumerate integer masks `0:2^length(S)-1`.
The smallest index changes fastest; bit zero means binary 0 or spin -1 and bit one
means 1. The empty separator has one branch. A full separator has no residual
components. Residual components are ordered by minimum original index; isolates
remain explicit. Their topology and expected original/reduced maps are planned
once. Assignments are streamed; the implementation does not store all branches.

Each branch starts from a private copy of the input start with its separator
values overwritten. Evaluate that state, then condition and solve each residual
component using the public fixing, child validation and lifting transaction.
Constant residuals are evaluated directly. Strict improvements within this private
state are independent of the global incumbent: an initially worse separator value
is still explored. Every required residual transaction must finish before the
complete branch is independently evaluated and compared to the global incumbent.
Equal energy keeps the incumbent. Failure, interruption or an incomplete scan
cannot commit the branch, its partial improvements or its proof to another branch.
All branches use the same parent call, candidate and deadline allowances.

The proof is classical exhaustive conditioning, following Dechter's
[conditioning framework](https://ics.uci.edu/~dechter/publications/r76A.pdf)
(Section 10, Figure 30). Every original assignment has exactly one separator value.
Fixing that value removes all edges between distinct residual components, leaving
independent objectives plus a branch constant. Certified residual optima therefore
produce a branch optimum; comparing every certified complete branch yields an
original global optimum. Separator-only terms, boundary interactions, signed
scale, sense and offset enter the original full evaluation. Child energies are
never summed. This is original Julia code, not a literal QSplit port; the
[Ponce et al. paper](https://doi.org/10.1007/s11128-025-04675-z) provides graph
decomposition context rather than this implementation's algorithm or certificate.

This argument assumes correct Float64 transformations and valid public child
certificates, as explained in [global guarantees](guarantees.md). It is not an
exact-arithmetic proof checker. No tolerance-based pruning is used. The guarantee
concerns the logical input; source constraints still require valid encoding,
penalties and decoding. See [results](results.md), [budgets](budgets.md) and the
[bounded comparison](https://github.com/JuliaQUBO/QUBODecomposition.jl/blob/main/examples/separator/README.md).


## Automatic articulation selection

Use `strategy=:separator, separator=:articulation` to discover a supported plan:

1. If all existing components fit `max_variables`, select `Int[]` (one branch),
   even when `max_separator_size=0`.
2. Otherwise consider only genuine articulation vertices: deletion must increase
   the graph's component count. Require **every** residual component in the entire
   model to fit, including components outside the vertex's original component.
3. Minimize the largest residual size, breaking ties by ascending original
   free-variable position. Selecting one vertex requires `max_separator_size>=1`.
4. If no supported plan exists, return `INVALID_OPTION` before child dispatch;
   keep the initial incumbent. This means neither QUBO infeasibility nor that no
   other separator exists. No heuristic fallback is performed.

For a six-vertex path at capacity three, positions 3 and 4 tie and position 3 is
selected. A star at capacity one selects its center. Two oversized disconnected
components cannot be repaired by one deletion. A cycle has no articulation even
when a supplied single-vertex separator leaves a fitting path; use the supplied
vector API for that plan. Isolates and every nonzero interaction, including very
small signed coefficients, participate in topology. Absolute adjacency weights
never replace the original objective coefficients.

The iterative DFS records discovery/low-link indices and subtree sizes. A child
subtree detaches on deletion when its low link cannot reach above its parent;
the remaining parent-side size and the largest untouched component complete the
score. Root articulation requires multiple DFS children. Candidates are scored
without constructing or rescanning `G−v` for each vertex. There is no language-stack
recursion, general minimum-separator search, partitioner or preprocessing dependency.
The selected vector then passes the same cap, index, residual-capacity and map
validation as a supplied plan, and uses the unchanged exhaustive enumeration.

The pinned [Graphs.jl implementation](https://github.com/JuliaGraphs/Graphs.jl/blob/dffc7a640133850569647851b4533a56fc7d40c8/src/biconnectivity/articulation.jl)
and its tests were inspected as references (BSD-2-Clause); this implementation is
independently authored and adapts no upstream code. Independent vertex-deletion
and original-energy oracles provide correctness checks.


## Graph-partition sweeps

Set `selection=:partition, partition_plan=[[1,2,3],[4,5,6],[7]]` or supply a
callback `(indices, adjacency, max_variables) -> blocks`. `indices` is a fresh
vector of **all original free-variable positions**, including isolates: positions
in `decomposition.labels`, after MOI fixed-variable removal, rather than arbitrary
labels or original MOI variable IDs. `adjacency[i]` is a fresh dictionary mapping
neighbor positions to optional absolute weights `abs(scale * coefficient)`.
Mutating these callback inputs cannot change the original objective. Callbacks
own any captured state; setter/getter ownership applies to supplied vectors.

The callback runs once per solve and returns a complete flat vector of nonempty
index vectors. Blocks must be disjoint, cover exactly the declared indices, and
fit `max_variables`. Empty, duplicate, omitted, out-of-range or oversized plans
return `INVALID_OPTION` before child dispatch; callback exceptions return
`OTHER_ERROR`, and interrupts retain existing interruption semantics. There is
no recursive callback/splitting API: an oversized unchanged region is rejected
in one invocation. Adapters doing their own recursive bisection must enforce
strict progress themselves and return a final valid flat plan.

Validation runs before the constant, whole-model and component routes, even when
no sweep will be needed. These existing exact special cases retain their proof
rules; the plan creates no additional certificate. The separator strategy ignores
neighborhood selection and partition plans, retaining its own plan/proof contract.
Fitting independent components
are solved first as usual. When any component is oversized, each complete sweep
visits **every supplied block**, including blocks containing fitting components
or isolates. Sort indices inside each block, then sort blocks by minimum original
index. No block can be empty after validation. The plan is rebuilt and revalidated
every invocation, including after coefficient, topology, label, start, capacity or
option changes; no stale callback output is cached.

Each block uses `child_call!`: condition its entire complement to the latest
committed incumbent, solve in the original domain/sense with signed scale and
offset, validate and lift all results, evaluate against the original full model,
and accept only strict improvement. Cross-block interactions become boundary
linear terms. Do not solve bare principal submatrices or sum the child constants.
Calls share the existing child-call, candidate-evaluation and deadline allowances.
Planning has cooperative checks before/after callback execution and throughout
validation; an arbitrary callback cannot be forcibly interrupted by the optimizer.
A callback that returns after the deadline cannot dispatch a child.

`decomposition.partition` records canonical `blocks`, `block_sizes`, unique
`cut_edges`, `cut_absolute_weight` (sum of `abs(scale * coefficient)` over cuts),
and `planning_sec`. Planning is a measured subset of preparation/selection time;
`phase_sec.conditioning` and each call's conditioning duration record boundary
construction separately. Complete effective time also includes factory/copying,
child execution, validation, reconstruction, original-energy evaluation and output
attachment. Absolute graph weights are selection aids; the signed model remains
the solve objective.

The [region-growing example](https://github.com/JuliaQUBO/QUBODecomposition.jl/blob/main/examples/partition/region_growing.jl)
seeds the smallest unused index and grows a bounded region by greatest total
boundary weight, breaking ties by index and preserving isolates. It is original
Julia code, with no METIS dependency or adapted upstream code. Design inputs were
QSplit's pinned [recursive splitter](https://github.com/alpha-unito/QSplit/blob/279aff6e1b1a499c36120cd0dbd3e85e57f83080/cpp/splitting.cpp#L186),
[METIS multilevel partitioning](https://karypis.github.io/glaros/software/metis/overview.html),
DQAOA's [principal-submatrix proposals/full-energy acceptance](https://github.com/Seongmin-Kim-ornl/DQAOA/blob/9ed1842760fee1f20e2e25c8eabd97c841a51233/DQAOA/DQAOA.py),
and MLQAOA's [coarsening/refinement orchestration](https://github.com/bachbao/MLQAOA/blob/41ba8b8b31185e620254293db9ec9fb3da79b280/maxcut.py).
Partition selection here retains exact boundary conditioning; it does not add
coarsening, a multilevel hierarchy, preprocessing or a global search algorithm.

Coupled partition sweeps remain **heuristic even with exact children**. For six
bits with `E=sum(x)-2sum(x[i]*x[j], i<j)` and blocks `[1,2]`, `[3,4]`, `[5,6]`,
all-zero starts cannot strictly improve with any two-bit conditional optimum:
one flip costs 1, two cost 0. The sweep returns 0 with `LOCALLY_SOLVED`, while
the independent global optimum is -24. The exact-child counterexample and
exhaustive binary/spin, min/max, signed-scale boundary tests are retained in
`test/unit/partition.jl`. Zero observed benchmark gap supplies no certificate.
See the [bounded comparison](https://github.com/JuliaQUBO/QUBODecomposition.jl/blob/main/examples/partition/README.md).


## Frozen-batch voting and disagreement repair

Opt in with `strategy=:frozen_batch, batch_size=8, repair=true`. Fitting whole-model
and independent-component routes run first with their existing proof rules.
Oversized components use the existing `:strongest_edge` or `:bfs` neighborhoods,
in component and anchor index order. Only these two selectors are supported;
other combinations fail before any shortcut or dispatch. Serial remains the default.
Each sweep groups at most `batch_size` consecutive neighborhoods (hard ceiling 64),
including a smaller final batch. Neighborhoods overlap intentionally and each
obeys `max_variables`; disjoint-partition validation does not apply. A batch can
span oversized components, but only votes on selected indices.

Every proposal conditions against one complete frozen incumbent. All returned rows
must pass existing mapping, domain, primal-status and finite-objective validation.
Choose one best full proposal per neighborhood by original-model energy, breaking
proposal energy ties lexicographically in original index order. Each neighborhood
casts one unweighted vote per selected variable, even if its best proposal does
not improve the incumbent. Duplicate rows, row multiplicities, physical reads and
reported child energies do not affect vote weights. The electorate consists of
anchor-driven neighborhood **invocations**, preserving the existing selector
sequence. If two anchors select the same index set, each invocation casts one
vote; no selected-set deduplication occurs. This can change the majority compared
with a unique-set electorate, and repeats cost child work even for deterministic
children. Anchor/component diagnostics make this policy explicit. Strict majority determines
the original bit/spin value; tied and uncovered indices retain the frozen value.

The disagreement set consists of indices with both proposed values, including
majority outcomes as well as ties. With `repair=true`, sort that set by original
index and split it into consecutive blocks of at most `max_variables`. Visit each
block once, condition its full outside complement against the **current scratch
repair state**, and retain only strict scratch improvements. This includes all
boundary interactions, including interactions with other disagreement blocks.
With `repair=false`, evaluate consensus without repair. Empty disagreement makes
no repair call. Repair is bounded coordinate search, not an exhaustive solve of
an oversized disagreement set.

Consensus may initially worsen the objective. Finish all repair blocks before
global acceptance. Compare the frozen incumbent, each selected full individual
proposal, consensus and final repaired consensus using original objective energies.
Commit at most one best strictly improving assignment per batch; retain the
incumbent on energy ties. Ties among improving assignments use lexicographic order.
A failed, malformed, interrupted or unfinished child/batch discards the entire
transaction, retaining any incumbent committed before it. A child's limit status
aborts this route even if it returned valid rows; existing serial handling is
unchanged. No failed neighborhood is dropped from the electorate.

Coupled voting/repair is **heuristic even with exact children and exact repair**.
The existing constant, whole-model and independent-component exact special cases
remain valid; voting itself has no original-problem global certificate or bound.
The six-bit exact-child trap in `test/unit/voting.jl` retains energy 0 while an
independent exhaustive oracle finds -24. Neighborhood and disagreement coverage
are not assignment-space coverage. See [global guarantees](guarantees.md).

The narrow design was informed by QSplit's pinned
[voting](https://github.com/alpha-unito/QSplit/blob/279aff6e1b1a499c36120cd0dbd3e85e57f83080/cpp/aggregation.cpp#L80),
[conditional repair](https://github.com/alpha-unito/QSplit/blob/279aff6e1b1a499c36120cd0dbd3e85e57f83080/cpp/aggregation.cpp#L245)
and [full-objective acceptance](https://github.com/alpha-unito/QSplit/blob/279aff6e1b1a499c36120cd0dbd3e85e57f83080/cpp/refinement.cpp#L240).
This implementation is independently authored; it copies no upstream code. It
uses actual frozen bit/spin boundaries, rather than HADOF's marginal-boundary
proposal model. Parallel execution, weighted voting, preprocessing, coarse moves
and sample-guided fixing remain outside this strategy.


For one coordinated group-orientation proposal, see [coarse proposals](coarse.md).
This route substitutes the complete objective into a frozen affine macro map;
its macrovariable count controls capacity and its nonconstant completion is heuristic.

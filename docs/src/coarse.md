# Block-orientation coarse proposals

Use `strategy=:coarse, coarse_groups=[[1,2],[3,4]]` for one coordinated proposal
from a frozen complete incumbent. Each group defines one macrovariable, so two
groups representing eight original variables need child capacity two. Indices are
positions in `decomposition.labels`, after MOI-fixed variables are removed. Groups
must be nonempty, disjoint, and in range; their count must fit `max_variables`.
They may cover a subset, including isolates. The complement stays frozen. Group
order defines macrovariable order; indices inside groups are sorted. Setters and
getters own copies. An empty original model accepts only an empty plan.

For binary variables, the map is `xᵢ=rᵢ+(1−2rᵢ)y_g(i)` with binary `y`. For spins,
it is `xᵢ=rᵢz_g(i)` with spin `z`. The zero binary or all-plus spin macrostate
reproduces `r`; a macro flip reverses every member of its group. Substitute this
map into the entire original objective, retaining offset, scale and sense, linear
terms, internal interactions, cross-group interactions and interactions with the
fixed complement. Normalize a shared-group square using `y²=y` or `z²=1`.
Consequently `E_coarse(m)=E_original(lift(m))` algebraically. Floating-point
construction can round; independently recomputed original energy decides every
strict improvement. Child-reported objective values are only checked for finiteness.

This opt-in strategy runs even when the whole original model fits capacity.
Planning and validation precede constant/zero-scale shortcuts. It accepts serial
execution and default selection; component executors, partition/consensus plans,
separators, pruning and nondefault selection are rejected. It performs one
proposal per `optimize!`, with no automatic grouping or recursive hierarchy.
All maps, starts, groups and counters rebuild on each invocation.

Every result row must be valid and scanned before a strict improvement commits.
Malformed output, exceptions, incomplete scans or an expired deadline discard
staged candidates. A normally returned `INTERRUPTED` may supply a fully scanned
strict improvement, then stops the parent with `INTERRUPTED`. Other child limit
statuses remain visible. Parent caps and deadlines apply to planning,
construction, copying, child work, lifting and original evaluations; exact final
parent allowances retain their usual `ITERATION_LIMIT` precedence. No allowance
restarts within this route.

The method is heuristic for the original nonconstant problem. A public `OPTIMAL`
child proves only optimality over the represented assignments. Even singleton
groups covering all variables conservatively report `LOCALLY_SOLVED` in this first
implementation: certificate transfer through coefficient arithmetic is not
implemented. Original constant objectives retain the existing direct `OPTIMAL`
proof. No global bound or approximation guarantee is supplied.

`decomposition.coarse` records `macro_groups`, `macro_count`,
`represented_original_count`, `original_to_macro` (zero for uncovered indices),
`frozen_incumbent`, its version and invocation, the affine orientation constants
and coefficients, child status and completion/acceptance. Coarse calls record the
actual macro source-to-child index map. They do not fabricate an
original-to-reduced bijection. Per-call `exact` describes only the child;
`original_proof=false` states the coarse route's conservative certificate boundary.

The [offline example](https://github.com/JuliaQUBO/QUBODecomposition.jl/blob/main/examples/coarse/offline.jl)
uses nonzero linears and a joint two-group improvement missed by separate exact
partition updates. See the [bounded comparison](https://github.com/JuliaQUBO/QUBODecomposition.jl/blob/main/examples/coarse/README.md)
for its finite evaluation scope. This feature does not compose preprocessing,
sample fixing, consensus or voting into a new production pipeline.

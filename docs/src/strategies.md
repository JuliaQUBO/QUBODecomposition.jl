# Strategies

The [global-guarantee design decision](guarantees.md) classifies whole-model and
independent-component solving as globally exact with certified exact children.
Coupled neighborhood sweeps, including `:single_flip_gain`, are heuristic even
when every child is exact. The default strategy can take either route depending
on component sizes; completion of the appropriate proof determines run status.

For an original objective

```math
E(x) = \alpha\left(\beta + \sum_i a_i x_i + \sum_{i<j} b_{ij} x_i x_j\right),
```

the committed complete assignment is evaluated using the original scale
`α`, offset `β`, coefficients and objective sense.

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
The gain policy is opt-in; neither quality nor runtime improvement is guaranteed.

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
and decomposition continues while parent allowances remain. Whole-model dispatch preserves them.

A default sweep visits all queued anchors once; a gain sweep covers each oversized component's
indices once as described above. Interruptions/failures/caps leave it started but incomplete.
`stagnation` counts consecutive complete sweeps with no strict improvements. Parent call/candidate/
sweep caps produce `ITERATION_LIMIT`; a reached parent cap or deadline precedes heuristic completion.
Exactly equaling a parent cap counts as reaching it, including after every heuristic component
is processed or when the last allowed sweep also satisfies stagnation. Those cases return
`ITERATION_LIMIT` and name the reached counter; completed-call/sweep metadata still records the
complete work. A fully assembled separable proof survives a later work check. Failures detected on child return
precede parent limits, and interruption discards in-flight results. Prior validated calls remain
committed. `incumbent_energy_trace` contains the initial energy and energy after each completed call.
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

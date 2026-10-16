# Block-orientation coarse proposals

Run `julia --project=. examples/coarse/offline.jl` from the package checkout.
The binary barrier has scalar objective
`E(x)=sum(x)-2*(x1+x2)*(x3+x4)`. From all zero, a separate original-block change
costs +2 while reversing both groups gives -4. The coarse objective is
`2y1+2y2-8y1*y2`: two macrovariables represent four originals. Nonconstant
original status remains heuristic even when the child is exact.

The [manual](../../docs/src/coarse.md) explains configuration, maps, budgets,
provenance, failure and status contracts. This is an independently authored
Julia-native implementation with no new dependency.

The [bounded comparison report](REPORT.md) recommends adoption as an opt-in
proposal. One coarse move crossed the joint barrier; the two controls matched
ordinary partition sweeps. Timings were mixed, with no general quality/runtime
advantage established. All 18 arms and 36 parent invocations are retained in
[evidence](evidence/20261016/plan.toml): 726 child assignments and 324 scalar audits,
including 144 spent in a failed provenance preflight. There were no measured-arm
retries. The [campaign](compare.jl), [guard](guarded_child.jl) and
[record verifier](summarize.py) preserve the finite shared work/time ceilings.
The producing ExactSampler 0.6.6 is a pinned candidate, not a registration claim.

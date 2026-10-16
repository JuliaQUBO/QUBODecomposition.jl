# Block-orientation coarse proposals

Run `julia --project=. examples/coarse/offline.jl` from the package checkout.
The four-variable barrier has scalar objective
`E(x)=sum(x)-2*(x1+x2)*(x3+x4)` in binary variables. From all zero, a separate
original-block change costs +2 while reversing both groups gives -4. The coarse
objective is `2y1+2y2-8y1*y2`. The child has two macrovariables, and original status
remains heuristic even when the child is exact.

The [manual](../../docs/src/coarse.md) explains maps, shared costs, failure and
status contracts. The implementation is Julia-native and adapts no cited source.

A bounded CPU comparison is being prepared. It will compare three partition
sweeps plus one further partition sweep against the same first phase plus one
coarse proposal, from identical starts with one shared deadline and shared work
allowances per arm. The planned ceiling is three fixtures, one warmup pair and
two measured pairs each: 18 arms / 36 parent invocations, at most 9,216 child
assignments and 512 independent scalar audit assignments. No advantage or
acceptance outcome is claimed before retained measurements are available.

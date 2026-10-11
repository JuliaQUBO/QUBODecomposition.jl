# README rewrite for @bernalde

The reviewer explicitly requested human authorship. These notes are an outline
and factual checks, not replacement README wording. The remaining narrative in
the README predates this PR; removing bookkeeping does not certify its authorship.

## Suggested outline

1. Package name and the real CI, documentation, manual and coverage badges.
2. A short description in your own words of the problem this package solves.
3. Installation for the publication state you verify when writing.
4. The existing optimizer construction example, with both imports installed.
5. One brief explanation of exact solves versus heuristic improvement.
6. Manual link, assistance disclosure, contribution link and license.

## Factual checklist

- [ ] Purpose: a local QUBO/Ising composite optimizer built on QUBODrivers and
  MathOptInterface. The child optimizer is supplied as a factory.
- [ ] Julia minimum is 1.10; runtime uses QUBOTools >=0.16.2 on 0.16 and
  QUBODrivers >=0.6.5 on 0.6, and MathOptInterface 1.
- [ ] The existing construction example imports `QUBODecomposition` and
  `QUBODrivers`, creates an ExactSampler child, and sets `max_variables=8`
  and `seed=123`. Construction alone does not solve a model; link the
  executable whole-model example for a complete solve.
- [ ] An exhaustive eight-variable binary child call examines 256 candidates;
  the parent candidate cap includes its initial evaluation and all calls.
- [ ] Default strategy is `:components_then_sweeps`. Whole-model and fitting
  independent-component solves can transfer valid child certificates;
  exact child calls in coupled sweeps do not prove a global optimum.
  Separator certification requires complete enumeration and certified residuals.
- [ ] At inspection, General #171137 is open; no package tags or releases exist
  and General has no package record. Use a URL install at `main` or a full SHA,
  and install QUBODrivers explicitly for the construction example. Recheck this
  state before substituting an unqualified registry installation command.
- [ ] Manual: https://juliaqubo.github.io/QUBODecomposition.jl/dev/ . CI and
  Documentation badges point at their actual workflows. The Codecov badge
  points at this repository; it does not establish that coverage is available.
- [ ] Describe AI assistance and your review/sign-off responsibility in your
  own words; do not imply this draft PR has already received your review.
- [ ] MPL-2.0 license and CONTRIBUTING.md links resolve locally.

Verify against `Project.toml`, `README.md`, `src/`, `docs/src/guarantees.md`,
`examples/whole_model.jl`, the construction doctest in `docs/src/start.md`,
and the final PR validation record.

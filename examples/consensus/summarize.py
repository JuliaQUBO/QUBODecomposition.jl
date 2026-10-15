# SPDX-License-Identifier: MPL-2.0
"""Audit retained attempts and print paired results without running solvers (Python 3.11+)."""
from pathlib import Path
import statistics
import tomllib

folder = Path(__file__).with_name("evidence")
plan = tomllib.loads((folder / "plan.toml").read_text())
rows = [tomllib.loads(p.read_text()) for p in sorted(folder.glob("attempt-*.toml"))]
assert len(rows) == plan["total_solves"] == 18
assert [r["attempt"] for r in rows] == list(range(1, 19))
assert all(r["outcome"] == "ok" for r in rows)
assert all(r["calls"] <= 64 and r["candidate_evaluations"] <= 2000
           and r["child_assignments"] <= 1024 for r in rows)
assert all(r["certified_lower"] <= r["oracle_optimum"] <= r["energy"]
           for r in rows if r["bound_available"])
print("fixture | energies partition/consensus | consensus bound | calls | child assignments | parent evaluations | paired wall delta C-P (ms)")
for fixture in plan["fixtures"]:
    name = fixture["name"]
    pairs = []
    for repetition in (1, 2):
        pair = [r for r in rows if r["fixture"] == name and r["repetition"] == repetition]
        assert [r["mode"] for r in pair] == ["partition", "consensus"]
        pairs.append(pair)
    a, b = pairs[0]
    for field in ("energy", "calls", "child_assignments", "candidate_evaluations"):
        assert all((x[field], y[field]) == (a[field], b[field]) for x, y in pairs)
    deltas = [(y["wall_sec"] - x["wall_sec"]) * 1000 for x, y in pairs]
    print(f"{name} | {a['energy']:g}/{b['energy']:g} | {b['certified_lower']:g} | "
          f"{a['calls']}/{b['calls']} | {a['child_assignments']}/{b['child_assignments']} | "
          f"{a['candidate_evaluations']}/{b['candidate_evaluations']} | "
          f"{statistics.median(deltas):+.3f} ({', '.join(f'{d:+.3f}' for d in deltas)})")
print(f"All attempts: {sum(r['child_assignments'] for r in rows)} child assignments; "
      f"{sum(r['wall_sec'] for r in rows):.6f} s summed complete solve wall time, including warmups")

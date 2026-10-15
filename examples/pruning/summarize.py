# SPDX-License-Identifier: MPL-2.0
"""Audit retained attempts and aggregate paired measured wall-time differences."""
import pathlib
import statistics
import tomllib

root = pathlib.Path(__file__).parent / "evidence"
plan = tomllib.loads((root / "plan.toml").read_text())
rows = [tomllib.loads(p.read_text()) for p in sorted(root.glob("attempt-*.toml"))]
assert len(rows) == plan["total_solves"] == 18
assert [r["attempt"] for r in rows] == list(range(1, 19))
assert all(r["outcome"] == "ok" for r in rows), "retain and report failures"
assert all(r["calls"] <= 64 and r["candidate_evaluations"] <= 2000 for r in rows)
print("| Fixture | Calls off/on | Wall off/on (ms) | Paired on−off (ms) | Bound on (ms) |")
print("|---|---:|---:|---:|---:|")
for fixture in plan["fixtures"]:
    measured = [r for r in rows if r["fixture"] == fixture["name"] and not r["warmup"]]
    off = sorted((r for r in measured if not r["pruning"]), key=lambda r: r["repetition"])
    on = sorted((r for r in measured if r["pruning"]), key=lambda r: r["repetition"])
    assert len(off) == len(on) == 2
    assert all(a["repetition"] == b["repetition"] for a, b in zip(off, on))
    assert all(a["energy"] == b["energy"] for a, b in zip(off, on))
    assert len({r["calls"] for r in off}) == len({r["calls"] for r in on}) == 1
    median_ms = lambda cohort, key: 1000 * statistics.median(r[key] for r in cohort)
    delta = 1000 * statistics.median(b["wall_sec"] - a["wall_sec"] for a, b in zip(off, on))
    print(f'| {fixture["name"]} | {off[0]["calls"]}/{on[0]["calls"]} | '
          f'{median_ms(off,"wall_sec"):.3f}/{median_ms(on,"wall_sec"):.3f} | '
          f'{delta:+.3f} | {median_ms(on,"bound_sec"):.3f} |')

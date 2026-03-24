"""Dummy binary that depends on all bench targets to produce a complete runfiles tree."""
from bench_deep.deep import deep_result
from bench_heavy.heavy import compute_stats
from bench_wide.wide import summary

print(deep_result())
print(compute_stats([1.0, 2.0, 3.0]))
print(summary())

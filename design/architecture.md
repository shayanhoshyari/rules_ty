# Architecture

How users interact with rules_ty and how it works internally. Covers both UX decisions and implementation details.

## 1. User-Facing Behavior

### 1.1 Always-on by default

Type checking is always enabled. There is no opt-in mode (no `opt_in_tags`). Users who want to skip specific targets can use suppression tags (e.g., `tags = ["no-ty"]`).

Rationale: opt-in mode in rules_mypy was useful for gradual adoption in existing codebases, but adds complexity. For rules_ty, the expectation is that users enable it project-wide. Skipping individual targets via tags covers the escape hatch.

### 1.2 Does not require venvs_site_packages

rules_ty works with any `rules_python` configuration. It does **not** require
`venvs_site_packages=yes`.

The aspect resolves modules via `PyInfo.imports` and `PyInfo.transitive_sources`, which are
populated by `rules_python` regardless of the `venvs_site_packages` setting. The venv
layout is a runtime execution concern; it does not affect the `PyInfo` providers that the
aspect reads at analysis/action time.

**History:** we initially planned to require `venvs_site_packages` and use the venv's
`site-packages/` layout for third-party module discovery. The PoC ([Issue #2](https://github.com/shayanhoshyari/rules_ty/issues/2))
disproved this — the venv symlinks are broken outside the Bazel execution sandbox, and
`py_library` targets don't have runfiles at all. The working approach uses `PyInfo`
providers, which makes `venvs_site_packages` irrelevant to type checking.

### 1.3 Module resolution strategy

The aspect uses **`PyInfo` providers** and **`--extra-search-path`** for both first-party
and third-party deps:

- **Action inputs:** `PyInfo.transitive_sources` + `PyInfo.transitive_pyi_files` from deps
  are passed as action inputs. This makes all source and stub files available in the
  sandbox for ty to resolve imports.
- **Search paths:** `PyInfo.imports` from deps provides path prefixes relative to the
  exec root (e.g., `../rules_python++pip+pip_312_numpy/site-packages` for pip packages).
  These are passed as `--extra-search-path` entries to ty.
- **Scope:** the aspect only checks the target's own `srcs`. Transitive deps are in the
  sandbox for import resolution, not for type checking.

This is the same approach `rules_lint` uses — it collects `PyInfo.imports` from deps and
constructs `--extra-search-path` entries, with transitive sources as action inputs.

**Status:** host-side validation confirmed `--extra-search-path` works for ty
(`examples/poc/validate.sh`). Sandbox validation via a minimal Bazel aspect is in progress
(Phase 3 of the PoC).

## 2. Key Design Decisions

### 2.1 Scaling strategy: accept quadratic, rely on remote cache

Without inter-target caching, running ty across a Bazel build graph is quadratic: each of N targets
re-analyzes its O(M) transitive deps, giving O(N*M) total work. Even at 100x mypy's speed, this
blows up for large monorepos on a clean build.

**Why we can't copy rules_mypy's caching approach:**

rules_mypy propagates a file-based `.mypy_cache/` directory between Bazel actions via the
`MypyCacheInfo` provider. ty has no equivalent — it uses [salsa](https://github.com/salsa-rs/salsa)
for in-memory incremental computation with no `--cache-dir` or persistent file cache to pass
between actions. ty has a TODO for persistent caching but it's not implemented
(`crates/ty_project/src/db.rs`, line 104). Even if implemented, Bazel would need ty to support
merging pre-computed type info across actions, which is a fundamentally different problem.

**Decision: accept quadratic for now, mitigated by Bazel's remote cache.**

The quadratic cost is a cold-start problem, not a per-CI-run problem. Bazel's remote cache
ensures that if a target's transitive inputs haven't changed, the ty action is a cache hit —
ty doesn't run at all. In steady-state CI:
- A typical PR touching a few files: most targets are cache hits. Only targets whose transitive
  inputs changed re-run.
- Worst case (changing a widely-used utility library): all downstream targets re-check. But this
  is bounded by what actually changed and reflects real work that needs re-validation.

This is the same approach [rules_lint](https://blog.aspect.build/rules-lint-2) uses in
production. They acknowledge the quadratic concern and are working with Astral on incremental
support as a future improvement.

**Future improvements (not blocking v1):**
1. **ty persistent caching.** ty has a TODO for salsa database persistence
   (`crates/ty_project/src/db.rs`, line 104). When this lands, investigate whether the
   serialized database can be passed between Bazel actions to avoid redundant analysis of
   transitive deps. Track upstream: https://github.com/astral-sh/ruff
2. **Incremental Bazel support.** Aspect Build is collaborating with Astral on this
   (per [blog.aspect.build/rules-lint-2](https://blog.aspect.build/rules-lint-2)). Unknown
   timeline and form. May overlap with (1).
3. **Generate `.pyi` stubs as action outputs.** Each target outputs stubs; downstream targets
   receive stubs instead of full sources. Gives O(N) total work but ty doesn't have a
   "generate stubs" mode today.

**PoC success criteria (validated — see `plans/issue2-poc.md`):**

*Per-target (< 1 second) — all pass:*
1. ~~**Massive third-party dep** — torch~~ — deferred (large download), expected to pass given (2).
2. **Multiple heavy third-party deps** — pandas + numpy: **0.323s** ✅
3. **Deep first-party chain** — 25 transitive `py_library` deps: **0.131s** ✅
4. **Wide third-party imports** — 7 packages (click, flask, httpx, numpy, pandas, pydantic, requests): **0.166s** ✅
5. **Leaf library (baseline)** — no deps: **0.172s** ✅

*Total build scaling:*
6. **Full graph build** — deferred until the aspect is implemented. Per-target numbers give
   high confidence that individual action times will be acceptable.

### 2.2 No types mapping

rules_mypy requires a `types` dict mapping deps to their stub packages. We drop this and rely on gazelle's `python_generate_pyi_deps` to add stub deps to the dependency graph automatically. ty finds them via `--extra-search-path`.

### 2.3 Python version from toolchain

rules_mypy requires `python_version` as a parameter on `mypy_cli`. We infer it from the Python toolchain (`ctx.toolchains`) and pass `--python-version` to ty automatically.

## 3. Open: Module Resolution in Sandbox

**Status:** partially validated. See §1.3 for strategy.

**Host-side validation (Phase 1–2):** confirmed that ty's `--extra-search-path` resolves
both first-party and third-party imports, and performance is well under 1 second per target.
However, this ran ty from the host against `py_binary` runfiles — not inside a Bazel action
sandbox, and not for `py_library` targets (which have no runfiles).

**Sandbox validation (Phase 3, in progress):** a minimal `.bzl` aspect that runs ty as a
Bazel action using `PyInfo.transitive_sources` as action inputs and `PyInfo.imports` for
`--extra-search-path`. This is the real test — it validates that the file layout in the
action sandbox matches what ty expects.

# Architecture

How users interact with rules_ty and how it works internally. Covers both UX decisions and implementation details.

## 1. User-Facing Behavior

### 1.1 Always-on by default

Type checking is always enabled. There is no opt-in mode (no `opt_in_tags`). Users who want to skip specific targets can use suppression tags (e.g., `tags = ["no-ty"]`).

Rationale: opt-in mode in rules_mypy was useful for gradual adoption in existing codebases, but adds complexity. For rules_ty, the expectation is that users enable it project-wide. Skipping individual targets via tags covers the escape hatch.

### 1.2 Requires venvs_site_packages

rules_ty only supports projects with `--@rules_python//python/config_settings:venvs_site_packages=yes` enabled. This is the modern rules_python mode where each `py_binary` gets a proper `.venv/site-packages/` layout with symlinks.

**Important:** `venvs_site_packages` only affects third-party packages pulled in via pip. First-party `py_library` sources remain in the runfiles tree and are not placed in site-packages.

Rationale for requiring the feature despite only covering third-party:
- **Simplifies the harder problem.** Third-party resolution was the most complex and fragile part of rules_mypy (constructing MYPYPATH for all transitive pip deps). venvs_site_packages eliminates this entirely.
- **Future-looking.** venvs_site_packages is the direction rules_python is heading. Building on the old `sys.path`-based layout would mean supporting a mode that is likely to be superseded.
- **Better third-party compatibility.** Packages like torch, nvidia CUDA libs, and others that assume site-packages layout work correctly with this mode.

### 1.3 Module resolution strategy (validated)

**PoC result ([Issue #2](https://github.com/shayanhoshyari/rules_ty/issues/2)):** the venv
`site-packages/` layout created by `venvs_site_packages` uses symlinks that are only valid
inside the Bazel execution sandbox. Outside the sandbox (in `bazel-bin/`), the symlinks are
broken. This means we **cannot** use `--python` pointing at the venv for third-party
discovery.

Instead, we use **`--extra-search-path` for both first-party and third-party deps**, using
the **runfiles tree** (which has valid symlinks):

- **First-party `py_library` deps:** `--extra-search-path <runfiles>/_main` (or the repo
  name). Sources are symlinked from the workspace into the runfiles tree.
- **Third-party (pip) deps:** `--extra-search-path <runfiles>/<pip_repo>/site-packages` for
  each pip package. The pip packages live under
  `rules_python++pip+pip_<version>_<pkg>/site-packages/` in the runfiles tree.

This is the same approach `rules_lint` uses — it collects `PyInfo.imports` from deps and
constructs `--extra-search-path` entries.

**Validated in `examples/poc/validate.sh`:** all ty checks pass for leaf libraries,
transitive first-party chains, and third-party imports (numpy, requests).

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

## 3. ✅ Resolved: Module Resolution in Sandbox

Validated in PoC ([Issue #2](https://github.com/shayanhoshyari/rules_ty/issues/2)).

**Finding:** the venv created by `venvs_site_packages` has broken symlinks outside the sandbox.
The aspect must use `--extra-search-path` on the **runfiles tree** for both first-party and
third-party resolution. See §1.3 for the validated strategy.

**Key PoC results:**
- First-party `py_library` chain: `--extra-search-path <runfiles>/_main` — works.
- Third-party pip deps: `--extra-search-path <runfiles>/<pip_repo>/site-packages` — works.
- Type errors across transitive first-party deps are correctly detected.
- Per-target ty check time: 50–100ms (well under the 1-second criterion).

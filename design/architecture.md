# Architecture

How users interact with rules_ty and how it works internally. Covers both UX decisions and implementation details.

## 1. User-Facing Behavior

### 1.1 Always-on by default

Type checking is always enabled. There is no opt-in mode (no `opt_in_tags`). Users who want to skip specific targets can use suppression tags (e.g., `tags = ["no-ty"]`).

Rationale: opt-in mode in rules_mypy was useful for gradual adoption in existing codebases, but adds complexity. For rules_ty, the expectation is that users enable it project-wide. Skipping individual targets via tags covers the escape hatch.

### 1.2 Requires venvs_site_packages

rules_ty only supports projects with `--@rules_python//python/config_settings:venvs_site_packages=yes` enabled. This is the modern rules_python mode where each `py_binary` gets a proper `.venv/site-packages/` layout with symlinks.

**Important:** `venvs_site_packages` only affects third-party packages pulled in via pip. First-party `py_library` sources remain in the runfiles tree and are not placed in site-packages. This means module resolution has two paths:
- **Third-party (pip) deps:** ty discovers them via the venv `site-packages/` layout.
- **First-party `py_library` deps:** the aspect must use `--extra-search-path` (or `--python`) to point ty at runfiles directories, similar to how rules_mypy sets `MYPYPATH`.

Rationale for requiring the feature despite only covering third-party:
- **Simplifies the harder problem.** Third-party resolution was the most complex and fragile part of rules_mypy (constructing MYPYPATH for all transitive pip deps). venvs_site_packages eliminates this entirely.
- **Future-looking.** venvs_site_packages is the direction rules_python is heading. Building on the old `sys.path`-based layout would mean supporting a mode that is likely to be superseded.
- **Better third-party compatibility.** Packages like torch, nvidia CUDA libs, and others that assume site-packages layout work correctly with this mode.

The exact mechanism (how the aspect wires up both paths) will be determined during the PoC ([Issue #2](https://github.com/shayanhoshyari/rules_ty/issues/2)).

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

**PoC success criteria:**

The PoC must measure both per-target time AND total build scaling:

*Per-target (< 1 second):*
1. **Massive third-party dep** — `py_library` with 1 source file importing torch.
2. **Multiple heavy third-party deps** — `py_library` importing pandas + numpy.
3. **Deep first-party chain** — `py_library` at the bottom of ~20+ transitive `py_library` deps, each with a few files.
4. **Wide third-party imports** — `py_library` importing 10-15 different third-party packages.
5. **Leaf library (baseline)** — small `py_library` near the top of the chain with few deps.

*Total build scaling:*
6. **Full graph build** — `bazel build ...` on the entire example project. Measure total wall time
   and CPU time. Compare O(N*M) observed growth against target count to quantify how fast it
   degrades.

### 2.2 No types mapping

rules_mypy requires a `types` dict mapping deps to their stub packages. We drop this and rely on gazelle's `python_generate_pyi_deps` to add stub deps to the dependency graph automatically. ty finds them via `--extra-search-path`.

### 2.3 Python version from toolchain

rules_mypy requires `python_version` as a parameter on `mypy_cli`. We infer it from the Python toolchain (`ctx.toolchains`) and pass `--python-version` to ty automatically.

## 3. Open Risk: Module Resolution in Sandbox

ty discovers packages via virtual environments or `python` on PATH. In a Bazel sandbox, neither exists natively. Our strategy uses two complementary mechanisms:

- **Third-party (pip) deps:** `venvs_site_packages` creates a `.venv/site-packages/` layout. ty can discover these via `--python` pointing at the venv, or `VIRTUAL_ENV`.
- **First-party `py_library` deps:** sources live in the runfiles tree. The aspect must pass their paths via `--extra-search-path`, similar to rules_mypy's `MYPYPATH`.

Both paths need PoC validation in [Issue #2](https://github.com/shayanhoshyari/rules_ty/issues/2):
- Can ty use the venv created by `venvs_site_packages` for third-party discovery?
- Does `--extra-search-path` work for first-party modules in the runfiles layout?
- Do stubs (`.pyi`) resolve correctly through both paths?

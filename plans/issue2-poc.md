Proof of concept for feasibility.

Description is in: https://github.com/shayanhoshyari/rules_ty/issues/2

---

## Prior art: rules_lint ty integration

Aspect Build's [rules_lint](https://github.com/aspect-build/rules_lint) already ships a ty
integration (`lint/ty.bzl`). Cloned to `.worktrees/rules_lint/` for reference.

### How it works

- Aspect visits `py_binary`, `py_library`, `py_test` targets.
- For each target, collects `PyInfo.transitive_sources` + `PyInfo.transitive_pyi_files` from deps
  and passes them as action inputs (so ty can resolve imports in the sandbox).
- Extracts `PyInfo.imports` from deps, prefixes with `external/` to form `--extra-search-path`
  entries for third-party (pip) packages.
- Separates stub paths (`_types_`, `_stubs`) from code paths, passing stubs first so they take
  priority (see [astral-sh/ty#1967](https://github.com/astral-sh/ty/issues/1967)).
- Only lints the target's own direct `srcs` — transitive deps are in the sandbox for resolution only.
- Uses `run_shell` with a param file because there can be many `--extra-search-path` entries and
  some pip package directories may not exist (checks with `[ -d ]` before adding).
- Uses `cfg = "exec"` for the ty binary (same as our decision).
- Does NOT use `venvs_site_packages` — uses the old `PyInfo.imports` approach.

### No cache propagation

rules_lint does not propagate caches between targets. Each target re-runs ty from scratch including
re-analyzing all transitive deps.

### Quadratic runtime concern

From [blog.aspect.build/rules-lint-2](https://blog.aspect.build/rules-lint-2):

> Pythonistas will love the new ty linter support. Ty is a fast Python type-checker written in
> Rust from Astral - and we're working with them to add incremental type-check support to avoid
> quadratic runtime. Thank you to https://github.com/whoahbot for the contribution!

This confirms that without caching, `bazel build ...` on a large project has quadratic behavior:
each of N targets re-analyzes its O(M) transitive deps, giving O(N*M) total work.

### Bazel symlink support in ty

ty's file walker now follows symlinks ([astral-sh/ty#922](https://github.com/astral-sh/ty/issues/922),
fixed Aug 2025). This is needed because Bazel's execution sandbox uses a symlink forest.

### ty incremental checking

ty supports file-level incremental checking via `--watch` mode and the LSP server. When a file
changes, ty re-checks only that file and reuses type info from unchanged files
([astral-sh/ty#466](https://github.com/astral-sh/ty/issues/466)). However, this is designed for
IDE use — unclear how it maps to Bazel's action model.

### Aspect Build context

Aspect Build maintains their own variants of several Bazel rulesets:
- [rules_lint](https://github.com/aspect-build/rules_lint) — linter/formatter integration
- [rules_py](https://github.com/aspect-build/rules_py) — Python rules
- [AXL](https://www.aspect.build/axl) — Aspect extension language

They are a Bazel consultancy and build commercial tooling (Aspect Workflows) on top of these.
Their open-source rulesets serve as the foundation.

---

## ty internals: how caching works (and doesn't)

Source: `.worktrees/ty-ruff/` (sparse clone of `astral-sh/ruff`, crates: `ty`, `ty_project`,
`ty_python_semantic`, `ruff_db`).

### salsa framework — in-memory incrementality

ty uses the [salsa](https://github.com/salsa-rs/salsa) framework for incremental computation.
Key queries like `infer_scope_types`, `infer_definition_types`, `infer_expression_types`
(`ty_python_semantic/src/types/infer.rs`) are `#[salsa::tracked]` functions — salsa memoizes
their results and tracks dependencies between them.

When a file changes (via `--watch` or LSP), salsa knows which queries depend on that file and
only re-executes those. This is why ty is fast for IDE use — editing one file doesn't re-check
the world.

### No persistent cache — confirmed

Each `ty check` invocation creates a fresh `ProjectDatabase`. There is no save/load of the salsa
database between runs. The code has an explicit TODO for this:

```
// TODO: Use the `program_settings` to compute the key for the database's persistent
//   cache and load the cache if it exists.
//   we may want to have a dedicated method for this?
```
(`crates/ty_project/src/db.rs`, line 104)

salsa has an optional `persistence` feature (adds serde derives to internal types) but it's not
wired up in ty.

### Why persistent caching alone doesn't solve the Bazel problem

Even if ty adds persistent caching (save/load the salsa DB to disk), it helps across sequential
runs on the *same project* — not across Bazel actions that each run in isolated sandboxes with
different file sets.

For Bazel, you'd need ty to support something like: "here's pre-computed type info for deps A,
B, C — merge it before checking target D." That's fundamentally different from file-level
persistence and doesn't exist in salsa or ty today.

The Aspect/Astral "incremental type-check support" collaboration is likely about exactly this —
but its form, scope, and timeline are unknown.

---

## ✅ Scaling strategy decision

**Decision: accept quadratic, rely on Bazel remote cache.**

The quadratic cost (each target re-analyzes transitive deps) is a cold-start problem. With
Bazel's remote cache, steady-state CI only re-runs ty for targets whose transitive inputs
actually changed. A typical PR touching a few files will see most targets as cache hits.

This is the same approach rules_lint uses in production. Future improvements (ty persistent
caching, stub generation) can be layered on later without changing the aspect's interface.

Captured in `design/architecture.md` §2.1.

---

I want to kick off this project.

Description is in: https://github.com/shayanhoshyari/rules_ty/issues/1

Let's brainstorm together and plan to do this.

---

## ✅ AI native development

Reviewed the AI-native setup from Adobe-Firefly/foundry/experimental/hoshyari/job_ui.
Carried over the good parts (design/ → src/ sync contract, plans as decision logs) and
fixed the issues (AGENTS.md as source of truth instead of CLAUDE.md, split conventions
into a separate doc, keep AGENTS.md compact).

Landed in:
- `AGENTS.md` — project summary, sync contract, directory layout
- `CLAUDE.md` — pointer to AGENTS.md
- `design/conventions.md` — plan lifecycle, folder roles, coding standards

Key decisions:
- Tool-agnostic: AGENTS.md is the real content, CLAUDE.md just points to it.
- No .gitattributes linguist-generated marking — want hands-on code review for this project.
- No runtime context (unlike job_ui, this is a Bazel ruleset, not an MCP server).
- Plans get frozen with a status header after implementation; design/ stays living.

----

## ✅ How to resolve and run ty

### Findings

- ty is a standalone Rust binary (not a Python library). No `py_binary` wrapper needed.
- ty publishes releases on GitHub: https://github.com/astral-sh/ty/releases
- rules_uv uses `rules_multitool` to download uv — same pattern works for ty.

### rules_multitool approach (from rules_uv)

1. `MODULE.bazel`: `bazel_dep(name = "rules_multitool", ...)`, set up `multitool.hub()` with a lockfile.
2. `ty/private/ty.lock.json`: per-platform URLs + SHAs pointing to ty's GitHub releases.
3. Aspect references the binary as `attr.label(default = "@multitool//tools/ty", executable = True, cfg = "exec")`.

The lockfile can be auto-updated via the `multitool` CLI.

### Toolchain approach (rejected)

A full Bazel toolchain (`ty_toolchain_type`, `ty_toolchain`, registration in MODULE.bazel) adds
significant boilerplate for no real benefit. Toolchains are useful when you need per-target tool
version selection — we don't. Every target uses the same ty.

### exec vs target platform (transition_to_target)

rules_uv has a `transition_to_target` hack ([PR #122](https://github.com/bazel-contrib/rules_uv/pull/122))
because its `pip_compile` is a run rule (`executable = True`) — the shell script runs on the local
machine (target platform), but `cfg = "exec"` downloads the binary for the exec platform. This is a
mismatch in cross-compilation / remote execution scenarios.

Not an issue for us: our ty aspect uses `ctx.actions.run()` — a proper build action that runs in
the sandbox on the exec platform. `cfg = "exec"` is correct. No transition needed.

The rules_uv maintainer also noted this is a design smell and suggested converting to build actions
with `write_source_files` to copy output back to the source tree.

### Decision

Use `rules_multitool` with `cfg = "exec"`. No toolchain, no transition hack.

Landed in:
- `design/reference.md` (section on rules_multitool)

----
## ✅ How to update dependency versions

Captured the convention (keep deps current, no fixed cadence yet) and procedures (multitool CLI
for ty binary, manual version bumps for MODULE.bazel, future renovate/dependabot automation).

Landed in:
- `design/conventions.md` (section 6 — dependency updates policy)
- `design/reference.md` (section 4 — update procedures)

----

## ✅ Project structure

Proposed layout based on rules_mypy, simplified for ty:

```
rules_ty/
  MODULE.bazel              # Bazel module definition + bazel_binaries extension for integration tests
  BUILD.bazel               # filegroup "local_repository_files" for integration tests
  .bazelversion             # Pin Bazel 9.x
  .bazelrc                  # Default flags + --deleted_packages for example child workspaces
  REPO.bazel                # ignore_directories() for non-Bazel dirs (plans/, design/, docs/, .worktrees/)

  AGENTS.md / CLAUDE.md / plans/ / design/ / .worktrees/   # (established)

  ty/
    ty.bzl                  # Public API: ty() aspect factory
    BUILD.bazel             # includes filegroup "all_files" for integration tests
    private/
      ty.bzl                # Aspect implementation
      ty.lock.json          # multitool lockfile for ty binary
      BUILD.bazel

  examples/
    BUILD.bazel             # bazel_integration_tests() targets + test_suite
    simple/
      MODULE.bazel          # local_path_override(module_name = "rules_ty", path = "../..")
      BUILD.bazel           # Minimal: one py_library, shows basic usage
    comprehensive/
      MODULE.bazel          # local_path_override(module_name = "rules_ty", path = "../..")
      BUILD.bazel           # Full coverage: cross-deps, third-party, generated files, etc.
      ...                   # Adapted from rules_mypy demo (stripped: types ext, cache, opt-in)

  docs/                     # Sphinx / readthedocs
  .bcr/                     # Bazel Central Registry metadata
  .github/
    workflows/
      ci.yml                # Runs bazel test //examples:all_integration_tests
```

Key simplifications vs rules_mypy:
- No Python runner (ty is a standalone binary, not a Python library)
- No `types.bzl` extension (rely on gazelle's `python_generate_pyi_deps`)
- No WORKSPACE (Bazel 9+ only, bzlmod only)
- No cache propagation (ty is fast enough to not need it)

### Decisions

- [x] **ty resolution:** Use `rules_multitool` (see "How to resolve and run ty" section above).
- [x] **Integration testing:** Use `rules_bazel_integration_test` to test examples against multiple
      Bazel versions. Each example is an independent Bazel module with `local_path_override` pointing
      to the parent. Tests are `bazel test` targets, runnable locally — not just in CI.
- [x] **`examples/` scope:** Two examples: `examples/simple/` (minimal, human-friendly) and
      `examples/comprehensive/` (full coverage, adapted from rules_mypy demo). No opt-in example —
      we're always-on by default (see design/architecture.md section 1.1).
- [x] **CI from the start:** Yes, minimal. Single workflow running
      `bazel test //examples:all_integration_tests`.
- [x] **All checks as `bazel test`:** buildifier format, `--deleted_packages` sync, integration
      tests — all runnable via `bazel test //...`. No manual sanity checks.
- [x] **`tools/` directory:** Not needed. `buildifier` comes from `buildifier_prebuilt` as a
      `bazel_dep`. CI lives in `.github/workflows/`.

### ignore_directories() vs --deleted_packages

Two mechanisms for hiding directories from Bazel, used for different purposes:

| Directory | Mechanism | Why |
|-----------|-----------|-----|
| `plans/`, `design/`, `docs/`, `.worktrees/` | `ignore_directories()` in REPO.bazel | Completely invisible to Bazel |
| `examples/simple/`, `examples/comprehensive/`, etc. | `--deleted_packages` in .bazelrc | Removes child packages from parent, but files remain visible to `glob()` so integration tests can collect them |

`ignore_directories()` makes files completely invisible — `glob()` can't see them.
`--deleted_packages` removes packages but files are still glob-able — required by
`rules_bazel_integration_test` which uses `glob_workspace_files()` from the parent.

The integration test repo provides a tool to auto-populate deleted_packages:
`bazel run @rules_bazel_integration_test//tools:update_deleted_packages`

Landed in:
- `design/reference.md` (sections on ignore_directories, rules_bazel_integration_test)

----

## ✅ Feasibility analysis

ty maps cleanly to the Bazel aspect pattern: `ty check [PATH...]` with `--extra-search-path`
replaces mypy + MYPYPATH, `--python-version` can be inferred from the toolchain, typeshed is
bundled, and ty's speed eliminates the need for cache propagation.

All four issues from the GitHub issue are addressable:
1. Remove `types` mapping → rely on gazelle's `python_generate_pyi_deps`
2. Fix torch performance → ty is 10-100x faster
3. Bazel 9 compat → starting fresh, Bazel 9+ only
4. Remove `python_version` param → infer from Python toolchain

**Key decision:** require `rules_python` `venvs_site_packages=yes`. This mode gives each
`py_binary` a standard `.venv/site-packages/` layout, which ty natively discovers. This
simplifies module resolution (no manual `--extra-search-path` per dep) and is future-looking
(this is the direction rules_python is heading). See `design/architecture.md` §1.2.

**One concrete risk:** module resolution in the Bazel sandbox. Need to verify that ty can
use the venv layout provided by `venvs_site_packages` for first-party, third-party, and
stub packages. This will be validated via a PoC.

**Next step:** [Issue #2](https://github.com/shayanhoshyari/rules_ty/issues/2) — proof-of-concept
to validate ty's module resolution in a Bazel sandbox with venvs_site_packages.

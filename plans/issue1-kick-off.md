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

## Project structure

Proposed layout based on rules_mypy, simplified for ty:

```
rules_ty/
  MODULE.bazel              # Bazel module definition
  BUILD.bazel
  .bazelversion             # Pin Bazel 9.x
  .bazelrc                  # Default flags
  REPO.bazel                # ignore_directories() for non-Bazel dirs (plans/, design/, docs/, .worktrees/, etc.)

  AGENTS.md / CLAUDE.md / plans/ / design/ / .worktrees/   # (established)

  ty/
    ty.bzl                  # Public API: ty() aspect factory
    BUILD.bazel
    private/
      ty.bzl                # Aspect implementation
      BUILD.bazel

  examples/
    basic/
      MODULE.bazel
      BUILD.bazel
      ...

  docs/                     # Sphinx / readthedocs
  .bcr/                     # Bazel Central Registry metadata
```

Key simplifications vs rules_mypy:
- No Python runner (ty is a standalone binary, not a Python library)
- No `types.bzl` extension (rely on gazelle's `python_generate_pyi_deps`)
- No WORKSPACE (Bazel 9+ only, bzlmod only)
- No cache propagation (ty is fast enough to not need it)

### Open questions

- [x] **ty resolution:** Resolved — use `rules_multitool` (see "How to resolve and run ty" section above).
- [ ] **`tools/` directory:** Do we need one for buildifier config, CI scripts, etc.?
- [ ] **`examples/` scope:** Single basic example or multiple (basic, opt-in, custom-config)?
- [ ] **CI from the start:** Set up `.github/workflows/` now or defer?

----

## Other things to discuss one by one

- Is it possible to achieve this in first place.

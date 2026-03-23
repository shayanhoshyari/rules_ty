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

- [ ] **ty toolchain:** How to resolve the ty binary? Options: (a) toolchain that downloads from GitHub releases per platform, (b) user provides it. Needs architecture discussion.
- [ ] **`tools/` directory:** Do we need one for buildifier config, CI scripts, etc.?
- [ ] **`examples/` scope:** Single basic example or multiple (basic, opt-in, custom-config)?
- [ ] **CI from the start:** Set up `.github/workflows/` now or defer?

----

## Other things to discuss one by one

- Is it possible to achieve this in first place.

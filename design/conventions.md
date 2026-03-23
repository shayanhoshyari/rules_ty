# Development Conventions

## 1. Document Structure

`AGENTS.md` is the compact entry point that summarizes the project and points to `design/` files. Documents in `design/` must be **standalone** -- they should not reference back to `AGENTS.md` for their content. If both files need the same information, the full version lives in `design/` and `AGENTS.md` contains a short summary with a pointer.

`design/architecture.md` covers both UX decisions and internal architecture in a single file. The boundary between "how users use it" and "how it works" is blurry for a Bazel ruleset. Split if the file grows unwieldy.

## 2. Folder Roles

| Folder | Role | Mutability |
|--------|------|------------|
| `README.md` | Public landing page: project summary, status, usage (once available) | Updated as milestones land |
| `plans/` | Proposals, ideations, brainstorming | Frozen after implementation |
| `design/` | Living specs — architecture, conventions, reference | Updated as the project evolves |
| `ty/` | Bazel rules source code | Derived from `design/` |
| `examples/` | Example usage of the rules | Updated alongside `ty/` |
| `docs/` | User-facing documentation (Sphinx / readthedocs) | Updated alongside `design/` |
| `.worktrees/` | Cloned external repos for reference and git worktrees of this repo. Gitignored. | Agent-managed, not committed |

## 3. Plan Lifecycle

Plans are the equivalent of RFCs or ADRs (Architecture Decision Records).

### Creating a plan

- One plan per effort, named `plans/issueN-short-description.md`.
- A plan starts as a brainstorm: context, options, open questions.
- The human and agent collaborate on the plan until decisions are made.

### Implementing a plan

1. Update `design/` files with the outcomes from the plan.
2. Update source code to match `design/`.
3. Mark completed items in the plan with checkmarks.

### Freezing a plan

Once fully implemented, add a status header at the top of the plan:

```
Status: Implemented
Landed in: design/architecture.md (section X), design/conventions.md (section Y)
```

A frozen plan is never edited again. If something changes later, that's a new plan that references the old one.

### Why keep frozen plans?

`design/` says *what* the current state is. Plans say *why* we chose it over alternatives. They're the decision log.

## 4. The Sync Contract

This is an **AI-native development** project. `design/` is the source of truth. Source code is derived from it.

**Order of operations for every change:**

1. Identify which `design/` file(s) are affected.
2. Update `design/` first with the new behavior/spec.
3. Then update source code to implement what `design/` now says.
4. If a change is purely internal (refactor, bug fix, no behavior change), code-only changes are OK — but explain why no design change was needed.

## 5. Coding Standards

### Starlark / Bazel

- Target Bazel 9+ only. No WORKSPACE support — bzlmod only.
- Use `aspect()` for the type-checking integration, following the pattern from rules_mypy.
- Private implementation files go in `ty/private/`. Public API in `ty/ty.bzl`.
- Use `buildifier` for formatting.

### Python (tooling, runners)

- Use type hints.
- Format with `ruff`.

### Testing

- All sanity checks must be `bazel test` targets. The agent should be able to run `bazel test //...` and get a pass/fail on everything — no manual steps.
- Integration tests via `rules_bazel_integration_test` on example workspaces.
- Formatting checks (buildifier) as test targets.
- `--deleted_packages` sync check as a test target.

## 6. Dependency Updates

Keep dependencies current. For now there is no fixed cadence — the human decides when to update. As the project matures, this may be automated with renovate or dependabot.

See [design/reference.md](reference.md) (section 4) for the actual update procedures.

## 7. Commit Conventions

- Commit messages should be concise and focus on *why*, not *what*.
- If a commit touches both `design/` and source code, lead with the design change in the message.

## 8. PR Checklist

Before creating a PR, verify all of the following:

### Design ↔ Code sync
- [ ] If source code changed, are the corresponding `design/` files up to date?
- [ ] If `design/` files changed, does the source code match?

### Conventions
- [ ] New conventions are in `design/conventions.md`, not scattered in code comments, commit messages, or other docs.

### Plans
- [ ] Implemented plans have a frozen status header (`Status: Implemented`, `Landed in: ...`).
- [ ] No edits to already-frozen plans. If something changes, create a new plan that references the old one.

### Cross-references
- [ ] All file references in `AGENTS.md` and `design/` files point to files that exist.

### Tests
- [ ] Existing tests still pass.
- [ ] New functionality has test coverage (integration tests or examples).

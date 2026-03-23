# rules_ty — Agent Guide

## 1. Project

Bazel rules for [ty](https://docs.astral.sh/ty/), the fast Python type checker by Astral.
Similar to [rules_mypy](https://github.com/bazel-contrib/rules_mypy) but targeting ty, Bazel 9+, and fixing known pain points.

GitHub: https://github.com/shayanhoshyari/rules_ty

## 2. The Sync Contract

`design/` is the source of truth. Source code is derived from it. Always update `design/` first, then code.

Full details in [design/conventions.md](design/conventions.md) (section 4).

## 3. Directory Layout

```
rules_ty/
  AGENTS.md              ← You are here. Workflow and pointers.
  plans/                 ← Proposals and ideations (frozen after implementation)
  design/
    conventions.md       ← Development conventions, coding standards, plan lifecycle
    architecture.md      ← How the aspect works, module layout, key decisions (TBD)
    reference.md         ← External knowledge: ty CLI, Bazel aspects, rules_mypy lessons (TBD)
  ty/                    ← Bazel rules source code
  examples/              ← Example usage of the rules
  docs/                  ← User-facing documentation (Sphinx / readthedocs)
```

## 4. Before Creating a PR

Follow the PR checklist in [design/conventions.md](design/conventions.md) (section 8).

## 5. Key References

- **Conventions and standards:** [design/conventions.md](design/conventions.md)
- **External knowledge (Bazel, ty, rules_mypy):** [design/reference.md](design/reference.md)

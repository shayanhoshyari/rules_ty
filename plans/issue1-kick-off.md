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

## Other things to discuss one by one

- Is it possible to achieve this in first place.
- Project structure

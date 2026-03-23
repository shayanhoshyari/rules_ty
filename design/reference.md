# External Reference

Knowledge about external tools and APIs that the agent needs during development. This file is the place to capture things the agent doesn't reliably know.

## 1. Bazel 9+

### 1.1 REPO.bazel and ignore_directories()

Use `REPO.bazel` with `ignore_directories()` to exclude non-Bazel directories. This replaces the legacy `.bazelignore` file.

```starlark
# REPO.bazel
ignore_directories(["plans", "design", "docs", ".worktrees"])
```

`ignore_directories()` takes a list of directory paths (relative to repo root) and supports glob patterns. Directories listed here are invisible to the build graph.

Reference: https://bazel.build/rules/lib/globals/repo

### 1.2 No WORKSPACE

Bazel 9+ uses bzlmod exclusively. Do not create `WORKSPACE` or `WORKSPACE.bazel` files. Use `MODULE.bazel` for all dependency management.

## 2. ty

### 2.1 CLI basics

ty is a standalone Rust binary (not a Python library). Key flags for Bazel integration:

```
ty check [PATH...]              # Check specific files
  --extra-search-path PATH      # Additional module resolution path (repeatable)
  --python-version VERSION      # Target Python version (3.7-3.15)
  --python PATH                 # Path to Python environment or interpreter
  --config-file PATH            # Path to ty.toml config
  --output-format FORMAT        # full, concise, github, gitlab, junit
  --project PATH                # Project directory
  --exit-zero                   # Always exit 0 (useful for non-blocking checks)
```

Reference: https://docs.astral.sh/ty/reference/cli/

### 2.2 Module resolution

ty discovers installed packages via:
1. Active virtual environment (`VIRTUAL_ENV`)
2. `.venv` in project root
3. `python3` or `python` on PATH

In a Bazel sandbox, none of these exist. Use `--extra-search-path` to point at the runfiles tree, similar to how rules_mypy sets `MYPYPATH`.

## 3. rules_mypy (prior art)

### 3.1 Architecture

rules_mypy uses a Bazel aspect that:
1. Attaches to `py_binary`, `py_library`, `py_test` targets
2. Skips non-root targets (`target.label.workspace_root != ""`)
3. Collects source files, dependency paths, and upstream caches
4. Runs mypy via a `py_binary` wrapper with `MYPYPATH` set to include all dependency paths
5. Produces a cache directory as output for downstream targets

### 3.2 Key patterns to reuse

- Aspect propagates along `deps` via `attr_aspects = ["deps"]`
- Opt-in/opt-out via tags (`suppression_tags`, `opt_in_tags`)
- External dep paths extracted from `PyInfo.imports`
- Config file passed as a label attribute

### 3.3 Key patterns to drop

- Cache propagation (`MypyCacheInfo`) -- ty is fast enough
- `py_binary` wrapper for the checker -- ty is a standalone binary
- `types` dict mapping deps to stub packages -- rely on gazelle instead
- `python_version` on the CLI macro -- infer from toolchain

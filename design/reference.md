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

### 1.2 ignore_directories() vs --deleted_packages

Two mechanisms for hiding directories from Bazel, used for different purposes:

- **`ignore_directories()`** (REPO.bazel): Makes directories completely invisible to Bazel. `glob()` cannot see files inside, labels cannot reference them. Use for non-Bazel directories.
- **`--deleted_packages`** (.bazelrc): Removes specific packages from the parent's package tree, but files remain visible to `glob()`. Use for child workspaces whose BUILD files would conflict with the parent, but whose files need to be passed to integration tests.

```
# .bazelrc — auto-populated by:
# bazel run @rules_bazel_integration_test//tools:update_deleted_packages
build --deleted_packages=examples/simple,examples/comprehensive
query --deleted_packages=examples/simple,examples/comprehensive
```

### 1.3 No WORKSPACE

Bazel 9+ uses bzlmod exclusively. Do not create `WORKSPACE` or `WORKSPACE.bazel` files. Use `MODULE.bazel` for all dependency management.

## 2. rules_multitool (binary resolution)

We use `rules_multitool` to download the ty binary per platform. This is the same approach rules_uv uses for uv.

### 2.1 Setup pattern (from rules_uv)

In `MODULE.bazel`:
```starlark
bazel_dep(name = "rules_multitool", version = "1.11.1")

multitool = use_extension("@rules_multitool//multitool:extension.bzl", "multitool")
multitool.hub(lockfile = "//ty/private:ty.lock.json")
use_repo(multitool, "multitool")
```

In rule attributes:
```starlark
"_ty": attr.label(default = "@multitool//tools/ty", executable = True, cfg = "exec"),
```

### 2.2 Lockfile format

`ty/private/ty.lock.json` specifies per-platform binary URLs and SHAs:
```json
{
  "$schema": "https://raw.githubusercontent.com/theoremlp/rules_multitool/main/lockfile.schema.json",
  "ty": {
    "binaries": [
      {
        "kind": "archive",
        "url": "https://github.com/astral-sh/ty/releases/download/<version>/ty-<platform>.tar.gz",
        "file": "ty-<platform>/ty",
        "sha256": "<hash>",
        "os": "linux",
        "cpu": "x86_64"
      }
    ]
  }
}
```

The `multitool` CLI can auto-update this lockfile.

### 2.3 Why cfg = "exec" and not transition_to_target

Our aspect runs ty via `ctx.actions.run()` — a build action that executes on the exec platform.
`cfg = "exec"` downloads the correct binary for that platform. No transition hack needed.

This differs from rules_uv's run rules which needed a `transition_to_target` workaround
([PR #122](https://github.com/bazel-contrib/rules_uv/pull/122)).

Reference: https://github.com/theoremlp/rules_multitool

## 3. ty

### 3.1 CLI basics

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

### 3.2 Module resolution

ty discovers installed packages via:
1. Active virtual environment (`VIRTUAL_ENV`)
2. `.venv` in project root
3. `python3` or `python` on PATH

In a Bazel sandbox, none of these exist. Use `--extra-search-path` to point at the runfiles tree, similar to how rules_mypy sets `MYPYPATH`.

## 4. Updating Dependencies

### 4.1 ty binary (multitool lockfile)

Update `ty/private/ty.lock.json` to the latest ty release:

```bash
# Install multitool CLI if not available
cargo install multitool

# Update the lockfile (fetches latest release, updates URLs and SHAs)
multitool --lockfile ty/private/ty.lock.json update
```

Reference: https://github.com/theoremlp/multitool

### 4.2 Bazel module deps (MODULE.bazel)

`bazel_dep()` versions for rules_python, rules_multitool, bazel_skylib, etc. are pinned in `MODULE.bazel`. To update:

1. Check for new versions on the [Bazel Central Registry](https://registry.bazel.build/).
2. Update the version string in the `bazel_dep()` call.
3. Run `bazel build //...` to verify compatibility.

### 4.3 Automation (future)

Once the project matures, set up renovate or dependabot to automate the above. Renovate supports both Bazel MODULE.bazel and custom lockfile patterns.

## 5. rules_bazel_integration_test

We use `rules_bazel_integration_test` to test examples against multiple Bazel versions. Tests are regular `bazel test` targets — runnable locally, not just in CI.

Reference: https://github.com/bazel-contrib/rules_bazel_integration_test

### 5.1 Setup pattern

In `MODULE.bazel`:
```starlark
bazel_dep(name = "rules_bazel_integration_test", version = "0.37.1", dev_dependency = True)

bazel_binaries = use_extension(
    "@rules_bazel_integration_test//:extensions.bzl",
    "bazel_binaries",
    dev_dependency = True,
)
bazel_binaries.download(version_file = "//:.bazelversion")
bazel_binaries.download(version = "9.0.0")
use_repo(bazel_binaries, "bazel_binaries")
```

In `examples/BUILD.bazel`:
```starlark
load("@bazel_binaries//:defs.bzl", "bazel_binaries")
load("@rules_bazel_integration_test//bazel_integration_test:defs.bzl",
     "bazel_integration_tests", "default_test_runner", "integration_test_utils")

default_test_runner(name = "test_runner")

bazel_integration_tests(
    name = "basic_test",
    bazel_binaries = bazel_binaries,
    bazel_versions = bazel_binaries.versions.all,
    test_runner = ":test_runner",
    workspace_files = integration_test_utils.glob_workspace_files("basic") + [
        "//:local_repository_files",
    ],
    workspace_path = "basic",
)
```

### 5.2 Child workspace pattern

Each example has its own `MODULE.bazel` referencing the parent via `local_path_override`:
```starlark
# examples/basic/MODULE.bazel
bazel_dep(name = "rules_ty", version = "0.0.0")
local_path_override(module_name = "rules_ty", path = "../..")
```

### 5.3 Parent workspace filegroup

The root `BUILD.bazel` must expose parent files for child workspaces:
```starlark
filegroup(
    name = "local_repository_files",
    srcs = [
        "BUILD.bazel",
        "MODULE.bazel",
        "//ty:all_files",
        "//ty/private:all_files",
    ],
    visibility = ["//:__subpackages__"],
)
```

Each parent package needs an `all_files` filegroup:
```starlark
filegroup(name = "all_files", srcs = glob(["*"]), visibility = ["//:__subpackages__"])
```

## 6. rules_mypy (prior art)

### 6.1 Architecture

rules_mypy uses a Bazel aspect that:
1. Attaches to `py_binary`, `py_library`, `py_test` targets
2. Skips non-root targets (`target.label.workspace_root != ""`)
3. Collects source files, dependency paths, and upstream caches
4. Runs mypy via a `py_binary` wrapper with `MYPYPATH` set to include all dependency paths
5. Produces a cache directory as output for downstream targets

### 6.2 Key patterns to reuse

- Aspect propagates along `deps` via `attr_aspects = ["deps"]`
- Opt-in/opt-out via tags (`suppression_tags`, `opt_in_tags`)
- External dep paths extracted from `PyInfo.imports`
- Config file passed as a label attribute

### 6.3 Key patterns to drop

- Cache propagation (`MypyCacheInfo`) -- ty is fast enough
- `py_binary` wrapper for the checker -- ty is a standalone binary
- `types` dict mapping deps to stub packages -- rely on gazelle instead
- `python_version` on the CLI macro -- infer from toolchain

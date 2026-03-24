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

### 3.2 Internals: salsa and caching

ty uses the [salsa](https://github.com/salsa-rs/salsa) framework for in-memory incremental
computation. Queries like `infer_scope_types`, `infer_definition_types` are `#[salsa::tracked]`
— salsa memoizes results and only re-executes queries whose inputs changed.

**No persistent cache today.** Each `ty check` invocation starts fresh. The code has a TODO for
persistence (`crates/ty_project/src/db.rs`, line 104) but it's not implemented. salsa has a
`persistence` feature (serde derives) but it's not wired up in ty.

**Bazel symlink support.** ty's file walker follows symlinks since
[astral-sh/ty#922](https://github.com/astral-sh/ty/issues/922) (Aug 2025), which is required
for Bazel's symlink forest execution sandbox.

Source: `.worktrees/ty-ruff/` (sparse clone of `astral-sh/ruff`).

### 3.3 Module resolution

ty discovers installed packages via:
1. Active virtual environment (`VIRTUAL_ENV`)
2. `.venv` in project root
3. `python3` or `python` on PATH
4. `--extra-search-path` for additional module resolution paths
5. `--python` pointing to a Python interpreter or venv

In a Bazel sandbox, (1-3) don't exist. The aspect uses (4) `--extra-search-path` with paths
derived from `PyInfo.imports`. See `design/architecture.md` §1.3.

### 3.3 rules_python venvs_site_packages

**Not required by rules_ty.** Documented here for reference since it was initially
considered and investigated during the PoC.

When enabled, rules_python creates a per-binary `.venv/lib/pythonX.Y/site-packages/` with
symlinks to packages in runfiles. However, the PoC ([Issue #2](https://github.com/shayanhoshyari/rules_ty/issues/2))
found that these symlinks are broken outside the Bazel execution sandbox and `py_library`
targets don't have runfiles at all. The aspect uses `PyInfo.imports` +
`PyInfo.transitive_sources` instead, which work regardless of `venvs_site_packages`.

**Scope limitation:** this feature only affects third-party packages from pip. First-party
`py_library` sources are not placed in site-packages.

**Enabling:**
- Flag: `--@rules_python//python/config_settings:venvs_site_packages=yes`
- Default is `no`. Only affects PyPI dependencies of `--bootstrap_impl=script` binaries.
- Requires `--@rules_python//python/config_settings:bootstrap_impl=script` (which requires rules_python toolchain, i.e. Bazel 7+ with bzlmod).

**Provider API (`PyInfo.venv_symlinks`):**

Added in rules_python 1.5.0. A depset of `VenvSymlinkEntry`, each with:
- `kind`: one of `VenvSymlinkKind.LIB` (site-packages), `VenvSymlinkKind.BIN`, or `VenvSymlinkKind.INCLUDE`
- `venv_path`: path relative to the kind directory in the venv
- `link_to_path`: runfiles-root relative path that `venv_path` symlinks to (if `link_to_file` is None)
- `link_to_file`: a File that `venv_path` should point to (added in 1.7.0)
- `files`: depset of Files under `link_to_path`
- `package`: normalized PyPI package name (added for overlap resolution)
- `version`: PEP 440 normalized version

Per-binary: each `py_binary` gets its own venv. `py_library` targets don't create a venv but carry the provider for downstream binaries.

**Status:** still marked experimental as of rules_python 1.x (API may change). The provider evolved from `site_packages_symlinks` (tuples) to `venv_symlinks` (VenvSymlinkEntry). Known open issues exist (flask compat [#3056], overlapping action outputs [#3204]).

**References:**
- Config setting docs: https://rules-python.readthedocs.io/en/stable/api/rules_python/python/config_settings/index.html
- PyInfo / VenvSymlinkEntry API: https://rules-python.readthedocs.io/en/latest/api/rules_python/python/private/py_info.html
- Tracking issue: https://github.com/bazelbuild/rules_python/issues/2156
- Initial PR: https://github.com/bazelbuild/rules_python/pull/2617
- Known issues: https://github.com/bazel-contrib/rules_python/issues/3056, https://github.com/bazel-contrib/rules_python/issues/3204

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

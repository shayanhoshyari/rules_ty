# Architecture

How users interact with rules_ty and how it works internally. Covers both UX decisions and implementation details.

## 1. User-Facing Behavior

### 1.1 Always-on by default

Type checking is always enabled. There is no opt-in mode (no `opt_in_tags`). Users who want to skip specific targets can use suppression tags (e.g., `tags = ["no-ty"]`).

Rationale: opt-in mode in rules_mypy was useful for gradual adoption in existing codebases, but adds complexity. For rules_ty, the expectation is that users enable it project-wide. Skipping individual targets via tags covers the escape hatch.

### 1.2 Requires venvs_site_packages

rules_ty only supports projects with `--@rules_python//python/config_settings:venvs_site_packages=yes` enabled. This is the modern rules_python mode where each py_binary gets a proper `.venv/site-packages/` layout with symlinks.

Rationale:
- **Simpler module resolution.** ty natively discovers packages in standard venv layouts. Requiring venvs_site_packages means we can leverage this instead of manually constructing search paths from runfiles (the most complex and fragile part of rules_mypy).
- **Future-looking.** venvs_site_packages is the direction rules_python is heading. Building on the old `sys.path`-based layout would mean supporting a mode that is likely to be superseded.
- **Better third-party compatibility.** Packages like torch, nvidia CUDA libs, and others that assume site-packages layout work correctly with this mode.

The exact mechanism (how the aspect uses the venv layout or `PyInfo.venv_symlinks` provider) will be determined during the PoC ([Issue #2](https://github.com/shayanhoshyari/rules_ty/issues/2)).

## 2. Key Design Decisions

### 2.1 No cache propagation (assumption — needs PoC validation)

ty is reported as 10-100x faster than mypy. The working assumption is that this eliminates the need for the `MypyCacheInfo` provider and inter-target cache merging that rules_mypy uses.

However, in Bazel each target runs ty independently. If many targets depend on a large package (e.g., torch), ty would analyze that package once per target. Even at 10x mypy's speed, this could add up. The PoC ([Issue #2](https://github.com/shayanhoshyari/rules_ty/issues/2)) must measure per-target times with large transitive deps to validate this assumption. If it doesn't hold, we may need to revisit caching.

### 2.2 No types mapping

rules_mypy requires a `types` dict mapping deps to their stub packages. We drop this and rely on gazelle's `python_generate_pyi_deps` to add stub deps to the dependency graph automatically. ty finds them via `--extra-search-path`.

### 2.3 Python version from toolchain

rules_mypy requires `python_version` as a parameter on `mypy_cli`. We infer it from the Python toolchain (`ctx.toolchains`) and pass `--python-version` to ty automatically.

## 3. Open Risk: Module Resolution in Sandbox

ty discovers packages via virtual environments or `python` on PATH. In a Bazel sandbox, neither exists. The plan is to use `--extra-search-path` pointing at runfiles directories (same strategy as rules_mypy's `MYPYPATH`).

This needs validation: [Issue #2](https://github.com/shayanhoshyari/rules_ty/issues/2) — proof-of-concept to verify ty's module resolution works with Bazel's runfiles layout for first-party, third-party, and stub packages.

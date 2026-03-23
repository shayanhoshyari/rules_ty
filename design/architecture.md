# Architecture

How users interact with rules_ty and how it works internally. Covers both UX decisions and implementation details.

## 1. User-Facing Behavior

### 1.1 Always-on by default

Type checking is always enabled. There is no opt-in mode (no `opt_in_tags`). Users who want to skip specific targets can use suppression tags (e.g., `tags = ["no-ty"]`).

Rationale: opt-in mode in rules_mypy was useful for gradual adoption in existing codebases, but adds complexity. For rules_ty, the expectation is that users enable it project-wide. Skipping individual targets via tags covers the escape hatch.

### 1.2 Requires venvs_site_packages

rules_ty only supports projects with `--@rules_python//python/config_settings:venvs_site_packages=yes` enabled. This is the modern rules_python mode where each `py_binary` gets a proper `.venv/site-packages/` layout with symlinks.

**Important:** `venvs_site_packages` only affects third-party packages pulled in via pip. First-party `py_library` sources remain in the runfiles tree and are not placed in site-packages. This means module resolution has two paths:
- **Third-party (pip) deps:** ty discovers them via the venv `site-packages/` layout.
- **First-party `py_library` deps:** the aspect must use `--extra-search-path` (or `--python`) to point ty at runfiles directories, similar to how rules_mypy sets `MYPYPATH`.

Rationale for requiring the feature despite only covering third-party:
- **Simplifies the harder problem.** Third-party resolution was the most complex and fragile part of rules_mypy (constructing MYPYPATH for all transitive pip deps). venvs_site_packages eliminates this entirely.
- **Future-looking.** venvs_site_packages is the direction rules_python is heading. Building on the old `sys.path`-based layout would mean supporting a mode that is likely to be superseded.
- **Better third-party compatibility.** Packages like torch, nvidia CUDA libs, and others that assume site-packages layout work correctly with this mode.

The exact mechanism (how the aspect wires up both paths) will be determined during the PoC ([Issue #2](https://github.com/shayanhoshyari/rules_ty/issues/2)).

## 2. Key Design Decisions

### 2.1 No cache propagation (assumption — needs PoC validation)

ty is reported as 10-100x faster than mypy. The working assumption is that this eliminates the need for the `MypyCacheInfo` provider and inter-target cache merging that rules_mypy uses.

However, in Bazel each target runs ty independently. If many targets depend on a large package (e.g., torch), ty would analyze that package once per target. Even at 10x mypy's speed, this could add up.

**Success criterion:** any single `py_library` target must complete `ty check` in under 1 second, regardless of its position in the dependency graph. If it doesn't, we need to revisit caching.

The PoC ([Issue #2](https://github.com/shayanhoshyari/rules_ty/issues/2)) must measure these scenarios:
1. **Massive third-party dep** — `py_library` with 1 source file importing torch.
2. **Multiple heavy third-party deps** — `py_library` importing pandas + numpy.
3. **Deep first-party chain** — `py_library` at the bottom of ~20+ transitive `py_library` deps, each with a few files.
4. **Wide third-party imports** — `py_library` importing 10-15 different third-party packages.
5. **Leaf library (baseline)** — small `py_library` near the top of the chain with few deps. Should be fast; if not, something is fundamentally wrong.

### 2.2 No types mapping

rules_mypy requires a `types` dict mapping deps to their stub packages. We drop this and rely on gazelle's `python_generate_pyi_deps` to add stub deps to the dependency graph automatically. ty finds them via `--extra-search-path`.

### 2.3 Python version from toolchain

rules_mypy requires `python_version` as a parameter on `mypy_cli`. We infer it from the Python toolchain (`ctx.toolchains`) and pass `--python-version` to ty automatically.

## 3. Open Risk: Module Resolution in Sandbox

ty discovers packages via virtual environments or `python` on PATH. In a Bazel sandbox, neither exists natively. Our strategy uses two complementary mechanisms:

- **Third-party (pip) deps:** `venvs_site_packages` creates a `.venv/site-packages/` layout. ty can discover these via `--python` pointing at the venv, or `VIRTUAL_ENV`.
- **First-party `py_library` deps:** sources live in the runfiles tree. The aspect must pass their paths via `--extra-search-path`, similar to rules_mypy's `MYPYPATH`.

Both paths need PoC validation in [Issue #2](https://github.com/shayanhoshyari/rules_ty/issues/2):
- Can ty use the venv created by `venvs_site_packages` for third-party discovery?
- Does `--extra-search-path` work for first-party modules in the runfiles layout?
- Do stubs (`.pyi`) resolve correctly through both paths?

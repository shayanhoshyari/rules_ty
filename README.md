# rules_ty

Bazel rules for [ty](https://docs.astral.sh/ty/), the fast Python type checker by Astral.

Similar to [rules_mypy](https://github.com/bazel-contrib/rules_mypy) but targeting ty, Bazel 9+, and fixing known pain points:

- No `types` mapping — rely on [gazelle](https://rules-python.readthedocs.io/en/latest/gazelle/docs/directives.html#python-generate-pyi-deps) instead
- No per-target cache propagation — ty is fast enough
- No `python_version` parameter — inferred from the Python toolchain
- Requires [`venvs_site_packages`](https://rules-python.readthedocs.io/en/stable/api/rules_python/python/config_settings/index.html) for third-party module resolution

## Status

**Under development — design phase. No usable rules yet.**

- [x] Project kick-off and architectural decisions ([#1](https://github.com/shayanhoshyari/rules_ty/issues/1))
- [ ] PoC: validate ty's module resolution in a Bazel sandbox ([#2](https://github.com/shayanhoshyari/rules_ty/issues/2))
- [ ] Sphinx / readthedocs documentation ([#3](https://github.com/shayanhoshyari/rules_ty/issues/3))

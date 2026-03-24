"""Minimal ty aspect for PoC validation.

Runs ty check as a Bazel action using PyInfo providers for module resolution.
This is a simplified version of what rules_lint does — production rules_ty
will be more robust.
"""

load("@rules_python//python:defs.bzl", "PyInfo")

TyInfo = provider("Output of ty type checking", fields = {"output": "File"})

def _ty_aspect_impl(target, ctx):
    if ctx.rule.kind not in ("py_library", "py_binary", "py_test"):
        return []

    srcs = []
    if hasattr(ctx.rule.attr, "srcs"):
        for src in ctx.rule.attr.srcs:
            for f in src.files.to_list():
                if f.extension == "py":
                    srcs.append(f)

    if not srcs:
        return []

    transitive_sources = []
    import_paths = {}

    if hasattr(ctx.rule.attr, "deps"):
        for dep in ctx.rule.attr.deps:
            if PyInfo in dep:
                transitive_sources.append(dep[PyInfo].transitive_sources)
                for import_path in dep[PyInfo].imports.to_list():
                    if import_path != ctx.workspace_name:
                        import_paths["external/" + import_path] = True

    output = ctx.actions.declare_file(target.label.name + ".ty_check")

    script_lines = ['ARGS=""\n']
    for path in import_paths.keys():
        script_lines.append(
            'if [ -d "{path}" ]; then ARGS="$ARGS --extra-search-path {path}"; fi\n'.format(path = path),
        )

    command = """{extra_search_path_script}
{ty} check --python-version 3.12 $ARGS {srcs} > {output} 2>&1
RET=$?
if [ "$RET" -eq 0 ]; then
    echo "All checks passed!" > {output}
    exit 0
else
    cat {output} >&2
    exit "$RET"
fi
"""

    ctx.actions.run_shell(
        inputs = depset(srcs, transitive = transitive_sources),
        outputs = [output],
        command = command.format(
            ty = ctx.executable._ty.path,
            output = output.path,
            extra_search_path_script = "".join(script_lines),
            srcs = " ".join([f.path for f in srcs]),
        ),
        tools = [ctx.executable._ty],
        mnemonic = "TyCheck",
        progress_message = "Type checking %{label} with ty",
    )

    return [
        TyInfo(output = output),
        OutputGroupInfo(ty_check = depset([output])),
    ]

ty_aspect = aspect(
    implementation = _ty_aspect_impl,
    attr_aspects = ["deps"],
    attrs = {
        "_ty": attr.label(
            default = "@ty_bin//:ty",
            allow_files = True,
            executable = True,
            cfg = "exec",
        ),
    },
)

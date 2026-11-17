"""The `py_wasm_headers` rule: CPython's headers for `wasm32-wasi`."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")

def _host_platform_transition_impl(settings, attr):
    """Build for the host, where the rules_python toolchain of the Python version is."""
    _ = attr  # @unused
    return {"//command_line_option:platforms": [settings["//command_line_option:host_platform"]]}

_host_platform_transition = transition(
    implementation = _host_platform_transition_impl,
    inputs = ["//command_line_option:host_platform"],
    outputs = ["//command_line_option:platforms"],
)

def _py_wasm_headers_impl(ctx):
    # A transitioned attribute holds a list, of one here.
    host_headers = ctx.attr._host_headers
    if type(host_headers) == "list":
        host_headers = host_headers[0]
    compilation_context = host_headers[CcInfo].compilation_context
    roots = compilation_context.includes.to_list() + compilation_context.system_includes.to_list() + compilation_context.quote_includes.to_list()
    roots = sorted(roots, key = len, reverse = True)
    outputs = []
    for header in compilation_context.headers.to_list():
        relative = None
        for root in roots:
            if header.path.startswith(root + "/"):
                relative = header.path[len(root) + 1:]
                break
        if relative == None or relative == "pyconfig.h":
            continue
        output = ctx.actions.declare_file(paths.join(ctx.label.name, relative))
        ctx.actions.symlink(output = output, target_file = header)
        outputs.append(output)
    pyconfig = ctx.actions.declare_file(paths.join(ctx.label.name, "pyconfig.h"))
    ctx.actions.symlink(output = pyconfig, target_file = ctx.file.pyconfig)
    outputs.append(pyconfig)
    include = paths.join(ctx.bin_dir.path, ctx.label.workspace_root, ctx.label.package, ctx.label.name)
    return [
        DefaultInfo(files = depset(outputs)),
        CcInfo(compilation_context = cc_common.create_compilation_context(
            headers = depset(outputs),
            system_includes = depset([include]),
        )),
    ]

py_wasm_headers = rule(
    doc = """\
The headers of the current Python version for `wasm32-wasi`: the rules_python
toolchain's, which are the same on every platform but for `pyconfig.h`, under
one directory with the `pyconfig.h` of the CPython built for wasm32-wasi.

The `py_wasm` extension declares one per Python version as the `headers` of a
`py_cc_toolchain` registered for the `//python/wasm:wasm32_wasi` platform, so
that a `cc_library` built for it compiles its extension module against
`@rules_python//python/cc:current_py_cc_headers` as it would for the host.
""",
    implementation = _py_wasm_headers_impl,
    attrs = {
        "pyconfig": attr.label(
            doc = "The `pyconfig.h` of the CPython built for wasm32-wasi.",
            allow_single_file = True,
            mandatory = True,
        ),
        "_allowlist_function_transition": attr.label(
            default = Label("@bazel_tools//tools/allowlists/function_transition_allowlist"),
        ),
        "_host_headers": attr.label(
            doc = "The rules_python toolchain's headers, resolved for the host.",
            default = Label("@rules_python//python/cc:current_py_cc_headers"),
            cfg = _host_platform_transition,
            providers = [CcInfo],
        ),
    },
    provides = [CcInfo],
)

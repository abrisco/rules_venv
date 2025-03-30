"""Bazel rules for building c extensions."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@rules_cc//cc:cc_binary.bzl", "cc_binary")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//python:defs.bzl", "PyInfo")

def _compilation_mode_transition_impl(settings, attr):
    output = dict(settings)
    if attr.compilation_mode in ["dbg", "fastbuild", "opt"]:
        output["//command_line_option:compilation_mode"] = attr.compilation_mode
    return output

_compilation_mode_transition = transition(
    implementation = _compilation_mode_transition_impl,
    inputs = ["//command_line_option:compilation_mode"],
    outputs = ["//command_line_option:compilation_mode"],
)

def _get_imports(ctx, imports):
    """Determine the import paths from a target's `imports` attribute.

    Args:
        ctx (ctx): The rule's context object.
        imports (list): A list of import paths.

    Returns:
        depset: A set of the resolved import paths.
    """
    workspace_name = ctx.label.workspace_name
    if not workspace_name:
        workspace_name = ctx.workspace_name

    import_root = "{}/{}".format(workspace_name, ctx.label.package).rstrip("/")

    result = [workspace_name]
    for import_str in imports:
        import_str = ctx.expand_make_variables("imports", import_str, {})
        if import_str.startswith("/"):
            continue

        # To prevent "escaping" out of the runfiles tree, we normalize
        # the path and ensure it doesn't have up-level references.
        import_path = paths.normalize("{}/{}".format(import_root, import_str))
        if import_path.startswith("../") or import_path == "..":
            fail("Path '{}' references a path above the execution root".format(
                import_str,
            ))
        result.append(import_path)

    return depset(result)

def _py_cc_extension_library_impl(ctx):
    files = []

    extension = ctx.executable.extension
    is_windows = extension.basename.endswith(".dll")
    is_macos = extension.basename.endswith(".dylib")

    py_toolchain = ctx.toolchains["//python:toolchain_type"]
    py_runtime = py_toolchain.py3_runtime

    pyc_tag = py_runtime.pyc_tag
    if is_windows:
        pyc_tag = "cp{major}{minor}".format(
            major = py_runtime.interpreter_version_info.major,
            minor = py_runtime.interpreter_version_info.minor,
        )

    extension_template = "{module}.{pyc_tag}-{platform}.{ext}"
    ext = ctx.actions.declare_file(extension_template.format(
        module = ctx.label.name,
        pyc_tag = pyc_tag,
        platform = "darwin" if is_macos else ("win_amd64" if is_windows else "linux"),
        ext = "pyd" if is_windows else "so",
    ))

    ctx.actions.symlink(
        output = ext,
        target_file = extension,
    )
    files.append(ext)

    providers = [
        DefaultInfo(
            files = depset([ext]),
            runfiles = ctx.runfiles(
                transitive_files = depset(files),
            ).merge(
                ctx.attr.extension[DefaultInfo].default_runfiles,
            ),
        ),
        PyInfo(
            imports = _get_imports(ctx, ctx.attr.imports),
            transitive_sources = depset(),
        ),
        coverage_common.instrumented_files_info(
            ctx,
            dependency_attributes = ["extension"],
        ),
    ]

    # Forward any aspect-generated outputs
    if OutputGroupInfo in ctx.attr.extension:
        providers.append(ctx.attr.extension[OutputGroupInfo])

    return providers

py_cc_extension_library = rule(
    doc = "Define a Python library for a module extension.",
    implementation = _py_cc_extension_library_impl,
    cfg = _compilation_mode_transition,
    attrs = {
        "compilation_mode": attr.string(
            doc = (
                "Specify the mode `extension` will be built in. For details see " +
                " [`--compilation_mode`](https://bazel.build/reference/command-line-reference#flag--compilation_mode)"
            ),
            values = [
                "dbg",
                "fastbuild",
                "opt",
                "current",
            ],
            default = "opt",
        ),
        "extension": attr.label(
            doc = "The module extension library.",
            cfg = "target",
            providers = [CcInfo],
            executable = True,
            mandatory = True,
        ),
        "imports": attr.string_list(
            doc = "List of import directories to be added to the `PYTHONPATH`.",
        ),
    },
    toolchains = ["//python:toolchain_type"],
)

def py_cc_extension(
        *,
        name,
        srcs,
        conlyopts = [],
        copts = [],
        cxxopts = [],
        data = [],
        defines = [],
        deps = [],
        dynamic_deps = [],
        imports = [],
        includes = [],
        linkopts = [],
        local_defines = None,
        malloc = None,
        compilation_mode = "opt",
        **kwargs):
    """Define a Python C extension module.

    This target is consumed just as a `py_library` would be.

    Args:
        name (str): The name of the target.
        srcs (list): he list of C and C++ files that are processed to create the library target. These
            are C/C++ source and header files, either non-generated (normal source code) or generated.
            For more details see [cc_binary.srcs](https://bazel.build/reference/be/c-cpp#cc_binary.srcs)
        conlyopts (list, optional): Add these options to the C compilation command.
            For more details see [cc_binary.conlyopts](https://bazel.build/reference/be/c-cpp#cc_binary.conlyopts)
        copts (list, optional): Add these options to the C/C++ compilation command.
            For more details see [cc_binary.copts](https://bazel.build/reference/be/c-cpp#cc_binary.copts)
        cxxopts (list, optional): Add these options to the C++ compilation command.
            For more details see [cc_binary.cxxopts](https://bazel.build/reference/be/c-cpp#cc_binary.cxxopts)
        data (list, optional): List of files used by this rule at compile time and runtime.
            For more details see [cc_binary.data](https://bazel.build/reference/be/c-cpp#cc_binary.data)
        defines (list, optional): List of defines to add to the compile line of this and all dependent targets
            For more details see [cc_binary.defines](https://bazel.build/reference/be/c-cpp#cc_binary.defines)
        deps (list, optional): The list of other libraries to be linked in to the binary target.
            For more details see [cc_binary.deps](https://bazel.build/reference/be/c-cpp#cc_binary.deps)
        dynamic_deps (list, optional): These are other cc_shared_library dependencies the current target depends on.
            For more details see [cc_binary.dynamic_deps](https://bazel.build/reference/be/c-cpp#cc_binary.dynamic_deps)
        imports (list, optional): List of import directories to be added to the `PYTHONPATH`.
            For more details see [py_library.imports](https://bazel.build/reference/be/python#py_binary.imports).
        includes (list, optional): List of include dirs to be added to the compile line.
            For more details see [cc_binary.includes](https://bazel.build/reference/be/c-cpp#cc_binary.includes)
        linkopts (list, optional): Add these flags to the C++ linker command.
            For more details see [cc_binary.linkopts](https://bazel.build/reference/be/c-cpp#cc_binary.linkopts)
        local_defines (list, optional): List of defines to add to the compile line.
            For more details see [cc_binary.local_defines](https://bazel.build/reference/be/c-cpp#cc_binary.local_defines)
        malloc (Label, optional): Override the default dependency on malloc.
            For more details see [cc_binary.malloc](https://bazel.build/reference/be/c-cpp#cc_binary.malloc)
        compilation_mode (str, optional): The [compilation_mode](https://bazel.build/reference/command-line-reference#flag--compilation_mode)
            value to build the extension for. If set to `"current"`, the current configuration will be used.
        **kwargs (dict): Additional keyword arguments for common definition attributes.
    """
    tags = kwargs.pop("tags", [])
    visibility = kwargs.pop("visibility", None)

    cc_binary(
        name = name + "_shared",
        conlyopts = conlyopts,
        copts = copts,
        cxxopts = cxxopts,
        data = data,
        defines = defines,
        deps = [
            Label("@rules_python//python/cc:current_py_cc_headers"),
            Label("@rules_python//python/cc:current_py_cc_libs"),
        ] + deps,
        dynamic_deps = dynamic_deps,
        includes = includes,
        linkopts = linkopts,
        linkshared = True,
        local_defines = local_defines,
        malloc = malloc,
        srcs = srcs,
        tags = depset(tags + ["manual"]).to_list(),
        visibility = ["//visibility:private"],
        **kwargs
    )

    py_cc_extension_library(
        name = name,
        extension = name + "_shared",
        compilation_mode = compilation_mode,
        imports = imports,
        tags = tags,
        visibility = visibility,
        **kwargs
    )

"""Bazel rules for building c extensions."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@rules_cc//cc:cc_binary.bzl", "cc_binary")
load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("@rules_cc//cc/common:debug_package_info.bzl", "DebugPackageInfo")
load("//python:py_info.bzl", "PyInfo")

PyCcExtensionInfo = provider(
    doc = "An extension module in C, as `py_wasm_module` links one into a WebAssembly module.",
    fields = {
        "cc_info": "The `CcInfo` of the extension's library and its dependencies.",
        "module": "The name the module is imported by, whose `PyInit_<module>` the library defines.",
    },
)

def _module_name(target_name):
    """The module a `py_cc_extension` defines: the last component of its name, `_ext` for `src/pkg.sub._ext`."""
    return target_name.rsplit("/", 1)[-1].rsplit(".", 1)[-1]

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

def target_platform_has_any_constraint(ctx, constraints):
    """Check if target platform has any of a list of constraints.

    Args:
        ctx: rule context.
        constraints: label_list of constraints.

    Returns:
        True if target platform has at least one of the constraints.
    """
    for constraint in constraints:
        constraint_value = constraint[platform_common.ConstraintValueInfo]
        if ctx.target_platform_has_constraint(constraint_value):
            return True
    return False

def _linux_cpu(ctx):
    if target_platform_has_any_constraint(ctx, [ctx.attr._cpu_aarch64]):
        return "aarch64"

    if target_platform_has_any_constraint(ctx, [ctx.attr._cpu_armv7]):
        return "arm"

    return "x86_64"

def _extension_name(*, name, linux_cpu, linux_abi, extension, py_toolchain):
    is_windows = extension.basename.endswith(".dll")
    is_macos = extension.basename.endswith(".dylib")

    py_runtime = py_toolchain.py3_runtime
    pyc_tag = py_runtime.pyc_tag
    extension = "so"

    if is_windows:
        extension = "pyd"
        platform = "win_amd64"
        pyc_tag = "cp{major}{minor}".format(
            major = py_runtime.interpreter_version_info.major,
            minor = py_runtime.interpreter_version_info.minor,
        )
    elif is_macos:
        platform = "darwin"
    else:
        platform = "{cpu}-linux-{abi}".format(
            cpu = linux_cpu,
            abi = linux_abi,
        ).rstrip("-")

    extension_template = "{module}.{pyc_tag}-{platform}.{ext}"
    extension_name = extension_template.format(
        module = name,
        pyc_tag = pyc_tag,
        platform = platform,
        ext = extension,
    )

    return extension_name

def _py_cc_extension_library_impl(ctx):
    files = []
    extension_info = PyCcExtensionInfo(
        cc_info = ctx.attr.library[CcInfo],
        module = _module_name(ctx.label.name),
    )

    py_toolchain = ctx.toolchains["//python:toolchain_type"]
    if py_toolchain == None:
        # A platform without a Python toolchain, as the one `py_wasm_module`
        # builds its extensions for: the module links the library itself,
        # and no shared object is wanted.
        return [DefaultInfo(), extension_info]

    if ctx.attr.stripped:
        extension = ctx.attr.extension[DebugPackageInfo].stripped_file
    else:
        extension = ctx.executable.extension

    ext = ctx.actions.declare_file(_extension_name(
        linux_cpu = _linux_cpu(ctx),
        linux_abi = ctx.attr.abi,
        name = ctx.label.name,
        extension = extension,
        py_toolchain = py_toolchain,
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
        extension_info,
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
        "abi": attr.string(
            doc = "An optional abi value for the output library name.",
        ),
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
        "library": attr.label(
            doc = "The extension's code as a library, which `extension` links and a `py_wasm_module` links itself.",
            providers = [CcInfo],
            mandatory = True,
        ),
        "stripped": attr.bool(
            doc = "Use the stripped output from `extension`.",
            default = False,
        ),
        "_cpu_aarch64": attr.label(
            default = Label("@platforms//cpu:aarch64"),
        ),
        "_cpu_armv7": attr.label(
            default = Label("@platforms//cpu:armv7"),
        ),
    },
    toolchains = [
        # Absent on the platform a `py_wasm_module` builds its extensions for.
        config_common.toolchain_type("//python:toolchain_type", mandatory = False),
    ],
)

_LINUX_ABI = select({
    Label("@platforms//os:linux"): "gnu",
    "//conditions:default": "",
})

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
        abi = _LINUX_ABI,
        stripped = None,
        **kwargs):
    """Define a Python C extension module.

    This target is consumed just as a `py_library` would be, and by the
    `extensions` of a `py_wasm_module`, which links the same code into its
    WebAssembly module. The module's name is the last component of `name`:
    `_ext` for `src/pkg.sub._ext`, and `PyInit__ext` is its entry point.

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
        abi (str, optional): The ABI value to use for the output library name.
        stripped (bool, optional): Use the stripped output of the c extension for the library.
        **kwargs (dict): Additional keyword arguments for common definition attributes.
    """
    tags = kwargs.pop("tags", [])
    visibility = kwargs.pop("visibility", None)

    # The code, which the shared object links and a `py_wasm_module` links
    # into its module; `alwayslink` keeps `PyInit_*` where nothing refers to it.
    cc_library(
        name = name + "_lib",
        srcs = srcs,
        alwayslink = True,
        conlyopts = conlyopts,
        copts = copts,
        cxxopts = cxxopts,
        defines = defines,
        includes = includes,
        linkstatic = True,
        local_defines = local_defines,
        tags = depset(tags + ["manual"]).to_list(),
        visibility = ["//visibility:private"],
        deps = [Label("@rules_python//python/cc:current_py_cc_headers")] + deps,
        **kwargs
    )

    cc_binary(
        name = name + "_shared",
        data = data,
        deps = [
            ":" + name + "_lib",
            Label("@rules_python//python/cc:current_py_cc_libs"),
        ],
        dynamic_deps = dynamic_deps,
        linkopts = linkopts,
        linkshared = True,
        malloc = malloc,
        tags = depset(tags + ["manual"]).to_list(),
        visibility = ["//visibility:private"],
        **kwargs
    )

    py_cc_extension_library(
        name = name,
        extension = name + "_shared",
        library = name + "_lib",
        abi = abi,
        compilation_mode = compilation_mode,
        imports = imports,
        stripped = stripped,
        tags = tags,
        visibility = visibility,
        **kwargs
    )

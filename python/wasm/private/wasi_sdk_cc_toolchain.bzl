"""A C toolchain for `wasm32-wasi` over a wasi-sdk.

The `py_wasm` extension declares one in each wasi-sdk repository and registers
it for the `//python/wasm:wasm32_wasi` platform, which `py_wasm_module`
transitions its `extensions` to, so that a plain `cc_library` compiles for the
module with the wasi-sdk's clang.
"""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@rules_cc//cc:action_names.bzl", "ACTION_NAMES")
load("@rules_cc//cc:cc_toolchain_config_lib.bzl", "feature", "flag_group", "flag_set", "tool_path", "with_feature_set")
load("@rules_cc//cc:defs.bzl", "cc_toolchain")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/toolchains:cc_toolchain_config_info.bzl", "CcToolchainConfigInfo")

_COMPILE_ACTIONS = [
    ACTION_NAMES.assemble,
    ACTION_NAMES.c_compile,
    ACTION_NAMES.cpp_compile,
    ACTION_NAMES.cpp_header_parsing,
    ACTION_NAMES.cpp_module_compile,
    ACTION_NAMES.linkstamp_compile,
    ACTION_NAMES.preprocess_assemble,
]

_LINK_ACTIONS = [
    ACTION_NAMES.cpp_link_dynamic_library,
    ACTION_NAMES.cpp_link_executable,
    ACTION_NAMES.cpp_link_nodeps_dynamic_library,
]

# The tools Bazel asks for, as the wasi-sdk names them.
_TOOLS = {
    "ar": "llvm-ar",
    "cpp": "clang-cpp",
    "gcc": "clang",
    "ld": "wasm-ld",
    "nm": "llvm-nm",
    "objcopy": "llvm-objcopy",
    "objdump": "llvm-objdump",
    "strip": "llvm-strip",
}

def _repository_relative(ctx, path):
    """`path`, a path under the execroot, relative to the rule's repository."""
    root = ctx.label.workspace_root
    if root and path.startswith(root + "/"):
        return path[len(root) + 1:]
    return path

def _wasi_sdk_cc_toolchain_config_impl(ctx):
    resource_include = None
    for header in ctx.files.resource_headers:
        if header.basename == "stddef.h":
            resource_include = paths.dirname(_repository_relative(ctx, header.path))
    if resource_include == None:
        fail("`resource_headers` of {} has no `stddef.h`; it should be the compiler's `lib/clang/*/include`".format(ctx.label))

    features = [
        feature(
            name = "default_compile_flags",
            enabled = True,
            flag_sets = [
                # Without `-no-canonical-prefixes` the compiler names its own
                # headers by the absolute path of its binary, which the check
                # against `cxx_builtin_include_directories` would reject.
                flag_set(
                    actions = _COMPILE_ACTIONS,
                    flag_groups = [flag_group(flags = ["--target=wasm32-wasi", "-no-canonical-prefixes"])],
                ),
                flag_set(
                    actions = _COMPILE_ACTIONS,
                    flag_groups = [flag_group(flags = ["-O2", "-DNDEBUG"])],
                    with_features = [with_feature_set(features = ["opt"])],
                ),
                flag_set(
                    actions = _COMPILE_ACTIONS,
                    flag_groups = [flag_group(flags = ["-g"])],
                    with_features = [with_feature_set(features = ["dbg"])],
                ),
            ],
        ),
        feature(
            name = "default_link_flags",
            enabled = True,
            flag_sets = [
                flag_set(
                    actions = _LINK_ACTIONS,
                    flag_groups = [flag_group(flags = ["--target=wasm32-wasi", "-no-canonical-prefixes"])],
                ),
            ],
        ),
        feature(name = "dbg"),
        feature(name = "fastbuild"),
        feature(name = "opt"),
    ]
    return cc_common.create_cc_toolchain_config_info(
        ctx = ctx,
        abi_libc_version = "unknown",
        abi_version = "unknown",
        builtin_sysroot = paths.join(ctx.label.workspace_root, ctx.attr.sysroot),
        compiler = "clang",
        cxx_builtin_include_directories = [
            "%crosstool_top%/" + resource_include,
            "%sysroot%/include/wasm32-wasi",
            "%sysroot%/include",
        ],
        features = features,
        host_system_name = "local",
        target_cpu = "wasm32",
        target_libc = "wasi",
        target_system_name = "wasm32-wasi",
        tool_paths = [tool_path(name = name, path = "bin/" + tool + ctx.attr.exe) for name, tool in _TOOLS.items()],
        toolchain_identifier = "wasm32-wasi",
    )

_wasi_sdk_cc_toolchain_config = rule(
    doc = "The configuration of the `wasm32-wasi` toolchain of a wasi-sdk repository.",
    implementation = _wasi_sdk_cc_toolchain_config_impl,
    attrs = {
        "exe": attr.string(
            doc = "The suffix of an executable on the host, `.exe` on Windows.",
        ),
        "resource_headers": attr.label_list(
            doc = "The compiler's own headers, `lib/clang/*/include`, which locate its resource directory.",
            allow_files = True,
            mandatory = True,
        ),
        "sysroot": attr.string(
            doc = "The sysroot, relative to the repository.",
            mandatory = True,
        ),
    },
    provides = [CcToolchainConfigInfo],
)

def wasi_sdk_cc_toolchain(name, exe = ""):
    """Declare the `cc_toolchain` of a wasi-sdk repository, at its root.

    Args:
        name (str): The name of the `cc_toolchain`.
        exe (str): The suffix of an executable on the host, `.exe` on Windows.
    """
    _wasi_sdk_cc_toolchain_config(
        name = name + "_config",
        exe = exe,
        resource_headers = native.glob(["lib/clang/*/include/**"]),
        sysroot = "share/wasi-sysroot",
        tags = ["manual"],
    )

    # The compiler finds its resource directory and sysroot relative to
    # itself, so every action gets the whole tree.
    native.filegroup(
        name = name + "_files",
        srcs = native.glob(["**"]),
    )
    cc_toolchain(
        name = name,
        all_files = ":" + name + "_files",
        ar_files = ":" + name + "_files",
        compiler_files = ":" + name + "_files",
        dwp_files = ":" + name + "_files",
        linker_files = ":" + name + "_files",
        objcopy_files = ":" + name + "_files",
        strip_files = ":" + name + "_files",
        supports_param_files = True,
        tags = ["manual"],
        toolchain_config = ":" + name + "_config",
        toolchain_identifier = "wasm32-wasi",
    )

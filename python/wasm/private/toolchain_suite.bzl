"""The toolchains of the `py_wasm` extension's hub, each with its `toolchain` registration target.

The extension writes a repository whose BUILD file calls `py_wasm_toolchain_suite`
once per supported Python version and host, `wasm32_wasi_cc_toolchain` once per
wasi-sdk and host, and `wasm32_wasi_py_cc_toolchain` once per Python version;
`register_toolchains("@<hub>//:all")` then registers them all, and resolution
picks by host and, through rules_python's `is_python_X.Y`, by the Python
version a module builds for. The C toolchains are registered for the
`//python/wasm:wasm32_wasi` platform, which `py_wasm_module` builds its
`extensions` for.
"""

load("@bazel_skylib//lib:selects.bzl", "selects")
load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("@rules_python//python/cc:py_cc_toolchain.bzl", "py_cc_toolchain")
load("//python/wasm:py_wasm_toolchain.bzl", "py_wasm_toolchain")
load(":py_wasm_headers.bzl", "py_wasm_headers")

_WASM32_WASI = [
    Label("@platforms//cpu:wasm32"),
    Label("@platforms//os:wasi"),
]

_CONSTRAINTS = {
    "linux-aarch64": [
        Label("@platforms//os:linux"),
        Label("@platforms//cpu:aarch64"),
    ],
    "linux-x86_64": [
        Label("@platforms//os:linux"),
        Label("@platforms//cpu:x86_64"),
    ],
    "macos-aarch64": [
        Label("@platforms//os:macos"),
        Label("@platforms//cpu:aarch64"),
    ],
    "macos-x86_64": [
        Label("@platforms//os:macos"),
        Label("@platforms//cpu:x86_64"),
    ],
    "windows-x86_64": [
        Label("@platforms//os:windows"),
        Label("@platforms//cpu:x86_64"),
    ],
}

SUPPORTED_HOSTS = _CONSTRAINTS.keys()

def _is_python(version):
    return Label("@rules_python//python/config_settings:is_python_" + version)

def wasm32_wasi_cc_toolchain(*, name, host, cc_toolchain, python_versions):
    """Register a wasi-sdk's `cc_toolchain` for `wasm32-wasi`, for the Python versions whose CPython it built.

    Args:
        name (str): The name of the `toolchain` target.
        host (str): The host the compiler runs on, one of `SUPPORTED_HOSTS`.
        cc_toolchain (Label): The `cc_toolchain` in the wasi-sdk repository.
        python_versions (list[str]): The `X.Y` versions of CPython the wasi-sdk built.
    """
    if host not in _CONSTRAINTS:
        fail("wasm32_wasi_cc_toolchain {}: unknown host `{}`; one of {}".format(name, host, sorted(_CONSTRAINTS)))
    selects.config_setting_group(
        name = name + "_python_versions",
        match_any = [_is_python(version) for version in python_versions],
    )
    native.toolchain(
        name = name,
        exec_compatible_with = _CONSTRAINTS[host],
        tags = ["manual"],
        target_compatible_with = _WASM32_WASI,
        target_settings = [":" + name + "_python_versions"],
        toolchain = cc_toolchain,
        toolchain_type = Label("@rules_cc//cc:toolchain_type"),
        visibility = ["//visibility:public"],
    )

def wasm32_wasi_py_cc_toolchain(*, name, python_version, pyconfig, libs):
    """Declare the `py_cc_toolchain` of a Python version for `wasm32-wasi` and register it.

    Args:
        name (str): The name of the `toolchain` target; the implementation is `<name>_impl`.
        python_version (str): The `X.Y` of the CPython.
        pyconfig (Label): The `pyconfig.h` of the CPython built for wasm32-wasi.
        libs (list[Label]): Its static libraries, `libpython` and its modules'; may be a `select()`.
    """
    py_wasm_headers(
        name = name + "_headers",
        pyconfig = pyconfig,
        tags = ["manual"],
    )
    cc_library(
        name = name + "_libs",
        srcs = libs,
        tags = ["manual"],
    )
    py_cc_toolchain(
        name = name + "_impl",
        headers = ":" + name + "_headers",
        libs = ":" + name + "_libs",
        python_version = python_version,
        tags = ["manual"],
    )
    native.toolchain(
        name = name,
        tags = ["manual"],
        target_compatible_with = _WASM32_WASI,
        target_settings = [_is_python(python_version)],
        toolchain = ":" + name + "_impl",
        toolchain_type = Label("@rules_python//python/cc:toolchain_type"),
        visibility = ["//visibility:public"],
    )

def py_wasm_toolchain_suite(*, name, python_version, host, clang, compiler_files, cpython_libs, pyconfig, stdlib, wizer, linkopts = None):
    """Declare a `py_wasm_toolchain` and the `toolchain` that registers it.

    Args:
        name (str): The name of the `toolchain` target; the implementation is `<name>_impl`.
        python_version (str): The `X.Y` of the CPython, which the rules_python toolchain must match.
        host (str): The host the compiler runs on, one of `SUPPORTED_HOSTS`.
        clang (Label): See `py_wasm_toolchain`.
        compiler_files (Label): See `py_wasm_toolchain`.
        cpython_libs (Label): See `py_wasm_toolchain`.
        pyconfig (Label): See `py_wasm_toolchain`.
        stdlib (Label): See `py_wasm_toolchain`.
        wizer (Label): See `py_wasm_toolchain`.
        linkopts (list): See `py_wasm_toolchain`; its default when None.
    """
    if host not in _CONSTRAINTS:
        fail("py_wasm_toolchain_suite {}: unknown host `{}`; one of {}".format(name, host, sorted(_CONSTRAINTS)))

    extra = {} if linkopts == None else {"linkopts": linkopts}
    py_wasm_toolchain(
        name = name + "_impl",
        clang = clang,
        compiler_files = compiler_files,
        cpython_libs = cpython_libs,
        pyconfig = pyconfig,
        python_version = python_version,
        stdlib = stdlib,
        # Not reached by `//...`: analyzing it fetches the archives.
        tags = ["manual"],
        wizer = wizer,
        **extra
    )

    native.toolchain(
        name = name,
        exec_compatible_with = _CONSTRAINTS[host],
        tags = ["manual"],
        target_settings = [Label("@rules_python//python/config_settings:is_python_" + python_version)],
        toolchain = ":" + name + "_impl",
        toolchain_type = Label("//python/wasm:toolchain_type"),
        visibility = ["//visibility:public"],
    )

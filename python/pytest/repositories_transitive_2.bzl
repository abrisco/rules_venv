"""Pytest dependencies"""

load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@rules_req_compile//:defs.bzl", "py_requirements_repository")
load("@rules_req_compile//:repositories_transitive.bzl", "req_compile_transitive_dependencies")

# buildifier: disable=unnamed-macro
def rules_pytest_transitive_deps_2():
    """Defines pytest transitive dependencies"""

    req_compile_transitive_dependencies()

    maybe(
        py_requirements_repository,
        name = "pip_deps",
        requirements_locks = {
            Label("//python/pytest:requirements.linux.txt"): "@platforms//os:linux",
            Label("//python/pytest:requirements.macos.txt"): "@platforms//os:macos",
            Label("//python/pytest:requirements.windows.txt"): "@platforms//os:windows",
        },
    )

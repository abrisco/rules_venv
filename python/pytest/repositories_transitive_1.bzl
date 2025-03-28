"""Pytest dependencies"""

load("@rules_python//python:repositories.bzl", "py_repositories")
load("@rules_req_compile//:repositories.bzl", "req_compile_dependencies")

# buildifier: disable=unnamed-macro
def rules_pytest_transitive_deps_1():
    """Defines pytest transitive dependencies"""

    py_repositories()
    req_compile_dependencies()

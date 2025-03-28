"""Pytest dependencies"""

load("@pip_deps//:defs.bzl", pip_repositories = "repositories")

# buildifier: disable=unnamed-macro
def rules_pytest_transitive_deps_3():
    """Defines pytest transitive dependencies"""

    pip_repositories()

"""Pytest dependencies"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")

# buildifier: disable=unnamed-macro
def rules_pytest_dependencies():
    """Defines pytest dependencies"""
    maybe(
        http_archive,
        name = "rules_python",
        sha256 = "778aaeab3e6cfd56d681c89f5c10d7ad6bf8d2f1a72de9de55b23081b2d31618",
        strip_prefix = "rules_python-0.34.0",
        url = "https://github.com/bazelbuild/rules_python/releases/download/0.34.0/rules_python-0.34.0.tar.gz",
    )

    maybe(
        http_archive,
        name = "rules_venv",
        integrity = "sha256-b5xOZLqWC9YIs5oFIyGwj6brEGdUEw6fiTiyEa9EO2k=",
        urls = ["https://github.com/periareon/rules_venv/releases/download/0.0.8/rules_venv-0.0.8.tar.gz"],
    )

    maybe(
        http_archive,
        name = "rules_req_compile",
        sha256 = "24e937f7e8a06b3c7072083c3a94a4e2ff3e7d2bf30fbb4fb723809ce82f5d58",
        urls = ["https://github.com/periareon/req-compile/releases/download/1.0.0rc32/rules_req_compile-1.0.0rc32.tar.gz"],
    )

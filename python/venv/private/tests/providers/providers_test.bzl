"""Unittests verifying `py_venv_*` rules return the same providers as `rules_python` rules."""

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load("//python:py_cc_link_params_info.bzl", "PyCcLinkParamsInfo")
load("//python:py_executable_info.bzl", "PyExecutableInfo")
load("//python:py_info.bzl", "PyInfo")
load("//python:py_runtime_info.bzl", "PyRuntimeInfo")
load("//python/venv:defs.bzl", "py_venv_binary", "py_venv_library", "py_venv_test")

def _linking_dep_impl(ctx):
    linker_input = cc_common.create_linker_input(
        owner = ctx.label,
        user_link_flags = ["-l{}".format(ctx.label.name)],
    )
    cc_info = CcInfo(linking_context = cc_common.create_linking_context(
        linker_inputs = depset([linker_input]),
    ))

    providers = [PyInfo(transitive_sources = depset())]
    if ctx.attr.wrapped:
        providers.append(PyCcLinkParamsInfo(cc_info = cc_info))
    else:
        providers.append(cc_info)

    return providers

linking_dep = rule(
    doc = "A python dependency carrying C++ linking information.",
    implementation = _linking_dep_impl,
    attrs = {
        "wrapped": attr.bool(
            doc = "Whether to provide `PyCcLinkParamsInfo` instead of a bare `CcInfo`.",
        ),
    },
)

_COMMON_PROVIDERS = [PyInfo, PyCcLinkParamsInfo, OutputGroupInfo, InstrumentedFilesInfo]
_EXECUTABLE_PROVIDERS = [PyExecutableInfo, PyRuntimeInfo, RunEnvironmentInfo]

def _providers_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)

    expected = list(_COMMON_PROVIDERS)
    if ctx.attr.executable:
        expected.extend(_EXECUTABLE_PROVIDERS)
    else:
        for provider in _EXECUTABLE_PROVIDERS:
            asserts.false(env, provider in target, "Expected {} not to provide `{}`".format(target.label, provider))

    for provider in expected:
        asserts.true(env, provider in target, "Expected {} to provide `{}`".format(target.label, provider))

    # Output groups mirror `rules_python`.
    sources = [file.path for file in target[PyInfo].transitive_sources.to_list()]
    output_groups = target[OutputGroupInfo]
    for group in ["compilation_prerequisites_INTERNAL_", "compilation_outputs"]:
        asserts.true(env, hasattr(output_groups, group), "Expected output group `{}` on {}".format(group, target.label))
        asserts.equals(env, sources, [file.path for file in getattr(output_groups, group).to_list()])

    # Linking information from dependencies is merged into `PyCcLinkParamsInfo`.
    linker_inputs = target[PyCcLinkParamsInfo].cc_info.linking_context.linker_inputs.to_list()
    owners = [str(linker_input.owner) for linker_input in linker_inputs]
    for dep in ctx.attr.expected_link_deps:
        asserts.true(
            env,
            str(dep.label) in owners,
            "Expected linking information from {} in `PyCcLinkParamsInfo` of {}".format(dep.label, target.label),
        )

    return analysistest.end(env)

providers_test = analysistest.make(
    _providers_test_impl,
    attrs = {
        "executable": attr.bool(
            doc = "Whether the target under test is an executable rule.",
        ),
        "expected_link_deps": attr.label_list(
            doc = "Targets whose linking information is expected in `PyCcLinkParamsInfo`.",
        ),
    },
)

def providers_test_suite(name, **kwargs):
    """Define a test suite for the providers returned by `py_venv_*` rules.

    Args:
        name (str): The name of the test suite.
        **kwargs (dict): Additional keyword arguments for the test suite.
    """
    linking_dep(
        name = "cc_dep",
        tags = ["manual"],
    )

    linking_dep(
        name = "wrapped_cc_dep",
        wrapped = True,
        tags = ["manual"],
    )

    py_venv_library(
        name = "lib",
        srcs = ["lib.py"],
        deps = [
            ":cc_dep",
            ":wrapped_cc_dep",
        ],
        tags = ["manual"],
    )

    py_venv_binary(
        name = "binary",
        srcs = ["main.py"],
        deps = [":lib"],
        tags = ["manual"],
    )

    py_venv_test(
        name = "test",
        srcs = ["main_test.py"],
        deps = [":lib"],
        tags = ["manual"],
    )

    tests = []
    for target, executable in [("lib", False), ("binary", True), ("test", True)]:
        test_name = "{}_providers_test".format(target)
        providers_test(
            name = test_name,
            target_under_test = ":{}".format(target),
            executable = executable,
            expected_link_deps = [
                ":cc_dep",
                ":wrapped_cc_dep",
            ],
        )
        tests.append(":{}".format(test_name))

    native.test_suite(
        name = name,
        tests = tests,
        **kwargs
    )

"""# Wheel

A framework for defining wheels from a tree of Bazel targets

## Setup

TODO
"""

load(
    "//python/wheel/private:wheel.bzl",
    _package_tag = "package_tag",
    _py_module = "py_module",
    _py_wheel_library = "py_wheel_library",
    _py_wheel_toolchain = "py_wheel_toolchain",
)

package_tag = _package_tag
py_module = _py_module
py_wheel_library = _py_wheel_library
py_wheel_toolchain = _py_wheel_toolchain

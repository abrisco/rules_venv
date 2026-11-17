"""# py_cc_extension"""

load(
    "//python/module_extension/private:cc_extension.bzl",
    _PyCcExtensionInfo = "PyCcExtensionInfo",
    _py_cc_extension = "py_cc_extension",
)

PyCcExtensionInfo = _PyCcExtensionInfo
py_cc_extension = _py_cc_extension

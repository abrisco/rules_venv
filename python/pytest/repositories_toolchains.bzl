"""Pytest dependencies"""

# buildifier: disable=unnamed-macro
def register_pytest_toolchains(register_toolchains = True):
    """Defines pytest dependencies"""
    if register_toolchains:
        native.register_toolchains(
            str(Label("//python/pytest/toolchain")),
        )

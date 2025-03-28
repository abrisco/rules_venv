#!/usr/bin/env python3
"""This test verifies that certain attributes are appropriately set on `py_pytest_test` rules.

This code is not expected to be run.
"""

import sys

if __name__ == "__main__":
    print(
        "The fact that this test ran means the some attribute was "
        "not applied to the target that prevented it from running.",
        file=sys.stderr,
    )
    raise AssertionError()

"""Compile source files into pyc files
"""

import py_compile
import sys
from pathlib import Path
from typing import NamedTuple


class ParsedArgs(NamedTuple):
    """A fast alternative to `argparse.Namespace`."""

    src: Path
    """The python source file to compile."""

    output: Path
    """The compiled output."""


def parse_args() -> ParsedArgs:
    """Parse command line arguments."""

    return ParsedArgs(
        src=Path(sys.argv[1]),
        output=Path(sys.argv[2]),
    )

def main() -> None:
    """The main entrypoint."""
    args = parse_args()

    py_compile.compile(
        file=args.src,
        cfile=args.output,
        doraise=True,
        optimize=0,
    )

if __name__ == "__main__":
    main()

"""Rules for compiling Python `.pyc` files"""

load(":venv_common.bzl", "py_venv_common")
load(":utils.bzl", "create_python_startup_args")

PyCompileInfo = provider(
    doc = "TODO",
    fields = {
        "srcs": "Dict[File, File]: A mapping of source file to compiled pyc files.",
    },
)

def _file_stem(file):
    return file.basename

def _py_pyc_aspect_impl(target, ctx):
    venv_toolchain = py_venv_common.get_toolchain(ctx)
    py_toolchain = venv_toolchain.py_toolchain

    py_runtime = py_toolchain.py3_runtime
    interpreter = None
    if py_runtime.interpreter:
        interpreter = path_fn(py_runtime.interpreter, workspace_name)
    else:
        interpreter = py_runtime.interpreter_path

    if not interpreter:
        fail("Unable to locate interpreter from py_toolchain: {}".format(py_toolchain))

    python_args = create_python_startup_args(ctx = ctx, version_info = version_info)
    python_args.add(venv_toolchain.pyc_compiler)

    srcs = {}
    for src in ctx.rule.file.srcs:
        output = ctx.actions.declare_file("{}.pyc".format(_file_stem(src)))
        srcs[src] = output

        args = ctx.actions.args()
        args.add(src)
        args.add(output)

        ctx.actions.run(
            mnemonic = "PyCompile",
            executable = interpreter,
            inputs = [src],
            outputs = [output],
            arguments = [python_args, args],
        )

    return [PyCompileInfo(
        srcs = srcs,
    )]

py_pyc_aspect = aspect(
    doc = "TODO",
    implementation = _py_pyc_aspect_impl,
    attr_aspects = ["deps"],
    toolchains = [py_venv_common.TOOLCHAIN_TYPE],
)

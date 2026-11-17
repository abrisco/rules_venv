/* An extension module compiled into the example's module: `_shout.shout`. */
#define PY_SSIZE_T_CLEAN
#include <Python.h>
#include <ctype.h>

/* The text in capitals, letter by letter in ASCII. */
static PyObject* shout(PyObject* self, PyObject* arg) {
    (void)self;
    Py_ssize_t length;
    const char* text = PyUnicode_AsUTF8AndSize(arg, &length);
    if (text == NULL) {
        return NULL;
    }
    char* loud = PyMem_Malloc((size_t)length);
    if (loud == NULL) {
        return PyErr_NoMemory();
    }
    for (Py_ssize_t i = 0; i < length; i++) {
        loud[i] = (char)toupper((unsigned char)text[i]);
    }
    PyObject* result = PyUnicode_FromStringAndSize(loud, length);
    PyMem_Free(loud);
    return result;
}

static PyMethodDef methods[] = {
    {"shout", shout, METH_O, "The text in capitals."},
    {NULL, NULL, 0, NULL},
};

static struct PyModuleDef module = {
    PyModuleDef_HEAD_INIT,
    "_shout",
    "An extension module linked into the py_wasm_module.",
    -1,
    methods,
    NULL,
    NULL,
    NULL,
    NULL,
};

PyMODINIT_FUNC PyInit__shout(void) { return PyModule_Create(&module); }

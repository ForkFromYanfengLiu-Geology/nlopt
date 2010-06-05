// -*- C++ -*-

//////////////////////////////////////////////////////////////////////////////

%{
#define SWIG_FILE_WITH_INIT
#define array_stride(a,i)        (((PyArrayObject *)a)->strides[i])
%}
%include "numpy.i"
%init %{
  import_array();
%}
%numpy_typemaps(double, NPY_DOUBLE, unsigned)

//////////////////////////////////////////////////////////////////////////////
// numpy.i does not include maps for std::vector<double>, so I add them here,
// taking advantage of the conversion functions provided by numpy.i

// Typemap for input arguments of type const std::vector<double> &
%typecheck(SWIG_TYPECHECK_POINTER, fragment="NumPy_Macros")
  const std::vector<double> &
{
  $1 = is_array($input) || PySequence_Check($input);
}
%typemap(in, fragment="NumPy_Fragments")
  const std::vector<double> &
(PyArrayObject* array=NULL, int is_new_object=0, std::vector<double> arrayv)
{
  npy_intp size[1] = { -1 };
  array = obj_to_array_allow_conversion($input, DATA_TYPECODE, &is_new_object);
  if (!array || !require_dimensions(array, 1) ||
      !require_size(array, size, 1)) SWIG_fail;
  arrayv = std::vector<double>(array_size(array,0));
  $1 = &arrayv;
  {
    double *arr_data = (double *) array_data(array);
    int arr_i, arr_s = array_stride(array,0), arr_sz = array_size(array,0);
    for (arr_i = 0; arr_i < arr_sz; ++arr_i)
      arrayv[arr_i] = arr_data[arr_i * arr_s];
  }
}
%typemap(freearg)
  const std::vector<double> &
{
  if (is_new_object$argnum && array$argnum)
    { Py_DECREF(array$argnum); }
}

// Typemap for return values of type std::vector<double>
%typemap(out, fragment="NumPy_Fragments") std::vector<double>
{
  npy_intp sz = $1.size();
  $result = PyArray_SimpleNew(1, &sz, NPY_DOUBLE);
  std::memcpy(array_data($result), $1.empty() ? NULL : &$1[0],
	      sizeof(double) * sz);
}

//////////////////////////////////////////////////////////////////////////////
// Wrapper for objective function callbacks

%{
static void *free_pyfunc(void *p) { Py_DECREF((PyObject*) p); return p; }
static void *dup_pyfunc(void *p) { Py_INCREF((PyObject*) p); return p; }

static double func_python(unsigned n, const double *x, double *grad, void *f)
{
  npy_intp sz = npy_intp(n), sz0 = 0;
  PyObject *xpy = PyArray_SimpleNewFromData(1, &sz, NPY_DOUBLE, x);
  PyObject *gradpy = grad ? PyArray_SimpleNew(1, &sz0, NPY_DOUBLE)
    : PyArray_SimpleNewFromData(1, &sz, NPY_DOUBLE, grad);
  
  PyObject *arglist = Py_BuildValue("OO", xpy, gradpy);
  PyObject *result = PyEval_CallObject((PyObject *) f, arglist);
  Py_DECREF(arglist);

  Py_DECREF(gradpy);
  Py_DECREF(xpy);

  double val = HUGE_VAL;
  if (SWIG_IsOK(SWIG_AsVal_double(result, &val))) {
    Py_DECREF(result);
  }
  else {
    Py_DECREF(result);
    throw std::invalid_argument("invalid result passed to nlopt");
  }
  return val;
}
%}

%typemap(in)(nlopt::func f, void *f_data, nlopt_munge md, nlopt_munge mc) {
  $1 = func_python;
  $2 = dup_pyfunc((void*) $input);
  $3 = free_pyfunc;
  $4 = dup_pyfunc;
}
%typecheck(SWIG_TYPECHECK_POINTER)(nlopt::func f, void *f_data) {
  $1 = PyCallable_Check($input);
}

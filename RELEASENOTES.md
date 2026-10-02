## 0.1.1

* build system maintenance: updated mulle-sde and cmake support, regenerated reflection data

## 0.1.0




feature: add Metal backing surface for macOS windows with no GL context

* macOS windows created with `GLFW_NO_API` now get an attached CAMetalLayer, enabling a Metal rendering backend
* new `-backendMetalLayer` accessor vends the CAMetalLayer (as `void *`) to the Metal CG backend
* Metal windows no longer claim the retained/two-context backing store, which relies on GL context sharing Metal does not have
* active-graphics-thread tracking now works for Metal windows without a GL context

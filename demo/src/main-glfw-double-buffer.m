// GLFW_INCLUDE_... keep undefined for OpenGL3
// see: https://www.glfw.org/docs/latest/build_guide.html

#define GL_GLEXT_PROTOTYPES
#ifdef __APPLE__
# include <OpenGL/gl.h>
# include <OpenGL/glext.h>
#else
# include <GL/gl.h>
# include <GL/glext.h>
#endif

//#define GLFW_INCLUDE_NONE
#include <GLFW/glfw3.h>

#define GLFW_EXPOSE_NATIVE_WAYLAND
#define GLFW_EXPOSE_NATIVE_EGL
#include <GLFW/glfw3native.h>

#include <stdlib.h>
#include <stdio.h>


static void error_callback(int error, const char* description)
{
    fprintf(stderr, "Error: %s\n", description);
}

static char   *eglErrorUTF8String( int error)
{
   switch( error)
   {
   case EGL_SUCCESS             : return( "The last function succeeded without error.");
   case EGL_NOT_INITIALIZED     : return( "EGL is not initialized, or could not be initialized, for the specified EGL display connection.");
   case EGL_BAD_ACCESS          : return( "EGL cannot access a requested resource (for example a context is bound in another thread).");
   case EGL_BAD_ALLOC           : return( "EGL failed to allocate resources for the requested operation.");
   case EGL_BAD_ATTRIBUTE       : return( "An unrecognized attribute or attribute value was passed in the attribute list.");
   case EGL_BAD_CONTEXT         : return( "An EGLContext argument does not name a valid EGL rendering context.");
   case EGL_BAD_CONFIG          : return( "An EGLConfig argument does not name a valid EGL frame buffer configuration.");
   case EGL_BAD_CURRENT_SURFACE : return( "The current surface of the calling thread is a window, pixel buffer or pixmap that is no longer valid.");
   case EGL_BAD_DISPLAY         : return( "An EGLDisplay argument does not name a valid EGL display connection.");
   case EGL_BAD_SURFACE         : return( "An EGLSurface argument does not name a valid surface (window, pixel buffer or pixmap) configured for GL rendering.");
   case EGL_BAD_MATCH           : return( "Arguments are inconsistent (for example, a valid context requires buffers not supplied by a valid surface).");
   case EGL_BAD_PARAMETER       : return( "One or more argument values are invalid.");
   case EGL_BAD_NATIVE_PIXMAP   : return( "A NativePixmapType argument does not refer to a valid native pixmap.");
   case EGL_BAD_NATIVE_WINDOW   : return( "A NativeWindowType argument does not refer to a valid native window.");
   case EGL_CONTEXT_LOST        : return( "A power management event has occurred. The application must destroy all contexts and reinitialise OpenGL ES state and objects to continue rendering.");
   }
   return( "???");
}


int main(void)
{
    glfwSetErrorCallback(error_callback);

    if (!glfwInit())
        exit(EXIT_FAILURE);

    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
    // (nat) need to add this for macOS
    glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE);
    glfwWindowHint(GLFW_CONTEXT_CREATION_API, GLFW_EGL_CONTEXT_API);

    GLFWwindow* window = glfwCreateWindow(640, 480, "Demo", NULL, NULL);
    if (!window)
    {
        glfwTerminate();
        exit(EXIT_FAILURE);
    }

    glfwMakeContextCurrent(window);
    glfwSwapInterval(0);

#if 0
    {
      EGLSurface surface;
      EGLDisplay display;
      EGLint  error;

      display = glfwGetEGLDisplay();
      surface = glfwGetEGLSurface( window);

      fprintf( stderr, "display: %p surface: %p :", (void *) display, (void *) surface);
      if( eglSurfaceAttrib( display, surface, EGL_SWAP_BEHAVIOR, EGL_BUFFER_PRESERVED) == EGL_FALSE)
      {
         error = eglGetError();
         fprintf( stderr, "failed %d (%s)\n", error, eglErrorUTF8String( error));
      }
      else
         fprintf( stderr, "success\n");
    }
#endif

    glClearColor( 0.7, 0.3, 0.0, 0.0);
    glClear(GL_COLOR_BUFFER_BIT);
    glfwSwapBuffers(window);
    glClearColor( 0.0, 0.3, 0.7, 0.0);
    glClear(GL_COLOR_BUFFER_BIT);
    glfwSwapBuffers(window);
    glfwSwapInterval(2);

    while (!glfwWindowShouldClose(window))
    {
        glfwSwapBuffers(window);
        glfwPollEvents();
    }

    glfwDestroyWindow(window);

    glfwTerminate();
    exit( EXIT_SUCCESS);
}

//! [code]

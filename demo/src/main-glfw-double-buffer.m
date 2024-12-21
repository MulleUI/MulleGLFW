// GLFW_INCLUDE_... keep undefined for OpenGL3
// see: https://www.glfw.org/docs/latest/build_guide.html

//#define GLFW_INCLUDE_NONE
#ifdef __APPLE__
# define GLFW_INCLUDE_GLCOREARB
# define GLFW_EXPOSE_NATIVE_COCOA
#else
# define GLFW_INCLUDE_ES2
#endif 

#include <GLFW/glfw3.h>

#ifndef __APPLE__
# define GLFW_EXPOSE_NATIVE_WAYLAND
# define GLFW_EXPOSE_NATIVE_EGL
# include <GLFW/glfw3native.h>
#endif


#define GL_GLEXT_PROTOTYPES
#ifdef __APPLE__
# include <OpenGL/gl3.h>
#else
# include <GLES2/gl2.h>
# include <EGL/egl.h>
#endif


#include <stdlib.h>
#include <stdio.h>
#include <string.h>


// THIS DEMO CAN'T WORK AS EXPECTED FOR TECHNICAL REASONS OUTSIDE OF OUR
// CONTROL:
//
// https://discourse.glfw.org/t/problem-with-double-buffering-and-nvidia-on-linux-wayland/2170/4
//
//
//
// GFLW on Wayland uses EGL by default for context creation 5, and thus the glfwSwapBuffers calls eglSwapBuffers 1.
//
// From the documentation EGL_SWAP_BEHAVIOR attribute would need to be set to EGL_BUFFER_PRESERVED to preserve the back buffer, and this is not set by GLFW. The behaviour of buffer swapping is not consistent across APIs/OSs/Drivers so I do not think it would be useful for GLFW to set this, but you could use the native interface 3 to get the EGL surface and set the surface attribute yourself.
// The behaviour of EGL without EGL_BUFFER_PRESERVED set and the behaviour of GLX are that The contents of the color buffer are undefined. The swap behaviour of some drivers/hardware is to copy the contents, so the results you see on GLX could be due to this. Generally it is not safe to assume undefined behaviour will do a specific thing.
//

static void error_callback(int error, const char* description)
{
    fprintf(stderr, "Error: %s\n", description);
}

static char   *eglErrorUTF8String( int error)
{
#ifndef __APPLE__   
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
#endif   
   return( "???");
}


static void   usage( char *argv0)
{
   char   *s;

   s = strrchr( argv0, '/');
   s = s ? s + 1 : argv0;

   fprintf( stderr, "%s [api] [version] [options] [swapInterval]\n"
"\n"
"Api:\n"
"   --gl         :\n"
"   --gles       :\n"
"   --np-api     :\n"
"\n"
"Version:\n"
"   --[0-9].[0-9]:\n"
"\n"
"Options:\n"
"   --any        :\n"
"   --core       :\n"
"   --compat     :\n"
"\n"
"   --no-forward :\n"
"   --forward    :\n"
"\n"
"   --native     :\n"
"   --egl        :\n"
"   --mesa       :\n", s);
      exit( 1);
}



int   main( int argc, char *argv[])
{
   int    client_api;
   int    creation_api;
   int    forward;
   int    major;
   int    minor;
   int    profile;
   int    i;
   char   *s;
   int    swapInterval;

   client_api    = -1;
   creation_api  = -1;
   forward       = -1;
   major         = -1;
   minor         = -1;
   profile       = -1;
   swapInterval  = 20;

   for( i = 1; i < argc; i++)
   {
      if( ! strcmp( argv[ i], "--gl"))
      {
         client_api = GLFW_OPENGL_API;
         continue;
      }
      if( ! strcmp( argv[ i], "--gles"))
      {
         client_api = GLFW_OPENGL_ES_API;
         continue;
      }
      if( ! strcmp( argv[ i], "--no-api"))
      {
         client_api = GLFW_NO_API;
         continue;
      }

      // profile
      if( ! strcmp( argv[ i], "--any"))
      {
         profile = GLFW_OPENGL_ANY_PROFILE;
         continue;
      }
      if( ! strcmp( argv[ i], "--core"))
      {
         profile = GLFW_OPENGL_CORE_PROFILE;
         continue;
      }
      if( ! strcmp( argv[ i], "--compat"))
      {
         profile = GLFW_OPENGL_COMPAT_PROFILE;
         continue;
      }

      // forward
      if( ! strcmp( argv[ i], "--no-forward"))
      {
         forward = 0;
         continue;
      }
      if( ! strcmp( argv[ i], "--forward"))
      {
         forward = 1;
         continue;
      }

      // creation_api
      if( ! strcmp( argv[ i], "--native"))
      {
         creation_api = GLFW_NATIVE_CONTEXT_API;
         continue;
      }
      if( ! strcmp( argv[ i], "--egl"))
      {
         creation_api = GLFW_EGL_CONTEXT_API;
         continue;
      }
      if( ! strcmp( argv[ i], "--mesa"))
      {
         creation_api = GLFW_OSMESA_CONTEXT_API;
         continue;
      }

      if( ! strncmp( argv[ i], "--", 2))
      {
         major = atoi( &argv[ i][ 2]);
         s     = strchr( &argv[ i][ 2], '.');
         minor = s ? atoi( s + 1) : 0;
         continue;
      }

      if( argv[ i][ 0] != '-')
         break;

      usage( argv[ 0]);
   }

   if( i == argc - 1)
      swapInterval = atoi( argv[ i]);
   else
      if( i != argc)
         usage( argv[ 0]);

    glfwSetErrorCallback(error_callback);

    if (!glfwInit())
        exit(EXIT_FAILURE);

   if( major != -1)
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, major);
   if( minor != -1)
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, minor);
    // (nat) need to add this for macOS
    if( profile != -1)
      glfwWindowHint(GLFW_OPENGL_PROFILE, profile);
    if( client_api != -1)
      glfwWindowHint(GLFW_CLIENT_API, client_api);
    if( creation_api != -1)
      glfwWindowHint(GLFW_CONTEXT_CREATION_API, creation_api);
    if( forward != -1)
      glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, forward ? GL_TRUE : GL_FALSE);
   glfwWindowHint(GLFW_DOUBLEBUFFER, GLFW_TRUE);

    fprintf( stderr, "major        : %d\n", major);
    fprintf( stderr, "minor        : %d\n", minor);
    fprintf( stderr, "profile      : %d\n", profile);
    fprintf( stderr, "client_api   : 0x%x\n", client_api);
    fprintf( stderr, "creation_api : 0x%x\n", creation_api);
    fprintf( stderr, "forward      : %d\n", forward);
    fprintf( stderr, "swapInterval : %d\n", swapInterval);

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

    glClearColor( 0.7, 0.0, 0.0, 1.0);
    glClear(GL_COLOR_BUFFER_BIT);
    glFlush();
    glfwSwapBuffers(window);
    glClearColor( 0.0, 0.0, 0.7, 1.0);
    glClear(GL_COLOR_BUFFER_BIT);
    glFlush();
    glfwSwapInterval( swapInterval);
    glfwSwapBuffers(window);

    while (!glfwWindowShouldClose(window))
    {
        glfwSwapBuffers(window);
        glfwPollEvents();
//        glfwWaitEventsTimeout( swapInterval / 60.0);
        putchar( '.');
        fflush( stdout);
    }

    glfwDestroyWindow(window);

    glfwTerminate();
    exit( EXIT_SUCCESS);
}

//! [code]

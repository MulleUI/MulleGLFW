#define _GNU_SOURCE

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

#define GLFW_INCLUDE_NONE
#include <GLFW/glfw3.h>

#include <stdlib.h>
#include <stdio.h>
#include <time.h>


int main(void)
{
   struct timespec delay = { 0, 500 * 1000L * 1000L};

   if (!glfwInit())
     exit(EXIT_FAILURE);

   glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
   glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
   glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
   glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE);
   glfwWindowHint(GLFW_DOUBLEBUFFER, GLFW_FALSE);
//   glfwWindowHint(GLFW_CONTEXT_CREATION_API, GLFW_EGL_CONTEXT_API);

   GLFWwindow* window = glfwCreateWindow(640, 480, "Demo", NULL, NULL);
   if (!window)
   {
      fprintf( stderr, "No window for you! (single buffer not supported)\n");
      glfwTerminate();
      exit(EXIT_FAILURE);
   }

   glfwMakeContextCurrent(window);

   for(;;)
   {
      glfwPollEvents();
      if( glfwWindowShouldClose(window))
         break;

      glClearColor( 0.7, 0.3, 0.0, 0.0);
      glClear(GL_COLOR_BUFFER_BIT);
      glFlush();
      nanosleep( &delay, NULL);

      glfwPollEvents();
      if( glfwWindowShouldClose(window))
         break;

      glClearColor( 0.0, 0.3, 0.7, 0.0);
      glClear(GL_COLOR_BUFFER_BIT);
      glFlush();
      nanosleep( &delay, NULL);
   }

   glfwDestroyWindow(window);

   glfwTerminate();
   exit( EXIT_SUCCESS);
}

//! [code]

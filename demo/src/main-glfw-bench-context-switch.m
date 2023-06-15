#define _GNU_SOURCE

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


// check how much we lose by doing context switches of CGContext / OpenGL
// context really...

int main(void)
{
   struct timespec delay = { 0, 500 * 1000L * 1000L};
   unsigned int   i, j;

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
   glfwSwapInterval( 0);

   for( j = 0; j < 10; j++)
   {
      putchar( '.');
      fflush( stdout);
      glfwPollEvents();
      if( glfwWindowShouldClose(window))
         break;

      //
      // 10000 switches = ~ 1s
      // 1 switch       = 1/10000 0.0001s
      //
      for( i = 0; i < 1000; i++)
      {
         glfwMakeContextCurrent(NULL);
         glfwMakeContextCurrent(window);
      }    
      glFlush();
      glfwSwapBuffers(window);
   }

   glfwDestroyWindow(window);

   glfwTerminate();
   exit( EXIT_SUCCESS);
}

//! [code]

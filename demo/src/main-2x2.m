//
// Two windows each rendered in their own pthread.
// GLFW requires that window creation and glfwPollEvents run on the main thread.
// Each render thread owns its GL context via glfwMakeContextCurrent.
//

#ifdef HAVE_GLAD
#define GLAD_GL_IMPLEMENTATION
#include <glad/gl.h>
#else
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
#endif

#define GLFW_INCLUDE_NONE
#include <GLFW/glfw3.h>

#ifdef __APPLE__
# define glGenVertexArrays   glGenVertexArraysAPPLE
# define glBindVertexArray   glBindVertexArrayAPPLE
#endif

#include "linmath.h"

#include <pthread.h>
#include <stdlib.h>
#include <stddef.h>
#include <stdio.h>


typedef struct Vertex
{
   vec2   pos;
   vec3   col;
} Vertex;

// Window 1: classic RGB triangle
static const Vertex   vertices_1[ 3] =
{
   { { -0.6f, -0.4f }, { 1.f, 0.f, 0.f } },
   { {  0.6f, -0.4f }, { 0.f, 1.f, 0.f } },
   { {  0.0f,  0.6f }, { 0.f, 0.f, 1.f } }
};

// Window 2: CMY triangle, spins the other way
static const Vertex   vertices_2[ 3] =
{
   { { -0.6f, -0.4f }, { 0.f, 1.f, 1.f } },
   { {  0.6f, -0.4f }, { 1.f, 0.f, 1.f } },
   { {  0.0f,  0.6f }, { 1.f, 1.f, 0.f } }
};

static const char   *vertex_shader_text =
   "#version 330\n"
   "uniform mat4 MVP;\n"
   "in vec3 vCol;\n"
   "in vec2 vPos;\n"
   "out vec3 color;\n"
   "void main()\n"
   "{\n"
   "    gl_Position = MVP * vec4(vPos, 0.0, 1.0);\n"
   "    color = vCol;\n"
   "}\n";

static const char   *fragment_shader_text =
   "#version 330\n"
   "in vec3 color;\n"
   "out vec4 fragment;\n"
   "void main()\n"
   "{\n"
   "    fragment = vec4(color, 1.0);\n"
   "}\n";


struct WindowData
{
   GLFWwindow     *window;
   const Vertex   *vertices;
   float           rotation_speed; // 1.0 forward, -1.0 reverse, etc.
};


static void error_callback( int error, const char *description)
{
   fprintf( stderr, "Error: %s\n", description);
}


static void *render_thread( void *arg)
{
   struct WindowData   *data     = arg;
   GLFWwindow          *window   = data->window;
   const Vertex        *vertices = data->vertices;

   // Each thread owns its GL context.
   glfwMakeContextCurrent( window);
   glfwSwapInterval( 1);

#ifdef HAVE_GLAD
   gladLoadGL( glfwGetProcAddress);
#endif

   GLuint   vertex_buffer;
   glGenBuffers( 1, &vertex_buffer);
   glBindBuffer( GL_ARRAY_BUFFER, vertex_buffer);
   glBufferData( GL_ARRAY_BUFFER, sizeof( Vertex) * 3, vertices, GL_STATIC_DRAW);

   const GLuint   vertex_shader = glCreateShader( GL_VERTEX_SHADER);
   glShaderSource( vertex_shader, 1, &vertex_shader_text, NULL);
   glCompileShader( vertex_shader);

   const GLuint   fragment_shader = glCreateShader( GL_FRAGMENT_SHADER);
   glShaderSource( fragment_shader, 1, &fragment_shader_text, NULL);
   glCompileShader( fragment_shader);

   const GLuint   program = glCreateProgram();
   glAttachShader( program, vertex_shader);
   glAttachShader( program, fragment_shader);
   glLinkProgram( program);

   const GLint   mvp_location  = glGetUniformLocation( program, "MVP");
   const GLint   vpos_location = glGetAttribLocation( program, "vPos");
   const GLint   vcol_location = glGetAttribLocation( program, "vCol");

   GLuint   vertex_array;
   glGenVertexArrays( 1, &vertex_array);
   glBindVertexArray( vertex_array);
   glEnableVertexAttribArray( vpos_location);
   glVertexAttribPointer( vpos_location, 2, GL_FLOAT, GL_FALSE,
                          sizeof( Vertex), (void *) offsetof( Vertex, pos));
   glEnableVertexAttribArray( vcol_location);
   glVertexAttribPointer( vcol_location, 3, GL_FLOAT, GL_FALSE,
                          sizeof( Vertex), (void *) offsetof( Vertex, col));

   while( !glfwWindowShouldClose( window))
   {
      int     width, height;
      float   ratio;

      glfwGetFramebufferSize( window, &width, &height);
      ratio = width / (float) height;

      glViewport( 0, 0, width, height);
      glClearColor( 0.f, 0.f, 0.f, 1.f);
      glClear( GL_COLOR_BUFFER_BIT);

      mat4x4   m, p, mvp;
      mat4x4_identity( m);
      mat4x4_rotate_Z( m, m, (float) glfwGetTime() * data->rotation_speed);
      mat4x4_ortho( p, -ratio, ratio, -1.f, 1.f, 1.f, -1.f);
      mat4x4_mul( mvp, p, m);

      glUseProgram( program);
      glUniformMatrix4fv( mvp_location, 1, GL_FALSE, (const GLfloat *) &mvp);
      glBindVertexArray( vertex_array);
      glDrawArrays( GL_TRIANGLES, 0, 3);

      glfwSwapBuffers( window);
   }

   glfwMakeContextCurrent( NULL);
   return( NULL);
}


int main( void)
{
   glfwSetErrorCallback( error_callback);

   if( !glfwInit())
      exit( EXIT_FAILURE);

   glfwWindowHint( GLFW_CONTEXT_VERSION_MAJOR, 3);
   glfwWindowHint( GLFW_CONTEXT_VERSION_MINOR, 3);
   glfwWindowHint( GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
   // required on macOS
   glfwWindowHint( GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE);

   GLFWwindow *window1 = glfwCreateWindow( 640, 480, "Thread 1 - RGB", NULL, NULL);
   if( !window1)
   {
      glfwTerminate();
      exit( EXIT_FAILURE);
   }

   GLFWwindow *window2 = glfwCreateWindow( 640, 480, "Thread 2 - CMY", NULL, NULL);
   if( !window2)
   {
      glfwDestroyWindow( window1);
      glfwTerminate();
      exit( EXIT_FAILURE);
   }

   // Place window2 to the right of window1
   {
      int   xpos, ypos, width;

      glfwGetWindowPos( window1, &xpos, &ypos);
      glfwGetWindowSize( window1, &width, NULL);
      glfwSetWindowPos( window2, xpos + width + 32, ypos);
   }

   struct WindowData   data1 = { window1, vertices_1,  1.0f };
   struct WindowData   data2 = { window2, vertices_2, -0.7f };

   pthread_t   thread1, thread2;
   pthread_create( &thread1, NULL, render_thread, &data1);
   pthread_create( &thread2, NULL, render_thread, &data2);

   // Main thread: poll events (GLFW requirement) until both windows close.
   while( !glfwWindowShouldClose( window1) && !glfwWindowShouldClose( window2))
      glfwPollEvents();

   // If one window closes, close the other too.
   glfwSetWindowShouldClose( window1, GLFW_TRUE);
   glfwSetWindowShouldClose( window2, GLFW_TRUE);

   pthread_join( thread1, NULL);
   pthread_join( thread2, NULL);

   glfwDestroyWindow( window2);
   glfwDestroyWindow( window1);
   glfwTerminate();
   exit( EXIT_SUCCESS);
}

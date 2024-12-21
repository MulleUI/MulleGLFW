#include <stdio.h>
#include <stdlib.h>
#include <mulle-time/mulle-time.h>

// random stole code, just drawing a triangle with a shader

#ifdef __APPLE__
# define GLFW_INCLUDE_GLCOREARB
# define GLFW_EXPOSE_NATIVE_COCOA
#else
# define GLFW_INCLUDE_ES2
#endif 

#include <GLFW/glfw3.h>

#define WIDTH  800
#define HEIGHT 600

static char   *vertex_shader_source =
    "#version 100\n"
    "attribute vec3 position;\n"
    "void main() {\n"
    "   gl_Position = vec4(position, 1.0);\n"
    "}\n";

static char  *fragment_shader_source =
    "#version 100\n"
    "void main() {\n"
    "   gl_FragColor = vec4(1.0, 0.0, 0.0, 1.0);\n"
    "}\n";

static GLfloat vertices[] =
{
   0.0f,  0.5f, 0.0f,
   0.5f, -0.5f, 0.0f,
   -0.5f, -0.5f, 0.0f,
};


#define INFOLOG_LEN  512

GLint   common_get_shader_program( char *vertex_shader_source,
                                   char *fragment_shader_source)
{
   GLchar  infoLog[ INFOLOG_LEN];
   GLint   fragment_shader;
   GLint   shader_program;
   GLint   success;
   GLint   vertex_shader;

   /* Vertex shader */
   vertex_shader = glCreateShader(GL_VERTEX_SHADER);
   glShaderSource( vertex_shader, 1, &vertex_shader_source, NULL);
   glCompileShader( vertex_shader);
   glGetShaderiv( vertex_shader, GL_COMPILE_STATUS, &success);
   if( ! success)
   {
      glGetShaderInfoLog(vertex_shader, INFOLOG_LEN, NULL, infoLog);
      fprintf( stderr, "VERTEX COMPILATION FAILED: %s\n", infoLog);
   }

   /* Fragment shader */
   fragment_shader = glCreateShader(GL_FRAGMENT_SHADER);
   glShaderSource( fragment_shader, 1, &fragment_shader_source, NULL);
   glCompileShader( fragment_shader);
   glGetShaderiv( fragment_shader, GL_COMPILE_STATUS, &success);

   if( ! success)
   {
      glGetShaderInfoLog( fragment_shader, INFOLOG_LEN, NULL, infoLog);
      fprintf( stderr, "FRAGMENT COMPILATION FAILED: %s\n", infoLog);
   }

   /* Link shaders */
   shader_program = glCreateProgram();
   glAttachShader(shader_program, vertex_shader);
   glAttachShader(shader_program, fragment_shader);
   glLinkProgram(shader_program);
   glGetProgramiv(shader_program, GL_LINK_STATUS, &success);
   if (!success)
   {
      glGetProgramInfoLog(shader_program, INFOLOG_LEN, NULL, infoLog);
      fprintf( stderr, "LINKING FAILED: %s\n", infoLog);
   }

   glDeleteShader(vertex_shader);
   glDeleteShader(fragment_shader);
   return shader_program;
}


int main( int argc, char *argv[])
{
   GLuint       shader_program;
   GLuint       vbo;
   GLint        pos;
   GLFWwindow   *window;
   int          major, minor, revision;

   glfwInit();

   glfwWindowHint(GLFW_CLIENT_API, GLFW_OPENGL_ES_API);
   glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 2);
   glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 0);

   window = glfwCreateWindow( WIDTH, HEIGHT, __FILE__, NULL, NULL);
   glfwMakeContextCurrent(window);

   printf("GL_VERSION  : %s\n", glGetString( GL_VERSION));
   printf("GL_RENDERER : %s\n", glGetString( GL_RENDERER));
   glfwGetVersion( &major, &minor, &revision);
   printf("GLFW v%i.%i.%i\n", major, minor, revision);

   shader_program = common_get_shader_program( vertex_shader_source,
                                               fragment_shader_source);
   pos            = glGetAttribLocation( shader_program, "position");

   glClearColor( 0.0f, 0.0f, 0.0f, 1.0f);
   glViewport( 0, 0, WIDTH, HEIGHT);

   glGenBuffers( 1, &vbo);
   glBindBuffer( GL_ARRAY_BUFFER, vbo);
   glBufferData( GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);
   glVertexAttribPointer( pos, 3, GL_FLOAT, GL_FALSE, 0, (GLvoid*) 0);
   glEnableVertexAttribArray( pos);
   glBindBuffer( GL_ARRAY_BUFFER, 0);

   while( ! glfwWindowShouldClose( window))
   {
      glClear( GL_COLOR_BUFFER_BIT);
      glUseProgram( shader_program);
      glDrawArrays( GL_TRIANGLES, 0, 3);
      mulle_relativetime_sleep( 20 * 1 / 60.0);
      glfwSwapBuffers( window);
      fprintf( stderr, "%.6f\n", mulle_timeinterval_now());
      glfwWaitEvents();
   }

   glDeleteBuffers(1, &vbo);
   glfwTerminate();

   return( EXIT_SUCCESS);
}


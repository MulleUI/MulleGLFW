//
// Same as main-two-x-two-windows.m, but with window/thread creation order
// changed to match UIPureWindow's actual sequence, per the differential
// trace investigation in
// MulleUIPureWindow/demo/WAYLAND-RETAINED-WINDOW-PAIR-AGONY.md:
//
// main-two-x-two-windows.m creates BOTH pairs' GLFW windows fully upfront,
// then starts BOTH render threads afterward. UIPureWindow's actual
// sequence is different: window A is fully constructed AND its render
// thread is started (and confirmed running, via a blocking handshake)
// BEFORE window B's GLFW windows are created at all. This means in the
// real bug, window A's render thread is guaranteed to already be active
// -- making its own GLFW/GL calls (context activation, rendering, swap)
// on a second OS thread -- WHILE window B's GLFW windows are still being
// created on the main thread. main-two-x-two-windows.m never tests this
// ordering, which is the one concrete untested variable identified by
// the differential trace.
//
// Everything else (window/context hints, FBO/texture sharing, render
// loop, shaders) is unchanged from main-two-x-two-windows.m.
//
// Usage: two-x-two-windows-ordered [--samples N]   (default 4, 0/1 = off)
//

#ifdef HAVE_GLAD
#define GLAD_GL_IMPLEMENTATION
#include <glad/gl.h>
#else
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
# define glGenVertexArrays    glGenVertexArraysAPPLE
# define glBindVertexArray    glBindVertexArrayAPPLE
# define glDeleteVertexArrays glDeleteVertexArraysAPPLE
#endif

#include "linmath.h"

#include <pthread.h>
#include <stdlib.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <time.h>


#define FBO_W   640
#define FBO_H   480


typedef struct Vertex
{
   vec2   pos;
   vec3   col;
} Vertex;

static const Vertex   vertices_1[ 3] =
{
   { { -0.6f, -0.4f }, { 1.f, 0.f, 0.f } },
   { {  0.6f, -0.4f }, { 0.f, 1.f, 0.f } },
   { {  0.0f,  0.6f }, { 0.f, 0.f, 1.f } }
};

static const Vertex   vertices_2[ 3] =
{
   { { -0.6f, -0.4f }, { 0.f, 1.f, 1.f } },
   { {  0.6f, -0.4f }, { 1.f, 0.f, 1.f } },
   { {  0.0f,  0.6f }, { 1.f, 1.f, 0.f } }
};


static const char   *tri_vert_src =
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

static const char   *tri_frag_src =
   "#version 330\n"
   "in vec3 color;\n"
   "out vec4 fragment;\n"
   "void main()\n"
   "{\n"
   "    fragment = vec4(color, 1.0);\n"
   "}\n";

static const float   quad_verts[ 4][ 4] =
{
   { -1.f, -1.f,  0.f, 0.f },
   {  1.f, -1.f,  1.f, 0.f },
   { -1.f,  1.f,  0.f, 1.f },
   {  1.f,  1.f,  1.f, 1.f },
};

static const char   *quad_vert_src =
   "#version 330\n"
   "in vec2 aPos;\n"
   "in vec2 aTexCoord;\n"
   "out vec2 vTexCoord;\n"
   "void main()\n"
   "{\n"
   "    gl_Position = vec4(aPos, 0.0, 1.0);\n"
   "    vTexCoord = aTexCoord;\n"
   "}\n";

static const char   *quad_frag_src =
   "#version 330\n"
   "in vec2 vTexCoord;\n"
   "out vec4 fragment;\n"
   "uniform sampler2D uTex;\n"
   "void main()\n"
   "{\n"
   "    fragment = texture(uTex, vTexCoord);\n"
   "}\n";


struct WindowPair
{
   GLFWwindow         *offscreen;
   GLFWwindow         *display;
   const Vertex       *vertices;
   float               rotation_speed;
   int                 samples;

   // handshake: main thread blocks until render thread signals "running"
   pthread_mutex_t      ready_mutex;
   pthread_cond_t       ready_cond;
   int                  is_ready;
};


static void error_callback( int error, const char *description)
{
   fprintf( stderr, "GLFW error %d: %s\n", error, description);
}


static void   gl_check_errors( const char *label)
{
   GLenum   err;

   while( (err = glGetError()) != GL_NO_ERROR)
      fprintf( stderr, "GL error at [%s]: 0x%x\n", label, err);
}


static void   check_shader( GLuint shader, const char *label)
{
   GLint   ok = GL_TRUE;

   glGetShaderiv( shader, GL_COMPILE_STATUS, &ok);
   if( !ok)
   {
      char   log[ 2048];
      glGetShaderInfoLog( shader, sizeof( log), NULL, log);
      fprintf( stderr, "Shader compile error [%s]:\n%s\n", label, log);
   }
}


static void   check_program( GLuint prog, const char *label)
{
   GLint   ok = GL_TRUE;

   glGetProgramiv( prog, GL_LINK_STATUS, &ok);
   if( !ok)
   {
      char   log[ 2048];
      glGetProgramInfoLog( prog, sizeof( log), NULL, log);
      fprintf( stderr, "Program link error [%s]:\n%s\n", label, log);
   }
}


static void   check_fbo( const char *label)
{
   GLenum   status = glCheckFramebufferStatus( GL_FRAMEBUFFER);

   if( status != GL_FRAMEBUFFER_COMPLETE)
      fprintf( stderr, "FBO incomplete [%s]: 0x%x\n", label, status);
}


static GLuint   build_program( const char *vert_src, const char *frag_src,
                                const char *label)
{
   GLuint   vs = glCreateShader( GL_VERTEX_SHADER);
   glShaderSource( vs, 1, &vert_src, NULL);
   glCompileShader( vs);
   check_shader( vs, label);

   GLuint   fs = glCreateShader( GL_FRAGMENT_SHADER);
   glShaderSource( fs, 1, &frag_src, NULL);
   glCompileShader( fs);
   check_shader( fs, label);

   GLuint   prog = glCreateProgram();
   glAttachShader( prog, vs);
   glAttachShader( prog, fs);
   glLinkProgram( prog);
   check_program( prog, label);
   return( prog);
}


// Signal that this render thread's setup is complete and it has entered
// its render loop -- matches UIPureWindow(Thread)'s
// startWindowThreadMainIfNeeded blocking handshake (main thread waits
// for the render thread to signal UIWindowThreadLockConditionIdle before
// proceeding to the next window).
static void   signal_ready( struct WindowPair *pair)
{
   pthread_mutex_lock( &pair->ready_mutex);
   pair->is_ready = 1;
   pthread_cond_signal( &pair->ready_cond);
   pthread_mutex_unlock( &pair->ready_mutex);
}


static void   wait_ready( struct WindowPair *pair)
{
   pthread_mutex_lock( &pair->ready_mutex);
   while( ! pair->is_ready)
      pthread_cond_wait( &pair->ready_cond, &pair->ready_mutex);
   pthread_mutex_unlock( &pair->ready_mutex);
}


static void *render_thread( void *arg)
{
   struct WindowPair   *pair      = arg;
   GLFWwindow          *offscreen = pair->offscreen;
   GLFWwindow          *display   = pair->display;

   glfwMakeContextCurrent( offscreen);

#ifdef HAVE_GLAD
   gladLoadGL( glfwGetProcAddress);
#endif

   if( !glGetString( GL_VERSION))
   {
      fprintf( stderr, "ERROR: GL context is not functional.\n");
      signal_ready( pair);   // don't hang the main thread on failure
      return( NULL);
   }

   fprintf( stderr, "[offscreen] GL renderer: %s | GL version: %s | samples: %d\n",
            glGetString( GL_RENDERER), glGetString( GL_VERSION), pair->samples);

   int   msaa = (pair->samples > 1);

   GLuint   fbo_tex;
   glGenTextures( 1, &fbo_tex);
   glBindTexture( GL_TEXTURE_2D, fbo_tex);
   glTexImage2D( GL_TEXTURE_2D, 0, GL_RGBA, FBO_W, FBO_H, 0,
                 GL_RGBA, GL_UNSIGNED_BYTE, NULL);
   glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
   glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
   gl_check_errors( "resolve texture");

   GLuint   resolve_fbo;
   glGenFramebuffers( 1, &resolve_fbo);
   glBindFramebuffer( GL_FRAMEBUFFER, resolve_fbo);
   glFramebufferTexture2D( GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                           GL_TEXTURE_2D, fbo_tex, 0);
   check_fbo( "resolve_fbo");

   GLuint   msaa_fbo   = 0;
   GLuint   msaa_color = 0;
   if( msaa)
   {
      glGenTextures( 1, &msaa_color);
      glBindTexture( GL_TEXTURE_2D_MULTISAMPLE, msaa_color);
      glTexImage2DMultisample( GL_TEXTURE_2D_MULTISAMPLE,
                               pair->samples, GL_RGBA, FBO_W, FBO_H, GL_TRUE);
      gl_check_errors( "msaa texture");

      glGenFramebuffers( 1, &msaa_fbo);
      glBindFramebuffer( GL_FRAMEBUFFER, msaa_fbo);
      glFramebufferTexture2D( GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                              GL_TEXTURE_2D_MULTISAMPLE, msaa_color, 0);
      check_fbo( "msaa_fbo");
   }

   GLuint   render_fbo = msaa ? msaa_fbo : resolve_fbo;

   GLuint   tri_prog    = build_program( tri_vert_src, tri_frag_src, "triangle");
   GLint    mvp_loc     = glGetUniformLocation( tri_prog, "MVP");
   GLint    vpos_loc    = glGetAttribLocation(  tri_prog, "vPos");
   GLint    vcol_loc    = glGetAttribLocation(  tri_prog, "vCol");

   GLuint   tri_vbo;
   glGenBuffers( 1, &tri_vbo);
   glBindBuffer( GL_ARRAY_BUFFER, tri_vbo);
   glBufferData( GL_ARRAY_BUFFER, sizeof( Vertex) * 3, pair->vertices, GL_STATIC_DRAW);

   GLuint   tri_vao;
   glGenVertexArrays( 1, &tri_vao);
   glBindVertexArray( tri_vao);
   glEnableVertexAttribArray( vpos_loc);
   glVertexAttribPointer( vpos_loc, 2, GL_FLOAT, GL_FALSE,
                          sizeof( Vertex), (void *) offsetof( Vertex, pos));
   glEnableVertexAttribArray( vcol_loc);
   glVertexAttribPointer( vcol_loc, 3, GL_FLOAT, GL_FALSE,
                          sizeof( Vertex), (void *) offsetof( Vertex, col));
   gl_check_errors( "triangle setup");

   glfwMakeContextCurrent( display);
   glfwSwapInterval( 1);

   fprintf( stderr, "[display]   GL renderer: %s | GL version: %s\n",
            glGetString( GL_RENDERER), glGetString( GL_VERSION));

   GLuint   quad_prog   = build_program( quad_vert_src, quad_frag_src, "quad");
   GLint    tex_loc     = glGetUniformLocation( quad_prog, "uTex");
   GLint    apos_loc    = glGetAttribLocation(  quad_prog, "aPos");
   GLint    atex_loc    = glGetAttribLocation(  quad_prog, "aTexCoord");

   GLuint   quad_vbo;
   glGenBuffers( 1, &quad_vbo);
   glBindBuffer( GL_ARRAY_BUFFER, quad_vbo);
   glBufferData( GL_ARRAY_BUFFER, sizeof( quad_verts), quad_verts, GL_STATIC_DRAW);

   GLuint   quad_vao;
   glGenVertexArrays( 1, &quad_vao);
   glBindVertexArray( quad_vao);
   glEnableVertexAttribArray( apos_loc);
   glVertexAttribPointer( apos_loc,  2, GL_FLOAT, GL_FALSE,
                          4 * sizeof( float), (void *) 0);
   glEnableVertexAttribArray( atex_loc);
   glVertexAttribPointer( atex_loc, 2, GL_FLOAT, GL_FALSE,
                          4 * sizeof( float), (void *) (2 * sizeof( float)));
   gl_check_errors( "quad setup");

   // Setup complete -- signal main thread we're up and running, exactly
   // like UIPureWindow's render thread signaling
   // UIWindowThreadLockConditionIdle before the main thread proceeds to
   // construct/add the next window.
   fprintf( stderr, "[thread] setup complete, signaling ready\n");
   signal_ready( pair);

   while( !glfwWindowShouldClose( display))
   {
      float   ratio = FBO_W / (float) FBO_H;

      glfwMakeContextCurrent( offscreen);

      glBindFramebuffer( GL_FRAMEBUFFER, render_fbo);
      glViewport( 0, 0, FBO_W, FBO_H);
      glClearColor( 0.f, 0.f, 0.f, 1.f);
      glClear( GL_COLOR_BUFFER_BIT);

      mat4x4   m, p, mvp;
      mat4x4_identity( m);
      mat4x4_rotate_Z( m, m, (float) glfwGetTime() * pair->rotation_speed);
      mat4x4_ortho( p, -ratio, ratio, -1.f, 1.f, 1.f, -1.f);
      mat4x4_mul( mvp, p, m);

      glUseProgram( tri_prog);
      glUniformMatrix4fv( mvp_loc, 1, GL_FALSE, (const GLfloat *) &mvp);
      glBindVertexArray( tri_vao);
      glDrawArrays( GL_TRIANGLES, 0, 3);

      if( msaa)
      {
         glBindFramebuffer( GL_READ_FRAMEBUFFER, msaa_fbo);
         glBindFramebuffer( GL_DRAW_FRAMEBUFFER, resolve_fbo);
         glBlitFramebuffer( 0, 0, FBO_W, FBO_H,
                            0, 0, FBO_W, FBO_H,
                            GL_COLOR_BUFFER_BIT, GL_NEAREST);
      }

      glFinish();

      glfwMakeContextCurrent( display);

      int   dw, dh;
      glfwGetFramebufferSize( display, &dw, &dh);
      glViewport( 0, 0, dw, dh);
      glClear( GL_COLOR_BUFFER_BIT);

      glUseProgram( quad_prog);
      glActiveTexture( GL_TEXTURE0);
      glBindTexture( GL_TEXTURE_2D, fbo_tex);
      glUniform1i( tex_loc, 0);
      glBindVertexArray( quad_vao);
      glDrawArrays( GL_TRIANGLE_STRIP, 0, 4);

      glfwSwapBuffers( display);
   }

   glfwMakeContextCurrent( NULL);
   return( NULL);
}


int main( int argc, char **argv)
{
   int   left_samples  = 4;
   int   right_samples = 0;
   int   compare       = 0;
   int   context_api   = 0;

   for( int i = 1; i < argc; i++)
   {
      if( !strcmp( argv[ i], "--samples") && i + 1 < argc)
         left_samples = right_samples = atoi( argv[ ++i]);
      else if( !strncmp( argv[ i], "--samples=", 10))
         left_samples = right_samples = atoi( argv[ i] + 10);
      else if( !strcmp( argv[ i], "--compare"))
         compare = 1;
      else if( !strcmp( argv[ i], "--native"))
         context_api = GLFW_NATIVE_CONTEXT_API;
      else if( !strcmp( argv[ i], "--egl"))
         context_api = GLFW_EGL_CONTEXT_API;
      else if( !strcmp( argv[ i], "--mesa"))
         context_api = GLFW_OSMESA_CONTEXT_API;
      else
      {
         fprintf( stderr,
                  "Usage: %s [options]\n"
                  "  --samples N        : MSAA for both windows\n"
                  "  --compare          : same geometry both sides\n"
                  "  --native / --egl / --mesa\n",
                  argv[ 0]);
         exit( EXIT_FAILURE);
      }
   }

   fprintf( stderr,
            "ORDERED variant: pair 1 fully created + thread started + "
            "confirmed running BEFORE pair 2 is created (matches "
            "UIPureWindow's actual sequence, unlike main-two-x-two-windows.m "
            "which creates both pairs upfront before starting either thread)\n");

   glfwSetErrorCallback( error_callback);

   if( !glfwInit())
      exit( EXIT_FAILURE);

   glfwWindowHint( GLFW_CONTEXT_VERSION_MAJOR, 3);
   glfwWindowHint( GLFW_CONTEXT_VERSION_MINOR, 3);
   glfwWindowHint( GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
   if( context_api != GLFW_OSMESA_CONTEXT_API)
      glfwWindowHint( GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE);
   if( context_api)
      glfwWindowHint( GLFW_CONTEXT_CREATION_API, context_api);

   struct WindowPair   pair1 = { 0 };
   struct WindowPair   pair2 = { 0 };

   pthread_mutex_init( &pair1.ready_mutex, NULL);
   pthread_cond_init(  &pair1.ready_cond,  NULL);
   pthread_mutex_init( &pair2.ready_mutex, NULL);
   pthread_cond_init(  &pair2.ready_cond,  NULL);

   // ---- Pair 1: create windows, start thread, BLOCK until it's running ----
   glfwWindowHint( GLFW_VISIBLE, GLFW_FALSE);
   GLFWwindow *offscreen1 = glfwCreateWindow( FBO_W, FBO_H, "", NULL, NULL);
   if( !offscreen1)
   {
      glfwTerminate();
      exit( EXIT_FAILURE);
   }

   glfwWindowHint( GLFW_VISIBLE, GLFW_TRUE);
   GLFWwindow *display1 = glfwCreateWindow( FBO_W, FBO_H,
                              compare ? "Left" : "Thread 1 - RGB (ordered)",
                              NULL, offscreen1);
   if( !display1)
   {
      glfwDestroyWindow( offscreen1);
      glfwTerminate();
      exit( EXIT_FAILURE);
   }

   pair1.offscreen      = offscreen1;
   pair1.display        = display1;
   pair1.vertices        = vertices_1;
   pair1.rotation_speed  = 1.0f;
   pair1.samples         = left_samples;

   pthread_t   thread1;
   pthread_create( &thread1, NULL, render_thread, &pair1);

   fprintf( stderr, "[main] waiting for pair 1's render thread to be ready...\n");
   wait_ready( &pair1);
   fprintf( stderr, "[main] pair 1 ready. NOW creating pair 2's GLFW windows "
                    "while pair 1's thread is already active.\n");

   // ---- Pair 2: created only now, while pair 1's thread is already running ----
   glfwWindowHint( GLFW_VISIBLE, GLFW_FALSE);
   GLFWwindow *offscreen2 = glfwCreateWindow( FBO_W, FBO_H, "", NULL, NULL);
   if( !offscreen2)
   {
      glfwSetWindowShouldClose( display1, GLFW_TRUE);
      pthread_join( thread1, NULL);
      glfwTerminate();
      exit( EXIT_FAILURE);
   }

   glfwWindowHint( GLFW_VISIBLE, GLFW_TRUE);
   GLFWwindow *display2 = glfwCreateWindow( FBO_W, FBO_H,
                              compare ? "Right" : "Thread 2 - CMY (ordered)",
                              NULL, offscreen2);
   if( !display2)
   {
      glfwDestroyWindow( offscreen2);
      glfwSetWindowShouldClose( display1, GLFW_TRUE);
      pthread_join( thread1, NULL);
      glfwTerminate();
      exit( EXIT_FAILURE);
   }

   {
      int   xpos, ypos, width;

      glfwGetWindowPos( display1, &xpos, &ypos);
      glfwGetWindowSize( display1, &width, NULL);
      glfwSetWindowPos( display2, xpos + width + 32, ypos);
   }

   pair2.offscreen      = offscreen2;
   pair2.display        = display2;
   pair2.vertices        = compare ? vertices_1 : vertices_2;
   pair2.rotation_speed  = compare ? 1.0f : -0.7f;
   pair2.samples         = right_samples;

   pthread_t   thread2;
   pthread_create( &thread2, NULL, render_thread, &pair2);

   fprintf( stderr, "[main] waiting for pair 2's render thread to be ready...\n");
   wait_ready( &pair2);
   fprintf( stderr, "[main] pair 2 ready. Entering main event loop.\n");

   while( !glfwWindowShouldClose( display1) && !glfwWindowShouldClose( display2))
      glfwPollEvents();

   glfwSetWindowShouldClose( display1, GLFW_TRUE);
   glfwSetWindowShouldClose( display2, GLFW_TRUE);

   pthread_join( thread1, NULL);
   pthread_join( thread2, NULL);

   glfwDestroyWindow( display2);
   glfwDestroyWindow( offscreen2);
   glfwDestroyWindow( display1);
   glfwDestroyWindow( offscreen1);
   glfwTerminate();
   exit( EXIT_SUCCESS);
}

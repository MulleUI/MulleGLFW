//
// Two window-pairs, each pair rendered in its own pthread.
//
// Each pair consists of:
//   offscreen window  - hidden (GLFW_VISIBLE=FALSE), renders into an FBO
//   display window    - visible, blits the FBO result to screen
//
// The render thread per pair:
//   1. Render triangle into an FBO in the offscreen context.
//      If --samples N > 1: render into a multisample FBO, then resolve
//      via glBlitFramebuffer into a regular FBO whose texture is shared.
//      If samples <= 1: render directly into the shared-texture FBO.
//   2. Switch to display context, draw a fullscreen quad sampling the
//      shared (resolved) texture, then SwapBuffers.
//
// GLFW rule: window creation and glfwPollEvents must stay on the main thread.
// GL objects that ARE shared across a context share group: textures, buffer
// objects, programs/shaders.  Objects that are NOT shared: VAOs, FBOs.
//
// Usage: two-x-two-windows [--samples N]   (default 4, 0/1 = off)
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


#define FBO_W   640
#define FBO_H   480


typedef struct Vertex
{
   vec2   pos;
   vec3   col;
} Vertex;

// Pair 1: classic RGB triangle
static const Vertex   vertices_1[ 3] =
{
   { { -0.6f, -0.4f }, { 1.f, 0.f, 0.f } },
   { {  0.6f, -0.4f }, { 0.f, 1.f, 0.f } },
   { {  0.0f,  0.6f }, { 0.f, 0.f, 1.f } }
};

// Pair 2: CMY triangle, spins the other way
static const Vertex   vertices_2[ 3] =
{
   { { -0.6f, -0.4f }, { 0.f, 1.f, 1.f } },
   { {  0.6f, -0.4f }, { 1.f, 0.f, 1.f } },
   { {  0.0f,  0.6f }, { 1.f, 1.f, 0.f } }
};


// --- Triangle shader (renders into FBO in offscreen context) ---

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


// --- Fullscreen quad shader (blits FBO texture to display context) ---

// positions in NDC + texcoords, interleaved: x y u v
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
   GLFWwindow     *offscreen;  // hidden, renders into FBO
   GLFWwindow     *display;    // visible, blits FBO texture to screen
   const Vertex   *vertices;
   float           rotation_speed;
   int             samples;    // MSAA sample count: 0/1 = off, 2/4/8/16 = on
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


static void *render_thread( void *arg)
{
   struct WindowPair   *pair      = arg;
   GLFWwindow          *offscreen = pair->offscreen;
   GLFWwindow          *display   = pair->display;

   // ------------------------------------------------------------------ setup
   // Activate offscreen context first — this is where we render the triangle.
   glfwMakeContextCurrent( offscreen);

#ifdef HAVE_GLAD
   gladLoadGL( glfwGetProcAddress);
#endif

   // Sanity-check: if glGetString returns NULL the context is not functional.
   // With OSMesa (--mesa), GLFW creates the context fine but libGL's GLX/EGL
   // TLS dispatch doesn't route to it — you need GLAD or glfwGetProcAddress
   // to load function pointers from the OSMesa context.
   if( !glGetString( GL_VERSION))
   {
      fprintf( stderr,
               "ERROR: GL context is not functional (glGetString returned NULL).\n"
               "       OSMesa contexts require function pointers loaded via\n"
               "       glfwGetProcAddress/GLAD — direct libGL calls don't\n"
               "       route through OSMesa's context dispatch.\n"
               "       Build this demo with GLAD (HAVE_GLAD) for --mesa support.\n");
      return( NULL);
   }

   fprintf( stderr, "[offscreen] GL renderer: %s | GL version: %s | samples: %d\n",
            glGetString( GL_RENDERER), glGetString( GL_VERSION), pair->samples);

   int   msaa = (pair->samples > 1);

   // -- Shared resolve texture (regular GL_TEXTURE_2D, visible in display ctx)
   GLuint   fbo_tex;
   glGenTextures( 1, &fbo_tex);
   glBindTexture( GL_TEXTURE_2D, fbo_tex);
   glTexImage2D( GL_TEXTURE_2D, 0, GL_RGBA, FBO_W, FBO_H, 0,
                 GL_RGBA, GL_UNSIGNED_BYTE, NULL);
   glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
   glTexParameteri( GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
   gl_check_errors( "resolve texture");

   // -- Resolve FBO (always present; display context reads from its texture)
   GLuint   resolve_fbo;
   glGenFramebuffers( 1, &resolve_fbo);
   glBindFramebuffer( GL_FRAMEBUFFER, resolve_fbo);
   glFramebufferTexture2D( GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                           GL_TEXTURE_2D, fbo_tex, 0);
   check_fbo( "resolve_fbo");

   // -- MSAA FBO (only when samples > 1)
   //    GL_TEXTURE_2D_MULTISAMPLE can't be sampled with sampler2D, so we
   //    always resolve into fbo_tex via glBlitFramebuffer.
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

   // render_fbo is where we actually draw the triangle
   GLuint   render_fbo = msaa ? msaa_fbo : resolve_fbo;

   // -- Triangle program + geometry (in offscreen context)
   GLuint   tri_prog    = build_program( tri_vert_src, tri_frag_src, "triangle");
   GLint    mvp_loc     = glGetUniformLocation( tri_prog, "MVP");
   GLint    vpos_loc    = glGetAttribLocation(  tri_prog, "vPos");
   GLint    vcol_loc    = glGetAttribLocation(  tri_prog, "vCol");

   GLuint   tri_vbo;
   glGenBuffers( 1, &tri_vbo);
   glBindBuffer( GL_ARRAY_BUFFER, tri_vbo);
   glBufferData( GL_ARRAY_BUFFER, sizeof( Vertex) * 3, pair->vertices, GL_STATIC_DRAW);

   // VAOs are NOT shared — create one per context
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

   // -- Switch to display context and set up the blit quad
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

   // ---------------------------------------------------------------- render loop
   while( !glfwWindowShouldClose( display))
   {
      float   ratio = FBO_W / (float) FBO_H;

      // 1. Render triangle into FBO (offscreen context)
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

      // Resolve MSAA into the shared texture if needed
      if( msaa)
      {
         glBindFramebuffer( GL_READ_FRAMEBUFFER, msaa_fbo);
         glBindFramebuffer( GL_DRAW_FRAMEBUFFER, resolve_fbo);
         glBlitFramebuffer( 0, 0, FBO_W, FBO_H,
                            0, 0, FBO_W, FBO_H,
                            GL_COLOR_BUFFER_BIT, GL_NEAREST);
      }

      // Flush so the texture is fully written before the display context reads it
      glFinish();

      // 2. Blit FBO texture to display window
      glfwMakeContextCurrent( display);

      int   dw, dh;
      glfwGetFramebufferSize( display, &dw, &dh);
      glViewport( 0, 0, dw, dh);
      glClear( GL_COLOR_BUFFER_BIT);

      glUseProgram( quad_prog);
      glActiveTexture( GL_TEXTURE0);
      glBindTexture( GL_TEXTURE_2D, fbo_tex);  // shared texture
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
   int   left_samples  = 4;  // MSAA for left/pair1;  0/1 = off
   int   right_samples = 0;  // MSAA for right/pair2; 0/1 = off
   int   compare       = 0;  // --compare: same geometry both sides
   int   context_api   = 0;  // 0=default, GLFW_NATIVE_CONTEXT_API, GLFW_EGL_CONTEXT_API, GLFW_OSMESA_CONTEXT_API

   for( int i = 1; i < argc; i++)
   {
      if( !strcmp( argv[ i], "--samples") && i + 1 < argc)
      {
         left_samples = right_samples = atoi( argv[ ++i]);
      }
      else if( !strncmp( argv[ i], "--samples=", 10))
      {
         left_samples = right_samples = atoi( argv[ i] + 10);
      }
      else if( !strcmp( argv[ i], "--left-samples") && i + 1 < argc)
      {
         left_samples = atoi( argv[ ++i]);
      }
      else if( !strncmp( argv[ i], "--left-samples=", 15))
      {
         left_samples = atoi( argv[ i] + 15);
      }
      else if( !strcmp( argv[ i], "--right-samples") && i + 1 < argc)
      {
         right_samples = atoi( argv[ ++i]);
      }
      else if( !strncmp( argv[ i], "--right-samples=", 16))
      {
         right_samples = atoi( argv[ i] + 16);
      }
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
                  "  --left-samples N   : MSAA for left  window (default 4)\n"
                  "  --right-samples N  : MSAA for right window (default 0)\n"
                  "  --samples N        : MSAA for both windows\n"
                  "  --compare          : same geometry both sides\n"
                  "  --native           : use native GL context API\n"
                  "  --egl              : use EGL context API\n"
                  "  --mesa             : use OSMesa (software) context API\n",
                  argv[ 0]);
         exit( EXIT_FAILURE);
      }
   }

   {
      const char   *api_name = "default";
      if( context_api == GLFW_NATIVE_CONTEXT_API)  api_name = "native";
      if( context_api == GLFW_EGL_CONTEXT_API)     api_name = "egl";
      if( context_api == GLFW_OSMESA_CONTEXT_API)  api_name = "mesa (software)";

      fprintf( stderr, "context API: %s | left samples: %d | right samples: %d%s\n",
               api_name, left_samples, right_samples,
               compare ? " | compare mode (same geometry)" : "");
   }

   glfwSetErrorCallback( error_callback);

   if( !glfwInit())
      exit( EXIT_FAILURE);

   glfwWindowHint( GLFW_CONTEXT_VERSION_MAJOR, 3);
   glfwWindowHint( GLFW_CONTEXT_VERSION_MINOR, 3);
   glfwWindowHint( GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
   // required on macOS; OSMesa doesn't support it so skip when using mesa
   if( context_api != GLFW_OSMESA_CONTEXT_API)
      glfwWindowHint( GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE);

   if( context_api)
      glfwWindowHint( GLFW_CONTEXT_CREATION_API, context_api);

   // ---- Pair 1 ----
   // Create offscreen window first (invisible), then display sharing with it.
   glfwWindowHint( GLFW_VISIBLE, GLFW_FALSE);
   GLFWwindow *offscreen1 = glfwCreateWindow( FBO_W, FBO_H, "", NULL, NULL);
   if( !offscreen1)
   {
      glfwTerminate();
      exit( EXIT_FAILURE);
   }

   glfwWindowHint( GLFW_VISIBLE, GLFW_TRUE);
   GLFWwindow *display1 = glfwCreateWindow( FBO_W, FBO_H,
                              compare ? "Left"
                                      : "Thread 1 - RGB (offscreen→display)",
                              NULL, offscreen1);
   if( !display1)
   {
      glfwDestroyWindow( offscreen1);
      glfwTerminate();
      exit( EXIT_FAILURE);
   }

   // ---- Pair 2 ----
   glfwWindowHint( GLFW_VISIBLE, GLFW_FALSE);
   GLFWwindow *offscreen2 = glfwCreateWindow( FBO_W, FBO_H, "", NULL, NULL);
   if( !offscreen2)
   {
      glfwDestroyWindow( display1);
      glfwDestroyWindow( offscreen1);
      glfwTerminate();
      exit( EXIT_FAILURE);
   }

   glfwWindowHint( GLFW_VISIBLE, GLFW_TRUE);
   GLFWwindow *display2 = glfwCreateWindow( FBO_W, FBO_H,
                              compare ? "Right"
                                      : "Thread 2 - CMY (offscreen→display)",
                              NULL, offscreen2);
   if( !display2)
   {
      glfwDestroyWindow( offscreen2);
      glfwDestroyWindow( display1);
      glfwDestroyWindow( offscreen1);
      glfwTerminate();
      exit( EXIT_FAILURE);
   }

   // Place display2 to the right of display1
   {
      int   xpos, ypos, width;

      glfwGetWindowPos( display1, &xpos, &ypos);
      glfwGetWindowSize( display1, &width, NULL);
      glfwSetWindowPos( display2, xpos + width + 32, ypos);
   }

   // Update titles to reflect actual sample counts
   {
      char   buf[ 128];

      if( compare)
      {
         snprintf( buf, sizeof( buf), "Left  — %s",
                   left_samples  > 1 ? "MSAA" : "no MSAA");
         glfwSetWindowTitle( display1, buf);

         snprintf( buf, sizeof( buf), "Right — %s",
                   right_samples > 1 ? "MSAA" : "no MSAA");
         glfwSetWindowTitle( display2, buf);
      }
   }

   struct WindowPair   pair1 = { offscreen1, display1, vertices_1,                    1.0f, left_samples  };
   struct WindowPair   pair2 = { offscreen2, display2,
                                 compare ? vertices_1 : vertices_2,
                                 compare ?       1.0f : -0.7f,
                                 right_samples };

   pthread_t   thread1, thread2;
   pthread_create( &thread1, NULL, render_thread, &pair1);
   pthread_create( &thread2, NULL, render_thread, &pair2);

   // Main thread: poll events (GLFW requirement) until both display windows close.
   while( !glfwWindowShouldClose( display1) && !glfwWindowShouldClose( display2))
      glfwPollEvents();

   // Signal both render threads to stop
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

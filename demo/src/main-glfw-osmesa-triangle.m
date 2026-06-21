//
// glfw-osmesa-triangle — spinning triangle using MulleGLFW + OSMesa blit.
//
// PURPOSE
//   This is the "integration demo": it is the first demo in the series that
//   uses MulleGLFW's Objective-C API (GLFWOSWindow / UIApplication) together
//   with OSMesa software rendering, instead of calling GLFW / X11 / Wayland
//   directly.
//
//   The previous demos in the series built up knowledge step by step:
//     x11-osmesa               — raw X11 + OSMesa, no GLFW at all
//     glfw-x11-osmesa          — GLFW_NO_API window + manual OSMesa + XPutImage
//     glfw-x11-osmesa-grok     — GLFW-managed OSMesa context + XPutImage
//     glfw-wayland-osmesa      — GLFW Wayland + OSMesa + wl_shm blit
//
//   This demo hands the blit responsibility to the MulleGLFW library itself.
//   GLFWOSWindow.os_swapBuffers now detects GLFW_OSMESA_CONTEXT_API at runtime
//   and performs the XPutImage / wl_shm blit automatically — so this demo
//   just calls [window os_swapBuffers] like any normal GL window and it works
//   on both X11 and Wayland.
//
// HOW IT WORKS
//   1. graphicsHints = GLFWGraphicsHintsMake(core, noFwd, OpenGL, mesa, 3, 3)
//      — lib=3 maps to GLFW_OSMESA_CONTEXT_API inside GLFWOSWindow.
//   2. [window os_activateGraphicsContext] — locks the context for this thread.
//   3. Normal GL draw calls (no GLAD needed — we link -lOSMesa directly so
//      gl* symbols resolve to OSMesa at link time).
//   4. glFinish() — ensures OSMesa pixels are ready before the blit.
//   5. [window os_swapBuffers] — library blits RGBA → XRGB8888 into the
//      native window (XPutImage on X11, wl_shm on Wayland).
//   6. [window os_deactivateGraphicsContext] — unlocks the context.
//
// WHAT IS NOT NEEDED HERE (vs. standalone demos)
//   - No #include <X11/Xlib.h> or <wayland-client.h>
//   - No XImage / XPutImage / wl_shm setup
//   - No GLAD / glfwGetProcAddress
//   - No manual OSMesaCreateContextAttribs
//
// BUILD / RUN
//   mulle-sde run glfw-osmesa-triangle
//   mulle-sde run glfw-osmesa-triangle -- --width 1024 --height 768
//
#define GL_GLEXT_PROTOTYPES
#include <GL/osmesa.h>   // must come before GLFW to resolve gl* via OSMesa

#import "import.h"

#include <GLFW/glfw3.h>

// linmath.h is bundled with GLFW stash
#include "linmath.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <math.h>


// ---------------------------------------------------------------------------
// Tiny timer
// ---------------------------------------------------------------------------
static double now_sec( void)
{
   struct timespec ts;
   clock_gettime( CLOCK_MONOTONIC, &ts);
   return( (double) ts.tv_sec + (double) ts.tv_nsec * 1e-9);
}


// ---------------------------------------------------------------------------
// GL helpers
// ---------------------------------------------------------------------------
static void gl_check_errors( const char *where)
{
   GLenum e;
   while( (e = glGetError()) != GL_NO_ERROR)
      fprintf( stderr, "GL error at %s: 0x%x\n", where, e);
}

static GLuint compile_shader( GLenum type, const char *src)
{
   GLuint s = glCreateShader( type);
   glShaderSource( s, 1, (const GLchar * const *) &src, NULL);
   glCompileShader( s);

   GLint ok;
   glGetShaderiv( s, GL_COMPILE_STATUS, &ok);
   if( ! ok)
   {
      char buf[512];
      glGetShaderInfoLog( s, sizeof( buf), NULL, buf);
      fprintf( stderr, "Shader compile error: %s\n", buf);
      glDeleteShader( s);
      return( 0);
   }
   return( s);
}

static GLuint build_program( const char *vert_src, const char *frag_src)
{
   GLuint vs = compile_shader( GL_VERTEX_SHADER,   vert_src);
   GLuint fs = compile_shader( GL_FRAGMENT_SHADER, frag_src);
   GLuint p  = glCreateProgram();
   glAttachShader( p, vs);
   glAttachShader( p, fs);
   glLinkProgram( p);

   GLint ok;
   glGetProgramiv( p, GL_LINK_STATUS, &ok);
   if( ! ok)
   {
      char buf[512];
      glGetProgramInfoLog( p, sizeof( buf), NULL, buf);
      fprintf( stderr, "Program link error: %s\n", buf);
   }
   glDeleteShader( vs);
   glDeleteShader( fs);
   return( p);
}


// ---------------------------------------------------------------------------
// Shaders and geometry (same as standalone demos)
// ---------------------------------------------------------------------------
static const char *vert_src =
   "#version 330 core\n"
   "uniform mat4 mvp;\n"
   "layout(location=0) in vec3 pos;\n"
   "layout(location=1) in vec3 col;\n"
   "out vec3 vCol;\n"
   "void main() { vCol = col; gl_Position = mvp * vec4(pos, 1.0); }\n";

static const char *frag_src =
   "#version 330 core\n"
   "in vec3 vCol;\n"
   "out vec4 fragColor;\n"
   "void main() { fragColor = vec4(vCol, 1.0); }\n";

static const float vertices[] = {
   // x      y      z      r     g     b
   -0.6f, -0.4f,  0.0f,  1.0f, 0.0f, 0.0f,
    0.6f, -0.4f,  0.0f,  0.0f, 1.0f, 0.0f,
    0.0f,  0.6f,  0.0f,  0.0f, 0.0f, 1.0f,
};


// ---------------------------------------------------------------------------
// Key callback
// ---------------------------------------------------------------------------
static void key_callback( GLFWwindow *window, int key, int scancode,
                           int action, int mods)
{
   (void) scancode; (void) mods;
   if( action == GLFW_PRESS && (key == GLFW_KEY_ESCAPE || key == GLFW_KEY_Q))
      glfwSetWindowShouldClose( window, GLFW_TRUE);
}


// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------
int main( int argc, char **argv)
{
   int   width   = 800;
   int   height  = 600;

   for( int i = 1; i < argc; i++)
   {
      if( ! strcmp( argv[i], "--width")  && i + 1 < argc) width  = atoi( argv[++i]);
      else if( ! strcmp( argv[i], "--height") && i + 1 < argc) height = atoi( argv[++i]);
      else
      {
         fprintf( stderr,
                  "Usage: %s [--width N] [--height N]\n"
                  "  OSMesa (software rendering) is always used.\n"
                  "  The blit to the native window is handled by MulleGLFW.\n",
                  argv[0]);
         return( 1);
      }
   }

   UIApplication  *app    = [UIApplication sharedInstance];
   GLFWOSWindow   *gWindow;

   @autoreleasepool
   {
      //
      // graphicsHints: profile=core(2), forward=0, api=OpenGL(3), lib=OSMesa(3), major=3, minor=3
      GLFWGraphicsHints  hints = { .profile = 2, .api = 3, .lib = 3, .major = 3, .minor = 3 };

      gWindow = [[[GLFWOSWindow alloc]
                        initWithFrame:CGRectMake( 0.0, 0.0, width, height)
                      titleUTF8String:"OSMesa Triangle (MulleGLFW)"
                            styleMask:UIWindowStyleBare | UIWindowStyleResizable
                        graphicsHints:hints] autorelease];

      if( ! gWindow)
      {
         fprintf( stderr, "Failed to create GLFWOSWindow with OSMesa context\n");
         return( [app terminate]);
      }

      GLFWwindow *window = [gWindow os_window];
      glfwSetKeyCallback( window, key_callback);

      // Activate context on this thread
      [gWindow os_activateGraphicsContext];

      // Confirm OSMesa is actually active
      const GLubyte *renderer = glGetString( GL_RENDERER);
      const GLubyte *version  = glGetString( GL_VERSION);
      if( ! renderer)
      {
         fprintf( stderr, "GL context is not functional — "
                  "OSMesa symbols may not have resolved correctly.\n"
                  "Ensure this binary links -lOSMesa before -lGL.\n");
         [gWindow os_deactivateGraphicsContext];
         return( [app terminate]);
      }
      printf( "GL renderer : %s\n", renderer);
      printf( "GL version  : %s\n", version);

      // OSMesa top-down Y order (matches X11 / Wayland scanline order)
      OSMesaPixelStore( OSMESA_Y_UP, 0);

      // Build GL objects
      GLuint prog    = build_program( vert_src, frag_src);
      GLint  mvp_loc = glGetUniformLocation( prog, "mvp");

      GLuint vao, vbo;
      glGenVertexArrays( 1, &vao);
      glGenBuffers( 1, &vbo);
      glBindVertexArray( vao);
      glBindBuffer( GL_ARRAY_BUFFER, vbo);
      glBufferData( GL_ARRAY_BUFFER, sizeof( vertices), vertices, GL_STATIC_DRAW);
      glEnableVertexAttribArray( 0);
      glVertexAttribPointer( 0, 3, GL_FLOAT, GL_FALSE, 6 * sizeof( float), (void *) 0);
      glEnableVertexAttribArray( 1);
      glVertexAttribPointer( 1, 3, GL_FLOAT, GL_FALSE, 6 * sizeof( float),
                             (void *) (3 * sizeof( float)));
      gl_check_errors( "GL setup");

      [gWindow os_deactivateGraphicsContext];

      // ---- render loop ----
      double t0 = now_sec();

      while( ! glfwWindowShouldClose( window))
      {
         glfwPollEvents();

         [gWindow os_activateGraphicsContext];

         double angle = now_sec() - t0;
         glViewport( 0, 0, width, height);
         glClearColor( 0.15f, 0.15f, 0.15f, 1.0f);
         glClear( GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

         mat4x4 m, p, mvp;
         mat4x4_identity( m);
         mat4x4_rotate_Z( m, m, (float) angle);
         float ratio = (float) width / (float) height;
         mat4x4_ortho( p, -ratio, ratio, -1.f, 1.f, 1.f, -1.f);
         mat4x4_mul( mvp, p, m);

         glUseProgram( prog);
         glUniformMatrix4fv( mvp_loc, 1, GL_FALSE, (const float *) mvp);
         glBindVertexArray( vao);
         glDrawArrays( GL_TRIANGLES, 0, 3);

         // glFinish ensures OSMesa has written all pixels before the blit
         glFinish();

         // MulleGLFW handles the blit: RGBA → XRGB8888 → XPutImage or wl_shm
         [gWindow os_swapBuffers];

         [gWindow os_deactivateGraphicsContext];
      }

      [gWindow os_activateGraphicsContext];
      glDeleteVertexArrays( 1, &vao);
      glDeleteBuffers( 1, &vbo);
      glDeleteProgram( prog);
      [gWindow os_deactivateGraphicsContext];

      [gWindow os_destroyWindow];
   }

   return( [app terminate]);
}

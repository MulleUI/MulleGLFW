//
// glfw-x11-osmesa — GLFW window + OSMesa context, no GLX/EGL.
//
// PURPOSE
//   One step up from x11-osmesa: GLFW now owns the window and the event loop,
//   but the GL context is still OSMesa (software, CPU buffer).  This tests
//   whether GLFW's window management can be decoupled from its context
//   management — i.e. can we use GLFW just as a "create a window and poll
//   events" layer while wiring in our own GL backend?
//
//   The answer is yes: create the GLFW window with GLFW_CLIENT_API=GLFW_NO_API
//   so GLFW does not touch GL at all, then retrieve the underlying X11 Display
//   and Window via glfw3native.h and use XPutImage to blit the OSMesa pixel
//   buffer exactly as x11-osmesa does.
//
// HOW IT WORKS
//   1. glfwInit() + glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API)
//      GLFW creates an X11 window with no GL/EGL context.
//   2. OSMesaCreateContextAttribs() creates a software GL 3.3 Core context
//      backed by llvmpipe.  OSMesaMakeCurrent() binds it to our CPU buffer.
//   3. glfwGetX11Display() / glfwGetX11Window() retrieve the native handles
//      so we can call XPutImage each frame.
//   4. glfwPollEvents() drives the event loop; glfwWindowShouldClose() and
//      a key callback handle exit.
//
//   Because GLFW_CLIENT_API=GLFW_NO_API, GLFW never calls any GL function —
//   so there is no GLX/EGL TLS context in play and no dispatch confusion.
//   OSMesa's GL calls go directly to the OSMesa context via -lOSMesa symbols.
//   No GLAD / proc-address loader is needed (unlike the GLFW_OSMESA_CONTEXT_API
//   path where libGL.so dispatches through GLX TLS and misses OSMesa).
//
// BUILD
//   Linked with: -lOSMesa -lX11  (MulleGLFW / libglfw pulled in as usual)
//   Define GLFW_EXPOSE_NATIVE_X11 before including glfw3native.h.
//
// RUN
//   glfw-x11-osmesa [--width W] [--height H]
//   Close with Escape, Q, or the window's close button.
//

// OSMesa provides the OpenGL implementation directly; osmesa.h pulls in GL/gl.h.
// GL_GLEXT_PROTOTYPES exposes glext.h function prototypes without a loader.
#define GL_GLEXT_PROTOTYPES
#include <GL/osmesa.h>
#include <GL/glext.h>

// GLFW: no GL context, just a window.
#define GLFW_INCLUDE_NONE
#include <GLFW/glfw3.h>

// Expose glfwGetX11Display / glfwGetX11Window.
#define GLFW_EXPOSE_NATIVE_X11
#include <GLFW/glfw3native.h>

// We still need XPutImage / XCreateImage / GC.
#include <X11/Xlib.h>
#include <X11/Xutil.h>

#include "linmath.h"

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <time.h>


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
   glShaderSource( s, 1, &src, NULL);
   glCompileShader( s);
   GLint ok;
   glGetShaderiv( s, GL_COMPILE_STATUS, &ok);
   if( !ok)
   {
      char buf[ 512];
      glGetShaderInfoLog( s, sizeof buf, NULL, buf);
      fprintf( stderr, "Shader compile error: %s\n", buf);
   }
   return s;
}

static GLuint build_program( const char *vert_src, const char *frag_src)
{
   GLuint prog = glCreateProgram();
   GLuint vs   = compile_shader( GL_VERTEX_SHADER,   vert_src);
   GLuint fs   = compile_shader( GL_FRAGMENT_SHADER, frag_src);
   glAttachShader( prog, vs);
   glAttachShader( prog, fs);
   glLinkProgram( prog);
   GLint ok;
   glGetProgramiv( prog, GL_LINK_STATUS, &ok);
   if( !ok)
   {
      char buf[ 512];
      glGetProgramInfoLog( prog, sizeof buf, NULL, buf);
      fprintf( stderr, "Program link error: %s\n", buf);
   }
   glDeleteShader( vs);
   glDeleteShader( fs);
   return prog;
}


// ---------------------------------------------------------------------------
// Shaders
// ---------------------------------------------------------------------------

static const char *vert_src =
   "#version 330 core\n"
   "layout(location=0) in vec2 pos;\n"
   "layout(location=1) in vec3 col;\n"
   "uniform mat4 mvp;\n"
   "out vec3 vCol;\n"
   "void main(){\n"
   "  gl_Position = mvp * vec4(pos, 0.0, 1.0);\n"
   "  vCol = col;\n"
   "}\n";

static const char *frag_src =
   "#version 330 core\n"
   "in vec3 vCol;\n"
   "out vec4 fragColor;\n"
   "void main(){ fragColor = vec4(vCol, 1.0); }\n";

// triangle: position (x,y) + color (r,g,b)
static const float vertices[] = {
   -0.6f, -0.4f,   1.f, 0.f, 0.f,
    0.6f, -0.4f,   0.f, 1.f, 0.f,
    0.0f,  0.6f,   0.f, 0.f, 1.f,
};


// ---------------------------------------------------------------------------
// Tiny timer
// ---------------------------------------------------------------------------

static double now_sec(void)
{
   struct timespec ts;
   clock_gettime( CLOCK_MONOTONIC, &ts);
   return ts.tv_sec + ts.tv_nsec * 1e-9;
}


// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

static void key_callback( GLFWwindow *win, int key, int scancode, int action, int mods)
{
   (void) scancode; (void) mods;
   if( action == GLFW_PRESS && (key == GLFW_KEY_ESCAPE || key == GLFW_KEY_Q))
      glfwSetWindowShouldClose( win, GLFW_TRUE);
}

int  main( int argc, char **argv)
{
   int   width   = 800;
   int   height  = 600;

   for( int i = 1; i < argc; i++)
   {
      if( !strcmp( argv[i], "--width") && i + 1 < argc)
         width = atoi( argv[ ++i]);
      else if( !strcmp( argv[i], "--height") && i + 1 < argc)
         height = atoi( argv[ ++i]);
      else
      {
         fprintf( stderr, "Usage: %s [--width W] [--height H]\n", argv[0]);
         return 1;
      }
   }

   // ---- GLFW window (no GL context) ----
   if( !glfwInit())
   {
      fprintf( stderr, "glfwInit failed\n");
      return 1;
   }

   glfwWindowHint( GLFW_CLIENT_API, GLFW_NO_API);   // do NOT create a GL context
   glfwWindowHint( GLFW_RESIZABLE,  GLFW_FALSE);

   GLFWwindow *glfw_win = glfwCreateWindow( width, height,
                                            "GLFW + OSMesa (no GLX/EGL)",
                                            NULL, NULL);
   if( !glfw_win)
   {
      fprintf( stderr, "glfwCreateWindow failed\n");
      glfwTerminate();
      return 1;
   }

   glfwSetKeyCallback( glfw_win, key_callback);

   // Retrieve the native X11 handles GLFW created for us.
   Display *dpy = glfwGetX11Display();
   Window   win = glfwGetX11Window( glfw_win);
   int      screen = DefaultScreen( dpy);

   // ---- OSMesa context ----
   int attribs[] = {
      OSMESA_FORMAT,                OSMESA_BGRA,
      OSMESA_DEPTH_BITS,            24,
      OSMESA_STENCIL_BITS,          8,
      OSMESA_PROFILE,               OSMESA_CORE_PROFILE,
      OSMESA_CONTEXT_MAJOR_VERSION, 3,
      OSMESA_CONTEXT_MINOR_VERSION, 3,
      0
   };
   OSMesaContext ctx = OSMesaCreateContextAttribs( attribs, NULL);
   if( !ctx)
   {
      fprintf( stderr, "OSMesaCreateContextAttribs failed\n");
      return 1;
   }

   // CPU pixel buffer (BGRA, 4 bytes/pixel)
   size_t buf_bytes = (size_t) width * height * 4;
   unsigned char *pixels = malloc( buf_bytes);
   if( !pixels)
   {
      fprintf( stderr, "Out of memory\n");
      return 1;
   }

   if( !OSMesaMakeCurrent( ctx, pixels, GL_UNSIGNED_BYTE, width, height))
   {
      fprintf( stderr, "OSMesaMakeCurrent failed\n");
      return 1;
   }

   // OSMesa renders bottom-up by default; flip Y to match X11 top-down.
   OSMesaPixelStore( OSMESA_Y_UP, 0);

   // Verify the context is functional
   const GLubyte *ver = glGetString( GL_VERSION);
   if( !ver)
   {
      fprintf( stderr, "OSMesa context not functional\n");
      return 1;
   }

   fprintf( stdout, "GL renderer : %s\n", glGetString( GL_RENDERER));
   fprintf( stdout, "GL version  : %s\n", glGetString( GL_VERSION));

   // ---- GL setup ----
   GLuint prog = build_program( vert_src, frag_src);
   GLint  mvp_loc = glGetUniformLocation( prog, "mvp");

   GLuint vao, vbo;
   glGenVertexArrays( 1, &vao);
   glGenBuffers( 1, &vbo);
   glBindVertexArray( vao);
   glBindBuffer( GL_ARRAY_BUFFER, vbo);
   glBufferData( GL_ARRAY_BUFFER, sizeof vertices, vertices, GL_STATIC_DRAW);
   glEnableVertexAttribArray( 0);
   glVertexAttribPointer( 0, 2, GL_FLOAT, GL_FALSE,
                          5 * sizeof(float), (void*) 0);
   glEnableVertexAttribArray( 1);
   glVertexAttribPointer( 1, 3, GL_FLOAT, GL_FALSE,
                          5 * sizeof(float), (void*)(2 * sizeof(float)));
   gl_check_errors( "GL setup");

   // XImage wrapper around our pixel buffer for XPutImage.
   XImage *img = XCreateImage( dpy,
                               DefaultVisual( dpy, screen),
                               DefaultDepth(  dpy, screen),
                               ZPixmap, 0,
                               (char *) pixels,
                               width, height, 32, 0);
   if( !img)
   {
      fprintf( stderr, "XCreateImage failed\n");
      return 1;
   }

   GC gc = XCreateGC( dpy, win, 0, NULL);

   // ---- render loop ----
   double t0 = now_sec();

   while( !glfwWindowShouldClose( glfw_win))
   {
      glfwPollEvents();

      // render into CPU buffer
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
      glFinish();   // ensure pixels are ready before XPutImage

      // blit OSMesa pixel buffer into the GLFW-managed X11 window
      XPutImage( dpy, win, gc, img, 0, 0, 0, 0, width, height);
      XFlush( dpy);
   }

   // ---- cleanup ----
   img->data = NULL;   // don't let XDestroyImage free our buffer
   XDestroyImage( img);
   XFreeGC( dpy, gc);

   OSMesaMakeCurrent( NULL, NULL, 0, 0, 0);
   OSMesaDestroyContext( ctx);
   free( pixels);

   glfwDestroyWindow( glfw_win);
   glfwTerminate();

   return 0;
}

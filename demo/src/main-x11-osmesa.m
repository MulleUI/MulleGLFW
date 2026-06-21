//
// x11-osmesa — a minimal OpenGL demo using X11 and OSMesa, with no GLFW.
//
// PURPOSE
//   This demo exists to prove that OpenGL rendering works end-to-end without
//   any window-system GL integration layer (GLX, EGL, GLFW).  It is useful
//   for isolating rendering bugs: if something works here but not in the GLFW
//   path, the problem is in the window/context plumbing, not in the GL code.
//
// HOW IT WORKS
//   OSMesa (Off-Screen Mesa) is a Mesa sub-library that provides a complete
//   software OpenGL implementation that renders into a plain CPU memory buffer
//   instead of a GPU framebuffer.  No display, GPU, or driver support is
//   required for rendering itself.
//
//   The pixel buffer is then handed to X11 via XCreateImage / XPutImage each
//   frame, which copies it into the X11 window.  This is the simplest possible
//   display path: no DRI, no shared memory, just a plain XPutImage.
//
//   Key design points:
//     - OSMesa renders BGRA pixels bottom-up by default.  We call
//       OSMesaPixelStore(OSMESA_Y_UP, 0) to flip the Y axis so it matches
//       X11's top-down scanline order.
//     - glFinish() is called before XPutImage to ensure all GL rendering is
//       complete before we read the pixel buffer.
//     - No GLAD / proc-address loader is needed here.  Linking -lOSMesa
//       directly resolves all GL symbols (OSMesa IS the implementation).
//       This is unlike the GLFW+OSMesa case where libGL.so dispatches via
//       GLX/EGL TLS and never reaches the OSMesa context — that case DOES
//       require GLAD to re-route calls through glfwGetProcAddress.
//     - The demo uses OpenGL 3.3 Core Profile via OSMesaCreateContextAttribs.
//       llvmpipe (the LLVM-based software rasteriser bundled with Mesa) is the
//       backend; it supports up to GL 4.5.
//
// BUILD
//   Linked with: -lOSMesa -lX11
//   No special compile flags needed (GL_GLEXT_PROTOTYPES exposes glext.h
//   prototypes; osmesa.h includes GL/gl.h automatically).
//
// RUN
//   x11-osmesa [--width W] [--height H] [--samples N]
//   Close with Escape, Q, or the window's close button.
//

// OSMesa provides the OpenGL implementation directly; osmesa.h pulls in GL/gl.h.
// GL_GLEXT_PROTOTYPES exposes glext.h function prototypes without a loader.
#define GL_GLEXT_PROTOTYPES
#include <GL/osmesa.h>
#include <GL/glext.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/keysym.h>

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

int  main( int argc, char **argv)
{
   int   width   = 800;
   int   height  = 600;
   int   samples = 0;   // MSAA sample count; 0 = off

   for( int i = 1; i < argc; i++)
   {
      if( !strcmp( argv[i], "--width") && i + 1 < argc)
         width = atoi( argv[ ++i]);
      else if( !strcmp( argv[i], "--height") && i + 1 < argc)
         height = atoi( argv[ ++i]);
      else if( !strcmp( argv[i], "--samples") && i + 1 < argc)
         samples = atoi( argv[ ++i]);
      else
      {
         fprintf( stderr, "Usage: %s [--width W] [--height H] [--samples N]\n",
                  argv[0]);
         return 1;
      }
   }

   // ---- OSMesa context ----
   int attribs[] = {
      OSMESA_FORMAT,               OSMESA_BGRA,
      OSMESA_DEPTH_BITS,           24,
      OSMESA_STENCIL_BITS,         8,
      OSMESA_PROFILE,              OSMESA_CORE_PROFILE,
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

   // OSMesa renders bottom-up by default; flip Y so it matches X11 top-down.
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
   if( samples > 1)
      fprintf( stdout, "MSAA        : %dx (software via llvmpipe)\n", samples);

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

   // ---- X11 window ----
   Display *dpy = XOpenDisplay( NULL);
   if( !dpy)
   {
      fprintf( stderr, "XOpenDisplay failed (DISPLAY=%s)\n",
               getenv("DISPLAY") ? getenv("DISPLAY") : "(not set)");
      return 1;
   }

   int screen = DefaultScreen( dpy);
   Window root = RootWindow( dpy, screen);

   XSetWindowAttributes wa;
   wa.background_pixel = BlackPixel( dpy, screen);
   wa.event_mask       = ExposureMask | KeyPressMask | StructureNotifyMask;

   Window win = XCreateWindow( dpy, root,
                               100, 100, width, height, 0,
                               DefaultDepth( dpy, screen),
                               InputOutput,
                               DefaultVisual( dpy, screen),
                               CWBackPixel | CWEventMask, &wa);

   XStoreName( dpy, win, "X11 + OSMesa (no GLFW)");

   // Hook WM_DELETE_WINDOW so we can close cleanly
   Atom wm_delete = XInternAtom( dpy, "WM_DELETE_WINDOW", False);
   XSetWMProtocols( dpy, win, &wm_delete, 1);

   XMapWindow( dpy, win);
   XFlush( dpy);

   // XImage wrapper around our pixel buffer
   XImage *img = XCreateImage( dpy,
                               DefaultVisual( dpy, screen),
                               DefaultDepth( dpy, screen),
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
   double t0       = now_sec();
   int    running  = 1;

   while( running)
   {
      // drain X events
      while( XPending( dpy))
      {
         XEvent ev;
         XNextEvent( dpy, &ev);
         if( ev.type == KeyPress)
         {
            KeySym ks = XLookupKeysym( &ev.xkey, 0);
            if( ks == XK_Escape || ks == XK_q)
               running = 0;
         }
         else if( ev.type == ClientMessage)
         {
            if( (Atom) ev.xclient.data.l[0] == wm_delete)
               running = 0;
         }
      }

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

      // blit to X11 window
      XPutImage( dpy, win, gc, img, 0, 0, 0, 0, width, height);
      XFlush( dpy);
   }

   // ---- cleanup ----
   img->data = NULL;   // don't let XDestroyImage free our buffer
   XDestroyImage( img);
   XFreeGC( dpy, gc);
   XDestroyWindow( dpy, win);
   XCloseDisplay( dpy);

   OSMesaMakeCurrent( NULL, NULL, 0, 0, 0);
   OSMesaDestroyContext( ctx);
   free( pixels);

   return 0;
}

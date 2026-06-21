//
// glfw-wayland-osmesa — GLFW Wayland window + OSMesa + wl_shm blit.
//
// PURPOSE
//   Wayland counterpart to glfw-x11-osmesa-grok.  The rendering half is
//   identical (GLFW_OSMESA_CONTEXT_API, glfwGetOSMesaColorBuffer, glFinish).
//   The display half replaces XPutImage with the Wayland wl_shm protocol:
//   a shared-memory buffer is attached to the GLFW-managed wl_surface each
//   frame.
//
// HOW IT WORKS
//   1. glfwInitHint(GLFW_PLATFORM, GLFW_PLATFORM_WAYLAND) — BEFORE glfwInit.
//      This forces the Wayland backend even on systems that also have X11/XWayland.
//      (Note: the grok X11 demo got this wrong — hint was set after glfwInit.)
//   2. GLFW_OSMESA_CONTEXT_API — GLFW creates the OSMesa context and its
//      backing pixel buffer.  No manual OSMesaCreateContextAttribs needed.
//   3. glfwGetOSMesaColorBuffer() retrieves the live pixel pointer each frame.
//   4. wl_shm blit path (Wayland equivalent of XPutImage):
//        shm_open → ftruncate → mmap → wl_shm_create_pool
//        → wl_shm_pool_create_buffer → wl_surface_attach/damage/commit
//      We swap R↔B from OSMesa's RGBA buffer into the wl_shm region each frame.
//      A zero-copy variant is possible by making OSMesa render directly into
//      the shm region (manual OSMesaMakeCurrent with shm_data as the buffer),
//      but that requires GLFW_NO_API + manual context setup.
//
// PIXEL FORMAT
//   GLFW configures OSMesa with OSMESA_RGBA = GL_RGBA: bytes in memory are R,G,B,A.
//   WL_SHM_FORMAT_XRGB8888 on little-endian stores pixels as B,G,R,X in memory.
//   These do NOT match: R and B are swapped.  blit_rgba_to_xrgb() corrects this
//   per-frame.  WL_SHM_FORMAT_XBGR8888 would match directly but is not a
//   guaranteed Wayland format (only XRGB8888=1 and ARGB8888=0 are guaranteed).
//
// wl_shm ownership
//   GLFW has already done its own registry roundtrip during glfwInit to
//   obtain its Wayland globals.  We do a second roundtrip on the same
//   wl_display connection to grab wl_shm for ourselves.  This is safe —
//   Wayland allows multiple registry listeners on the same connection.
//   We also grab wl_compositor so we have it if needed, though GLFW already
//   owns the xdg_surface/toplevel — we only touch wl_surface directly.
//
// RESIZE
//   GLFW_RESIZABLE is set to FALSE.  OSMesa contexts managed by GLFW do not
//   automatically resize their backing buffer — supporting resize would require
//   destroying and recreating the context (and the wl_shm pool).  For a demo
//   this complexity is not worth it.
//
// BUILD
//   Linked with: -lOSMesa -lwayland-client
//   Requires GLFW built with Wayland support (GLFW_BUILD_WAYLAND=ON).
//
// RUN
//   WAYLAND_DISPLAY=wayland-0 glfw-wayland-osmesa [--width W] [--height H]
//   Close with Escape, Q, or the window close button.
//

#define GL_GLEXT_PROTOTYPES
#include <GL/osmesa.h>
#include <GL/glext.h>

#define GLFW_INCLUDE_NONE
#include <GLFW/glfw3.h>

// glfwGetWaylandDisplay / glfwGetWaylandWindow / glfwGetOSMesaColorBuffer
#define GLFW_EXPOSE_NATIVE_WAYLAND
#define GLFW_EXPOSE_NATIVE_OSMESA
#include <GLFW/glfw3native.h>

#include <wayland-client.h>
#include <wayland-client-protocol.h>

#include "linmath.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <time.h>


// ---------------------------------------------------------------------------
// Wayland state
// ---------------------------------------------------------------------------

struct wl_state
{
   struct wl_shm       *shm;
   struct wl_compositor *compositor;
   // buffer management
   struct wl_buffer    *buffer;
   void                *shm_data;
   size_t               shm_size;
   int                  buf_w;
   int                  buf_h;
};

static void shm_format( void *data, struct wl_shm *wl_shm, uint32_t format)
{
   (void) data; (void) wl_shm; (void) format;
}
static const struct wl_shm_listener shm_listener = { shm_format };

static void registry_global( void *data,
                              struct wl_registry *reg,
                              uint32_t name,
                              const char *interface,
                              uint32_t version)
{
   struct wl_state *st = data;
   (void) version;
   if( strcmp( interface, wl_shm_interface.name) == 0)
      st->shm = wl_registry_bind( reg, name, &wl_shm_interface, 1);
   else if( strcmp( interface, wl_compositor_interface.name) == 0)
      st->compositor = wl_registry_bind( reg, name, &wl_compositor_interface, 1);
}

static void registry_global_remove( void *data,
                                    struct wl_registry *reg,
                                    uint32_t name)
{
   (void) data; (void) reg; (void) name;
}

static const struct wl_registry_listener registry_listener = {
   registry_global,
   registry_global_remove,
};


// ---------------------------------------------------------------------------
// shm buffer helpers
// ---------------------------------------------------------------------------

// shm_open is POSIX and more portable than memfd_create (Linux 3.17+).
static int create_shm_fd( size_t size)
{
   char name[ 64];
   snprintf( name, sizeof name, "/glfw-osmesa-%d-%d", getpid(), rand());
   int fd = shm_open( name, O_RDWR | O_CREAT | O_EXCL, 0600);
   if( fd < 0) { perror( "shm_open"); return -1; }
   shm_unlink( name);   // unlink immediately; fd keeps it alive
   if( ftruncate( fd, (off_t) size) < 0) { perror( "ftruncate"); close( fd); return -1; }
   return fd;
}

static int create_wl_buffer( struct wl_state *st, int w, int h)
{
   if( st->buffer)
   {
      wl_buffer_destroy( st->buffer);
      munmap( st->shm_data, st->shm_size);
      st->buffer   = NULL;
      st->shm_data = NULL;
   }

   st->buf_w    = w;
   st->buf_h    = h;
   st->shm_size = (size_t) w * h * 4;

   int fd = create_shm_fd( st->shm_size);
   if( fd < 0) return 0;

   st->shm_data = mmap( NULL, st->shm_size, PROT_READ | PROT_WRITE,
                        MAP_SHARED, fd, 0);
   if( st->shm_data == MAP_FAILED) { perror( "mmap"); close( fd); return 0; }

   struct wl_shm_pool *pool = wl_shm_create_pool( st->shm, fd, st->shm_size);
   st->buffer = wl_shm_pool_create_buffer( pool, 0, w, h, w * 4,
                                           WL_SHM_FORMAT_XRGB8888);
   wl_shm_pool_destroy( pool);
   close( fd);
   return 1;
}


// ---------------------------------------------------------------------------
// Pixel format conversion
// ---------------------------------------------------------------------------
// GLFW's OSMesa context uses OSMESA_RGBA = GL_RGBA: bytes in memory are R,G,B,A.
// Wayland's guaranteed WL_SHM_FORMAT_XRGB8888 stores pixels as B,G,R,X in
// memory (little-endian uint32: X=bits[31:24] R=bits[23:16] G=bits[15:8] B=bits[7:0]).
// WL_SHM_FORMAT_XBGR8888 would match directly but is not a guaranteed format —
// compositors only guarantee XRGB8888 (=1) and ARGB8888 (=0).
// Therefore we must swap R↔B on every blit.
//
// If glfwGetOSMesaColorBuffer returns an unexpected format we warn once and
// skip the blit for that frame rather than displaying garbage.
//
static void blit_rgba_to_xrgb( void *dst, const void *src, int pixel_count)
{
   const uint32_t *s = (const uint32_t *) src;
   uint32_t       *d = (uint32_t *) dst;
   for( int i = 0; i < pixel_count; i++)
   {
      uint32_t p = s[i];
      // src LE uint32: R=bits[7:0]  G=bits[15:8]  B=bits[23:16]  A=bits[31:24]
      // dst LE uint32: B=bits[7:0]  G=bits[15:8]  R=bits[23:16]  X=bits[31:24]
      d[i] = (p & 0xFF00FF00u)             // keep G (byte1) and A→X (byte3)
           | ((p & 0x00FF0000u) >> 16)     // move B → byte0
           | ((p & 0x000000FFu) << 16);    // move R → byte2
   }
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

static const float vertices[] = {
   -0.6f, -0.4f,   1.f, 0.f, 0.f,
    0.6f, -0.4f,   0.f, 1.f, 0.f,
    0.0f,  0.6f,   0.f, 0.f, 1.f,
};


// ---------------------------------------------------------------------------
// Timer
// ---------------------------------------------------------------------------

static double now_sec(void)
{
   struct timespec ts;
   clock_gettime( CLOCK_MONOTONIC, &ts);
   return ts.tv_sec + ts.tv_nsec * 1e-9;
}


// ---------------------------------------------------------------------------
// Key callback
// ---------------------------------------------------------------------------

static void key_callback( GLFWwindow *win, int key, int scancode, int action, int mods)
{
   (void) scancode; (void) mods;
   if( action == GLFW_PRESS && (key == GLFW_KEY_ESCAPE || key == GLFW_KEY_Q))
      glfwSetWindowShouldClose( win, GLFW_TRUE);
}


// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

int main( int argc, char **argv)
{
   int width  = 800;
   int height = 600;

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

   // ---- GLFW: Wayland hint BEFORE glfwInit (init hints are ignored after) ----
   glfwInitHint( GLFW_PLATFORM, GLFW_PLATFORM_WAYLAND);

   if( !glfwInit())
   {
      fprintf( stderr, "glfwInit failed\n");
      return 1;
   }

   // ---- GLFW window + OSMesa context ----
   glfwWindowHint( GLFW_CONTEXT_CREATION_API,  GLFW_OSMESA_CONTEXT_API);
   glfwWindowHint( GLFW_CLIENT_API,            GLFW_OPENGL_API);
   glfwWindowHint( GLFW_CONTEXT_VERSION_MAJOR, 3);
   glfwWindowHint( GLFW_CONTEXT_VERSION_MINOR, 3);
   glfwWindowHint( GLFW_OPENGL_PROFILE,        GLFW_OPENGL_CORE_PROFILE);
   glfwWindowHint( GLFW_RESIZABLE,             GLFW_FALSE);

   GLFWwindow *glfw_win = glfwCreateWindow( width, height,
                                            "GLFW + OSMesa (Wayland wl_shm blit)",
                                            NULL, NULL);
   if( !glfw_win)
   {
      fprintf( stderr, "glfwCreateWindow failed (is WAYLAND_DISPLAY set?)\n");
      glfwTerminate();
      return 1;
   }

   glfwMakeContextCurrent( glfw_win);
   glfwSetKeyCallback( glfw_win, key_callback);

   // OSMesa renders bottom-up; flip to match Wayland top-down convention.
   OSMesaPixelStore( OSMESA_Y_UP, 0);

   const GLubyte *ver = glGetString( GL_VERSION);
   if( !ver)
   {
      fprintf( stderr, "OSMesa context not functional\n");
      glfwTerminate();
      return 1;
   }
   fprintf( stdout, "GL renderer : %s\n", glGetString( GL_RENDERER));
   fprintf( stdout, "GL version  : %s\n", glGetString( GL_VERSION));

   // ---- GL setup ----
   GLuint prog    = build_program( vert_src, frag_src);
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

   // ---- Wayland setup ----
   // Use glfwGetFramebufferSize — on HiDPI displays this may differ from
   // the window size in screen coordinates.
   int fb_w, fb_h;
   glfwGetFramebufferSize( glfw_win, &fb_w, &fb_h);

   struct wl_display *display = glfwGetWaylandDisplay();
   struct wl_surface *surface = glfwGetWaylandWindow( glfw_win);
   if( !display || !surface)
   {
      fprintf( stderr, "glfwGetWaylandDisplay/Window failed\n");
      glfwTerminate();
      return 1;
   }

   // Second registry roundtrip on the GLFW-owned connection to get our globals.
   struct wl_state    st       = {0};
   struct wl_registry *registry = wl_display_get_registry( display);
   wl_registry_add_listener( registry, &registry_listener, &st);
   wl_display_roundtrip( display);

   if( !st.shm)
   {
      fprintf( stderr, "wl_shm not available\n");
      glfwTerminate();
      return 1;
   }
   wl_shm_add_listener( st.shm, &shm_listener, NULL);

   if( !create_wl_buffer( &st, fb_w, fb_h))
   {
      fprintf( stderr, "create_wl_buffer failed\n");
      glfwTerminate();
      return 1;
   }

   // ---- Get OSMesa pixel buffer (GLFW-managed, fixed size since RESIZABLE=FALSE) ----
   int            buf_w, buf_h, buf_fmt;
   unsigned char *pixels = NULL;
   glfwGetOSMesaColorBuffer( glfw_win, &buf_w, &buf_h, &buf_fmt, (void**) &pixels);
   if( !pixels || buf_w != fb_w || buf_h != fb_h)
   {
      fprintf( stderr, "glfwGetOSMesaColorBuffer failed or size mismatch\n");
      glfwTerminate();
      return 1;
   }
   if( buf_fmt != GL_RGBA)
      fprintf( stderr, "Warning: unexpected OSMesa format 0x%x (expected GL_RGBA 0x%x)"
               " — blit will be skipped\n", buf_fmt, GL_RGBA);

   // ---- render loop ----
   double t0 = now_sec();

   while( !glfwWindowShouldClose( glfw_win))
   {
      glfwPollEvents();

      double angle = now_sec() - t0;
      glViewport( 0, 0, fb_w, fb_h);
      glClearColor( 0.15f, 0.15f, 0.15f, 1.0f);
      glClear( GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

      mat4x4 m, p, mvp;
      mat4x4_identity( m);
      mat4x4_rotate_Z( m, m, (float) angle);
      float ratio = (float) fb_w / (float) fb_h;
      mat4x4_ortho( p, -ratio, ratio, -1.f, 1.f, 1.f, -1.f);
      mat4x4_mul( mvp, p, m);

      glUseProgram( prog);
      glUniformMatrix4fv( mvp_loc, 1, GL_FALSE, (const float *) mvp);
      glBindVertexArray( vao);
      glDrawArrays( GL_TRIANGLES, 0, 3);
      glFinish();   // OSMesa pixels must be ready before blit

      // Swap R↔B (OSMesa=RGBA, WL_SHM_FORMAT_XRGB8888=BGRA) then present.
      if( buf_fmt == GL_RGBA)
      {
         blit_rgba_to_xrgb( st.shm_data, pixels, fb_w * fb_h);
         wl_surface_attach( surface, st.buffer, 0, 0);
         wl_surface_damage( surface, 0, 0, fb_w, fb_h);
         wl_surface_commit( surface);
         wl_display_flush( display);
      }
   }

   // ---- cleanup ----
   wl_buffer_destroy( st.buffer);
   munmap( st.shm_data, st.shm_size);
   if( st.shm)       wl_shm_destroy( st.shm);
   if( st.compositor) wl_compositor_destroy( st.compositor);
   wl_registry_destroy( registry);
   // display is owned by GLFW — do not close it

   glDeleteVertexArrays( 1, &vao);
   glDeleteBuffers( 1, &vbo);
   glDeleteProgram( prog);

   glfwDestroyWindow( glfw_win);
   glfwTerminate();

   return 0;
}

//
// PURPOSE
//   Wayland counterpart to glfw-x11-osmesa-grok.  The rendering half is
//   identical (GLFW_OSMESA_CONTEXT_API, glfwGetOSMesaColorBuffer, glFinish).
//   The display half replaces XPutImage with the Wayland wl_shm protocol:
//   a shared-memory buffer is attached to the GLFW-managed wl_surface each
//   frame.
//
// HOW IT WORKS
//   1. glfwInitHint(GLFW_PLATFORM, GLFW_PLATFORM_WAYLAND) — BEFORE glfwInit.
//      This forces the Wayland backend even on systems that also have X11/XWayland.
//      (Note: the grok X11 demo got this wrong — hint was set after glfwInit.)
//   2. GLFW_OSMESA_CONTEXT_API — GLFW creates the OSMesa context and its
//      backing pixel buffer.  No manual OSMesaCreateContextAttribs needed.
//   3. glfwGetOSMesaColorBuffer() retrieves the live pixel pointer each frame.
//   4. wl_shm blit path (Wayland equivalent of XPutImage):
//        memfd_create → ftruncate → mmap → wl_shm_create_pool
//        → wl_shm_pool_create_buffer → wl_surface_attach/damage/commit
//      We swap R↔B from OSMesa's RGBA buffer into the wl_shm region each frame.
//      A zero-copy variant is possible by making OSMesa render directly into
//      the shm region (manual OSMesaMakeCurrent with shm_data as the buffer),
//      but that requires GLFW_NO_API + manual context setup.
//
// PIXEL FORMAT
//   GLFW configures OSMesa with OSMESA_RGBA = GL_RGBA: bytes in memory are R,G,B,A.
//   WL_SHM_FORMAT_XRGB8888 on little-endian stores pixels as B,G,R,X in memory.
//   These do NOT match: R and B are swapped.  blit_rgba_to_xrgb() corrects this
//   per-frame.  WL_SHM_FORMAT_XBGR8888 would match directly but is not a
//   guaranteed Wayland format (only XRGB8888=1 and ARGB8888=0 are guaranteed).
//
// wl_shm ownership
//   GLFW has already done its own registry roundtrip during glfwInit to
//   obtain its Wayland globals.  We do a second roundtrip on the same
//   wl_display connection to grab wl_shm for ourselves.  This is safe —
//   Wayland allows multiple registry listeners on the same connection.
//
// BUILD
//   Linked with: -lOSMesa -lwayland-client
//   Requires GLFW built with Wayland support (GLFW_BUILD_WAYLAND=ON).
//
// RUN
//   WAYLAND_DISPLAY=wayland-0 glfw-wayland-osmesa [--width W] [--height H]
//   Close with Escape, Q, or the window close button.
//


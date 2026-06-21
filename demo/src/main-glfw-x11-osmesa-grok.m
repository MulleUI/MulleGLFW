// glfw-osmesa — a minimal OpenGL demo using GLFW + OSMesa (software rendering),
// with no manual X11/Wayland window or context code.
//
// PURPOSE
// Same as the original x11-osmesa demo: prove that the *rendering* path is
// pure OSMesa (no GLX/EGL dispatcher, no GPU required). This isolates GL
// bugs from window-system plumbing.
//
// WHAT CHANGED (modern GLFW adaptation)
// - GLFW now creates the *window* and the *OSMesa context* for you.
// - glfwWindowHint(GLFW_CONTEXT_CREATION_API, GLFW_OSMESA_CONTEXT_API) forces
//   a pure software OSMesa context (llvmpipe). All gl* calls go straight to
//   OSMesa — exactly what the original comment warned was tricky in the old
//   GLFW+OSMesa path.
// - No more manual OSMesaCreateContextAttribs / OSMesaMakeCurrent / pixel
//   buffer allocation. GLFW manages the OSMesa context and its backing buffer.
// - Window creation, title, mapping, close button, and event polling are
//   all handled by GLFW → no X11/Wayland "shisma" in the app code.
// - We still use X11 *only* for the final blit (XPutImage) because an OSMesa
//   context does not auto-present on glfwSwapBuffers (as documented in GLFW).
//   This is the minimal remaining platform-specific piece.
// - Force GLFW_PLATFORM_X11 so the native blit path always works (even on
//   Wayland systems that have XWayland).
//
// HOW IT WORKS
// - OSMesa renders into a CPU buffer (BGRA, managed by GLFW).
// - We retrieve the live buffer pointer each frame with glfwGetOSMesaColorBuffer.
// - OSMesaPixelStore(OSMESA_Y_UP, 0) flips it to X11 top-down order.
// - XPutImage blits it exactly like the original demo.
// - glFinish() ensures rendering is complete before the blit.
//
// BUILD (Linux)
// 1. Build GLFW with OSMesa support:
//      cmake -S . -B build -DGLFW_USE_OSMESA=ON -DCMAKE_BUILD_TYPE=Release
//      cmake --build build
// 2. Link with: -lglfw -lOSMesa -lX11
//    (GL_GLEXT_PROTOTYPES still works because we link -lOSMesa directly.)
//
// RUN
// ./glfw-osmesa [--width W] [--height H] [--samples N]
// Close with Escape, Q, or the window close button.
//
// This is the cleanest "modern GLFW" version while keeping the original
// demo's spirit: pure OSMesa rendering, minimal platform code.
#define GL_GLEXT_PROTOTYPES
#include <GL/osmesa.h>
#include <GL/glext.h>

#define GLFW_EXPOSE_NATIVE_X11
#define GLFW_EXPOSE_NATIVE_OSMESA   // ← ADD THIS
#include <GLFW/glfw3.h>
#include <GLFW/glfw3native.h>

#include <X11/Xlib.h>
#include <X11/Xutil.h>

#include "linmath.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

// ---------------------------------------------------------------------------
// Pixel format conversion
// ---------------------------------------------------------------------------
// GLFW's OSMesa context uses OSMESA_RGBA = GL_RGBA (R,G,B,A bytes in memory).
// X11's default visual (XRGB8888) stores pixels as B,G,R,X in memory.
// Wayland's guaranteed WL_SHM_FORMAT_XRGB8888 is identical.
// We must swap the R and B channels when copying to either display buffer.
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
      // p as LE uint32: R=bits[7:0]  G=bits[15:8]  B=bits[23:16]  A=bits[31:24]
      // want LE uint32: B=bits[7:0]  G=bits[15:8]  R=bits[23:16]  X=bits[31:24]
      d[i] = (p & 0xFF00FF00u)             // keep G (byte1) and A→X (byte3)
           | ((p & 0x00FF0000u) >> 16)     // B → byte0
           | ((p & 0x000000FFu) << 16);    // R → byte2
   }
}

// ---------------------------------------------------------------------------
// GL helpers (unchanged)
// ---------------------------------------------------------------------------
static void gl_check_errors(const char *where)
{
   GLenum e;
   while ((e = glGetError()) != GL_NO_ERROR)
      fprintf(stderr, "GL error at %s: 0x%x\n", where, e);
}

static GLuint compile_shader(GLenum type, const char *src)
{
   GLuint s = glCreateShader(type);
   glShaderSource(s, 1, &src, NULL);
   glCompileShader(s);
   GLint ok;
   glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
   if (!ok) {
      char buf[512];
      glGetShaderInfoLog(s, sizeof buf, NULL, buf);
      fprintf(stderr, "Shader compile error: %s\n", buf);
   }
   return s;
}

static GLuint build_program(const char *vert_src, const char *frag_src)
{
   GLuint prog = glCreateProgram();
   GLuint vs = compile_shader(GL_VERTEX_SHADER, vert_src);
   GLuint fs = compile_shader(GL_FRAGMENT_SHADER, frag_src);
   glAttachShader(prog, vs);
   glAttachShader(prog, fs);
   glLinkProgram(prog);
   GLint ok;
   glGetProgramiv(prog, GL_LINK_STATUS, &ok);
   if (!ok) {
      char buf[512];
      glGetProgramInfoLog(prog, sizeof buf, NULL, buf);
      fprintf(stderr, "Program link error: %s\n", buf);
   }
   glDeleteShader(vs);
   glDeleteShader(fs);
   return prog;
}

// ---------------------------------------------------------------------------
// Shaders (unchanged)
// ---------------------------------------------------------------------------
static const char *vert_src =
   "#version 330 core\n"
   "layout(location=0) in vec2 pos;\n"
   "layout(location=1) in vec3 col;\n"
   "uniform mat4 mvp;\n"
   "out vec3 vCol;\n"
   "void main(){\n"
   " gl_Position = mvp * vec4(pos, 0.0, 1.0);\n"
   " vCol = col;\n"
   "}\n";

static const char *frag_src =
   "#version 330 core\n"
   "in vec3 vCol;\n"
   "out vec4 fragColor;\n"
   "void main(){ fragColor = vec4(vCol, 1.0); }\n";

// triangle: position (x,y) + color (r,g,b)
static const float vertices[] = {
   -0.6f, -0.4f, 1.f, 0.f, 0.f,
    0.6f, -0.4f, 0.f, 1.f, 0.f,
    0.0f,  0.6f, 0.f, 0.f, 1.f,
};

// ---------------------------------------------------------------------------
// Tiny timer (unchanged)
// ---------------------------------------------------------------------------
static double now_sec(void)
{
   struct timespec ts;
   clock_gettime(CLOCK_MONOTONIC, &ts);
   return ts.tv_sec + ts.tv_nsec * 1e-9;
}

// ---------------------------------------------------------------------------
// Key callback for Escape / Q
// ---------------------------------------------------------------------------
static void key_callback(GLFWwindow* window, int key, int scancode, int action, int mods)
{
   (void)scancode; (void)mods;
   if (action == GLFW_PRESS && (key == GLFW_KEY_ESCAPE || key == GLFW_KEY_Q))
      glfwSetWindowShouldClose(window, GLFW_TRUE);
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------
int main(int argc, char **argv)
{
   int width = 800;
   int height = 600;
   int samples = 0;

   for (int i = 1; i < argc; i++) {
      if (!strcmp(argv[i], "--width") && i + 1 < argc)
         width = atoi(argv[++i]);
      else if (!strcmp(argv[i], "--height") && i + 1 < argc)
         height = atoi(argv[++i]);
      else if (!strcmp(argv[i], "--samples") && i + 1 < argc)
         samples = atoi(argv[++i]);
      else {
         fprintf(stderr, "Usage: %s [--width W] [--height H] [--samples N]\n", argv[0]);
         return 1;
      }
   }

   // ---- GLFW init + OSMesa context (modern way) ----
   if (!glfwInit()) {
      fprintf(stderr, "glfwInit failed\n");
      return 1;
   }

   // Force X11 backend so our minimal XPutImage blit path works everywhere
   // (hides Wayland completely for this demo).
   glfwInitHint(GLFW_PLATFORM, GLFW_PLATFORM_X11);

   glfwWindowHint(GLFW_CONTEXT_CREATION_API, GLFW_OSMESA_CONTEXT_API);
   glfwWindowHint(GLFW_CLIENT_API, GLFW_OPENGL_API);
   glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
   glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
   glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
   if (samples > 1)
      glfwWindowHint(GLFW_SAMPLES, samples);

   GLFWwindow *window = glfwCreateWindow(width, height,
                                         "GLFW + OSMesa (X11 blit)",
                                         NULL, NULL);
   if (!window) {
      fprintf(stderr, "glfwCreateWindow failed\n");
      glfwTerminate();
      return 1;
   }

   glfwMakeContextCurrent(window);

   // Hook Escape / Q
   glfwSetKeyCallback(window, key_callback);

   // OSMesa renders bottom-up by default → flip Y to match X11 top-down
   OSMesaPixelStore(OSMESA_Y_UP, 0);

   // Verify the context is functional
   const GLubyte *ver = glGetString(GL_VERSION);
   if (!ver) {
      fprintf(stderr, "OSMesa context not functional\n");
      glfwTerminate();
      return 1;
   }
   fprintf(stdout, "GL renderer : %s\n", glGetString(GL_RENDERER));
   fprintf(stdout, "GL version  : %s\n", glGetString(GL_VERSION));
   if (samples > 1)
      fprintf(stdout, "MSAA : %dx (software via llvmpipe)\n", samples);

   // ---- GL setup (unchanged) ----
   GLuint prog = build_program(vert_src, frag_src);
   GLint mvp_loc = glGetUniformLocation(prog, "mvp");

   GLuint vao, vbo;
   glGenVertexArrays(1, &vao);
   glGenBuffers(1, &vbo);
   glBindVertexArray(vao);
   glBindBuffer(GL_ARRAY_BUFFER, vbo);
   glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);

   glEnableVertexAttribArray(0);
   glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 5 * sizeof(float), (void*)0);
   glEnableVertexAttribArray(1);
   glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, 5 * sizeof(float), (void*)(2 * sizeof(float)));

   gl_check_errors("GL setup");

   // ---- Get OSMesa pixel buffer (managed by GLFW) ----
   int buf_w, buf_h, buf_fmt;
   unsigned char *pixels = NULL;
   glfwGetOSMesaColorBuffer( window, &buf_w, &buf_h, &buf_fmt, (void**) &pixels);
   if( !pixels || buf_w != width || buf_h != height)
   {
      fprintf( stderr, "glfwGetOSMesaColorBuffer failed\n");
      glfwTerminate();
      return 1;
   }
   if( buf_fmt != GL_RGBA)
      fprintf( stderr, "Warning: unexpected OSMesa format 0x%x (expected GL_RGBA 0x%x)"
               " -- blit will be skipped\n", buf_fmt, GL_RGBA);

   // Separate blit buffer: OSMesa is RGBA; X11 expects BGRA (XRGB8888 visual).
   // We swap R<->B into blit_buf before each XPutImage -- XImage points here.
   unsigned char *blit_buf = malloc( (size_t) width * height * 4);
   if( !blit_buf) { fprintf( stderr, "Out of memory\n"); return 1; }

   // ---- X11 blit setup ----
   Display *dpy = glfwGetX11Display();
   if( !dpy)
   {
      fprintf( stderr, "glfwGetX11Display failed (X11 backend required)\n");
      glfwTerminate();
      return 1;
   }
   Window xwin = glfwGetX11Window( window);
   if( !xwin)
   {
      fprintf( stderr, "glfwGetX11Window failed\n");
      glfwTerminate();
      return 1;
   }

   XImage *img = XCreateImage( dpy,
                               DefaultVisual( dpy, DefaultScreen( dpy)),
                               DefaultDepth(  dpy, DefaultScreen( dpy)),
                               ZPixmap, 0,
                               (char *) blit_buf,
                               width, height, 32, 0);
   if( !img) { fprintf( stderr, "XCreateImage failed\n"); glfwTerminate(); return 1; }

   GC gc = XCreateGC( dpy, xwin, 0, NULL);

   // ---- render loop ----
   double t0 = now_sec();
   while (!glfwWindowShouldClose(window)) {
      glfwPollEvents();

      // render into OSMesa buffer
      double angle = now_sec() - t0;
      glViewport(0, 0, width, height);
      glClearColor(0.15f, 0.15f, 0.15f, 1.0f);
      glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

      mat4x4 m, p, mvp;
      mat4x4_identity(m);
      mat4x4_rotate_Z(m, m, (float)angle);
      float ratio = (float)width / (float)height;
      mat4x4_ortho(p, -ratio, ratio, -1.f, 1.f, 1.f, -1.f);
      mat4x4_mul(mvp, p, m);

      glUseProgram(prog);
      glUniformMatrix4fv(mvp_loc, 1, GL_FALSE, (const float *)mvp);
      glBindVertexArray(vao);
      glDrawArrays(GL_TRIANGLES, 0, 3);

      glFinish(); // ensure pixels are ready

      // swap R<->B then blit to window (OSMesa=RGBA, X11 visual=BGRA)
      if( buf_fmt == GL_RGBA)
      {
         blit_rgba_to_xrgb( blit_buf, pixels, width * height);
         XPutImage( dpy, xwin, gc, img, 0, 0, 0, 0, width, height);
         XFlush( dpy);
      }
   }

   // ---- cleanup ----
   img->data = NULL; // XDestroyImage must not free blit_buf separately -- we do it below
   XDestroyImage(img);
   free( blit_buf);
   XFreeGC(dpy, gc);

   glDeleteVertexArrays(1, &vao);
   glDeleteBuffers(1, &vbo);
   glDeleteProgram(prog);

   glfwDestroyWindow(window);
   glfwTerminate();

   return 0;
}

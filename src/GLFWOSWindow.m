//
//  GLFWOSWindow.m
//  MulleGLFW
//
//  Copyright (c) 2022 Nat! - Mulle kybernetiK.
//  All rights reserved.
//
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are met:
//
//  Redistributions of source code must retain the above copyright notice, this
//  list of conditions and the following disclaimer.
//
//  Redistributions in binary form must reproduce the above copyright notice,
//  this list of conditions and the following disclaimer in the documentation
//  and/or other materials provided with the distribution.
//
//  Neither the name of Mulle kybernetiK nor the names of its contributors
//  may be used to endorse or promote products derived from this software
//  without specific prior written permission.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
//  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
//  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
//  ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
//  LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
//  CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
//  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
//  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
//  CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
//  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
//  POSSIBILITY OF SUCH DAMAGE.
//
#define GL_SILENCE_DEPRECATION
#define GLFW_INCLUDE_GLEXT

#define _POSIX_C_SOURCE 200112L
#include <stdlib.h>

#import "GLFWOSWindow.h"
#include <mulle-buffer/mulle-buffer.h>

#import "import-private.h"

#import "GLFWOSWindow+UIEvent.h"
#import <MulleUIApplication/UIOSWindow+DebugPrivate.h>


// ---------------------------------------------------------------------------
// OSMesa off-screen blit support
//
// GLFW's swapBuffers is a confirmed no-op for OSMESA_CONTEXT_API.  We detect
// this at runtime via glfwGetWindowAttrib(GLFW_CONTEXT_CREATION_API) and
// perform a manual blit into the native window.
//
// Each backend is guarded by its own compile-time define so that the binary
// only references the symbols that are actually available:
//
//   MULLE_GLFW_OSMESA   — libOSMesa / glfwGetOSMesaColorBuffer
//   MULLE_GLFW_X11      — libX11   / glfwGetX11Display, glfwGetX11Window
//   MULLE_GLFW_WAYLAND  — libwayland-client / glfwGetWaylandDisplay,
//                         glfwGetWaylandWindow
//
// CMakeLists sets these via find_package / pkg_check_modules and adds the
// required link targets.  If none are found the code falls back to the
// glfwSwapBuffers no-op (harmless, just shows nothing).
// ---------------------------------------------------------------------------

#if MULLE_GLFW_OSMESA

# include <GL/osmesa.h>

// Native platform headers — included only when the backend is available.
// Both X11 and Wayland can coexist on the same system, so independent #if
// blocks (not #elif).  The defines for GLFW_EXPOSE_NATIVE_* must appear
// before the single glfw3native.h inclusion.
// GLFW_EXPOSE_NATIVE_OSMESA exposes glfwGetOSMesaColorBuffer.
# define GLFW_EXPOSE_NATIVE_OSMESA
# if MULLE_GLFW_X11
#  define GLFW_EXPOSE_NATIVE_X11
#  include <X11/Xlib.h>
#  include <X11/Xutil.h>
# endif
# if MULLE_GLFW_WAYLAND
#  define GLFW_EXPOSE_NATIVE_WAYLAND
#  include <wayland-client.h>
#  include <sys/mman.h>    // mmap, munmap
#  include <fcntl.h>       // O_* flags
#  include <unistd.h>      // close
// ftruncate is POSIX but hidden under ISO C99 strict mode; forward-declare.
extern int ftruncate( int fd, long length);
// memfd_create + flags (Linux 3.17+; guarded in case the toolchain is old)
#  ifndef MFD_CLOEXEC
#   define MFD_CLOEXEC      (1U)
#   define MFD_ALLOW_SEALING (2U)
extern int memfd_create( const char *name, unsigned int flags);
#  endif
# endif
# if MULLE_GLFW_X11 || MULLE_GLFW_WAYLAND || 1   // always include for OSMESA
#  include <GLFW/glfw3native.h>
# endif

// Swap R↔B in-place: OSMesa gives GL_RGBA (R,G,B,A bytes), both X11's
// XRGB8888 visual and Wayland's WL_SHM_FORMAT_XRGB8888 want B,G,R,X in
// memory (little-endian).
static void
mulle__osmesa_blit_rgba_to_xrgb( void *dst, const void *src, int n)
{
   const uint32_t *s = (const uint32_t *) src;
   uint32_t       *d = (uint32_t *) dst;

   while( n--)
   {
      uint32_t p = *s++;
      // keep G (byte1) + A→X (byte3), swap R (byte0) ↔ B (byte2)
      *d++ = (p & 0xFF00FF00u)
           | ((p & 0x00FF0000u) >> 16)
           | ((p & 0x000000FFu) << 16);
   }
}


// ---------------------------------------------------------------------------
// Per-window OSMesa blit state
// ---------------------------------------------------------------------------

struct mulle__osmesa_blit_state
{
   void    *buffer;      // malloc'd R↔B swap staging buffer
   int      width;
   int      height;

# if MULLE_GLFW_X11
   Display *x11_display; // borrowed from glfwGetX11Display — do NOT close
   Window   x11_window;
   GC       x11_gc;
   XImage  *x11_image;   // wraps buffer; do not let XDestroyImage free it
# endif

# if MULLE_GLFW_WAYLAND
   struct wl_display    *wl_display;   // borrowed from GLFW — do NOT destroy
   struct wl_surface    *wl_surface;   // borrowed from GLFW — do NOT destroy
   struct wl_registry   *wl_registry;  // our binding — we destroy it
   struct wl_shm        *wl_shm;       // our binding — we destroy it
   struct wl_shm_pool   *wl_pool;      // our pool   — we destroy it
   struct wl_buffer     *wl_buffer;    // our buffer — we destroy it
   void                 *shm_data;     // mmap region
   size_t                shm_size;
# endif
};


# if MULLE_GLFW_WAYLAND
// ---------------------------------------------------------------------------
// Minimal Wayland registry listener to grab wl_shm
// ---------------------------------------------------------------------------

static void
wl_registry_handle_global( void *data,
                            struct wl_registry *registry,
                            uint32_t name,
                            const char *interface,
                            uint32_t version)
{
   struct mulle__osmesa_blit_state *st = data;

   if( ! st->wl_shm && strcmp( interface, wl_shm_interface.name) == 0)
      st->wl_shm = wl_registry_bind( registry, name, &wl_shm_interface, 1);
}

static void
wl_registry_handle_global_remove( void *data,
                                   struct wl_registry *registry,
                                   uint32_t name)
{
   (void) data; (void) registry; (void) name;
}

static const struct wl_registry_listener _wl_registry_listener =
{
   wl_registry_handle_global,
   wl_registry_handle_global_remove
};


static int
mulle__osmesa_create_shm_file( off_t size)
{
   int   fd;

   fd = memfd_create( "mulle-glfw-osmesa", MFD_CLOEXEC | MFD_ALLOW_SEALING);
   if( fd < 0)
      return( -1);
   if( ftruncate( fd, size) < 0)
   {
      close( fd);
      return( -1);
   }
   return( fd);
}
# endif // MULLE_GLFW_WAYLAND


// ---------------------------------------------------------------------------
// Create blit state for the current window / platform
// Returns non-zero on error.
// ---------------------------------------------------------------------------
static struct mulle__osmesa_blit_state *
mulle__osmesa_blit_state_create( void *glfw_window, int width, int height)
{
   struct mulle__osmesa_blit_state *st;

   st = calloc( 1, sizeof( *st));
   if( ! st)
      return( NULL);

   st->buffer = malloc( (size_t) width * height * 4);
   if( ! st->buffer)
   {
      free( st);
      return( NULL);
   }
   st->width  = width;
   st->height = height;

# if MULLE_GLFW_X11
   {
      int   platform;

      platform = glfwGetPlatform();
      if( platform == GLFW_PLATFORM_X11)
      {
         Display   *dpy;
         Window     xwin;

         dpy  = glfwGetX11Display();
         xwin = glfwGetX11Window( glfw_window);
         if( ! dpy || ! xwin)
         {
            free( st->buffer);
            free( st);
            return( NULL);
         }

         st->x11_display = dpy;
         st->x11_window  = xwin;
         st->x11_gc      = XCreateGC( dpy, xwin, 0, NULL);
         st->x11_image   = XCreateImage( dpy,
                                         DefaultVisual( dpy, DefaultScreen( dpy)),
                                         DefaultDepth( dpy,  DefaultScreen( dpy)),
                                         ZPixmap, 0,
                                         (char *) st->buffer,
                                         width, height, 32, 0);
         if( ! st->x11_image)
         {
            XFreeGC( dpy, st->x11_gc);
            free( st->buffer);
            free( st);
            return( NULL);
         }
      }
   }
# endif // MULLE_GLFW_X11

# if MULLE_GLFW_WAYLAND
   {
      int   platform;

      platform = glfwGetPlatform();
      if( platform == GLFW_PLATFORM_WAYLAND)
      {
         struct wl_display   *dpy;
         struct wl_surface   *surf;
         size_t               shm_size;
         int                  fd;

         dpy  = glfwGetWaylandDisplay();
         surf = glfwGetWaylandWindow( glfw_window);
         fprintf( stderr, "[OSMesa Wayland] dpy=%p surf=%p\n", dpy, surf);
         if( ! dpy || ! surf)
         {
            free( st->buffer);
            free( st);
            return( NULL);
         }

         st->wl_display = dpy;
         st->wl_surface = surf;

         // Second registry roundtrip to grab wl_shm (GLFW owns its own copy)
         st->wl_registry = wl_display_get_registry( dpy);
         wl_registry_add_listener( st->wl_registry, &_wl_registry_listener, st);
         wl_display_roundtrip( dpy);

         fprintf( stderr, "[OSMesa Wayland] wl_shm=%p after roundtrip\n",
                  st->wl_shm);
         if( ! st->wl_shm)
         {
            mulle_fprintf( stderr, "MulleGLFW: OSMesa Wayland blit: "
                           "wl_shm not available\n");
            wl_registry_destroy( st->wl_registry);
            free( st->buffer);
            free( st);
            return( NULL);
         }

         shm_size    = (size_t) width * height * 4;
         st->shm_size = shm_size;

         fd = mulle__osmesa_create_shm_file( (off_t) shm_size);
         if( fd < 0)
         {
            wl_shm_destroy( st->wl_shm);
            wl_registry_destroy( st->wl_registry);
            free( st->buffer);
            free( st);
            return( NULL);
         }

         st->shm_data = mmap( NULL, shm_size,
                              PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
         if( st->shm_data == MAP_FAILED)
         {
            close( fd);
            wl_shm_destroy( st->wl_shm);
            wl_registry_destroy( st->wl_registry);
            free( st->buffer);
            free( st);
            return( NULL);
         }

         st->wl_pool   = wl_shm_create_pool( st->wl_shm, fd, (int32_t) shm_size);
         st->wl_buffer = wl_shm_pool_create_buffer( st->wl_pool, 0,
                                                     width, height,
                                                     width * 4,
                                                     WL_SHM_FORMAT_XRGB8888);
         close( fd); // pool holds it open
      }
   }
# endif // MULLE_GLFW_WAYLAND

   return( st);
}


static void
mulle__osmesa_blit_state_destroy( struct mulle__osmesa_blit_state *st)
{
   if( ! st)
      return;

# if MULLE_GLFW_X11
   if( st->x11_image)
   {
      st->x11_image->data = NULL; // we own buffer; don't let X free it twice
      XDestroyImage( st->x11_image);
   }
   if( st->x11_gc)
      XFreeGC( st->x11_display, st->x11_gc);
# endif

# if MULLE_GLFW_WAYLAND
   if( st->wl_buffer)   wl_buffer_destroy( st->wl_buffer);
   if( st->wl_pool)     wl_shm_pool_destroy( st->wl_pool);
   if( st->shm_data)    munmap( st->shm_data, st->shm_size);
   if( st->wl_shm)      wl_shm_destroy( st->wl_shm);
   if( st->wl_registry) wl_registry_destroy( st->wl_registry);
# endif

   free( st->buffer);
   free( st);
}


static void
mulle__osmesa_do_blit( struct mulle__osmesa_blit_state *st,
                       void *pixels,
                       int   width,
                       int   height)
{
   mulle__osmesa_blit_rgba_to_xrgb( st->buffer, pixels, width * height);

# if MULLE_GLFW_X11
   if( st->x11_image)
   {
      fprintf( stderr, "[OSMesa blit] XPutImage %dx%d\n", width, height);
      XPutImage( st->x11_display, st->x11_window, st->x11_gc,
                 st->x11_image, 0, 0, 0, 0, width, height);
      XFlush( st->x11_display);
      return;
   }
# endif

# if MULLE_GLFW_WAYLAND
   if( st->wl_buffer)
   {
      fprintf( stderr, "[OSMesa blit] wl_shm blit %dx%d\n", width, height);
      memcpy( st->shm_data, st->buffer, st->shm_size);
      wl_surface_attach( st->wl_surface, st->wl_buffer, 0, 0);
      wl_surface_damage( st->wl_surface, 0, 0, width, height);
      wl_surface_commit( st->wl_surface);
      wl_display_flush( st->wl_display);
      return;
   }
# endif
}

#endif // MULLE_GLFW_OSMESA


// ---------------------------------------------------------------------------
// Apple Metal surface: we must NOT pull Apple AppKit/Foundation headers into
// this mulle-objc translation unit (mulle-clang cannot parse them). We only
// need the cocoa window handle as an opaque pointer, so forward-declare
// glfwGetCocoaWindow returning void * instead of including glfw3native.h, and
// use the pure-C shim (GLFWMetalLayer-apple.h) for the actual Metal work.
// ---------------------------------------------------------------------------
#ifdef __APPLE__
extern void   *glfwGetCocoaWindow( void *window);   // real return type is NSWindow *
# import "GLFWMetalLayer-apple.h"
#endif



@interface GLFWOSWindow( UIEventFuture) < MulleObjCFuture>

- (void) _windowFramebufferResizeCallback:(CGPixelSize) size;

@end

#pragma clang diagnostic ignored "-Wprotocol"


@implementation NSObject( UIOSWindow)

- (BOOL) __isUIOSWindow
{
   return( NO);
}

@end


void   GLFWGraphicsHintsApplyDriverEnv( GLFWGraphicsHints hints)
{
#ifndef _WIN32
   if( hints.glx_vendor)
      setenv( "__GLX_VENDOR_LIBRARY_NAME", hints.glx_vendor, 1);

   if( hints.driver)
      setenv( "MESA_LOADER_DRIVER_OVERRIDE", hints.driver, 1);

   if( hints.lib_path)
   {
      char   *old;

      old = getenv( "LD_LIBRARY_PATH");
      if( ! old || ! strstr( old, hints.lib_path))
      {
         mulle_buffer_do( buf)
         {
            if( old)
            {
               mulle_buffer_add_string( buf, (char *) hints.lib_path);
               mulle_buffer_add_string( buf, ":");
               mulle_buffer_add_string( buf, old);
            }
            else
               mulle_buffer_add_string( buf, (char *) hints.lib_path);
            setenv( "LD_LIBRARY_PATH", mulle_buffer_get_string( buf), 1);
         }
      }
      if( ! getenv( "LIBGL_DRIVERS_PATH"))
      {
         mulle_buffer_do( buf)
         {
            mulle_buffer_add_string( buf, (char *) hints.lib_path);
            mulle_buffer_add_string( buf, "/dri");
            setenv( "LIBGL_DRIVERS_PATH", mulle_buffer_get_string( buf), 0);
         }
      }
   }

   if( hints.egl_vendor)
      setenv( "__EGL_VENDOR_LIBRARY_FILENAMES", hints.egl_vendor, 1);

   if( hints.software)
      setenv( "LIBGL_ALWAYS_SOFTWARE", "1", 1);

   if( hints.dri_prime)
   {
      mulle_buffer_do( buf)
      {
         mulle_buffer_sprintf( buf, "%u", hints.dri_prime - 1);
         setenv( "DRI_PRIME", mulle_buffer_get_string( buf), 1);
      }
   }
#endif // _WIN32
}


@implementation GLFWOSWindow

- (BOOL) __isUIOSWindow
{
   return( YES);
}


static struct
{
   mulle_atomic_pointer_t   _shareIDs;
   NSUInteger               _debuggingFlags;
} ClassStatic;


// this will be called for subclasses as well, does it matter ?
+ (void) initialize
{
   char   *s;

   // don't run again for subclass
   if( MulleObjCClassGetID( self) != @selector( GLFWOSWindow))
      return;

   s = getenv( MULLE_C_STRINGIFY( GLFWOSWindow) "DebuggingFlags");
   if( ! s)
      s = getenv( "UIOSWindowDebuggingFlags");
   if( ! s)
      s = getenv( "UIDebuggingFlags");
   if( s)
      ClassStatic._debuggingFlags = strtol( s, NULL, 0);
}


+ (void) setDebuggingFlags:(NSUInteger) flag  MULLE_OBJC_THREADSAFE_METHOD
{
   ClassStatic._debuggingFlags = flag;
}


//
// Resolve an intended styleMask against what this backend can honor for the
// given graphics API. See the contract in the UIOSWindow protocol
// (UIWindowTypes.h). This is static (argument-driven, no live OS query), so it
// can be called before a window exists.
//
// The graphics API is encoded in hints.api (see the switch in
// -initWithFrame:...): api==1 is GLFW_NO_API, which on macOS means the window
// uses a CAMetalLayer (the Metal CG backend). Metal has no equivalent of GL's
// context sharing, so the retained backing store (offscreen->screen blit that
// relies on a shared texture namespace) cannot be honored. Drop those bits so
// the window falls back to the volatile (direct-to-window) backing store.
//
+ (NSUInteger) effectiveWindowStyleMask:(NSUInteger) styleMask
                          graphicsHints:(UIOSWindowGraphicsHints) hints
{
   // api == 1 -> GLFW_NO_API (Metal on Apple platforms)
   BOOL   isMetal = (hints.api == 1);

#ifdef __APPLE__
   if( isMetal)
   {
      // no context sharing under Metal -> no retained (two-context) backing store
      styleMask &= ~(UIWindowStyleRetained | UIWindowStyleRetainedOnMainThread);
   }
#endif

   // Wayland hook (future): the Wayland backend cannot honor arbitrary
   // programmatic resizes the way X11 does, so a Wayland window would clear
   // UIWindowStyleResizable here. Left unwired until the Wayland path is
   // verified; documented so the seam is obvious.
   (void) isMetal;

   return( styleMask);
}


// as we don't know, if we even use OpenGL here
static UIWindowDisplayBits   defaultFrameCallback( id <UIOSWindow> window_in)
{
   mulle_fprintf( stderr, "The GLFW window needs a frameCallback.\n"
"Typically you can use something like this with OpenGL:\n"
"   static UIWindowDisplayBits  frameCallback( id <UIOSWindow> window_in)\n"
"   {\n"
"      GLFWOSWindow  *window = MULLE_OBJC_CLASS_CAST( GLFWOSWindow, window_in);\n"
"      CGPixelSize   framebufferSize;\n"
"\n"
"      framebufferSize = [window os_framebufferSize];\n"
"      glViewport( 0, 0, framebufferSize.width, framebufferSize.height);\n"
"      glClearColor( 0, 0, 0, 0);\n"
"      glClear( GL_COLOR_BUFFER_BIT);\n"
"      return( 0);  // or 1, if you are animating\n"
"   }\n"
"\n"
"   [window setFrameCallback:frameCallback];\n"
"\n");
   abort();
}


+ (instancetype) windowWithFrame:(CGRect) frame
                titleUTF8String:(char *) title
                      styleMask:(NSUInteger) styleMask
{
   GLFWOSWindow *obj;

   obj = [self alloc];
   obj = [obj initWithFrame:frame
              titleUTF8String:title
                    styleMask:styleMask];
   obj = [obj autorelease];
   return(obj);
}


+ (instancetype) windowWithFrame:(CGRect) frame
                titleUTF8String:(char *) title
                      styleMask:(NSUInteger) styleMask
                  graphicsHints:(GLFWGraphicsHints) graphicsHints
{
   GLFWOSWindow *obj;

   obj = [self alloc];
   obj = [obj initWithFrame:frame
              titleUTF8String:title
                    styleMask:styleMask
                graphicsHints:graphicsHints];
   obj = [obj autorelease];
   return(obj);
}

// sharingWindow is retained. We will be able to share textures with it
+ (instancetype) windowWithFrame:(CGRect) frame
                titleUTF8String:(char *) title
                      styleMask:(NSUInteger) styleMask
                  graphicsHints:(GLFWGraphicsHints) graphicsHints
                  sharingWindow:(id <UIOSWindow>) sharingWindow
{
   GLFWOSWindow *obj;

   obj = [self alloc];
   obj = [obj initWithFrame:frame
              titleUTF8String:title
                    styleMask:styleMask
                graphicsHints:graphicsHints
                sharingWindow:sharingWindow];
   obj = [obj autorelease];
   return(obj);
}


//
// TODO: can't really figure out if wayland or X11
//       but glfw 3.4 will probably bring GLFW_PLATFORM, where this should
//       be possible to query (hope)
static UIGraphicsBackend  getWindowBackend( GLFWwindow *window)
{
   int   api;
   int   forward;
   int   major;
   int   minor;
   int   profile;

   api = glfwGetWindowAttrib( window, GLFW_CLIENT_API);
   if( api != GLFW_NO_API)
   {
      major    = glfwGetWindowAttrib( window, GLFW_CONTEXT_VERSION_MAJOR);
      minor    = glfwGetWindowAttrib( window, GLFW_CONTEXT_VERSION_MINOR);
      forward  = glfwGetWindowAttrib( window, GLFW_OPENGL_FORWARD_COMPAT);
      profile  = glfwGetWindowAttrib( window, GLFW_OPENGL_PROFILE);

      // we "simplify" foward and core to mean the same
      if( profile == GLFW_OPENGL_CORE_PROFILE)
         forward = 1;

      if( api == GLFW_OPENGL_ES_API)
         return( major >= 3 ? UIGraphicsBackendGLES3 : UIGraphicsBackendGLES2);

      assert( api == GLFW_OPENGL_API);

      if( (major == 3 && minor >= 2) || major > 3)
         return( forward ? UIGraphicsBackendGL3_2Forward : UIGraphicsBackendGL3_2);
      return( forward ? UIGraphicsBackendGL3Forward : UIGraphicsBackendGL3);
   }
   return( UIGraphicsBackendNone);
}



#ifdef DEBUG
static void   glfw_os_window_break_on_me( void)
{
}
#endif


// hope for fractional positioning in future ?
//
// gdb:
// b initWithFrame:titleUTF8String:styleMask:graphicsHints:sharingWindow:
//
- (instancetype) initWithFrame:(CGRect) frame
               titleUTF8String:(char *) title
                     styleMask:(NSUInteger) styleMask
                 graphicsHints:(GLFWGraphicsHints) hints
                 sharingWindow:(id <UIOSWindow>) sharingWindow
{
   int   api;
   int   forward;
   int   lib;
   int   major;
   int   minor;
   int   profile;
   int   explicit_lib_requested;
   int   first_lib;
   int   sharing_lib;
   int   samples;

   assert( [NSThread mulleIsMainThread]);

#ifdef DEBUG
   glfw_os_window_break_on_me();
#endif

#ifdef GLFW_OS_WINDOW_DEBUGGING_FLAGS
   _debuggingFlags = GLFW_OS_WINDOW_DEBUGGING_FLAGS;
#else
   _debuggingFlags = ClassStatic._debuggingFlags;
#endif

   // TODO: create windows invisible always, but make visible after first
   //       render call. pro: window won't show up empty for an unknown
   //       amount of time. con: window won't show up at all for an unknown
   //       amount of time.
   assert( ! sharingWindow || [sharingWindow isKindOfClass:[GLFWOSWindow class]]);
   assert( ! sharingWindow || ((GLFWOSWindow *) sharingWindow)->_window);

   if( ! styleMask)
      styleMask = GLFWOSWindowStyleMaskDefault;

   /*
    * Window Styling Hints
    *
    *  The following hints are always hard constraints:
    *  (https://www.glfw.org/docs/latest/window_guide.html#window_hints)
    *
    *  GLFW_STEREO
    *  GLFW_DOUBLEBUFFER
    *  GLFW_CLIENT_API
    *  GLFW_CONTEXT_CREATION_API 
    * 
    *  GLFW_OPENGL_FORWARD_COMPAT
    *  GLFW_OPENGL_PROFILE
    *
    */
   glfwWindowHint( GLFW_DOUBLEBUFFER, (styleMask & UIWindowStyleSingleBuffer) ? GLFW_FALSE : GLFW_TRUE);
   glfwWindowHint( GLFW_TRANSPARENT_FRAMEBUFFER, (styleMask & UIWindowStyleTransparent) ? GLFW_TRUE : GLFW_FALSE);

   // https://www.glfw.org/docs/3.4/window_guide.html#GLFW_RESIZABLE_hint
   glfwWindowHint( GLFW_RESIZABLE, (styleMask & UIWindowStyleResizable) ? GLFW_TRUE : GLFW_FALSE);
// always create invisible and then turn it on later
   glfwWindowHint( GLFW_VISIBLE, GLFW_FALSE);
   glfwWindowHint( GLFW_FLOATING,  (styleMask & UIWindowStyleFloating)  ? GLFW_TRUE : GLFW_FALSE);
   glfwWindowHint( GLFW_DECORATED, (styleMask & UIWindowStyleBare) ? GLFW_FALSE : GLFW_TRUE);

   // https://www.glfw.org/docs/3.4/window_guide.html#GLFW_CLIENT_API_hint
#ifdef DEBUG
   glfwWindowHint( GLFW_OPENGL_DEBUG_CONTEXT, GL_TRUE);
#endif

   /*
    * OpenGL Context Hints
    */

   api     = -1;
   lib     = -1;
   profile = -1;
   forward = -1;
   major   = -1;
   minor   = -1;

//
// These function can only be called from main thread (see above)
//
// GLFW_OPENGL_FORWARD_COMPAT specifies whether the OpenGL context has
// deprecated functionality removed.
// GLFW_OPENGL_CORE_PROFILE is a subset of OpenGL similiar to OpenGLES
//
   if( styleMask & UIWindowOpenGLDeprecated)
   {
#ifdef DEBUG
     mulle_fprintf( stderr, "Deprecated OpenGL requested\n");
#endif

      hints.api     = 3; // setOpenGL
      hints.profile = 3; // compat
      hints.forward = 0; // no forward

      assert( ! (styleMask & UIWindowOpenGLForward));
      assert( ! (styleMask & UIWindowOpenGLCoreProfile)) ;
   }

   major = hints.major;
   if( major)
   {
      glfwWindowHint( GLFW_CONTEXT_VERSION_MAJOR, major);
      minor = hints.minor;
      glfwWindowHint( GLFW_CONTEXT_VERSION_MINOR, minor);
   }

   // If requesting an OpenGL version below 3.2, GLFW_OPENGL_ANY_PROFILE must
   // be used. if we don't set major, the default in glfw is 1.0
   if( major < 3 || (major == 3 && minor < 2))
      hints.profile = 1; //any

   forward = styleMask & UIWindowOpenGLForward;
   if( forward)
      hints.forward = 1;

   // not super sure about this, but lets try to avoid "old" OpenGL
   // calls. alas, we are doing OpenGLES 2.0 minimum, so I don't know
   // if this is useful.

   switch( hints.api)
   {
   case 1 : api = GLFW_NO_API; break;  // special, don't want to hit this by default
   case 2 : api = GLFW_OPENGL_ES_API; break;
   case 3 : api = GLFW_OPENGL_API; break;
   }
   if( api != -1)
      glfwWindowHint( GLFW_CLIENT_API, api);

   // For OpenGL 3+ there is no "gimme" what you got, we demand :)
   if( (major > 3 || (major == 3 && minor >= 2)) && api == GLFW_OPENGL_API)
   {
      if( styleMask & UIWindowOpenGLCoreProfile)
         hints.profile = 2;
   }

   // TODO: could retry for profiles as well as for libs (see below)
   switch( hints.profile)
   {
   case 1 : profile = GLFW_OPENGL_ANY_PROFILE; break;
   case 2 : profile = GLFW_OPENGL_CORE_PROFILE; break;
   case 3 : profile = GLFW_OPENGL_COMPAT_PROFILE; break;
   }
#ifdef __APPLE__
   if( profile == GLFW_OPENGL_COMPAT_PROFILE)
   {
      UIOSWindowLog( "OpenGL compat not posible with Apple");
      [self release];
      return( nil);
   }
#endif
   // you can't set this or GLFW_OPENGL_CORE_PROFILE or GLFW_OPENGL_COMPAT_PROFILE on GL < 3.2
   if( profile != -1)
      glfwWindowHint( GLFW_OPENGL_PROFILE, profile);

   // forward compatibility is actually fairly restrictive
   // https://www.glfw.org/docs/3.3/window_guide.html#GLFW_OPENGL_FORWARD_COMPAT_hint
   if( hints.forward)
      glfwWindowHint( GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE);  // why not ?

   // remember what was opened first for retries
   switch( hints.lib)
   {
   case 1 : lib = GLFW_NATIVE_CONTEXT_API; break;
   case 2 : lib = GLFW_EGL_CONTEXT_API; break;
   case 3 : lib = GLFW_OSMESA_CONTEXT_API; break;
   }
   explicit_lib_requested = hints.lib != 0;
   first_lib              = lib;
   sharing_lib            = -1;

   if( sharingWindow)
   {
      sharing_lib = glfwGetWindowAttrib( ((GLFWOSWindow *) sharingWindow)->_window,
                                         GLFW_CONTEXT_CREATION_API);
      if( sharing_lib > 0)
      {
         if( lib > 0 && lib != sharing_lib)
            mulle_fprintf( stderr, "warning: shared context forces creation API %d over requested %d\n",
                           sharing_lib,
                           lib);
         lib = sharing_lib;
         first_lib = lib;
      }
   }

   if( styleMask & UIWindowStyleAntiAlias)
      UIOSWindowLog( "MSAA requested");

   glfwWindowHint( GLFW_SAMPLES, (styleMask & UIWindowStyleAntiAlias) ? 4 : 0);

retry:
   if( lib != -1)
      glfwWindowHint( GLFW_CONTEXT_CREATION_API, lib);

   _window = glfwCreateWindow( (int) frame.size.width,
                               (int) frame.size.height,
                               title ? title : "",
                               NULL,  // monitor to display
                               sharingWindow ? ((GLFWOSWindow *) sharingWindow)->_window : NULL);
   if( ! _window)
   {
      const char  *description;
      int         code;
      char        *aux;

      aux  = "";
      code = glfwGetError( &description);
      switch( code)
      {
      case 65542 :
         if( ! sharingWindow
             && ! explicit_lib_requested
             && (styleMask & UIWindowOpenGLLibraryFallback))
         {
            switch( first_lib)
            {
            case -1 :
            case GLFW_NATIVE_CONTEXT_API :   // native
               // native -> mesa -> egl
               if( lib == first_lib)
               {
                  lib = GLFW_OSMESA_CONTEXT_API;
                  goto retry;
               }
               else
                  if( lib == GLFW_OSMESA_CONTEXT_API)
                  {
                     lib = GLFW_EGL_CONTEXT_API;
                     goto retry;
                  }
               break;

            case GLFW_EGL_CONTEXT_API :
               // egl -> native -> mesa
               if( lib == first_lib)
               {
                  lib = GLFW_NATIVE_CONTEXT_API;
                  goto retry;
               }
               else
                  if( lib == GLFW_NATIVE_CONTEXT_API)
                  {
                     lib = GLFW_OSMESA_CONTEXT_API;
                     goto retry;
                  }
               break;

            case GLFW_OSMESA_CONTEXT_API :
               // mesa -> native -> egl
               if( lib == first_lib)
               {
                  lib = GLFW_NATIVE_CONTEXT_API;
                  goto retry;
               }
               else
                  if( lib == GLFW_NATIVE_CONTEXT_API)
                  {
                     lib = GLFW_EGL_CONTEXT_API;
                     goto retry;
                  }
               break;

            default :
               abort();
            }
         }
         else
            if( explicit_lib_requested)
               aux = "\nRequested context creation API failed; automatic fallback is disabled for explicit API selection.";
         break;

      case 65543 :
         aux = "\nThis error may be due to a graphics driver update. Please try rebooting your system.";
         break;

      case 65537 :
         aux = "\nUIApplication is likely not initialized yet.";
      }
      mulle_fprintf( stderr, "error #%d: glfwCreateWindow failed \"%s\"%s\n", code, description, aux);
      [self release];
      return( nil);
   }

   _sharingWindow = (GLFWOSWindow *) [sharingWindow retain];
   if( _sharingWindow)
   {
      UIOSWindowLog( "window %p (sharing with %p) created", _window, _sharingWindow);
   }
   else
   {
      UIOSWindowLog( "window %p created", _window);
      _shareID = (NSInteger) _mulle_atomic_pointer_increment( &ClassStatic._shareIDs) + 1;
   }

   // needed for wayland, else exit on zero size window during resize
   glfwSetWindowSizeLimits( _window, 32, 32, GLFW_DONT_CARE, GLFW_DONT_CARE);

   // this is basically the "rendezvous" point where nanoVG latches unto
   // its also the receiver for OpenGL calls. That's why we need a window
   // to draw stuff
   //
   glfwSetWindowUserPointer( _window, self);

   // zero origin means: let window manager choose
   if( ! CGPointEqualToPoint( frame.origin, CGPointZero))
      glfwSetWindowPos( _window, (int) frame.origin.x, (int) frame.origin.y);

   _mulle_atomic_pointer_nonatomic_write( &_needsRefresh, (void *) 1);

   _backend                     = getWindowBackend( (GLFWwindow *) _window);
   _frameCallback               = defaultFrameCallback;
   _haveGraphicsContext         = glfwGetWindowAttrib( _window, GLFW_CLIENT_API) != GLFW_NO_API;

#ifdef __APPLE__
   //
   // A GLFW_NO_API window on macOS has no GL context; we attach a CAMetalLayer
   // so the Metal CG backend has a surface. Only report Metal2 when the layer
   // was actually created (device present); otherwise leave the backend as
   // getWindowBackend reported (UIGraphicsBackendNone for NO_API).
   //
   if( glfwGetWindowAttrib( _window, GLFW_CLIENT_API) == GLFW_NO_API)
   {
      void   *nsWindow;

      nsWindow     = (void *) glfwGetCocoaWindow( _window);
      _metalLayer  = MulleGLFWMetalLayerCreate( nsWindow);
      if( _metalLayer)
         _backend = UIGraphicsBackendMetal2;
   }
#endif
   _otherRetainedEventsCallback = GLFWOSWindowRetainedEventDefaultCallback;
   _scrollWheelSensitivity      = 20.0;
   _styleMask                   = styleMask;
   _uninitializedFramebuffer    = YES;
   _windowEventsCallback        = GLFWOSWindowEventDefaultCallback;
   _doubleClickInterval         = [UIMouseButtonEvent doubleClickInterval]; // cache this to avoid latency
   if( _doubleClickInterval == 0.0)
      _doubleClickInterval = 1 / 3.0f;

   // get initial state for some demos
   {
      double   x, y;

      glfwGetCursorPos( _window, &x, &y);

      _inputState.locationInWindow.x = x;
      _inputState.locationInWindow.y = y;
   }
   assert( (api == GLFW_NO_API && ! _haveGraphicsContext) || _haveGraphicsContext);

   if( _haveGraphicsContext)
   {
      glfwMakeContextCurrent( _window);  // needed, otherwise glGetIntegerv( GL_SAMPLES_ARB, &samples) fails

      // A NULL GL_VERSION means the context was created by GLFW but GL
      // function calls are not reaching it. The most common cause is using
      // GLFW_OSMESA_CONTEXT_API without a function loader (GLAD /
      // glfwGetProcAddress): OSMesa maintains its own context TLS separate
      // from libGL's GLX/EGL dispatch, so direct libGL calls return NULL.
      if( ! glGetString( GL_VERSION))
      {
         int          code;
         const char   *description;

         code = glfwGetError( &description);
         mulle_fprintf( stderr, "error: GL context is not functional "
                                "(glGetString( GL_VERSION) returned NULL)\n"
                                "       Likely cause: context creation API is not "
                                "reachable via direct libGL calls.\n"
                                "       If OSMesa (--mesa) was requested, GL "
                                "functions must be loaded via glfwGetProcAddress "
                                "or GLAD — direct libGL calls do not route through "
                                "OSMesa.\n"
                                "       GLFW error %d: %s\n",
                        code, description ? description : "(none)");
         glfwMakeContextCurrent( NULL);
         [self release];
         return( nil);
      }

      samples = 0;
#if defined(__APPLE__)
      GLint sampleBuffers = 0;

      glGetIntegerv( GL_SAMPLE_BUFFERS, &sampleBuffers);
      if( sampleBuffers > 0) 
         glGetIntegerv( GL_SAMPLES, &samples);
#else
      glGetIntegerv( GL_SAMPLES_ARB, &samples);
#endif
      if( samples == 4)
         _antiAliasing = YES;
//      else
//         if( ! glfwExtensionSupported( "GL_ARB_multisample"))
//            fprintf( stderr, "MSAA OpenGL support not present\n");

      glfwMakeContextCurrent( NULL); // turn off to be consistent with lock
      _contextLock = [NSLock new];
   }

   if( ! (styleMask & UIWindowStyleHidden))
      [self os_show];

#ifdef DEBUG
   mulle_fprintf( stderr, "window style            : %s\n", [self os_windowInfoUTF8String]);
   // os_contextInfoUTF8String calls glGetString, which requires a current GL
   // context. A GLFW_NO_API window (Metal backend, CAMetalLayer) has none, so
   // making the context current / querying GL here would crash. Only report
   // the GL context description when the window actually has a GL context.
   if( _haveGraphicsContext)
   {
      glfwMakeContextCurrent( _window);
      mulle_fprintf( stderr, "window graphics context : %s\n", [self os_contextInfoUTF8String]);
      glfwMakeContextCurrent( NULL);
   }
#endif

   // read values once, afterwards these values are just updated by events
   // framerate by default
   _windowInfo.frameRate = UIWindowFrameRateAsync;

   [self updateWindowInfo];

   // init afterwards
   _windowInfoLock = [NSLock new];
   _inputStateLock = [NSLock new];

   return( self);
}


- (instancetype) initWithFrame:(CGRect) frame
               titleUTF8String:(char *) title
                     styleMask:(NSUInteger) styleMask
                 graphicsHints:(GLFWGraphicsHints) hints
{
   return( [self initWithFrame:frame
               titleUTF8String:title
                     styleMask:styleMask
                 graphicsHints:hints
                 sharingWindow:nil]);
}


- (instancetype) initWithFrame:(CGRect) frame
               titleUTF8String:(char *) title
                     styleMask:(NSUInteger) styleMask
{
   return( [self initWithFrame:frame
               titleUTF8String:title
                     styleMask:styleMask
                 graphicsHints:GLFWGraphicsHintsDefault
                 sharingWindow:nil]);
}


- (void) finalize
{
   // keep render context locked. As the window/context will be unusuable
   // a deadlock seems preferable and easier to debug for misbehavers
   if( [_contextLock tryLock]) // if already locked don't deadlock here
      _mulle_atomic_pointer_write( &_atomicActiveThread, [NSThread currentThread]);

   [_sharingWindow autorelease];
   _sharingWindow = nil;

   if( _window)
      [self os_destroyWindow];

   [super finalize];
}


- (void) dealloc
{
   [_contextLock release];
   [_windowInfoLock release];
   [_inputStateLock release];

#if MULLE_GLFW_OSMESA
   mulle__osmesa_blit_state_destroy( _osmesaBlitState);
   _osmesaBlitState = NULL;
#endif

#ifdef __APPLE__
   MulleGLFWMetalLayerRelease( _metalLayer);
   _metalLayer = NULL;
#endif

   [super dealloc];
}


- (id <UIOSWindow>) OSWindow
{
   return( self);
}


- (NSInteger) shareID
{
   return( _sharingWindow ? [_sharingWindow shareID] : _shareID);
}


- (void) getOSWindowInfo:(struct UIOSWindowInfo *) info
{
   [_windowInfoLock lock];
   {
      *info = _windowInfo;
   }
   [_windowInfoLock unlock];
}


- (BOOL) frameRateLimiter
{
   BOOL   flag;

   [_windowInfoLock lock];
   {
      flag = _windowInfo.frameRateLimiter;
   }
   [_windowInfoLock unlock];

   return( flag);
}


- (void) setFrameRateLimiter:(BOOL) flag
{
   [_windowInfoLock lock];
   {
      _windowInfo.frameRateLimiter = flag;
   }
   [_windowInfoLock unlock];
}


- (mulle_relativetime_t) frameRate
{
   mulle_relativetime_t   frameRate;

   [_windowInfoLock lock];
   {
      frameRate = _windowInfo.frameRate;
   }
   [_windowInfoLock unlock];

   return( frameRate);
}


// hmm, need to thread protect this...
- (mulle_absolutetime_t) lastSwapBuffersTimestamp
{
   return( _lastSwapBuffersTimestamp);
}


- (void) setFrameRate:(mulle_relativetime_t) frameRate
{
   [_windowInfoLock lock];
   {
      _windowInfo.frameRate = frameRate;
   }
   [_windowInfoLock unlock];
}


- (void) setFrameRateHz:(CGFloat) hz
{
   [self setFrameRate:hz <= 0.0 ? 0.0 : 1.0 / hz];
}


- (CGFloat) frameRateHz
{
   double   frameRate;

   frameRate = [self frameRate];
   if( frameRate <= 0.0f)
      return( 0.0f);
   if( isinf( frameRate)) // make positive infinity
      return( INFINITY);
   return( (CGFloat) (1.0 / frameRate));
}


- (NSUInteger) discardEventsMask
{
   void   *mask;

   mask = _mulle_atomic_pointer_read( &_discardEventsMask);
   return( (NSUInteger) mask);
}


- (void) setDiscardEventsMask:(NSUInteger) mask
{
   _mulle_atomic_pointer_write( &_discardEventsMask, (void *) mask);
}


- (id <UIScreen>) screenOrPrimaryScreen:(BOOL) flag
{
   struct UIOSWindowInfo   info;

   [self getOSWindowInfo:&info];

#ifdef DEBUG
   if( ! UIApp)
      MulleUICLog( "UIApp is not available, as +sharedInstance hasn't been called.");
#endif
   // should work for fullscreen as well I believe
   return( [UIApp screenForFrame:info.base.frame
            primaryIfNoneMatches:flag]);
}


- (id <UIScreen>) screen
{
   return( [self screenOrPrimaryScreen:NO]);
}


- (void *) os_window
{
   return( _window);
}


//
// Vends the CAMetalLayer * (as void *) attached on macOS for a GLFW_NO_API
// window. The Metal CG backend pulls this into its CGContext to feed
// nvgCreateMTL(). Returns NULL on non-Apple platforms or non-Metal windows.
// This is a plain C-pointer accessor; it never messages the layer here.
//
- (void *) backendMetalLayer
{
#ifdef __APPLE__
   return( _metalLayer);
#else
   return( NULL);
#endif
}


// bind GL context of the window to the current thread
- (void) os_activateGraphicsContext
{
   // can be called from any thread
   assert( _window);

   UIOSWindowSwapLog( "lock: %p", _window);
   [_contextLock lock];
   //
   // Track the owning thread regardless of backend: the CGContext's
   // -activeThread delegates to us, and CGContextIsActiveInCurrentThread
   // gates rendering on it. Only the GL glfwMakeContextCurrent call is
   // OpenGL-specific; a Metal (GLFW_NO_API) window has no GL context to make
   // current but still owns a render thread.
   //
   if( _haveGraphicsContext)
   {
      UIOSWindowSwapLog( "activate window: %p (thread=%p before-current=%p)",
                          _window, [NSThread currentThread],
                          glfwGetCurrentContext());
      glfwMakeContextCurrent( _window);
   }
   else
      UIOSWindowLogVerbose( "Activated without a GL context (Metal/NO_API)");
   _mulle_atomic_pointer_write( &_atomicActiveThread, [NSThread currentThread]);
}


// maybe a recursive lock would be better.
- (BOOL) os_tryActivateGraphicsContext;
{
   // can be called from any thread
   assert( _window);

   if( ! [_contextLock tryLock])
      return( NO);

   UIOSWindowSwapLog( "lock: %p", _window);

   if( _haveGraphicsContext)
   {
      UIOSWindowSwapLog( "activate window: %p", _window);
      glfwMakeContextCurrent( _window);
   }
   else
      UIOSWindowLogVerbose( "Did activate without a GL context (Metal/NO_API)");
   _mulle_atomic_pointer_write( &_atomicActiveThread, [NSThread currentThread]);

   return( YES);
}


- (void) os_deactivateGraphicsContext
{
   // can be called from any thread
   assert( _window);

   if( _haveGraphicsContext)
   {
      UIOSWindowSwapLog( "deactivate window: %p (thread=%p before-current=%p)",
                          _window, [NSThread currentThread],
                          glfwGetCurrentContext());
      glfwMakeContextCurrent( NULL);
   }
   _mulle_atomic_pointer_write( &_atomicActiveThread, NULL);
   UIOSWindowSwapLog( "unlock: %p", _window);
   [_contextLock unlock];
}


- (NSThread *) activeThread
{
   return( _mulle_atomic_pointer_read( &_atomicActiveThread));
}


- (void) os_setTitleUTF8String:(char *) s
{
   assert( [NSThread mulleIsMainThread]);
   assert( _window);

   s = s ? s : "";

   glfwSetWindowTitle( _window, s);
}


static char  *msaa_utf8string( int value)
{
   switch( value)
   {
   case 0  : return( "NOAA");
   case 4  : return( "MSAA4");
   default : return( "?");
   }
}


static char  *context_vendor_utf8string( int value)
{
   switch( value)
   {
   case GLFW_NATIVE_CONTEXT_API : return( "native");
   case GLFW_EGL_CONTEXT_API    : return( "egl");
   case GLFW_OSMESA_CONTEXT_API : return( "mesa");
   default                      : return( "?");
   }
}


static char  *context_api_utf8string( int value)
{
   switch( value)
   {
   case GLFW_NO_API        : return( "NONE");
   case GLFW_OPENGL_ES_API : return( "GLES");
   case GLFW_OPENGL_API    : return( "GL");
   default                 : return( "???");
   }
}


static char  *context_profile_utf8string( int value)
{
   switch( value)
   {
   case GLFW_OPENGL_ANY_PROFILE    : return( "?");
   case GLFW_OPENGL_CORE_PROFILE   : return( "Core_API");
   case GLFW_OPENGL_COMPAT_PROFILE : return( "Full_API");
   default                         : return( "???");
   }
}


- (char *) os_contextInfoUTF8String
{
   int    api;
   int    vendor;
   int    profile;
   int    major;
   int    minor;
   int    revision;
   int    forward;
   char   *s;
   char   *profile_s;
   char   *profile_prefix;
   char   *forward_s;
   char   *forward_prefix;
   int    glfw_major;
   int    glfw_minor;
   int    glfw_revision;

   assert( [NSThread mulleIsMainThread]);

   api      = glfwGetWindowAttrib( _window, GLFW_CLIENT_API);
   vendor   = glfwGetWindowAttrib( _window, GLFW_CONTEXT_CREATION_API);
   profile  = glfwGetWindowAttrib( _window, GLFW_OPENGL_PROFILE);
   major    = glfwGetWindowAttrib( _window, GLFW_CONTEXT_VERSION_MAJOR);
   minor    = glfwGetWindowAttrib( _window, GLFW_CONTEXT_VERSION_MINOR);
   revision = glfwGetWindowAttrib( _window, GLFW_CONTEXT_REVISION);
   forward  = glfwGetWindowAttrib( _window, GLFW_OPENGL_FORWARD_COMPAT);

   profile_s      = context_profile_utf8string( profile);
   profile_prefix = *profile_s ? " " : "";
   forward_s      = forward ? "forward" : "";
   forward_prefix = *forward_s ? " " : "";

   glfwGetVersion( &glfw_major, &glfw_minor, &glfw_revision);

   s = MulleObjC_asprintf( "%s %u.%u.%u%s%s%s%s %s (%s) [%s] - GLFW v%d.%d.%d",
                           context_api_utf8string( api),
                           major,
                           minor,
                           revision,
                           profile_prefix,
                           profile_s,
                           forward_prefix,
                           forward_s,
                           msaa_utf8string( _antiAliasing ? 4 : 0),
                           context_vendor_utf8string( vendor),
                           glGetString( GL_RENDERER) ? (char *) glGetString( GL_RENDERER) : "unknown",
                           glfw_major,
                           glfw_minor,
                           glfw_revision);
   return( s);
}


static struct
{
   unsigned int  key;
   char          *value;
   char          *inv_value;
} attribute_map[] =
{
   { GLFW_VISIBLE,                 "visible",     "invisible" },
   { GLFW_RESIZABLE,               "resizable",   "fixed"     },
   { GLFW_DECORATED,               "decorated",   "bare"      },
   { GLFW_TRANSPARENT_FRAMEBUFFER, "transparent", "opaque"    }
};


- (char *) os_windowInfoUTF8String
{
   char           *values[ 5];
   unsigned int   i;
   char           *s;

   assert( [NSThread mulleIsMainThread]);

   for( i = 0; i < 4; i++)
      values[ i] = glfwGetWindowAttrib( _window, attribute_map[ i].key)
                     ? attribute_map[ i].value
                     : attribute_map[ i].inv_value;

   values[ 4] = (_styleMask & UIWindowStyleSingleBuffer) ? "single" : "double";

   s = MulleObjC_asprintf( "%s,%s,%s,%s,%s",
                           values[ 0],
                           values[ 1],
                           values[ 2],
                           values[ 3],
                           values[ 4]);
   return( s);
}


- (void) os_swapBuffers
{
   // can be called from any thread
   // it'as assume that context need not be active here, but is it true ?
   assert( _window);

   // TODO: atomic ?
   if( _haveGraphicsContext)
   {
      // https://github.com/glfw/glfw/issues/2109
      if( glfwGetWindowAttrib( _window, GLFW_VISIBLE))
      {
         UIOSWindowSwapLog( "\033[1mswapped buffers\033[0m (thread=%p current-before-swap=%p %s)",
                             [NSThread currentThread], glfwGetCurrentContext(),
                             glfwGetCurrentContext() == _window ? "MATCH" : "*** MISMATCH ***");

#if MULLE_GLFW_OSMESA
         if( glfwGetWindowAttrib( _window, GLFW_CONTEXT_CREATION_API)
               == GLFW_OSMESA_CONTEXT_API)
         {
            // glfwSwapBuffers is a confirmed no-op for OSMesa contexts.
            // Lazily create the blit state on first swap.
            int   buf_w, buf_h, buf_fmt;
            void *pixels = NULL;

            glfwGetOSMesaColorBuffer( _window, &buf_w, &buf_h,
                                      &buf_fmt, &pixels);
            fprintf( stderr, "[OSMesa blit] glfwGetOSMesaColorBuffer: "
                     "pixels=%p buf_w=%d buf_h=%d buf_fmt=0x%x\n",
                     pixels, buf_w, buf_h, buf_fmt);
            if( pixels && buf_fmt == GL_RGBA)
            {
               if( ! _osmesaBlitState)
               {
                  fprintf( stderr, "[OSMesa blit] creating blit state\n");
                  _osmesaBlitState = mulle__osmesa_blit_state_create(
                                          _window, buf_w, buf_h);
                  fprintf( stderr, "[OSMesa blit] blit state=%p\n",
                           _osmesaBlitState);
               }
               if( _osmesaBlitState)
                  mulle__osmesa_do_blit( _osmesaBlitState,
                                        pixels, buf_w, buf_h);
            }
         }
         else
#endif // MULLE_GLFW_OSMESA
         {
            glfwSwapBuffers( _window);
         }

         // swapping buffers can take some time, so refresh with actual
         // TODO: atomic ?
         _lastSwapBuffersTimestamp = mulle_absolutetime_now();  // or do we need ... now here ?
      }
   }
   else
      UIOSWindowLogVerbose( "Can't swap, have no graphics context");
}


- (void) os_setSwapInterval:(NSUInteger) value
{
   // can be called from any thread
   if( _haveGraphicsContext)
   {
      UIOSWindowSwapLog( " swap interval set to %d", (int) value);
      glfwSwapInterval( (int) value);  // need for smooth pointer/control sync
   }
   else
      UIOSWindowLogVerbose( "Can't set swap interval, have no graphics context");
}


- (void) os_requestClose
{
   // can be called from any thread
   // we are finalized if _window nil 
   if( _window)
      glfwSetWindowShouldClose( _window, GL_TRUE);
   else
      UIOSWindowLogVerbose( "Can't set request close, have no window any more");
}


- (BOOL) os_windowShouldClose
{
   BOOL   flag;

   // can be called from any thread
   // we are finalized if _window nil 
   if( ! _window)
      return( YES);


   flag = glfwWindowShouldClose( _window) ? YES : NO;
   return( flag);
}


- (void) applicationDidChangeWindowCount:(NSUInteger) count
{
   MULLE_C_UNUSED( count);
   // no-op: GLFWOSWindow delegates window-level behaviour to UIWindow.
   // UIApplication calls this on every window when the count changes; the
   // higher-level UIWindow (e.g. UIPureWindow) uses it to tune
   // keepOSGraphicsContextActive. A bare GLFWOSWindow has nothing to do here,
   // but the UIOSWindow protocol requires the method to exist (UIApplication
   // invokes it unconditionally).
}


- (void) applicationDidAddWindow:(UIApplication *) app
{
   MULLE_C_UNUSED( app);

   assert( [NSThread mulleIsMainThread]);
   // ignore
}


- (void) applicationDidRemoveWindow:(UIApplication *) app
{
   MULLE_C_UNUSED( app);

   assert( [NSThread mulleIsMainThread]);
   [self mullePerformFinalize];
}



- (BOOL) shouldClose
{
   return( [self os_windowShouldClose]);
}


- (void) os_show
{
   assert( [NSThread mulleIsMainThread]);
   assert( _window);

   glfwShowWindow( _window);
}


- (void) os_hide
{
   assert( [NSThread mulleIsMainThread]);
   assert( _window);

   glfwHideWindow( _window);
}


- (void) os_destroyWindow
{
   if( _window)
   {
#if MULLE_GLFW_OSMESA
      // Destroy blit state before the window — the blit state borrows native
      // handles (Display*, wl_surface*) that are valid only while _window lives.
      mulle__osmesa_blit_state_destroy( _osmesaBlitState);
      _osmesaBlitState = NULL;
#endif
#ifdef __APPLE__
      // Release the CAMetalLayer before the window/view it is attached to.
      MulleGLFWMetalLayerRelease( _metalLayer);
      _metalLayer = NULL;
#endif
      glfwDestroyWindow( _window);
      _window = NULL;
   }
}


- (CGPoint) os_windowPosition
{
   int   x;
   int   y;

   assert( [NSThread mulleIsMainThread]);
   assert( _window);

   glfwGetWindowPos( _window, &x, &y);
   return( CGPointMake( x, y));
}


- (CGSize) os_windowSize
{
   int   w;
   int   h;

   assert( [NSThread mulleIsMainThread]);
   assert( _window);

   glfwGetWindowSize( _window, &w, &h);
   return( CGSizeMake( w, h));
}


- (CGRect) os_windowFrame
{
   int      x;
   int      y;
   int      w;
   int      h;
   CGRect   frame;

   assert( [NSThread mulleIsMainThread]);
   assert( _window);

   glfwGetWindowPos( _window, &x, &y);
   glfwGetWindowSize( _window, &w, &h);  // just to be sure...

   frame.origin = CGPointMake( x, y);
   frame.size   = CGSizeMake( w, h);
   return( frame);
}


- (void) os_setWindowPosition:(CGPoint) origin
{
   assert( [NSThread mulleIsMainThread]);
   assert( _window);

   glfwSetWindowPos( _window, (int) origin.x, (int) origin.y);
}


- (void) os_setWindowSize:(CGSize) size
{
   assert( [NSThread mulleIsMainThread]);
   assert( _window);

   glfwSetWindowSize( _window, (int) size.width, (int) size.height);
}


- (void) os_setWindowFrame:(CGRect) rect
{
   assert( [NSThread mulleIsMainThread]);
   assert( _window);

   glfwSetWindowPos( _window, (int) rect.origin.x, (int) rect.origin.y);
   glfwSetWindowSize( _window, (int) rect.size.width, (int) rect.size.height);
}


- (CGPixelSize) os_framebufferSize
{
   int   w;
   int   h;

   assert( [NSThread mulleIsMainThread]);
   assert( _window);

   glfwGetFramebufferSize( _window, &w, &h);  // just to be sure...

#ifdef __APPLE__
   // Keep the attached CAMetalLayer's drawable resolution in sync with the
   // window framebuffer size. Metal (unlike GL) has no implicit backbuffer:
   // nextDrawable's texture is sized from the layer's drawableSize, so if we
   // never set it the presented drawable does not match the window and nothing
   // shows. The reference nanovg-Metal demo sets this every frame from
   // glfwGetFramebufferSize; os_framebufferSize is the equivalent single point
   // in this integration (called on the main thread on init and on resize).
   if( _metalLayer && w > 0 && h > 0)
      MulleGLFWMetalLayerSetDrawableSize( _metalLayer, (double) w, (double) h);
#endif

   return( CGPixelSizeMake( w, h));
}


// TODO: framebuffer / size ?
- (CGVector) os_UIScale
{
   assert( [NSThread mulleIsMainThread]);
   assert( _window);

//   float xscale, yscale;

//   glfwGetWindowContentScale( _window, &xscale, &yscale);
//   return( CGVectorMake( xscale, yscale));
   return( CGVectorMake( 1.0, 1.0));
}


- (void) os_setCursor:(UICursor *) cursor
{
   assert( [NSThread mulleIsMainThread]);
   assert( _window);

   glfwSetCursor( _window, cursor);
}


- (void) os_setCursorCaptured:(BOOL) captured
{
   assert( [NSThread mulleIsMainThread]);
   assert( _window);

   glfwSetInputMode( _window, GLFW_CURSOR,
                     captured ? GLFW_CURSOR_DISABLED : GLFW_CURSOR_NORMAL);
}


//
// OS Pasteboard
// prefix with os ?
- (char *) pasteboardCString
{
   assert( [NSThread mulleIsMainThread]);
   assert( _window);

   return( (char *) glfwGetClipboardString( _window));
}


- (void) setPasteboardCString:(char *) s
{
   assert( [NSThread mulleIsMainThread]);
   assert( _window);

   glfwSetClipboardString( _window, s ? s : "");
}


//
// This flag is set by the OS (or the window thread) to indicate that
// either the most current offscreen buffer should be now copied to the
// foreground window (thread) or that everything needs to be drawn
// (direct)
//
- (void) setNeedsRefresh
{
   _mulle_atomic_pointer_write( &_needsRefresh, (void *) 1);

   //
   // this should preempt a waiting UIApplication (unless busy executing
   // events, which it shouldn't :) and then it will ask us if we need
   // to draw the frame...
   //
   [[UIApplication sharedInstance] os_sendEmptyEvent];
}


- (mulle_relativetime_t) displayFrameIfNeeded:(mulle_absolutetime_t) now
{
   mulle_relativetime_t   diff;
   mulle_relativetime_t   left;
   mulle_relativetime_t   frameRate;

   assert( [NSThread mulleIsMainThread]);

   frameRate = [self frameRate];

   if( _mulle_atomic_pointer_read( &_needsRefresh) == NULL)
   {
      // if we don't need a refresh, check if we can wait another frame.
      // if yes, return the temporal distance.
      //
      diff = (now - _lastSwapBuffersTimestamp);
      assert( now > _lastSwapBuffersTimestamp);

      left = frameRate - diff;

//      fprintf( stderr, "%p - frameRate:%.4f now:%.4f last:%.4f diff:%.4f left %.4fs\n",
//                           self, _frameRate, now, _lastSwapBuffersTimestamp, diff, left);

      if( left > 0.0)
         return( left);
   }

   // reset to 0, if this fails.. hmm a) it shouldn't b) it should if we
   // are framerate refreshing c) if it physically fails, just redraw again
   // next time, someone wants it maybe
   _mulle_atomic_pointer_cas( &_needsRefresh, (void *) 0, (void *) 1);

   [self os_activateGraphicsContext];
   {
     (*self->_frameCallback)( self);
     [self os_swapBuffers]; // sets _lastSwapBuffersTimestamp
   }
   [self os_deactivateGraphicsContext];


//   fprintf( stderr, "%p - swapped now:%.4f really:%.4f\n",
//                           self, now, mulle_absolutetime_now());

   return( frameRate);
}


- (void) setWindowEventsCallback:(UIOSWindowEventCallback_t) callback
{
   _windowEventsCallback = callback;
   if( callback)
      [self os_initWindowEvents];
}


- (void) setOtherRetainedEventsCallback:(UIOSWindowRetainedEventCallback_t) callback
{
   _otherRetainedEventsCallback = callback;
   if( callback)
      [self os_initInputEvents];
}


- (void) eventHandlingWithFrameRate:(mulle_relativetime_t) frameRate
{
   MULLE_C_UNUSED( frameRate);
   // GLFWOS windows handles events immediately
   // with the above callbacks
}


- (void) syncOSWindowPropertyChangesIfNeeded
{
}


- (struct UIInputState) inputState
{
   struct UIInputState  rval;

   NSLockingDo( _inputStateLock)
   {
      rval = _inputState;
   }
   return( rval);
}


- (CGPoint) mouseLocation
{
   CGPoint  rval;

   NSLockingDo( _inputStateLock)
   {
      rval = _inputState.locationInWindow;
   }
   return( rval);
}


- (NSUInteger) buttonStates
{
   NSUInteger  rval;

   NSLockingDo( _inputStateLock)
   {
      rval = _inputState.buttonStates;
   }
   return( rval);
}


- (NSUInteger) keyModifiers
{
   NSUInteger  rval;

   NSLockingDo( _inputStateLock)
   {
      rval = _inputState.keyModifiers;
   }
   return( rval);
}


- (struct UIKeyStates) keyStates
{
   struct UIKeyStates  rval;

   NSLockingDo( _inputStateLock)
   {
      rval = _inputState.keyStates;
   }
   return( rval);
}


- (NSUInteger) os_pressedKeys:(NSUInteger *) keys
                        count:(NSUInteger) count
{
   NSUInteger   n;
   int          key;

   assert( _window);

   n = 0;
   for( key = GLFW_KEY_SPACE; key <= GLFW_KEY_LAST; key++)
   {
      if( n >= count)
         break;
      if( glfwGetKey( _window, key) == GLFW_PRESS)
         keys[ n++] = key;  // GLFW key values == UIEventKey values
   }
   return( n);
}


- (void) os_pollInputState:(struct UIInputState *) state
{
   double   x, y;

   assert( _window);
   assert( state);

   memset( state, 0, sizeof( struct UIInputState));

   glfwGetCursorPos( _window, &x, &y);
   state->locationInWindow.x = x;
   state->locationInWindow.y = y;

   if( glfwGetMouseButton( _window, GLFW_MOUSE_BUTTON_LEFT) == GLFW_PRESS)
      state->buttonStates |= (1 << 0);
   if( glfwGetMouseButton( _window, GLFW_MOUSE_BUTTON_RIGHT) == GLFW_PRESS)
      state->buttonStates |= (1 << 1);
   if( glfwGetMouseButton( _window, GLFW_MOUSE_BUTTON_MIDDLE) == GLFW_PRESS)
      state->buttonStates |= (1 << 2);
   if( glfwGetMouseButton( _window, GLFW_MOUSE_BUTTON_4) == GLFW_PRESS)
      state->buttonStates |= (1 << 3);
   if( glfwGetMouseButton( _window, GLFW_MOUSE_BUTTON_5) == GLFW_PRESS)
      state->buttonStates |= (1 << 4);

   if( glfwGetKey( _window, GLFW_KEY_LEFT_SHIFT) == GLFW_PRESS ||
       glfwGetKey( _window, GLFW_KEY_RIGHT_SHIFT) == GLFW_PRESS)
      state->keyModifiers |= (1 << 0);

   if( glfwGetKey( _window, GLFW_KEY_LEFT_CONTROL) == GLFW_PRESS ||
       glfwGetKey( _window, GLFW_KEY_RIGHT_CONTROL) == GLFW_PRESS)
      state->keyModifiers |= (1 << 1);

   if( glfwGetKey( _window, GLFW_KEY_LEFT_ALT) == GLFW_PRESS ||
       glfwGetKey( _window, GLFW_KEY_RIGHT_ALT) == GLFW_PRESS)
      state->keyModifiers |= (1 << 2);

   if( glfwGetKey( _window, GLFW_KEY_LEFT_SUPER) == GLFW_PRESS ||
       glfwGetKey( _window, GLFW_KEY_RIGHT_SUPER) == GLFW_PRESS)
      state->keyModifiers |= (1 << 3);

   state->keyStates._count = [self os_pressedKeys:state->keyStates._keys
                                            count:UIKeyStatesMaxKeys];
}


- (NSUInteger) pressedKeys:(NSUInteger *) keys
                     count:(NSUInteger) count
{
   NSUInteger   n;

   NSLockingDo( _inputStateLock)
   {
      n = UIKeyStatesGetPressedKeys( UIInputStateGetKeyStates( &_inputState),
                                     keys,
                                     count);
   }
   return( n);
}

@end

//
// Copyright (c) 2021 Nat!, Mulle kybernetiK
//
#import "GLFWOSWindow.h"

#import "import-private.h"

#import "GLFWOSWindow+UIEvent.h"



@interface GLFWOSWindow( UIEventFuture)

- (void) _windowFramebufferResizeCallback:(struct CGBitmapSize) size;

@end



@implementation GLFWOSWindow

static struct
{
   mulle_atomic_pointer_t   shareIds;
} Self;


// as we don't know, if we even use OpenGL here
static void   defaultFrameCallback( GLFWOSWindow *window)
{
   fprintf( stderr, "The GLFW window needs a frameCallback.\n"
"Typically you can use something like this with OpenGL:\n"
"   static void  frameCallback( GLFWOSWindow *window)\n"
"   {\n"
"      struct CGBitmapSize   framebufferSize;\n"
"\n"
"      framebufferSize = [window os_framebufferSize];\n"
"      glViewport( 0, 0, framebufferSize.width, framebufferSize.height);\n"
"      glClearColor( 0, 0, 0, 0);\n"
"      glClear( GL_COLOR_BUFFER_BIT);\n"
"   }\n"
"\n"
"   [glfwWindow setFrameCallback:frameCallback];\n"
"\n");
   abort();
}


+ (instancetype) windowWithFrame:(CGRect) frame
                 titleUTF8String:(char *) title
                       styleMask:(NSUInteger) styleMask
{
   return( [[[self alloc] initWithFrame:frame
                        titleUTF8String:title
                              styleMask:styleMask] autorelease]);
}


+ (instancetype) windowWithFrame:(CGRect) frame
                 titleUTF8String:(char *) title
                       styleMask:(NSUInteger) styleMask
                   graphicsHints:(enum GLFWGraphicsHints) graphicsHints
{
   return( [[[self alloc] initWithFrame:frame
                        titleUTF8String:title
                              styleMask:styleMask
                          graphicsHints:graphicsHints] autorelease]);
}

// sharingWindow is retained. We will be able to share textures with it
+ (instancetype) windowWithFrame:(CGRect) frame
                 titleUTF8String:(char *) title
                       styleMask:(NSUInteger) styleMask
                   graphicsHints:(enum GLFWGraphicsHints) graphicsHints
                   sharingWindow:(id <UIOSWindow>) sharingWindow
{
   return( [[[self alloc] initWithFrame:frame
                        titleUTF8String:title
                              styleMask:styleMask
                          graphicsHints:graphicsHints
                          sharingWindow:sharingWindow] autorelease]);
}


#ifdef DEBUG
static void   break_on_me( void)
{
}
#endif


static enum UIGraphicsBackend  getWindowBackend( GLFWwindow *window)
{
   int   api;
   int   forward;
   int   major;
   int   minor;

   api = glfwGetWindowAttrib( window, GLFW_CLIENT_API);
   if( api != GLFW_NO_API)
   {
      major    = glfwGetWindowAttrib( window, GLFW_CONTEXT_VERSION_MAJOR);
      minor    = glfwGetWindowAttrib( window, GLFW_CONTEXT_VERSION_MINOR);
      forward  = glfwGetWindowAttrib( window, GLFW_OPENGL_FORWARD_COMPAT);

      if( api == GLFW_OPENGL_ES_API)
         return( major >= 3 ? UIGraphicsBackendGLES3 : UIGraphicsBackendGLES2);

      if( (major == 3 && minor >= 2) || major > 3)
         return( forward ? UIGraphicsBackendGL3_2Forward : UIGraphicsBackendGL3_2);
      return( forward ? UIGraphicsBackendGL3Forward : UIGraphicsBackendGL3);
   }
   return( UIGraphicsBackendNone);
}


// hope for fractional positioning in future ?
//
// gdb:
// b initWithFrame:titleUTF8String:styleMask:graphicsHints:sharingWindow:
//
- (instancetype) initWithFrame:(CGRect) frame
               titleUTF8String:(char *) title
                     styleMask:(NSUInteger) styleMask
                 graphicsHints:(enum GLFWGraphicsHints) hints
                 sharingWindow:(id <UIOSWindow>) sharingWindow
{
   int   profile;
   int   forward;
   int   major;
   int   minor;
   int   api;
   int   lib;
   int   first_lib;

   assert( [NSThread mulleIsMainThread]);

#ifdef DEBUG
   break_on_me();
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
   profile = -1;
   forward = -1;
   major   = -1;
   minor   = -1;
   api     = -1;
   lib     = -1;

//
// These function can only be called from main thread (see above)
//
// GLFW_OPENGL_FORWARD_COMPAT specifies whether the OpenGL context has
// deprecated functionality removed.
// GLFW_OPENGL_CORE_PROFILE is a subset of OpenGL similiar to OpenGLES
//
   if( styleMask & UIWindowOpenGLDeprecated)
   {
      hints = GLFWGraphicsHintsBySettingAPI( hints, 3);     // setOpenGL
      hints = GLFWGraphicsHintsBySettingProfile( hints, 0); // no core profile (guess)
      hints = GLFWGraphicsHintsBySettingForward( hints, 0); // no forward

      assert( ! (styleMask & UIWindowOpenGLForward));
      assert( ! (styleMask & UIWindowOpenGLCoreProfile)) ;
   }

   major = GLFWGraphicsHintsGetMajor( hints);
   if( major)
   {
      glfwWindowHint( GLFW_CONTEXT_VERSION_MAJOR, major);
      minor = GLFWGraphicsHintsGetMinor( hints);
      glfwWindowHint( GLFW_CONTEXT_VERSION_MINOR, minor);
   }

   forward = styleMask & UIWindowOpenGLForward;
   if( forward)
      hints = GLFWGraphicsHintsBySettingForward( hints, 1);

   // not super sure about this, but lets try to avoid "old" OpenGL
   // calls. alas, we are doing OpenGLES 2.0 minimum, so I don't know
   // if this is useful.

   switch( GLFWGraphicsHintsGetAPI( hints))
   {
   case 1  : api = GLFW_NO_API; break;  // special, don't want to hit this by default
   case 2  : api = GLFW_OPENGL_ES_API; break;
   case 3  : api = GLFW_OPENGL_API; break;
   }
   if( api != -1)
      glfwWindowHint( GLFW_CLIENT_API, api);

   // For OpenGL 3+ there is no "gimme" what you got, we demand :)
   if( (major > 3 || (major == 3 && minor >= 2)) && api == GLFW_OPENGL_API)
   {
      if( styleMask & UIWindowOpenGLCoreProfile)
         hints = GLFWGraphicsHintsBySettingProfile( hints, 1);
      else
         hints = GLFWGraphicsHintsBySettingProfile( hints, 2);
   }

   switch( GLFWGraphicsHintsGetProfile( hints))
   {
   case 0  : profile = GLFW_OPENGL_ANY_PROFILE; break;
   case 1  : profile = GLFW_OPENGL_CORE_PROFILE; break;
   case 2  : profile = GLFW_OPENGL_COMPAT_PROFILE; break;
   }

   // you can't set this or GLFW_OPENGL_CORE_PROFILE or GLFW_OPENGL_COMPAT_PROFILE on GL < 3.2
   if( profile != -1)
      glfwWindowHint( GLFW_OPENGL_PROFILE, profile);

   // forward compatibility is actually fairly restrictive
   // https://www.glfw.org/docs/3.3/window_guide.html#GLFW_OPENGL_FORWARD_COMPAT_hint
   if( GLFWGraphicsHintsGetForward( hints))
      glfwWindowHint( GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE);  // why not ?

   // remember what was opened first for retries
   switch( GLFWGraphicsHintsGetAPILibrary( hints))
   {
   case 0 : lib = GLFW_NATIVE_CONTEXT_API; break;
   case 1 : lib = GLFW_EGL_CONTEXT_API; break;
   case 2 : lib = GLFW_OSMESA_CONTEXT_API; break;
   }
   first_lib = lib;

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

      code = glfwGetError( &description);
      switch( code)
      {
      case 65542 :
         if( styleMask & UIWindowOpenGLLibraryFallback)
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
         break;

      case 65537 :
         fprintf( stderr, "UIApplication is likely not initialized yet\n");
      }
      fprintf( stderr, "error #%d: glfwCreateWindow failed \"%s\"\n", code, description);
      [self release];
      return( nil);
   }

   _sharingWindow = (GLFWOSWindow *) [sharingWindow retain];
   if( ! _sharingWindow)
      _shareId = (NSInteger) _mulle_atomic_pointer_increment( &Self.shareIds) + 1;

   if( _sharingWindow)
      fprintf( stderr, "window %p (sharing with %p) created\n", _window, _sharingWindow);
   else
      fprintf( stderr, "window %p created\n", _window);

   // this is basically the "rendezvous" point where nanoVG latches unto
   // its also the receiver for OpenGL calls. That's why we need a window
   // to draw stuff
   //
   glfwSetWindowUserPointer( _window, self);

   // zero origin means: let window manager choose
   if( ! CGPointEqualToPoint( frame.origin, CGPointZero))
      glfwSetWindowPos( _window, (int) frame.origin.x, (int) frame.origin.y);

   _contextLock                 = [NSLock new];
   glfwMakeContextCurrent( NULL); // turn off to be consistent with lock

   _mulle_atomic_pointer_nonatomic_write( &_needsRefresh, (void *) 1);

   _backend                     = getWindowBackend( (GLFWwindow *) _window);
   _frameCallback               = defaultFrameCallback;
   _haveGraphicsContext         = glfwGetWindowAttrib( _window, GLFW_CLIENT_API) != GLFW_NO_API;
   _mouseLocation               = CGPointMake( -1.0, -1.0);
   _otherRetainedEventsCallback = GLFWOSWindowRetainedEventDefaultCallback;
   _scrollWheelSensitivity      = 20.0;
   _styleMask                   = styleMask;
   _windowEventsCallback        = GLFWOSWindowEventDefaultCallback;

   assert( (api == GLFW_NO_API && ! _haveGraphicsContext) || _haveGraphicsContext);

   if( ! (styleMask & UIWindowStyleInvisible))
      [self os_show];

#ifdef DEBUG
   fprintf( stderr, "window style            : %s\n", [self os_windowInfoUTF8String]);
   fprintf( stderr, "window graphics context : %s\n", [self os_contextInfoUTF8String]);
#endif

   // read values once, afterwards these values are just updated by events
   // framerate by default
   _windowInfo.frameRate = UIWindowFrameRateAsync;

   [self updateWindowInfo];

   // init afterwards
   _windowInfoLock = [NSLock new];

   return( self);
}


- (instancetype) initWithFrame:(CGRect) frame
               titleUTF8String:(char *) title
                     styleMask:(NSUInteger) styleMask
                 graphicsHints:(enum GLFWGraphicsHints) hints
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
                 graphicsHints:0
                 sharingWindow:nil]);
}


- (void) finalize
{
   // keep render context locked. As the window/context will be unusuable
   // a deadlock seems preferable and easier to debug for misbehavers
   [_contextLock tryLock]; // if already locked don't deadlock here

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

   [super dealloc];
}


- (id <UIOSWindow>) OSWindow
{
   return( self);
}


- (NSInteger) shareId
{
   return( _sharingWindow ? [_sharingWindow shareId] : _shareId);
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


- (id <UIScreen>) screenOrPrimaryScreen:(BOOL) flag
{
   struct UIOSWindowInfo   info;

   [self getOSWindowInfo:&info];

   // should work for fullscreen as well I believe
   return( [[UIApplication sharedInstance] screenForFrame:info.base.frame
                                     primaryIfNoneMatches:flag]);
}


- (id <UIScreen>) screen
{
   return( [self screenOrPrimaryScreen:NO]);
}


- (void) os_destroyWindow
{
   if( _window)
   {
      glfwDestroyWindow( _window);
      _window = NULL;
   }
}


- (void *) os_window
{
   return( _window);
}


// bind GL context of the window to the current thread
- (void) os_activateGraphicsContext
{
   // can be called from any thread
   assert( _window);

   [_contextLock lock];
   if( _haveGraphicsContext)
      glfwMakeContextCurrent( _window);
}


// maybe a recursive lock would be better.
- (BOOL) os_tryActivateGraphicsContext;
{
   // can be called from any thread
   assert( _window);

   if( ! [_contextLock tryLock])
      return( NO);

   if( _haveGraphicsContext)
      glfwMakeContextCurrent( _window);
   return( YES);
}


- (void) os_deactivateGraphicsContext
{
   // can be called from any thread
   assert( _window);

   if( _haveGraphicsContext)
      glfwMakeContextCurrent( NULL);
   [_contextLock unlock];
}


- (void) os_setTitleUTF8String:(char *) s
{
   assert( [NSThread mulleIsMainThread]);
   assert( _window);

   s = s ? s : "";

   glfwSetWindowTitle( _window, s);
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
   case GLFW_OPENGL_ANY_PROFILE    : return( "");
   case GLFW_OPENGL_CORE_PROFILE   : return( "Core API");
   case GLFW_OPENGL_COMPAT_PROFILE : return( "Complete API");
   default                         : return( "?");
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

   s = MulleObjC_asprintf( "%s %u.%u.%u%s%s%s%s (%s)",
                           context_api_utf8string( api),
                           major,
                           minor,
                           revision,
                           profile_prefix,
                           profile_s,
                           forward_prefix,
                           forward_s,
                           context_vendor_utf8string( vendor));
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

   if( _haveGraphicsContext)
   {
      // https://github.com/glfw/glfw/issues/2109
      if( glfwGetWindowAttrib( _window, GLFW_VISIBLE))
         glfwSwapBuffers( _window);
   }
}


- (void) os_setSwapInterval:(NSUInteger) value
{
   // can be called from any thread
   if( _haveGraphicsContext)
      glfwSwapInterval( (int) value);  // need for smooth pointer/control sync
}


- (void) os_requestClose
{
   // can be called from any thread
   assert( _window);

   glfwSetWindowShouldClose( _window, GL_TRUE);
}


- (BOOL) os_windowShouldClose
{
   // can be called from any thread
   assert( _window);

   return( glfwWindowShouldClose( _window) ? YES : NO);
}


- (void) applicationDidAddWindow
{
   // ignore
}


- (void) applicationDidRemoveWindow
{
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


- (struct CGBitmapSize) os_framebufferSize
{
   int   w;
   int   h;

   assert( [NSThread mulleIsMainThread]);
   assert( _window);

   glfwGetFramebufferSize( _window, &w, &h);  // just to be sure...
   return( CGBitmapSizeMake( w, h));
}


- (CGVector) os_UIScale
{
   float xscale, yscale;

//   glfwGetWindowContentScale( _window, &xscale, &yscale);
//   return( CGVectorMake( xscale, yscale));
   return( CGVectorMake( 1.0, 1.0));
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
   [UIEvent os_sendEmptyEvent];
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
     [self os_swapBuffers];
   }
   [self os_deactivateGraphicsContext];

   _lastSwapBuffersTimestamp = now;  // or do we need ..._now() here ?

//   fprintf( stderr, "%p - swapped now:%.4f really:%.4f\n",
//                           self, now, mulle_absolutetime_now());

   return( frameRate);
}


- (void) setWindowEventsCallback:(GLFWOSWindowEventCallback_t) callback
{
   _windowEventsCallback = callback;
   if( callback)
      [self os_initWindowEvents];
}


- (void) setOtherRetainedEventsCallback:(GLFWOSWindowRetainedEventCallback_t) callback
{
   _otherRetainedEventsCallback = callback;
   if( callback)
      [self os_initInputEvents];
}


- (void) eventHandlingWithFrameRate:(mulle_relativetime_t) frameRate
{
   // GLFWOS windows handles events immediately
   // with the above callbacks
}


- (void) writeOSWindowPropertyChangesIfNeeded
{
   // GLFWOS windows property changes immediately
}

@end

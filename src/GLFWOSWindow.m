//
// Copyright (c) 2021 Nat!, Mulle kybernetiK
//
#define GL_SILENCE_DEPRECATION

#import "GLFWOSWindow.h"

#import "import-private.h"

#import "GLFWOSWindow+UIEvent.h"
#import <MulleUIApplication/UIOSWindow+DebugPrivate.h>



@interface GLFWOSWindow( UIEventFuture)

- (void) _windowFramebufferResizeCallback:(CGPixelSize) size;

@end

#pragma clang diagnostic ignored "-Wprotocol"


@implementation NSObject( GLFWOSWindow)

- (BOOL) __isUIOSWindow
{
   return( NO);
}

@end


@implementation GLFWOSWindow

- (BOOL) __isUIOSWindow
{
   return( YES);
}


static struct
{
   mulle_atomic_pointer_t   _shareIDs;
   NSUInteger               _debuggingFlags;
} Self;


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
      Self._debuggingFlags = strtol( s, NULL, 0);
}


+ (void) setDebuggingFlags:(NSUInteger) flag  MULLE_OBJC_THREADSAFE_METHOD
{
   Self._debuggingFlags = flag;
}


// as we don't know, if we even use OpenGL here
static int   defaultFrameCallback( GLFWOSWindow *window)
{
   fprintf( stderr, "The GLFW window needs a frameCallback.\n"
"Typically you can use something like this with OpenGL:\n"
"   static int  frameCallback( GLFWOSWindow *window)\n"
"   {\n"
"      CGPixelSize   framebufferSize;\n"
"\n"
"      framebufferSize = [window os_framebufferSize];\n"
"      glViewport( 0, 0, framebufferSize.width, framebufferSize.height);\n"
"      glClearColor( 0, 0, 0, 0);\n"
"      glClear( GL_COLOR_BUFFER_BIT);\n"
"      return( 0);  // or 1, if you are animating\n"
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
                   graphicsHints:(GLFWGraphicsHints) graphicsHints
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
                   graphicsHints:(GLFWGraphicsHints) graphicsHints
                   sharingWindow:(id <UIOSWindow>) sharingWindow
{
   return( [[[self alloc] initWithFrame:frame
                        titleUTF8String:title
                              styleMask:styleMask
                          graphicsHints:graphicsHints
                          sharingWindow:sharingWindow] autorelease]);
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
   int   first_lib;
   int   samples;

   assert( [NSThread mulleIsMainThread]);

#ifdef DEBUG
   glfw_os_window_break_on_me();
#endif

#ifdef GLFW_OS_WINDOW_DEBUGGING_FLAGS
   _debuggingFlags = GLFW_OS_WINDOW_DEBUGGING_FLAGS;
#else
   _debuggingFlags = Self._debuggingFlags;
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
     fprintf( stderr, "Deprecated OpenGL requested\n");
#endif

      hints = GLFWGraphicsHintsBySettingAPI( hints, 3);     // setOpenGL
      hints = GLFWGraphicsHintsBySettingProfile( hints, 3); // compat
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

   // If requesting an OpenGL version below 3.2, GLFW_OPENGL_ANY_PROFILE must
   // be used. if we don't set major, the default in glfw is 1.0
   if( major < 3 || (major == 3 && minor < 2))
      hints = GLFWGraphicsHintsBySettingProfile( hints, 1); //any

   forward = styleMask & UIWindowOpenGLForward;
   if( forward)
      hints = GLFWGraphicsHintsBySettingForward( hints, 1);

   // not super sure about this, but lets try to avoid "old" OpenGL
   // calls. alas, we are doing OpenGLES 2.0 minimum, so I don't know
   // if this is useful.

   switch( GLFWGraphicsHintsGetAPI( hints))
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
         hints = GLFWGraphicsHintsBySettingProfile( hints, 2);
   }

   // TODO: could retry for profiles as well as for libs (see below)
   switch( GLFWGraphicsHintsGetProfile( hints))
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
   if( GLFWGraphicsHintsGetForward( hints))
      glfwWindowHint( GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE);  // why not ?

   // remember what was opened first for retries
   switch( GLFWGraphicsHintsGetAPILibrary( hints))
   {
   case 1 : lib = GLFW_NATIVE_CONTEXT_API; break;
   case 2 : lib = GLFW_EGL_CONTEXT_API; break;
   case 3 : lib = GLFW_OSMESA_CONTEXT_API; break;
   }
   first_lib = lib;

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

      case 65543 :
         aux = "\nThis error may be due to a graphics driver update. Please try rebooting your system.";
         break;

      case 65537 :
         aux = "\nUIApplication is likely not initialized yet.";
      }
      fprintf( stderr, "error #%d: glfwCreateWindow failed \"%s\"%s\n", code, description, aux);
      [self release];
      return( nil);
   }

   // just a sanity assert
   assert( _window);

   _sharingWindow = (GLFWOSWindow *) [sharingWindow retain];
   if( ! _sharingWindow)
      _shareID = (NSInteger) _mulle_atomic_pointer_increment( &Self._shareIDs) + 1;

   if( _sharingWindow)
      UIOSWindowLog( "window %p (sharing with %p) created", _window, _sharingWindow);
   else
      UIOSWindowLog( "window %p created", _window);

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
   _inputState.locationInWindow = CGPointMake( -1.0, -1.0);
   _otherRetainedEventsCallback = GLFWOSWindowRetainedEventDefaultCallback;
   _scrollWheelSensitivity      = 20.0;
   _styleMask                   = styleMask;
   _uninitializedFramebuffer    = YES;
   _windowEventsCallback        = GLFWOSWindowEventDefaultCallback;

   assert( (api == GLFW_NO_API && ! _haveGraphicsContext) || _haveGraphicsContext);

   if( _haveGraphicsContext)
   {
      glfwMakeContextCurrent( _window);  // needed, otherwise glGetIntegerv( GL_SAMPLES_ARB, &samples) fails
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
   }

   _contextLock = [NSLock new];
   glfwMakeContextCurrent( NULL); // turn off to be consistent with lock

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


// bind GL context of the window to the current thread
- (void) os_activateGraphicsContext
{
   // can be called from any thread
   assert( _window);

   UIOSWindowLog( "lock: %p", _window);
   [_contextLock lock];
   if( _haveGraphicsContext)
   {
      UIOSWindowLog( "activate window: %p", _window);
      glfwMakeContextCurrent( _window);
   }      
   else
      UIOSWindowLogVerbose( "Activated, but we have no graphics context");
}


// maybe a recursive lock would be better.
- (BOOL) os_tryActivateGraphicsContext;
{
   // can be called from any thread
   assert( _window);

   if( ! [_contextLock tryLock])
      return( NO);

   UIOSWindowLog( "lock: %p", _window);

   if( _haveGraphicsContext)
   {
      UIOSWindowLog( "activate window: %p", _window);
      glfwMakeContextCurrent( _window);
   }
   else
      UIOSWindowLogVerbose( "Did activate, but we have no graphics context");

   return( YES);
}


- (void) os_deactivateGraphicsContext
{
   // can be called from any thread
   assert( _window);

   if( _haveGraphicsContext)
   {
      UIOSWindowLog( "deactivate window: %p", _window);
      glfwMakeContextCurrent( NULL);
   }
   UIOSWindowLog( "unlock: %p", _window);
   [_contextLock unlock];
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

   s = MulleObjC_asprintf( "%s %u.%u.%u%s%s%s%s %s (%s) - GLFW v%d.%d.%d",
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
         UIOSWindowLogVerbose( "\033[1mswapped buffers\033[0m");
         glfwSwapBuffers( _window);

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
      glfwSwapInterval( (int) value);  // need for smooth pointer/control sync
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


- (void) applicationDidAddWindow:(UIApplication *) app
{
   assert( [NSThread mulleIsMainThread]);
   // ignore
}


- (void) applicationDidRemoveWindow:(UIApplication *) app
{
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
   // GLFWOS windows handles events immediately
   // with the above callbacks
}


- (void) writeOSWindowPropertyChangesIfNeeded
{
   // GLFWOS windows property changes immediately
}


- (CGPoint) mouseLocation
{
   assert( [NSThread mulleIsMainThread]);

   return( _inputState.locationInWindow);
}


- (NSUInteger) buttonStates
{
   assert( [NSThread mulleIsMainThread]);

   return( _inputState.buttonStates);
}


- (NSUInteger) keyModifiers
{
   assert( [NSThread mulleIsMainThread]);

   return( _inputState.keyModifiers);
}


- (char *) UTF8String
{
   char   *s;

   s = MulleObjC_asprintf( "<%s %p>",
                           MulleObjCInstanceGetClassNameUTF8String( self),
                           self);
   return( s);
}

@end

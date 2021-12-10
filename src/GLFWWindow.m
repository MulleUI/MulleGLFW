//
// Copyright (c) 2021 Nat!, Mulle kybernetiK
//
#import "GLFWWindow.h"

#import "import-private.h"

#import "GLFWWindow+UIEvent.h"



@interface GLFWWindow( UIEventFuture)

- (void) _framebufferResizeCallback:(struct CGBitmapSize) size;

@end



@implementation GLFWWindow

void   GLFWWindowEventDefaultCallback( GLFWWindow *window, UIWindowEvent *event)
{
   [window->_windowEventsReceiver handleWindowEvent:event];
}


void   GLFWWindowRetainedEventDefaultCallback( GLFWWindow *window, UIEvent *retainedEvent)
{
   [window->_eventsReceiver queueRetainedEvent:retainedEvent];
}


static struct
{
   mulle_atomic_pointer_t   shareIds;
} Self;


// as we don't know, if we even use OpenGL here
static void   defaultRenderCallback( GLFWWindow *window, CARelativeTime time)
{
   fprintf( stderr, "The GLFW window needs a renderCallback.\n"
"Typically you can use something like this with OpenGL:\n"
"   static void  render( GLFWWindow *window, CARelativeTime now)\n"
"   {\n"
"      struct CGBitmapSize   framebufferSize;\n"
"\n"
"      framebufferSize = [window os_framebufferSize];\n"
"      glViewport( 0, 0, framebufferSize.width, framebufferSize.height);\n"
"      glColor( 0, 0, 0, 0);\n"
"      glClear( GL_COLOR_BUFFER_BIT|GL_STENCIL_BUFFER_BIT);\n"
"   }\n"
"   [glfwWindow setRenderCallback:render];\n"
"\n");
   abort();
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
                   sharingWindow:(GLFWWindow *) sharingWindow
{
   return( [[[self alloc] initWithFrame:frame
                        titleUTF8String:title
                              styleMask:styleMask
                          graphicsHints:graphicsHints
                          sharingWindow:sharingWindow] autorelease]);
}


// hope for fractional positioning in future ?
- (instancetype) initWithFrame:(CGRect) frame
               titleUTF8String:(char *) title
                     styleMask:(NSUInteger) styleMask
                 graphicsHints:(enum GLFWGraphicsHints) hints
                 sharingWindow:(GLFWWindow *) sharingWindow
{
   int   profile;
   int   forward;
   int   major;
   int   minor;
   int   api;
   int   lib;
   int   first_lib;

   assert( [NSThread mulleIsMainThread]);

   if( ! styleMask)
      styleMask = GLFWWindowStyleMaskDefault;

//
// These function can only be called from main thread (see above)
//
   if( styleMask & UIWindowOpenGLDeprecated)
   {
      hints = GLFWGraphicsHintsBySettingAPI( hints, 2);     // setOpenGL
      hints = GLFWGraphicsHintsBySettingProfile( hints, 0); // no core profile (guess)
      hints = GLFWGraphicsHintsBySettingForward( hints, 0); // no forward

      assert( ! (styleMask & UIWindowOpenGLForwardCompatible));
      assert( ! (styleMask & (UIWindowOpenGLCoreProfile|UIWindowOpenGLCompatProfile)));
   }

   profile = styleMask & (UIWindowOpenGLCoreProfile|UIWindowOpenGLCompatProfile);
   if( profile)
      hints = GLFWGraphicsHintsBySettingProfile( hints, (profile >> UIWindowOpenGLProfileShift) & 0x3);
   forward = styleMask & UIWindowOpenGLForwardCompatible;
   if( forward)
      hints = GLFWGraphicsHintsBySettingForward( hints, 1);

   // rememer which was opened first for retries
   first_lib = GLFW_NATIVE_CONTEXT_API;

   if( hints)
   {
      switch( GLFWGraphicsHintsGetAPILibrary( hints))
      {
      default : lib = GLFW_NATIVE_CONTEXT_API; break;
      case 1  : lib = GLFW_EGL_CONTEXT_API; break;
      case 2  : lib = GLFW_OSMESA_CONTEXT_API; break;
      }
      first_lib = lib;

retry:
      glfwWindowHint( GLFW_CONTEXT_CREATION_API, lib);

      switch( GLFWGraphicsHintsGetAPI( hints))
      {
      default : api = GLFW_NO_API; break;
      case 1  : api = GLFW_OPENGL_ES_API; break;
      case 2  : api = GLFW_OPENGL_API; break;
      }
      glfwWindowHint( GLFW_CLIENT_API, api);


      switch( GLFWGraphicsHintsGetProfile( hints))
      {
      default : profile = GLFW_OPENGL_ANY_PROFILE; break;
      case 1  : profile = GLFW_OPENGL_CORE_PROFILE; break;
      case 2  : profile = GLFW_OPENGL_COMPAT_PROFILE; break;
      }
      // you can't set this or GLFW_OPENGL_CORE_PROFILE or GLFW_OPENGL_COMPAT_PROFILE on GL < 3.2
      if( profile != GLFW_OPENGL_ANY_PROFILE)
         glfwWindowHint( GLFW_OPENGL_PROFILE, profile);

      // forward compatibility is actually fairly restrictive
      // https://www.glfw.org/docs/3.3/window_guide.html#GLFW_OPENGL_FORWARD_COMPAT_hint
      forward = GLFWGraphicsHintsGetForward( hints);
      if( forward)
         glfwWindowHint( GLFW_OPENGL_FORWARD_COMPAT, GLFW_TRUE);  // why not ?

      major = GLFWGraphicsHintsGetMajor( hints);
      glfwWindowHint( GLFW_CONTEXT_VERSION_MAJOR, major);

      minor = GLFWGraphicsHintsGetMinor( hints);
      glfwWindowHint( GLFW_CONTEXT_VERSION_MINOR, minor);
   }

	glfwWindowHint( GLFW_DOUBLEBUFFER, (styleMask & UIWindowStyleSingleBuffer) ? GLFW_FALSE : GLFW_TRUE);
	glfwWindowHint( GLFW_TRANSPARENT_FRAMEBUFFER, (styleMask & UIWindowStyleTransparent) ? GLFW_TRUE : GLFW_FALSE);

   // https://www.glfw.org/docs/3.4/window_guide.html#GLFW_RESIZABLE_hint
   glfwWindowHint( GLFW_RESIZABLE, (styleMask & UIWindowStyleResizable) ? GLFW_TRUE : GLFW_FALSE);
	glfwWindowHint( GLFW_VISIBLE,   (styleMask & UIWindowStyleInvisible) ? GLFW_FALSE : GLFW_TRUE);
	glfwWindowHint( GLFW_FLOATING,  (styleMask & UIWindowStyleFloating)  ? GLFW_TRUE : GLFW_FALSE);
	glfwWindowHint( GLFW_DECORATED, (styleMask & UIWindowStyleDecorated) ? GLFW_TRUE : GLFW_FALSE);

   // https://www.glfw.org/docs/3.4/window_guide.html#GLFW_CLIENT_API_hint
#ifdef DEBUG
   glfwWindowHint( GLFW_OPENGL_DEBUG_CONTEXT, GL_TRUE);
#endif
   // not super sure about this, but lets try to avoid "old" OpenGL
   // calls. alas, we are doing OpenGLES 2.0 minimum, so I don't know
   // if this is useful.

   // TODO: create windows invisible always, but make visible after first
   //       render call. pro: window won't show up empty for an unknown
   //       amount of time. con: window won't show up at all for an unknown
   //       amount of time.
   assert( ! sharingWindow  || sharingWindow->_window);
   _window = glfwCreateWindow( (int) frame.size.width,
                               (int) frame.size.height,
                               title ? title : "",
                               NULL,  // monitor to display
                               sharingWindow ? sharingWindow->_window : NULL);
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

   _sharingWindow = [sharingWindow retain];
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

   // zero origin, let window manager choose
   if( ! CGPointEqualToPoint( frame.origin, CGPointNull))
      glfwSetWindowPos( _window, (int) frame.origin.x, (int) frame.origin.y);

   _styleMask              = styleMask;

   _mouseLocation          = CGPointMake( -1.0, -1.0);
   _scrollWheelSensitivity = 20.0;
   _contextLock            = [NSLock new];
   glfwMakeContextCurrent( NULL); // turn off to be consistent with lock
   _renderCallback         = defaultRenderCallback;
   _windowEventsCallback   = GLFWWindowEventDefaultCallback;
   _otherEventsCallback    = GLFWWindowRetainedEventDefaultCallback;

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
   [_timerUserInfo autorelease];
   [_contextLock release];

   [super dealloc];
}


- (NSInteger) shareId
{
   return( _sharingWindow ? [_sharingWindow shareId] : _shareId);
}


- (void) os_destroyWindow
{
   if( _window)
   {
      glfwDestroyWindow( _window);
      _window = NULL;
   }
}


- (CGFloat) os_primaryMonitorPPI
{
   GLFWmonitor      *monitor;
   GLFWvidmode      *mode;
   int              h;
   CGFloat          ppi;

   assert( [NSThread mulleIsMainThread]);

   //
   monitor = glfwGetPrimaryMonitor();
   if( ! monitor)
      return( 0.0);

   h = 0; // for valgrind
   glfwGetMonitorPhysicalSize( monitor, NULL, &h);
   if( ! h)
       return( 0.0);

   mode = (GLFWvidmode *) glfwGetVideoMode( monitor);
   if( ! mode)
       return( 0.0);

   // need to convert h in mm to inches
   ppi = mode->height / (h * 0.03937007874);
   return( ppi);
}


- (void *) os_window
{
   return( _window);
}


- (CGRect) os_windowFrame
{
   int      xpos;
   int      ypos;
   int      width;
   int      height;
   CGRect   frame;

   assert( [NSThread mulleIsMainThread]);
   assert( _window);

   glfwGetWindowPos( _window, &xpos, &ypos);
   glfwGetWindowSize( _window, &width, &height);  // just to be sure...

   frame.origin = CGPointMake( xpos, ypos);
   frame.size   = CGSizeMake( width, height);
   return( frame);
}


- (CGSize) os_windowSize
{
   int   winWidth;
   int   winHeight;

   assert( [NSThread mulleIsMainThread]);
   assert( _window);

   glfwGetWindowSize( _window, &winWidth, &winHeight);
   return( CGSizeMake( winWidth, winHeight));
}


// bind GL context of the window to the current thread
- (void) os_activateContext
{
   // can be called from any thread
   assert( _window);

   [_contextLock lock];
   glfwMakeContextCurrent( _window);
}


- (void) os_deactivateContext
{
   // can be called from any thread
   assert( _window);

   glfwMakeContextCurrent( NULL);
   [_contextLock unlock];
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
   case GLFW_OPENGL_CORE_PROFILE   : return( "core");
   case GLFW_OPENGL_COMPAT_PROFILE : return( "compat");
   default                         : return( "?");
   }
}


- (char *) os_contextInfoUTF8String
{
   int   api;
   int   vendor;
   int   profile;
   int   major;
   int   minor;
   int   revision;
   int   forward;
   char  *s;
   char  *profile_s;
   char  *profile_prefix;
   char  *forward_s;
   char  *forward_prefix;

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


- (struct CGBitmapSize) os_framebufferSize
{
   int   fbWidth;
   int   fbHeight;

   assert( [NSThread mulleIsMainThread]);
   assert( _window);

   glfwGetFramebufferSize( _window, &fbWidth, &fbHeight);
   return( CGBitmapSizeMake( fbWidth, fbHeight));
}


- (void) os_swapBuffers
{
   // can be called from any thread
   // it'as assume that context need not be active here, but is it true ?
   assert( _window);

   glfwSwapBuffers( _window);
}


- (void) os_setSwapInterval:(NSUInteger) value
{
   glfwSwapInterval( (int) value);  // need for smooth pointer/control sync
}


- (CGFloat) os_primaryMonitorRefreshRate
{
   GLFWmonitor   *monitor;
   GLFWvidmode   *mode;

   assert( [NSThread mulleIsMainThread]);

   monitor = glfwGetPrimaryMonitor();
   mode    = (GLFWvidmode *) glfwGetVideoMode( monitor);

   return( mode->refreshRate);
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


- (void) renderFrame:(CARelativeTime) now
{
   (*self->_renderCallback)( self, now);

   [self os_swapBuffers];
}


- (void) renderFrame
{
   [self renderFrame:glfwGetTime()];
}


- (CARelativeTime) os_getRelativeTime
{
   return( glfwGetTime());
}


/*
 * support for GLFWWindow as a GLU substitute
 */
- (void) renderLoopHz:(CGFloat) frameRate
{
   CARelativeTime   now;

   // to get like GLU a reshape function called immediately we
   // fake such a thing
   [self _framebufferResizeCallback:[self os_framebufferSize]];

   now = glfwGetTime();
   while( ! glfwWindowShouldClose( _window))
   {
      [self renderFrame:now];

      [UIEvent waitForEventsHz:frameRate];

      now = glfwGetTime();
      if( now >= _lastTimerCall + _timerDelay)
      {
         if( _timerCallback)
            (*_timerCallback)( self, now, _timerUserInfo);
         _lastTimerCall = now;
      }
   }
}


- (void) setTimerCallback:(GLFWTimerCallback_t) timerCallback
                    delay:(CARelativeTime) delay
                 userInfo:(id) userInfo
{
   _timerCallback = timerCallback;
   _lastTimerCall = glfwGetTime();
   _timerDelay    = delay;

   [_timerUserInfo autorelease];
   _timerUserInfo = [userInfo retain];
}


- (void) setWindowEventsCallback:(GLFWWindowEventCallback_t) callback
{
   _windowEventsCallback = callback;
   if( callback)
      [self os_initWindowEvents];
}


- (void) setOtherEventsCallback:(GLFWWindowRetainedEventCallback_t) callback
{
   _otherEventsCallback = callback;
   if( callback)
      [self os_initInputEvents];
}


@end

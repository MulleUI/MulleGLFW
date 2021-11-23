//
// Copyright (c) 2021 Nat!, Mulle kybernetiK
//
#import "GLFWWindow.h"

#import "import-private.h"

#import "UIEvent.h"
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


// as we don't know if we even use OpenGL here
static void   defaultRenderCallback( GLFWWindow *window,
                                      struct CGFrameInfo *info)
{
   fprintf( stderr, "The GLFW windows needs a renderCallback.\n"
"Typically you can use minimally something like this with OpenGL:\n"
"   static void  render( GLFWWindow *window, struct CGFrameInfo *info)\n"
"   {\n"
"      glViewport( 0, 0, info->framebufferSize.width, info->framebufferSize.height);\n"
"      glColor( 0, 0, 0, 0);\n"
"      glClear( GL_COLOR_BUFFER_BIT|GL_STENCIL_BUFFER_BIT);\n"
"   }\n"
"   [glfwWindow setRenderCallback:render];\n"
"\n");
   abort();
}

// hope for fractional positioning in future ?
- (instancetype) initWithFrame:(CGRect) frame
               titleUTF8String:(char *) title
                    styleMask:(NSUInteger) styleMask
                graphicsHints:(enum GLFWGraphicsHints) hints
                sharingWindow:(GLFWWindow *) sharingWindow
{
   NSUInteger   core;
   NSUInteger   major;
   NSUInteger   minor;

   assert( [NSThread mulleIsMainThread]);
//
// These function can only be called from main thread (see above)
//
   if( hints)
   {
      major = GLFWGraphicsHintsGetMajor( hints);
      minor = GLFWGraphicsHintsGetMinor( hints);
      core  = GLFWGraphicsHintsGetCore( hints);
      glfwWindowHint( GLFW_CONTEXT_VERSION_MAJOR, major);
      glfwWindowHint( GLFW_CONTEXT_VERSION_MINOR, minor);
      glfwWindowHint( GLFW_OPENGL_PROFILE, core
                     ? GLFW_OPENGL_CORE_PROFILE
                     : GLFW_OPENGL_ANY_PROFILE);
   }

	glfwWindowHint( GLFW_RESIZABLE, (styleMask & UIWindowStyleResizable) ? GL_TRUE : GL_FALSE);
	glfwWindowHint( GLFW_VISIBLE,   (styleMask & UIWindowStyleInvisible) ? GL_FALSE : GL_TRUE);

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

   fprintf( stderr, "window %p (sharing with %p) created\n", _window, _sharingWindow ? _sharingWindow->_window : NULL);

   // this is basically the "rendezvous" point where nanoVG latches unto
   // its also the receiver for OpenGL calls. That's why we need a window
   // to draw stuff
   //
   glfwSetWindowUserPointer( _window, self);

   // zero origin, let window manager choose
   if( ! CGPointEqualToPoint( frame.origin, CGPointNull))
      glfwSetWindowPos( _window, (int) frame.origin.x, (int) frame.origin.y);

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


+ (CGFloat) os_primaryMonitorPPI
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


+ (CGFloat) os_primaryMonitorRefreshRate
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


- (void) renderFrame
{
   struct CGFrameInfo    frameInfo;

   frameInfo = CGFrameInfoSFMake( [self os_windowSize],
                                  [self os_framebufferSize],
                                  1.0);
   if( self->_renderCallback)
      (*self->_renderCallback)( self, &frameInfo);

   [self os_swapBuffers];
}


/*
 * support for GLFWWindow as a GLU substitute
 */
- (void) renderLoopHz:(CGFloat) frameRate
{
   CAAbsoluteTime    now;

   // to get like GLU a reshape function called immediately we
   // fake such a thing
   [self _framebufferResizeCallback:[self os_framebufferSize]];

   while( ! glfwWindowShouldClose( _window))
   {
      [self renderFrame];

      [UIEvent waitForEventsHz:frameRate];

      now = CAAbsoluteTimeNow();
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
   _lastTimerCall = CAAbsoluteTimeNow();
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

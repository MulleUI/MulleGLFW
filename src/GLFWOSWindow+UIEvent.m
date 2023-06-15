//
// Copyright (c) 2021 Nat!, Mulle kybernetiK
//
#import "GLFWOSWindow+UIEvent.h"

#import "import-private.h"

//#define CALLBACK_DEBUG
//#define MODIFIER_DEBUG

//#define MOUSE_MOTION_CALLBACK_DEBUG  // enable and turn CALLBACK_DEBUG on


@interface GLFWOSWindow( UIEventFuture)

- (void) _windowFramebufferResizeCallback:(struct MulleIntegerSize) size;
- (void) _windowResizeCallback:(struct MulleIntegerSize) size;
- (void) _windowCloseCallback;
- (void) _windowRefreshCallback;
- (void) _windowMoveCallback:(struct MulleIntegerPoint) position;

- (void) _updateWindowRefreshRate;

@end


#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

@implementation GLFWOSWindow ( UIEvent)


void   GLFWOSWindowEventDefaultCallback( GLFWOSWindow *window, UIWindowEvent *event)
{
   [window->_windowEventsReceiver handleWindowEvent:event];
}


void   GLFWOSWindowRetainedEventDefaultCallback( GLFWOSWindow *window,
                                                 NS_CONSUMED UIEvent *retainedEvent)
{
   [window->_eventsReceiver receiveRetainedEvent:retainedEvent];
}


static void   windowMoveCallback( GLFWwindow* window, int xpos, int ypos)
{
   GLFWOSWindow   *self;

   assert( [NSThread mulleIsMainThread]);

   self = glfwGetWindowUserPointer( window);
   [self _windowMoveCallback:MulleIntegerPointMake( xpos, ypos)];
}


static void   windowRefreshCallback( GLFWwindow* window)
{
   GLFWOSWindow   *self;

   assert( [NSThread mulleIsMainThread]);

   self = glfwGetWindowUserPointer( window);
   [self _windowRefreshCallback];
}


static void   windowCloseCallback( GLFWwindow* window)
{
   GLFWOSWindow   *self;

   assert( [NSThread mulleIsMainThread]);

   self = glfwGetWindowUserPointer( window);
   [self _windowCloseCallback];
}


// framebufferResize is more interesting though
static void   windowResizeCallback( GLFWwindow* window, int width, int height)
{
   GLFWOSWindow   *self;

   assert( [NSThread mulleIsMainThread]);

   self = glfwGetWindowUserPointer( window);
   [self _windowResizeCallback:MulleIntegerSizeMake( width, height)];
}


static void   windowFramebufferResizeCallback( GLFWwindow* window, int width, int height)
{
   GLFWOSWindow   *self;

   assert( [NSThread mulleIsMainThread]);

   self = glfwGetWindowUserPointer( window);
   [self _windowFramebufferResizeCallback:MulleIntegerSizeMake( width, height)];
}


- (void) os_initWindowEvents
{
   assert( _window);

   assert( [NSThread mulleIsMainThread]);

   // window events
   glfwSetWindowSizeCallback( _window, windowResizeCallback);
   glfwSetWindowPosCallback( _window, windowMoveCallback);
   glfwSetFramebufferSizeCallback( _window, windowFramebufferResizeCallback);
   glfwSetWindowRefreshCallback( _window, windowRefreshCallback);
   glfwSetWindowCloseCallback( _window, windowCloseCallback);
}


// the refresh rate is that what the monitor gives us
// the frame rate is that, what we can vary
- (void) _updateWindowRefreshRate
{
   id <UIScreen>   screen;

#ifdef DEBUG
   if( ! UIApp)
      MulleUILog( "UIApp is not available, as +sharedInstance hasn't been called.");
#endif

   screen = [UIApp screenForFrame:_windowInfo.base.frame
             primaryIfNoneMatches:YES];
 
   _windowInfo.refreshRate = screen ? [screen refreshRate] : (1.0 / 60.0);
}


- (void) updateWindowInfo
{
   struct CGWindowInfo   info;

   info = CGWindowInfoSFMakeVector( [self os_windowFrame],
                                    [self os_framebufferSize],
                                    [self os_UIScale]);
   [_windowInfoLock lock];
   {
      _windowInfo.base = info;
      [self _updateWindowRefreshRate];
   }
   [_windowInfoLock unlock];
}



/*
 * Special window events to be handled by UIApplication
 */
//
// callbacks from window events (via GLFW). It is NOT known if the event coming
// in is a direct callback from the host OS or if it has been queued by glfw
// and released during "waitForEvents" or "pollEvents." (See glfw3 events dox)
//
// What is unknown is, if the executing thread of a callback is always the
// mainThread. It is assumed here, though. The "core" windows events are
// handled immediately and they are handled on the main thread (or the main
// UIEvent thread).
//
//
// Move callback like refresh callback induces flicker
//
- (void) _windowMoveCallback:(struct MulleIntegerPoint) position
{
   UIWindowEvent   *event;

#ifdef CALLBACK_DEBUG
   MulleUILogThisMethod();
#endif

//   fprintf( stderr, "%p moved: x=%d y=%d\n", self, xpos, ypos);
   [_windowInfoLock lock];
   {
      _windowInfo.base.frame.origin = CGPointMakeWithIntegerPoint( position);
      [self _updateWindowRefreshRate];
   }
   [_windowInfoLock unlock];

   event = [[[UIWindowMoveEvent alloc] initWithOrigin:position] autorelease];
   _windowEventsCallback( self, event);
}


- (void) _windowResizeCallback:(struct MulleIntegerSize) size
{
   UIWindowEvent   *event;

#if defined( CALLBACK_DEBUG) || defined( RESIZE_CALLBACK_DEBUG)
    MulleUILog( "w=%td h=%td", size.width, size.height);
#endif

   // this assert can fail... it doesn't fail often but it can.
   // reason being, because the window manager is resizing in another
   // process

   // assert( CGSizeEqualToSize( [self os_windowSize], CGSizeMakeWithIntegerSize( size)));
   [_windowInfoLock lock];
   {
      _windowInfo.base.frame.size = CGSizeMakeWithIntegerSize( size);
      [self _updateWindowRefreshRate];
   }
   [_windowInfoLock unlock];

   event = [[[UIWindowResizeEvent alloc] initWithSize:size] autorelease];
   _windowEventsCallback( self, event);
}


- (void) _windowFramebufferResizeCallback:(struct MulleIntegerSize) size
{
   UIWindowEvent   *event;

#if defined( CALLBACK_DEBUG) || defined( RESIZE_CALLBACK_DEBUG)
    MulleUILog( "w=%td h=%td", size.width, size.height);
#endif
   [_windowInfoLock lock];
   {
      _windowInfo.base.framebufferSize = size;
      _uninitializedFramebuffer        = YES;      
   }
   [_windowInfoLock unlock];

   event = [[[UIWindowFramebufferResizeEvent alloc] initWithSize:size] autorelease];

   // TODO: we should do this atomically
   //
   _windowEventsCallback( self, event);
}


- (void) _windowRefreshCallback
{
   UIWindowEvent   *event;

#if defined( CALLBACK_DEBUG) || defined( RESIZE_CALLBACK_DEBUG)
   MulleUILogThisMethod();
#endif

   event = [[[UIWindowRefreshEvent alloc] init] autorelease];
//   [self receiveRetainedEvent:event];
   _uninitializedFramebuffer = YES;

   _windowEventsCallback( self, event);
}


- (void) _windowCloseCallback
{
   UIWindowEvent   *event;

#ifdef CALLBACK_DEBUG
   MulleUILogThisMethod();
#endif

   event = [[[UIWindowCloseEvent alloc] init] autorelease];
  _windowEventsCallback( self, event);
}


/*
 * Regular events to be handled by UIWindow
 */
static void   keyCallback( GLFWwindow* window,
                           int key,
                           int scancode,
                           int action,
                           int mods)
{
   GLFWOSWindow   *self;

   assert( [NSThread mulleIsMainThread]);

   self = glfwGetWindowUserPointer( window);
   [self _keyCallback:key
             scancode:scancode
               action:action
            modifiers:mods];
}


void   charCallback( GLFWwindow* window, unsigned int codepoint)
{
   GLFWOSWindow   *self;

   assert( [NSThread mulleIsMainThread]);

   self = glfwGetWindowUserPointer( window);
   [self _charCallback:codepoint];
}


static void   mouseButtonCallback( GLFWwindow* window,
                                   int button,
                                   int action,
                                   int mods)
{
   GLFWOSWindow   *self;

   assert( [NSThread mulleIsMainThread]);

   self  = glfwGetWindowUserPointer( window);
   [self _mouseButtonCallback:button
                       action:action
                    modifiers:mods];
}


static void   mouseMotionCallback( GLFWwindow* window,
                                 double xpos,
                                 double ypos)
{
   GLFWOSWindow   *self;

   assert( [NSThread mulleIsMainThread]);

   self = glfwGetWindowUserPointer( window);
   [self _mouseMotionCallback:CGPointMake( xpos, ypos)];
}


static void   mouseScrollCallback( GLFWwindow *window,
                                   double xoffset,
                                   double yoffset)
{
   GLFWOSWindow   *self;

   assert( [NSThread mulleIsMainThread]);

   self  = glfwGetWindowUserPointer( window);
   [self _mouseScrollCallback:CGPointMake( xoffset, yoffset)];
}


- (void) os_initInputEvents
{
   assert( _window);

   assert( [NSThread mulleIsMainThread]);

   // input device events
   glfwSetMouseButtonCallback( _window, mouseButtonCallback);
   glfwSetCursorPosCallback( _window, mouseMotionCallback);
   glfwSetKeyCallback( _window, keyCallback);
   glfwSetCharCallback( _window, charCallback);
   glfwSetScrollCallback( _window, mouseScrollCallback);
}


- (void) os_initEvents
{
   [self os_initWindowEvents];
   [self os_initInputEvents];
}


- (void) _keyCallback:(int) key
             scancode:(int) scancode
               action:(int) action
            modifiers:(int) mods
{
   UIEvent      *event;

#ifdef CALLBACK_DEBUG
   MulleUILogThisMethod();
#endif

//   //
//   // modifier bits are not set yet properly, but we want them
//   // for scrollEvents for example
//   //
//   if( action == GLFW_PRESS)
//   {
//      switch( key)
//      {
//      case GLFW_KEY_LEFT_SHIFT    :
//      case GLFW_KEY_RIGHT_SHIFT   :
//         self->_inputState.keyModifiers |= GLFW_MOD_SHIFT;
//         break;
//      case GLFW_KEY_LEFT_CONTROL  :
//      case GLFW_KEY_RIGHT_CONTROL :
//         self->_inputState.keyModifiers |= GLFW_MOD_CONTROL;
//         break;
//      case GLFW_KEY_LEFT_ALT      :
//      case GLFW_KEY_RIGHT_ALT     :
//         self->_inputState.keyModifiers |= GLFW_MOD_ALT;
//         break;
//      case GLFW_KEY_LEFT_SUPER    :
//      case GLFW_KEY_RIGHT_SUPER   :
//         self->_inputState.keyModifiers |= GLFW_MOD_SUPER;
//         break;
//      }
//   }
//   else

   self->_inputState.keyModifiers = mods;

#ifdef MODIFIER_DEBUG
   MulleUILog( "modifiers=0x%tx", self->_inputState.keyModifiers);
#endif

   if( self->_discardEventsMask & UIEventTypePresses)
      return;

   event = [[UIKeyboardEvent alloc] initWithInputState:&self->_inputState
                                                   key:key
                                              scanCode:scancode
                                                action:action];
  _otherRetainedEventsCallback( self, event);
}


- (void) _charCallback:(unsigned int) codepoint
{
   UIEvent    *event;

#ifdef CALLBACK_DEBUG
   MulleUILogThisMethod();
#endif

   if( self->_discardEventsMask & UIEventTypeUnicode)
      return;

   event = [[UIUnicodeEvent alloc] initWithInputState:&self->_inputState
                                            character:codepoint];
  _otherRetainedEventsCallback( self, event);
}


- (void) _mouseButtonCallback:(int) button
                       action:(int) action
                    modifiers:(int) mods
{
   UIEvent    *event;
   uint64_t   bit;

#if defined( CALLBACK_DEBUG)
   MulleUILogThisMethod();
#endif

#ifdef MODIFIER_DEBUG
   MulleUILog( "modifiers=0x%tx", mods);
#endif
   self->_inputState.keyModifiers = mods;

   bit = 1LL << button;
   self->_inputState.buttonStates &= ~bit;
   if( action == GLFW_PRESS)
      self->_inputState.buttonStates |= bit;

   if( self->_discardEventsMask & UIEventTypeTouches)
      return;

   event = [[UIMouseButtonEvent alloc] initWithInputState:&_inputState
                                                   button:button
                                                   action:action];
  _otherRetainedEventsCallback( self, event);

   // [self dump];
}


- (void) _mouseMotionCallback:(CGPoint) pos
{
   UIEvent   *event;

#if defined( CALLBACK_DEBUG) && defined( MOUSE_MOTION_CALLBACK_DEBUG)
   mulle_fprintf( stderr, "%s %@ (%.1f, %.1f)\n", __PRETTY_FUNCTION__, self, pos.x, pos.y);
#endif

   //
   // Observed behaviour on linux: Depending on mouse sensitivity, it may
   // become obvious that there is a rounding bug in the Linux mouse handling
   // where certain integer values are never returned. In my case this
   // turned out to be 200,200. So don't expect the mouse to provide all
   // possible integer coordinates for every pixel on the screen.
   //
   if( self->_discardEventsMask & UIEventTypeMotion)
      return;

   //
   // Coordinates are window relative! So for screen coordinates we'd need
   // to add the window frame.x/y.
   //
   // we get not events for the window title bar
   // TODO: we might need to scale the values for DPI or ?
   self->_inputState.locationInWindow.x = pos.x;
   self->_inputState.locationInWindow.y = pos.y;

   // TODO: wrap in autorelease pool ?
   //       + event don't leak if someone throws
   //       - latency

   // TODO: buttonStates need to be reset when the mouse leaves the
   //       window, but isn't
   event = [[UIMouseMotionEvent alloc] initWithInputState:&self->_inputState];
   _otherRetainedEventsCallback( self, event);
}


- (void) _mouseScrollCallback:(CGPoint) offset
{
   UIEvent   *event;
   CGPoint   scrollOffset;
   CGFloat   sensitivity;

#ifdef CALLBACK_DEBUG
   MulleUILogThisMethod();
#endif

   if( self->_discardEventsMask & UIEventTypeScroll)
      return;

   sensitivity = [self scrollWheelSensitivity];
   if( sensitivity != 0.0)
   {
      offset.x *= sensitivity;
      offset.y *= sensitivity;
   }

   if( [self isScrollWheelNatural])
      scrollOffset = CGPointMake( offset.x, offset.y);
   else
      scrollOffset = CGPointMake( -offset.x, -offset.y);

   event = [[UIMouseScrollEvent alloc] initWithInputState:&self->_inputState
                                             scrollOffset:scrollOffset];
   _otherRetainedEventsCallback( self, event);
}

@end

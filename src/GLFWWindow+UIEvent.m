//
// Copyright (c) 2021 Nat!, Mulle kybernetiK
//
#import "GLFWWindow+UIEvent.h"

#import "import-private.h"


@interface GLFWWindow( UIEventFuture)

- (void) _framebufferResizeCallback:(struct CGBitmapSize) size;
- (void) _windowResizeCallback:(struct CGBitmapSize) size;
- (void) _windowCloseCallback;
- (void) _windowRefreshCallback;
- (void) _windowMoveCallback:(struct CGBitmapPoint) position;

@end


@implementation GLFWWindow ( UIEvent)


static void   keyCallback( GLFWwindow* window,
                           int key,
                           int scancode,
                           int action,
                           int mods)
{
   GLFWWindow   *self;

   assert( [NSThread mulleIsMainThread]);

   self = glfwGetWindowUserPointer( window);
   [self _keyCallback:key
             scancode:scancode
               action:action
            modifiers:mods];
}


void   charCallback(GLFWwindow* window, unsigned int codepoint)
{
   GLFWWindow   *self;

   assert( [NSThread mulleIsMainThread]);

   self = glfwGetWindowUserPointer( window);
   [self _charCallback:codepoint];
}


static void   mouseButtonCallback( GLFWwindow* window,
                                   int button,
                                   int action,
                                   int mods)
{
   GLFWWindow   *self;

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
   GLFWWindow   *self;

   assert( [NSThread mulleIsMainThread]);

   self = glfwGetWindowUserPointer( window);
   [self _mouseMotionCallback:CGPointMake( xpos, ypos)];
}


static void   mouseScrollCallback( GLFWwindow *window,
                                   double xoffset,
                                   double yoffset)
{
   GLFWWindow   *self;

   assert( [NSThread mulleIsMainThread]);

   self  = glfwGetWindowUserPointer( window);
   [self _mouseScrollCallback:CGPointMake( xoffset, yoffset)];
}


static void   windowMoveCallback( GLFWwindow* window, int xpos, int ypos)
{
   GLFWWindow   *self;

   assert( [NSThread mulleIsMainThread]);

   self = glfwGetWindowUserPointer( window);
   [self _windowMoveCallback:CGBitmapPointMake( xpos, ypos)];
}


static void   windowRefreshCallback( GLFWwindow* window)
{
   GLFWWindow   *self;

   assert( [NSThread mulleIsMainThread]);

   self = glfwGetWindowUserPointer( window);
   [self _windowRefreshCallback];
}


static void   windowCloseCallback( GLFWwindow* window)
{
   GLFWWindow   *self;

   assert( [NSThread mulleIsMainThread]);

   self = glfwGetWindowUserPointer( window);
   [self _windowCloseCallback];
}


// framebufferResize is more interesting though
static void   windowResizeCallback( GLFWwindow* window, int width, int height)
{
   GLFWWindow   *self;

   assert( [NSThread mulleIsMainThread]);

   self = glfwGetWindowUserPointer( window);
   [self _windowResizeCallback:CGBitmapSizeMake( width, height)];
}


static void   framebufferResizeCallback( GLFWwindow* window, int width, int height)
{
   GLFWWindow   *self;
   CGRect      frame;

   assert( [NSThread mulleIsMainThread]);

   self = glfwGetWindowUserPointer( window);
   [self _framebufferResizeCallback:CGBitmapSizeMake( width, height)];
}


- (void) os_initWindowEvents
{
   assert( _window);

   assert( [NSThread mulleIsMainThread]);

   // window events
   glfwSetWindowSizeCallback( _window, windowResizeCallback);
   glfwSetWindowPosCallback( _window, windowMoveCallback);
   glfwSetFramebufferSizeCallback( _window, framebufferResizeCallback);
   glfwSetWindowRefreshCallback( _window, windowRefreshCallback);
   glfwSetWindowCloseCallback( _window, windowCloseCallback);
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
- (void) _windowResizeCallback:(struct CGBitmapSize) size
{
   UIWindowEvent    *event;
   GLFWWindow       *window;

#if defined( CALLBACK_DEBUG) || defined( RESIZE_CALLBACK_DEBUG)
   fprintf( stderr, "%s %s w=%.1f h=%.1f\n",
                     __PRETTY_FUNCTION__,
                     [self UTF8String],
                     size.width,
                     size.height);
#endif
   event = [[[UIWindowResizeEvent alloc] initWithMouseLocation:self->_mouseLocation
                                                     modifiers:self->_modifiers
                                                         size:size] autorelease];
   _windowEventsCallback( self, event);
}


- (void) _framebufferResizeCallback:(struct CGBitmapSize) size
{
   UIWindowEvent   *event;

#if defined( CALLBACK_DEBUG) || defined( RESIZE_CALLBACK_DEBUG)
   fprintf( stderr, "%s %s w=%ld h=%ld\n",
                     __PRETTY_FUNCTION__,
                     [self UTF8String],
                     (long) size.width,
                     (long) size.height);
#endif
   event = [[[UIWindowFramebufferResizeEvent alloc] initWithMouseLocation:self->_mouseLocation
                                                                modifiers:self->_modifiers
                                                                     size:size] autorelease];

   // TODO: we should do this atomically
   //
   _windowEventsCallback( self, event);
}



//
// Move callback like refresh callback induces flicker
//
- (void) _windowMoveCallback:(struct CGBitmapPoint) position
{
   UIWindowEvent   *event;

#ifdef CALLBACK_DEBUG
   fprintf( stderr, "%s %s\n", __PRETTY_FUNCTION__, [self UTF8String]);
#endif

//   fprintf( stderr, "%p moved: x=%d y=%d\n", self, xpos, ypos);

   event = [[[UIWindowMoveEvent alloc] initWithMouseLocation:self->_mouseLocation
                                                   modifiers:self->_modifiers
                                                      origin:position] autorelease];
   _windowEventsCallback( self, event);
}



- (void) _windowRefreshCallback
{
   UIWindowEvent   *event;

#if defined( CALLBACK_DEBUG) || defined( RESIZE_CALLBACK_DEBUG)
   fprintf( stderr, "%s %s\n", __PRETTY_FUNCTION__, [self UTF8String]);
#endif

   event = [[[UIWindowRefreshEvent alloc] initWithMouseLocation:self->_mouseLocation
                                                      modifiers:self->_modifiers] autorelease];
//   [self queueRetainedEvent:event];

   _windowEventsCallback( self, event);
}



- (void) _windowCloseCallback
{
   UIWindowEvent   *event;

#ifdef CALLBACK_DEBUG
   fprintf( stderr, "%s %s\n", __PRETTY_FUNCTION__, [self UTF8String]);
#endif

   event = [[[UIWindowCloseEvent alloc] initWithMouseLocation:self->_mouseLocation
                                                   modifiers:self->_modifiers] autorelease];
  _windowEventsCallback( self, event);
}


- (void) _keyCallback:(int) key
             scancode:(int) scancode
               action:(int) action
            modifiers:(int) mods
{
   UIEvent   *event;

#ifdef CALLBACK_DEBUG
   fprintf( stderr, "%s %s\n", __PRETTY_FUNCTION__, [self UTF8String]);
#endif

   self->_modifiers = mods;
   if( self->_discardEventsMask & UIEventTypePresses)
      return;

   event = [[UIKeyboardEvent alloc] initWithMouseLocation:self->_mouseLocation
                                                modifiers:mods
                                                      key:key
                                                 scanCode:scancode
                                                   action:action];
  _otherEventsCallback( self, event);
}


- (void) _charCallback:(unsigned int) codepoint
{
   UIEvent    *event;

#ifdef CALLBACK_DEBUG
   fprintf( stderr, "%s %s\n", __PRETTY_FUNCTION__, [self UTF8String]);
#endif

   if( self->_discardEventsMask & UIEventTypeUnicode)
      return;

   event = [[UIUnicodeEvent alloc] initWithMouseLocation:self->_mouseLocation
                                               modifiers:self->_modifiers
                                               character:codepoint];
  _otherEventsCallback( self, event);
}


- (void) _mouseButtonCallback:(int) button
                       action:(int) action
                    modifiers:(int) mods
{
   UIEvent    *event;
   uint64_t   bit;

#if defined( CALLBACK_DEBUG) || defined( MOUSE_BUTTON_CALLBACK_DEBUG)
   fprintf( stderr, "%s %s\n", __PRETTY_FUNCTION__, [self UTF8String]);
#endif

   bit = 1LL << button;
   self->_mouseButtonStates &= ~bit;
   if( action == GLFW_PRESS)
      self->_mouseButtonStates |= bit;
   self->_modifiers = mods;

   if( self->_discardEventsMask & UIEventTypeTouches)
      return;

   event = [[UIMouseButtonEvent alloc] initWithMouseLocation:self->_mouseLocation
                                                   modifiers:mods
                                                      button:button
                                                      action:action];
  _otherEventsCallback( self, event);

   // [self dump];
}


- (void) _mouseMotionCallback:(CGPoint) pos
{
   UIEvent    *event;
   CGRect     frame;

#if defined( CALLBACK_DEBUG) || defined( MOUSE_MOTION_CALLBACK_DEBUG)
   fprintf( stderr, "%s %s (%.1f, %.1f)\n", __PRETTY_FUNCTION__, [self UTF8String], pos.x, pos.y);
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
	self->_mouseLocation.x = pos.x;
	self->_mouseLocation.y = pos.y;

   // TODO: wrap in autorelease pool ?
   //       + event don't leak if someone throws
   //       - latency
   event = [[UIMouseMotionEvent alloc] initWithMouseLocation:self->_mouseLocation
                                                   modifiers:self->_modifiers
                                                buttonStates:self->_mouseButtonStates];
  _otherEventsCallback( self, event);
}


- (void) _mouseScrollCallback:(CGPoint) offset
{
   UIEvent    *event;
   uint64_t   bit;
   CGPoint    scrollOffset;
   CGFloat    sensitivity;

#ifdef CALLBACK_DEBUG
   fprintf( stderr, "%s %s\n", __PRETTY_FUNCTION__, [self UTF8String]);
#endif

   if( self->_discardEventsMask)
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

   event = [[UIMouseScrollEvent alloc] initWithMouseLocation:self->_mouseLocation
                                                   modifiers:self->_modifiers
                                                scrollOffset:scrollOffset];
  _otherEventsCallback( self, event);
}

@end

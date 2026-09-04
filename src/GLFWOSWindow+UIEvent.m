//
//  GLFWOSWindow+UIEvent.m
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
#import "GLFWOSWindow+UIEvent.h"

#import "import-private.h"

#import <MulleUIApplication/UIOSWindow+DebugPrivate.h>


@interface GLFWOSWindow( UIEventFuture) < MulleObjCFuture>

- (void) _windowFramebufferResizeCallback:(CGPixelSize) size;
- (void) _windowResizeCallback:(CGPixelSize) size;
- (void) _windowCloseCallback;
- (void) _windowRefreshCallback;
- (void) _windowMoveCallback:(CGPixelPoint) position;
- (void) _windowFocusCallback:(BOOL) focused;

- (void) _updateWindowRefreshRate;

@end


#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

@implementation GLFWOSWindow ( UIEvent)


void   GLFWOSWindowEventDefaultCallback( id <UIOSWindow> window, UIWindowEvent *event)
{
   GLFWOSWindow  *glfwWindow = (GLFWOSWindow *) window;

   assert( [glfwWindow isKindOfClass:[GLFWOSWindow class]]);
   [glfwWindow->_windowEventsReceiver handleWindowEvent:event];
}


void   GLFWOSWindowRetainedEventDefaultCallback( id <UIOSWindow> window,
                                                 NS_CONSUMED UIEvent *retainedEvent)
{
   GLFWOSWindow  *glfwWindow = (GLFWOSWindow *) window;

   assert( [glfwWindow isKindOfClass:[GLFWOSWindow class]]);
   [glfwWindow->_eventsReceiver receiveRetainedEvent:retainedEvent];
}


static void   windowMoveCallback( GLFWwindow* window, int xpos, int ypos)
{
   GLFWOSWindow   *self;

   assert( [NSThread mulleIsMainThread]);

   self = glfwGetWindowUserPointer( window);
   [self _windowMoveCallback:CGPixelPointMake( xpos, ypos)];
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


static void   windowFocusCallback( GLFWwindow* window, int focused)
{
   GLFWOSWindow   *self;

   assert( [NSThread mulleIsMainThread]);

   self = glfwGetWindowUserPointer( window);
   [self _windowFocusCallback:(BOOL) focused];
}


// framebufferResize is more interesting though
static void   windowResizeCallback( GLFWwindow* window, int width, int height)
{
   GLFWOSWindow   *self;

   assert( [NSThread mulleIsMainThread]);

   self = glfwGetWindowUserPointer( window);
   [self _windowResizeCallback:CGPixelSizeMake( width, height)];
}


static void   windowFramebufferResizeCallback( GLFWwindow* window, int width, int height)
{
   GLFWOSWindow   *self;

   assert( [NSThread mulleIsMainThread]);

   self = glfwGetWindowUserPointer( window);
   [self _windowFramebufferResizeCallback:CGPixelSizeMake( width, height)];
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
   glfwSetWindowFocusCallback( _window, windowFocusCallback);
}


- (void) os_finalizeWindowEvents
{
   assert( _window);

   assert( [NSThread mulleIsMainThread]);

   // window events
   glfwSetWindowSizeCallback( _window, 0);
   glfwSetWindowPosCallback( _window, 0);
   glfwSetFramebufferSizeCallback( _window, 0);
   glfwSetWindowRefreshCallback( _window, 0);
   glfwSetWindowCloseCallback( _window, 0);
   glfwSetWindowFocusCallback( _window, 0);
}


// the refresh rate is that what the monitor gives us
// the frame rate is that, what we can vary
- (void) _updateWindowRefreshRate
{
   id <UIScreen>   screen;

   if( ! UIApp)
      UIOSWindowLog( "UIApp is not available, as +sharedInstance hasn't been called.");

   screen = [UIApp screenForFrame:_windowInfo.base.frame
             primaryIfNoneMatches:YES];
 
   _windowInfo.refreshRate = [screen refreshRate];
   if( _windowInfo.refreshRate == 0.0)
      _windowInfo.refreshRate = UIScreenAssumedRefreshRate;
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
- (void) _windowMoveCallback:(CGPixelPoint) position
{
   UIWindowMoveEvent   *event;

   UIOSWindowEventLog("");

//   fprintf( stderr, "%p moved: x=%d y=%d\n", self, xpos, ypos);
   [_windowInfoLock lock];
   {
      _windowInfo.base.frame.origin = CGPointMakeWithPixelPoint( position);
      [self _updateWindowRefreshRate];
   }
   [_windowInfoLock unlock];

   event = [UIWindowMoveEvent alloc];
   event = [event initWithOrigin:position];
   event = [event autorelease];

   _windowEventsCallback( self, event);
}


- (void) _windowResizeCallback:(CGPixelSize) size
{
   UIWindowResizeEvent   *event;

   UIOSWindowEventLog( "w=%td h=%td", size.width, size.height);

   // this assert can fail... it doesn't fail often but it can.
   // reason being, because the window manager is resizing in another
   // process

   // assert( CGSizeEqualToSize( [self os_windowSize], CGSizeMakeWithPixelSize( size)));
   [_windowInfoLock lock];
   {
      _windowInfo.base.frame.size = CGSizeMakeWithPixelSize( size);
      [self _updateWindowRefreshRate];
   }
   [_windowInfoLock unlock];

   event = [UIWindowResizeEvent alloc];
   event = [event initWithSize:size];
   event = [event autorelease];

   _windowEventsCallback( self, event);
}


- (void) _windowFramebufferResizeCallback:(CGPixelSize) size
{
   UIWindowFramebufferResizeEvent   *event;

   UIOSWindowEventLog( "w=%td h=%td", size.width, size.height);

   [_windowInfoLock lock];
   {
      _windowInfo.base.framebufferSize = size;
      _uninitializedFramebuffer        = YES;      
   }
   [_windowInfoLock unlock];

   event = [UIWindowFramebufferResizeEvent alloc];
   event = [event initWithSize:size];
   event = [event autorelease];

   // TODO: we should do this atomically
   //
   _windowEventsCallback( self, event);
}


- (void) _windowRefreshCallback
{
   UIWindowEvent   *event;

   UIOSWindowEventLog( "");

   event = [UIWindowRefreshEvent alloc];
   event = [event init];
   event = [event autorelease];
//   [self receiveRetainedEvent:event];
   _uninitializedFramebuffer = YES;

   _windowEventsCallback( self, event);
}


- (void) _windowCloseCallback
{
   UIWindowEvent   *event;

   UIOSWindowEventLog( "");

   event = [UIWindowRefreshEvent alloc];
   event = [event init];
   event = [event autorelease];
   _windowEventsCallback( self, event);
}


- (void) _windowFocusCallback:(BOOL) focused
{
   UIWindowEvent   *event;

   UIOSWindowEventLog( "focused=%d", (int) focused);

   if( focused)
   {
      // GLFW clears its internal key state on focus loss,
      // so os_pressedKeys can't resync. But GLFW also sends synthetic
      // key-up events on focus loss, so keyboard state is already correct.
      // Nothing to do here for keyboard state.
      event = [UIWindowRefreshEvent alloc];
   }
   else
   {
      event = [UIWindowFocusLostEvent alloc];
   }
   event = [event init];
   event = [event autorelease];
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


static void   charCallback( GLFWwindow* window, unsigned int codepoint)
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


- (void) os_finalizeInputEvents
{
   assert( _window);

   assert( [NSThread mulleIsMainThread]);

   // input device events
   glfwSetMouseButtonCallback( _window, 0);
   glfwSetCursorPosCallback( _window, 0);
   glfwSetKeyCallback( _window, 0);
   glfwSetCharCallback( _window, 0);
   glfwSetScrollCallback( _window, 0);
}


- (void) os_initEvents
{
   [self os_initWindowEvents];
   [self os_initInputEvents];
}


- (void) os_finalizeEvents
{
   [self os_finalizeInputEvents];
   [self os_finalizeWindowEvents];
}


static inline int   shouldDiscardEvent( GLFWOSWindow *self, NSUInteger eventType)
{
   NSUInteger   mask;

   mask = (NSUInteger) _mulle_atomic_pointer_read( &self->_discardEventsMask);
   return( mask & eventType);
}


- (void) _keyCallback:(int) key
             scancode:(int) scancode
               action:(int) action
            modifiers:(int) mods
{
   UIEvent               *event;
   struct UIInputState   state;


   UIOSWindowEventLog( "modifiers=0x%tx", mods);

   NSLockingDo( _inputStateLock)
   {
      self->_inputState.timestamp    = mulle_absolutetime_now();
      self->_inputState.keyModifiers = mods;

      if( action == GLFW_PRESS)
      {
         UIKeyStatesHandleKeyDown( UIInputStateGetKeyStates( &self->_inputState), key);
         UIOSWindowEventLogVerbose( "keyboardState: down key=%d, count=%ld", key, (long) self->_inputState.keyStates._count);
      }
      else
      {
         if( action == GLFW_RELEASE)
         {
            UIKeyStatesHandleKeyUp( UIInputStateGetKeyStates( &self->_inputState), key);
            UIOSWindowEventLogVerbose( "keyboardState: up key=%d, count=%ld", key, (long) self->_inputState.keyStates._count);
         }
      }

      state = self->_inputState;
   }

   if( shouldDiscardEvent( self, UIEventTypePresses))
   {
      UIOSWindowEventLogVerbose( "discarded event");
      return;
   }

   event = [[UIKeyboardEvent alloc] initWithInputState:&state
                                                   key:key
                                              scanCode:scancode
                                                action:action
                                             isARepeat:NO];
  _otherRetainedEventsCallback( self, event);
}


- (void) _charCallback:(unsigned int) codepoint
{
   UIEvent               *event;
   struct UIInputState   state;

   UIOSWindowEventLog( nil, "");

   if( shouldDiscardEvent( self, UIEventTypeUnicode))
   {
      UIOSWindowEventLogVerbose( "discarded event");
      return;
   }

   NSLockingDo( _inputStateLock)
   {
      self->_inputState.timestamp = mulle_absolutetime_now();
      state = self->_inputState;
   }

   event = [[UIUnicodeEvent alloc] initWithInputState:&state
                                            character:codepoint];
  _otherRetainedEventsCallback( self, event);
}


- (void) _mouseButtonCallback:(int) glfwButton
                       action:(int) glfwAction
                    modifiers:(int) glfwModifiers
{
   UIEvent              *event;
   NSUInteger            button;
   struct UIInputState   state;

   UIOSWindowEventLog( "modifiers=0x%x", glfwModifiers);

   MULLE_C_ASSERT( (1U << GLFW_MOUSE_BUTTON_LEFT)   == UIEventMouseButtonLeft);
   MULLE_C_ASSERT( (1U << GLFW_MOUSE_BUTTON_MIDDLE) == UIEventMouseButtonMiddle);
   MULLE_C_ASSERT( (1U << GLFW_MOUSE_BUTTON_RIGHT)  == UIEventMouseButtonRight);

   MULLE_C_ASSERT( UIEventButtonActionUp     == GLFW_RELEASE);
   MULLE_C_ASSERT( UIEventButtonActionDown   == GLFW_PRESS);
   MULLE_C_ASSERT( UIEventButtonActionRepeat == GLFW_REPEAT);

   button = (NSUInteger) (1ULL << glfwButton);

   // ctrl+left click -> right click (macOS convention, on by default)
   {
      NSUInteger   modifiers = (NSUInteger) glfwModifiers;

      button        = UIEventMouseButtonWithModifiers( button, &modifiers);
      glfwModifiers = (int) modifiers;
   }

   NSLockingDo( _inputStateLock)
   {
      self->_inputState.timestamp    = mulle_absolutetime_now();
      self->_inputState.keyModifiers = glfwModifiers;

      if( glfwAction == GLFW_PRESS)
         self->_inputState.buttonStates |= button;
      else
         self->_inputState.buttonStates &= ~button;

      state = self->_inputState;
   }

   if( glfwAction == GLFW_PRESS)
   {
      CGFloat  dx;
      CGFloat  dy;
      BOOL     isMultiClick;

      dx = state.locationInWindow.x - _lastMouseButtonPressLocation.x;
      dy = state.locationInWindow.y - _lastMouseButtonPressLocation.y;

      isMultiClick = dx * dx + dy * dy < 5.0 * 5.0
                     && state.timestamp - _lastMouseButtonPressTime < [UIMouseButtonEvent doubleClickInterval];
      if( ! isMultiClick)
         _mouseButtonClickCount = 0;
      ++_mouseButtonClickCount;

      _lastMouseButtonPressTime     = state.timestamp;
      _lastMouseButtonPressLocation = state.locationInWindow;
   }

   if( shouldDiscardEvent( self, UIEventTypeTouches))
   {
      UIOSWindowEventLogVerbose( "discarded event");
      return;
   }

   event = [[UIMouseButtonEvent alloc] initWithInputState:&state
                                                   button:button
                                                   action:glfwAction
                                               clickCount:_mouseButtonClickCount];
  _otherRetainedEventsCallback( self, event);

   // [self dump];
}


- (void) _mouseMotionCallback:(CGPoint) pos
{
   UIEvent       *event;
   struct UIInputState   state;

   UIOSWindowMouseMotionEventLog( "%.1f, %.1f", pos.x, pos.y);

   //
   // Coordinates are window relative! So for screen coordinates we'd need
   // to add the window frame.x/y.
   //
   // We don't seem to get events for the window title bar.
   //
   // TODO: we might need to scale the values for DPI or ?
   // need this info, even if we don't send the event (for other events)
   //
   NSLockingDo( _inputStateLock)
   {
      self->_inputState.timestamp        = mulle_absolutetime_now();
      self->_inputState.locationInWindow = pos;

      state = self->_inputState;   // this can be avoided, since "we" are single-threaded
                                   // anyway, its only the callers that are multi-threaded
   }

   //
   // Observed behaviour on linux: Depending on mouse sensitivity, it may
   // become obvious that there is a rounding bug in the Linux mouse handling
   // where certain integer values are never returned. In my case this
   // turned out to be 200,200. So don't expect the mouse to provide all
   // possible integer coordinates for every pixel on the screen.
   //
   if( shouldDiscardEvent( self, UIEventTypeMotion))
   {
      UIOSWindowMouseMotionEventLog( "discarded event");
      return;
   }

   // TODO: wrap in autorelease pool ?
   //       + event don't leak if someone throws
   //       - latency

   // TODO: buttonStates need to be reset when the mouse leaves the
   //       window, but isn't
   event = [[UIMouseMotionEvent alloc] initWithInputState:&state];
   _otherRetainedEventsCallback( self, event);
}


- (void) _mouseScrollCallback:(CGPoint) offset
{
   UIEvent      *event;
   struct UIInputState  state;
   CGPoint       scrollOffset;
   CGFloat       sensitivity;

   UIOSWindowEventLog("");

   if( shouldDiscardEvent( self, UIEventTypeScroll))
   {
      UIOSWindowEventLogVerbose( "discarded event");
      return;
   }

   NSLockingDo( _inputStateLock)
   {
      self->_inputState.timestamp = mulle_absolutetime_now();
      state = self->_inputState;
   }

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

   event = [[UIMouseScrollEvent alloc] initWithInputState:&state
                                             scrollOffset:scrollOffset];
   _otherRetainedEventsCallback( self, event);
}



@end

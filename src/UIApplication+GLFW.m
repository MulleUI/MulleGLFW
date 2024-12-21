//
// Copyright (c) 2020 Nat!, Mulle kybernetiK
//
#ifdef __has_include
# if __has_include( "UIApplication.h")
#  import "UIApplication.h"
# endif
#endif


#import "import-private.h"

#import "GLFWOSScreen.h"
#import "GLFWOSGamepad.h"


#ifdef DEBUG
//# define GLFW_LOG_ERROR
#endif 

@interface UIApplication( UIScreenPrivate)

- (void) _addScreen:(id <UIScreen>) screen;
// does not call [UIWindow terminate]
- (void) _removeScreen:(id <UIScreen>) screen;

@end



@interface UIApplication( UIGamepadPrivate)

- (void) _addGamepad:(id <UIGamepad>) gamepad;
// does not call [UIWindow terminate]
- (void) _removeGamepad:(id <UIGamepad>) gamepad;

@end


@interface UIApplication ( GLFW)
@end


@implementation UIApplication ( GLFW)

#ifdef GLFW_LOG_ERROR
static void   callback_glfw_error(int code, const char* description)
{
   fprintf( stderr, "GLFW Error #%d: \"%s\"\n", code, description);
}
#endif


static void   monitorCallback( GLFWmonitor *monitor, int event)
{
   UIScreenEvent       *screenEvent;
   GLFWOSScreen        *screen;
   UIScreenEventType   type;

   switch( event)
   {
   case GLFW_CONNECTED    : type   = UIScreenEventTypeConnected;
                            screen = [[[GLFWOSScreen alloc] initWithGLFWMonitor:monitor] autorelease];
                            break;

   case GLFW_DISCONNECTED : type   = UIScreenEventTypeDisconnected;
                            screen = glfwGetMonitorUserPointer( monitor);
                            break;

   default                : fprintf( stderr, "GLFW unknown monitor event %d\n", event);
                            return;
   }

   screenEvent = [[[UIScreenEvent alloc] initWithScreen:screen
                                        screenEventType:type] autorelease];

#ifdef DEBUG
   if( ! UIApp)
      MulleUICLog( "UIApp is not available, as +sharedInstance hasn't been called.");
#endif
   [UIApp handleScreenEvent:screenEvent];
}


static void   joystickCallback( int jid, int event)
{
   GLFWOSGamepad        *gamepad;
   UIGamepadEvent       *gamepadEvent;
   UIGamepadEventType   type;

   switch( event)
   {
   case GLFW_CONNECTED    : type    = UIGamepadEventTypeConnected;
                            gamepad = [[[GLFWOSGamepad alloc] initWithOSGamepad:(void *) (uintptr_t) jid] autorelease];
                            break;

   case GLFW_DISCONNECTED : type    = UIGamepadEventTypeDisconnected;
                            gamepad = glfwGetJoystickUserPointer( jid);
                            break;

   default                : MulleUICLog( "GLFW unknown monitor event %d\n", event);
                            return;
   }

   if( ! gamepad)
   {
      MulleUICLog( "GLFW stray uninitializable gamepad event");
      return;
   }

   gamepadEvent = [[[UIGamepadEvent alloc] initWithGamepad:gamepad
                                          gamepadEventType:type] autorelease];

#ifdef DEBUG
   if( ! UIApp)
      MulleUICLog( "UIApp is not available, as +sharedInstance hasn't been called.");
#endif
   [UIApp handleGamepadEvent:gamepadEvent];
}


+ (void) os_initialize
{
   assert( [NSThread mulleIsMainThread]);

#ifdef GLFW_LOG_ERROR
   glfwSetErrorCallback( callback_glfw_error);
#endif

   // This function initializes the GLFW library. Before most GLFW functions
   // can be used, GLFW must be initialized, and before an application
   // terminates GLFW should be terminated in order to free any resources
   // allocated during or after initialization.
   //
   // Additional calls to this function after successful initialization but
   // before termination will return GLFW_TRUE immediately.

   // we don't want those mixed in, though frankly we don't want joysticks
   // either... (prefer gamepads)
   glfwInitHint( GLFW_JOYSTICK_HAT_BUTTONS, GLFW_FALSE);

   if( ! glfwInit())
   {
      fprintf( stderr, "Couldn't get GLFW initialized\n");
      abort();
   }
   // calling glSwapInterval here is too early, as the window isn't there yet
}


+ (void) os_deinitialize
{
   // this doesn't exit the app,

   // This function destroys all remaining windows and cursors, restores any
   // modified gamma ramps and frees any other allocated resources. Once this
   // function is called, you must again call glfwInit successfully before you
   // will be able to use most GLFW functions.
	glfwTerminate();

   glfwSetErrorCallback( 0);
}


- (void) os_init
{
   NSUInteger     i, n;
   GLFWOSScreen   *screen;
   GLFWOSGamepad  *gamepad;
   NSRange        range;
   NSUInteger     max;

   n = [GLFWOSScreen numberOfScreens];
   for( i = 0; i < n; i++)
   {
      screen = (GLFWOSScreen *) [GLFWOSScreen screenAtIndex:i];
      [self _addScreen:screen];
   }
   glfwSetMonitorCallback( monitorCallback);

   range = [GLFWOSGamepad osIndexRange];
   max   = NSMaxRange( range);
   for( i = range.location; i < max; i++)
   {
      gamepad = (GLFWOSGamepad *) [GLFWOSGamepad gamepadAtOSIndex:i];
      if( gamepad)
         [self _addGamepad:gamepad];
   }
   glfwSetJoystickCallback( joystickCallback);
}


- (void) os_finalize
{
   glfwSetJoystickCallback( 0);
   glfwSetMonitorCallback( 0);
}


- (void *) os_createStandardCursor:(UICursorStandardShape) shape
{
   assert( [NSThread mulleIsMainThread]);
   int   glfwShape;
        
   switch( shape)
   {
   default                       : glfwShape = GLFW_ARROW_CURSOR; break;
   case UICursorTextInput        : glfwShape = GLFW_IBEAM_CURSOR; break;
   case UICursorDrag             : glfwShape = GLFW_HAND_CURSOR; break;
   case UICursorHorizontalResize : glfwShape = GLFW_HRESIZE_CURSOR; break;
   case UICursorVerticalResize   : glfwShape = GLFW_VRESIZE_CURSOR; break;
#if (GLFW_VERSION_MAJOR > 3) || (GLFW_VERSION_MAJOR == 3 && GLFW_VERSION_MAJOR >= 4)
   case UICursorDiagonalResize   : glfwShape = GLFW_RESIZE_NWSE_CURSOR; break;
#endif
   }

   return( glfwCreateStandardCursor( glfwShape));
}


- (void *) os_createCursorWithBitmap:(struct CGBitmap) bitmap
                             hotSpot:(struct CGPixelPoint) hotSpot
{
   assert( [NSThread mulleIsMainThread]);

   GLFWcursor   *cursor;
   GLFWimage    image;

   if( CGBitmapIsNull( bitmap))
      return( NULL);

   image.width  = CGBitmapGetWidth( bitmap);
   image.height = CGBitmapGetHeight( bitmap);
   image.pixels = CGBitmapGetBytes( bitmap);

   cursor = glfwCreateCursor( &image, hotSpot.x, hotSpot.y);
   return( cursor);
}


- (void) os_destroyCursor:(void *) cursor
{
   assert( [NSThread mulleIsMainThread]);

   glfwDestroyCursor( cursor);
}


//
// don't use this manually on UIWindow, since we are using a queuing mechanism
// with our own timeout code. Use pollEvents on UIWindow, or maybe better
// use UIApplication run
- (void) os_waitEventsWithTimeout:(mulle_relativetime_t) timeout
{
   assert( [NSThread mulleIsMainThread]);

   // glfw can't cope with infinity and don't like < 0.0
   if( isinf( timeout))
      glfwWaitEvents();
   else
      if( timeout <= 0.0)
         glfwPollEvents();
      else
         glfwWaitEventsTimeout( timeout);
}


- (void) os_pollEvents
{
   assert( [NSThread mulleIsMainThread]);

   glfwPollEvents();
}


- (void) os_sendEmptyEvent
{
   // can be called from any thread
   glfwPostEmptyEvent();
}


- (void) os_pollGamepads
{
   id <UIGamepad>  gamepad;
   int             i;

   assert( [NSThread mulleIsMainThread]);

   // glfw actually lies and sends events during joystick functions and
   // not in pollEvents
   //     event=0x55555663d8f0) at /home/src/srcO/MulleUI/MulleUIApplication/src/UIApplication+UIEvent.m:50
   // #21 0x000055555586eb7c in joystickCallback (jid=1, event=262146) at /home/src/srcO/MulleUI/MulleGLFW/src/UIApplication+GLFW.m:118
   // #22 0x0000555555a47b4f in _glfwInputJoystick (js=0x55555606cc08 <_glfw+10152>, event=262146)
   //     at /home/nat/.mulle/var/demos-4fd3f1c00ec5/stash/glfw/src/input.c:427
   // #23 0x0000555555a64ade in closeJoystick (js=0x55555606cc08 <_glfw+10152>)
   //     at /home/nat/.mulle/var/demos-4fd3f1c00ec5/stash/glfw/src/linux_joystick.c:248
   // #24 0x0000555555a650d3 in _glfwPollJoystickLinux (js=0x55555606cc08 <_glfw+10152>, mode=0)
   //     at /home/nat/.mulle/var/demos-4fd3f1c00ec5/stash/glfw/src/linux_joystick.c:398
   // #25 0x0000555555a4a48e in glfwJoystickIsGamepad (jid=1) at /home/nat/.mulle/var/demos-4fd3f1c00ec5/stash/glfw/src/input.c:1336
   // #26 0x000055555586675f in -[GLFWOSGamepad updateGamepadInfo] (self=0x555558f50bf0, _cmd=<unvollständiger Typ>)

   // so UIApplication can't really do locking of its array and then call
   // -updateGamepadInfo, so we lame here
   for( i = GLFW_JOYSTICK_1; i <= GLFW_JOYSTICK_LAST; i++)
   {
      gamepad = glfwGetJoystickUserPointer( i);
      [gamepad os_pollGamepadInfo];
   }
}



@end


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


@interface UIApplication( UIScreenPrivate)

- (void) _addScreen:(id <UIScreen>) screen;
// does not call [UIWindow terminate]
- (void) _removeScreen:(id <UIScreen>) screen;

@end


@implementation UIApplication ( GLFW)

static void   error_callback(int code, const char* description)
{
   fprintf( stderr, "GLFW Error #%d: \"%s\"\n", code, description);
}


static void   monitorCallback( GLFWmonitor *monitor, int event)
{
   UIApplication            *app;
   UIScreenEvent            *screenEvent;
   GLFWOSScreen             *screen;
   enum UIScreenEventType   type;

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
   app = [UIApplication sharedInstance];
   [app handleScreenEvent:screenEvent];
}


+ (void) os_initialize
{
   assert( [NSThread mulleIsMainThread]);

   glfwSetErrorCallback( error_callback);

   // This function initializes the GLFW library. Before most GLFW functions
   // can be used, GLFW must be initialized, and before an application
   // terminates GLFW should be terminated in order to free any resources
   // allocated during or after initialization.
   //
   // Additional calls to this function after successful initialization but
   // before termination will return GLFW_TRUE immediately.

   if( ! glfwInit())
   {
      fprintf( stderr, "Couldn't get GLFW initialized\n");
      abort();
   }
   // calling glSwapInterval here is too early, as the window isn't there yet

}


+ (void) os_terminate
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

   n = [GLFWOSScreen numberOfScreens];
   for( i = 0; i < n; i++)
   {
      screen = [GLFWOSScreen screenAtIndex:i];
      [self _addScreen:screen];
   }

   glfwSetMonitorCallback( monitorCallback);
}

- (void) os_finalize
{
   glfwSetMonitorCallback( 0);
}


@end

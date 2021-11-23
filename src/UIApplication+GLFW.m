//
// Copyright (c) 2020 Nat!, Mulle kybernetiK
//
#ifdef __has_include
# if __has_include( "UIApplication.h")
#  import "UIApplication.h"
# endif
#endif


#import "import-private.h"



@implementation UIApplication ( GLFW)

static void   error_callback(int code, const char* description)
{
   fprintf( stderr, "GLFW Error #%d: \"%s\"\n", code, description);
}


+ (void) os_initialize
{
   assert( [NSThread mulleIsMainThread]);

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
   glfwSetErrorCallback( error_callback);
}


+ (void) os_terminate
{
   // this doesn't exit the app,

   // This function destroys all remaining windows and cursors, restores any
   // modified gamma ramps and frees any other allocated resources. Once this
   // function is called, you must again call glfwInit successfully before you
   // will be able to use most GLFW functions.
	glfwTerminate();
}

@end

//
// Copyright (c) 2020 Nat!, Mulle kybernetiK
//
#ifdef __has_include
# if __has_include( "UIEvent.h")
#  import "UIEvent.h"
# endif
#endif

#import "import-private.h"


@implementation UIEvent ( GLFW)

//
// don't use this manually on UIWindow, since we are using a queuing mechanism
// with our own timeout code. Use pollEvents on UIWindow, or maybe better
// use UIApplication run
+ (void) os_waitEventsWithTimeout:(mulle_relativetime_t) timeout
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


+ (void) os_pollEvents
{
   assert( [NSThread mulleIsMainThread]);

   glfwPollEvents();
}


+ (void) os_sendEmptyEvent
{
   // can be called from any thread
   glfwPostEmptyEvent();
}

@end

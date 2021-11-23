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
// with our own timeout code. Use pollEvents on UIWindow usually
//
+ (void) os_waitEventsTimeout:(CGFloat) seconds
{
   assert( [NSThread mulleIsMainThread]);

   glfwWaitEventsTimeout( seconds);
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

#import "UIApplication.h"

#import "UIEvent.h"

#import "import-private.h"


static uintptr_t   object_hash( struct mulle_container_keycallback *callback,
                               void * obj)
{
   return( (uintptr_t) [(id) obj hash]);
}

static int   object_is_equal( struct mulle_container_keycallback *callback,
                             void *obj,
                             void *other)
{
   return( [(id) obj isEqual:(id) other]);
}


static void   *object_retain( struct mulle_container_keycallback *callback,
                              void *obj,
                              struct mulle_allocator *allocator)
{
   return( [(id) obj retain]);
}


static void   object_autorelease( struct mulle_container_keycallback *callback,
                                  void *obj,
                                  struct mulle_allocator *allocator)
{
   [(id) obj autorelease];
}

static char   *object_describe( struct mulle_container_keycallback *callback,
                                void *obj,
                                struct mulle_allocator **p_allocator)
{
   *p_allocator = NULL;
   return( mulle_objc_object_call( (id) obj, @selector( UTF8String), (id) obj));
}




static const struct mulle_container_keycallback   key_retain_callback =
{
   object_hash,
   object_is_equal,
   object_retain,
   object_autorelease,
   object_describe,

   nil,
   NULL
};



@implementation UIApplication

+ (void) initialize
{
   [super initialize];  // call singleton initialize ?
   [UIApplication os_initialize];
}


- (id) init
{
   struct mulle_allocator   *allocator;

   assert( [NSThread mulleIsMainThread]);

   allocator = MulleObjCInstanceGetAllocator( self);
   mulle_array_init( &_windows,
                     2,
                     (struct mulle_container_keycallback *) &key_retain_callback,
                     allocator);
   return( self);
}


- (void) dealloc
{
   assert( [NSThread mulleIsMainThread]);

   mulle_array_done( &_windows);
   [super dealloc];
}


- (NSInteger) _indexOfWindow:(id <UIWindow>) window
{
   uintptr_t   found;

   assert( [NSThread mulleIsMainThread]);


   found = mulle_array_find_in_range_identical( &_windows,
                                                window,
                                                mulle_range_make_all());

   return( found == mulle_not_found_e ? NSNotFound : (NSInteger) found);
}


- (NSUInteger) numberOfWindows
{
   assert( [NSThread mulleIsMainThread]);

   return( mulle_array_get_count( &_windows));
}


- (NSUInteger) getWindows:(id <UIWindow> *) buf
                   length:(NSUInteger) length
{
   NSUInteger   n;

   assert( [NSThread mulleIsMainThread]);

   n = mulle_array_get_count( &_windows);
   if( length >= n)
      mulle_array_get_in_range( &_windows, mulle_range_make( 0, n), buf);
   return( n);
}


- (void) addWindow:(id <UIWindow>) window
{
   assert( window);
   assert( [self _indexOfWindow:window] == NSNotFound);
   assert( [NSThread mulleIsMainThread]);

   mulle_array_add( &_windows, window);
}


- (void) removeWindow:(id <UIWindow>) window
{
   NSInteger   found;

   assert( [NSThread mulleIsMainThread]);
   found = [self _indexOfWindow:window];
   if( found == NSNotFound)
      return;

   mulle_array_remove_in_range( &_windows,
                                mulle_range_make( found, 1));
}

// assume all windows thread are quiescent now... else why call terminate :)
- (int) terminate
{
   struct mulle_arrayenumerator   rover;
   id <UIWindow>                  window;

   // ensure all windows are not calling glfw/opengl anymore
   rover = mulle_array_enumerate( &_windows);
   while( _mulle_arrayenumerator_next( &rover, (void **) &window))
      [window mullePerformFinalize];
   mulle_arrayenumerator_done( &rover);

   mulle_array_reset( &_windows);

   // this shuts down glfw, it doesn't exit
   [[self class] os_terminate];
   return( _returnValue);
}


- (void) run
{
   for(;;)
   {
      //
      // Will just poll glfw for events, if events arrive this will
      // exit, and we just loop again. The event handling is done by
      // id <UIWindow>s+UIEvent mainly.
      // Since an emptyEvent wakes us up too, we need to figure out
      // if we need to send the empty event to the windows, but how ?
      [UIEvent os_waitEventsTimeout:3600.0];
   }
}


int  UIApplicationMain( int argc, char **argv, Class appClass, id delegate)
{
   UIApplication   *app;

   assert( [NSThread mulleIsMainThread]);

   appClass = appClass ? appClass : [UIApplication class];

   app = [appClass sharedInstance];
   [app setDelegate:delegate];
   [app run];
   return( [app returnValue]);
}

@end

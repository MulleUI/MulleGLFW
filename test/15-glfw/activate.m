#import <MulleGLFW/MulleGLFW.h>


#define LOOPS   10000

@interface GLFWOSWindow( Attach)
@end

@implementation GLFWOSWindow( Attach)

- (void) dummy
{
}

@end


//
// this is a little test program to gauge how slow graphics context switches
// are. Bottomline is "not negligble"
//
int   main( void)
{
   UIApplication          *app;
   GLFWOSWindow           *window;
   NSUInteger             i;
   mulle_timeinterval_t   start;
   mulle_timeinterval_t   end;

   app = [UIApplication sharedInstance];

   @autoreleasepool
   {
      window = [[[GLFWOSWindow alloc] initWithFrame:CGRectMake( 0, 0, 128, 128)
                                    titleUTF8String:"Foo"
                                          styleMask:UIWindowStyleBare|UIWindowStyleHidden
                                      graphicsHints:GLFWGraphicsHintsDefault] autorelease];
      if( ! window)
      {
         fprintf( stderr, "window: failed\n");
         exit( 1);
      }

      start = mulle_timeinterval_now();
      for( i = 0; i < 10000; i++)
      {
         [window dummy];
         [window dummy];
      }
      end = mulle_timeinterval_now();
      fprintf( stderr, "overhead : %.6f us\n", (end - start) / LOOPS * 1000 * 1000);

      start = mulle_timeinterval_now();
      for( i = 0; i < 10000; i++)
      {
         [window os_activateGraphicsContext];
         [window os_deactivateGraphicsContext];
      }
      end = mulle_timeinterval_now();

      fprintf( stderr, "cycle    : %.6f us\n", (end - start) / LOOPS * 1000 * 1000);
   }
   [app terminate];

   return( 0);
}
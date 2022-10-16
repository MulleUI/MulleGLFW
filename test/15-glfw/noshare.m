#import <MulleGLFW/MulleGLFW.h>


int   main( void)
{
   UIApplication   *app;
   GLFWOSWindow      *window;

   app    = [UIApplication sharedInstance];

   window = [[[GLFWOSWindow alloc] initWithFrame:CGRectMake( 0, 0, 128, 128)
                               titleUTF8String:"Foo"
                                     styleMask:UIWindowStyleBare|UIWindowStyleInvisible
                                 graphicsHints:0
                                 sharingWindow:nil] autorelease];
   if( ! window)
   {
      fprintf( stderr, "initWithFrame: failed\n");
      exit( 1);
   }
   [window mullePerformFinalize];

   [app terminate];
   return( 0);
}
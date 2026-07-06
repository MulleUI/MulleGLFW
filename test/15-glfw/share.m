#import <MulleGLFW/MulleGLFW.h>


int   main( void)
{
   UIApplication   *app;
   GLFWOSWindow      *window[ 2];

   app = [UIApplication sharedInstance];

   @autoreleasepool
   {
      window[ 0] = [[[GLFWOSWindow alloc] initWithFrame:CGRectMake( 0, 0, 128, 128)
                                        titleUTF8String:"Foo"
                                              styleMask:UIWindowStyleBare|UIWindowStyleHidden
                                          graphicsHints:GLFWGraphicsHintsDefault] autorelease];

      window[ 1] = [[[GLFWOSWindow alloc] initWithFrame:CGRectMake( 128, 0, 128, 128)
                                        titleUTF8String:"Bar"
                                              styleMask:UIWindowStyleBare|UIWindowStyleHidden
                                          graphicsHints:GLFWGraphicsHintsDefault
                                          sharingWindow:window[ 0]] autorelease];
      if( ! window[ 1])
      {
         fprintf( stderr, "sharingWindow: failed\n");
         exit( 1);
      }

      // GLFW windows are not part of UIApplication, but once we
      // terminate the app, the windows can't properly be reaped so.
      // either performFinalize them or wrap everything into an autoreleasepool
      // which is easier
   }
   [app terminate];

   return( 0);
}
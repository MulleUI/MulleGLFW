#include <MulleGLFW/MulleGLFW.h>

#include <time.h>


int main( int argc, char *argv[])
{
   struct timespec delay = { 0, 500 * 1000L * 1000L};

   GLFWOSWindow   *gWindow;

   @autoreleasepool
   {
      gWindow = [[[GLFWOSWindow alloc] initWithFrame:CGRectMake( 0, 0, 640, 480)
                                     titleUTF8String:"Demo"
                                           styleMask:GLFWOSWindowStyleMaskDefault|UIWindowStyleSingleBuffer
                                       graphicsHints:0] autorelease];
      if( ! gWindow)
      {
         fprintf( stderr, "No window for you!. Single buffer style is not supported.\n");
         return( 0);
      }

      [gWindow os_activateGraphicsContext];

      for(;;)
      {
         [UIEvent os_pollEvents];
         if( [gWindow shouldClose])
            break;

         glClearColor( 0.3, 0.3, 0.3, 0.0);
         glClear( GL_COLOR_BUFFER_BIT);
         glFlush();
         nanosleep( &delay, NULL);

         [UIEvent os_pollEvents];
         if( [gWindow shouldClose])
            break;

         glClearColor( 0.3, 0.3, 0.7, 0.0);
         glClear( GL_COLOR_BUFFER_BIT);
         glFlush();
         nanosleep( &delay, NULL);
      }
   }
   return( 0);
}

//! [code]

#include <MulleGLFW/MulleGLFW.h>


int main( int argc, char *argv[])
{
   GLFWOSWindow   *gWindow;

   @autoreleasepool
   {
      gWindow = [[[GLFWOSWindow alloc] initWithFrame:CGRectMake( 0, 0, 640, 480)
                                     titleUTF8String:"Demo"
                                           styleMask:GLFWOSWindowStyleMaskDefault
                                       graphicsHints:0] autorelease];

      [gWindow os_activateGraphicsContext];
      [gWindow os_setSwapInterval:30];

      glClearColor( 0.3, 0.3, 0.3, 0.0);
      glClear( GL_COLOR_BUFFER_BIT);

      [gWindow os_swapBuffers];

      glClearColor( 0.3, 0.3, 0.7, 0.0);
      glClear( GL_COLOR_BUFFER_BIT);

      [gWindow os_swapBuffers];

      while( ! [gWindow shouldClose])
      {
         [gWindow os_swapBuffers];
         [UIEvent os_pollEvents];
      }
   }
   return( 0);
}

//! [code]

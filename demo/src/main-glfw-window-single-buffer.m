#define _GNU_SOURCE
#define MULLE_GLFW_EXPOSE_OPEN_GL
#define GLFW_INCLUDE_GLEXT

#include <MulleGLFW/MulleGLFW.h>

#include <time.h>


int main( int argc, char *argv[])
{
   struct timespec delay = { 0, 500 * 1000L * 1000L};

   GLFWOSWindow    *gWindow;
   UIApplication   *app;

   app = [UIApplication sharedInstance];
   @autoreleasepool
   {
      gWindow = [[[GLFWOSWindow alloc] initWithFrame:CGRectMake( 0, 0, 640, 480)
                                     titleUTF8String:"Demo"
                                           styleMask:GLFWOSWindowStyleMaskDefault|UIWindowStyleSingleBuffer
                                       graphicsHints:GLFW_DEFAULT_CONTEXT] autorelease];
      if( ! gWindow)
      {
         fprintf( stderr, "No window for you!. Single buffer style is not supported.\n");
         return( 0);
      }

      [gWindow os_activateGraphicsContext];

      for(;;)
      {
         glfwPollEvents();
         if( glfwWindowShouldClose([gWindow os_window]))
            break;

         glClearColor( 0.3, 0.3, 0.3, 0.0);
         glClear( GL_COLOR_BUFFER_BIT);
         glFlush();
         nanosleep( &delay, NULL);

         glfwPollEvents();
         if( glfwWindowShouldClose([gWindow os_window]))
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

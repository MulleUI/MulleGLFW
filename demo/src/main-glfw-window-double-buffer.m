#define _GNU_SOURCE
#define MULLE_GLFW_EXPOSE_OPEN_GL
#define GLFW_INCLUDE_GLEXT

#include <MulleGLFW/MulleGLFW.h>

// THIS DEMO CAN'T WORK AS EXPECTED FOR TECHNICAL REASONS OUTSIDE OF OUR
// CONTROL. So we need to clear and redraw, which makes this somewhat useless.
//
// https://discourse.glfw.org/t/problem-with-double-buffering-and-nvidia-on-linux-wayland/2170/4
//
//
// GFLW on Wayland uses EGL by default for context creation 5, and thus the
// glfwSwapBuffers calls eglSwapBuffers 1.
//
// From the documentation EGL_SWAP_BEHAVIOR attribute would need to be set to
// EGL_BUFFER_PRESERVED to preserve the back buffer, and this is not set by
// GLFW. The behaviour of buffer swapping is not consistent across
// APIs/OSs/Drivers so I do not think it would be useful for GLFW to set this,
// but you could use the native interface 3 to get the EGL surface and set the
// surface attribute yourself.
// The behaviour of EGL without EGL_BUFFER_PRESERVED set and the behaviour of
// GLX are that The contents of the color buffer are undefined. The swap
// behaviour of some drivers/hardware is to copy the contents, so the results
// you see on GLX could be due to this. Generally it is not safe to assume
// undefined behaviour will do a specific thing.
//


int main( int argc, char *argv[])
{
   GLFWOSWindow     *gWindow;
   UIApplication    *app;

   app = [UIApplication sharedInstance];
   @autoreleasepool
   {
      gWindow = [[[GLFWOSWindow alloc] initWithFrame:CGRectMake( 0, 0, 640, 480)
                                     titleUTF8String:"Demo"
                                           styleMask:GLFWOSWindowStyleMaskDefault
                                       graphicsHints:GLFWGraphicsHintsDefault] autorelease];
      if( ! gWindow)
      {
         fprintf( stderr, "No window for you!. Double buffer style is not supported.\n");
         return( 0);
      }

      [gWindow os_activateGraphicsContext];

      // swapInterval is not really 120 :(
      [gWindow os_setSwapInterval:120];

      while( ! glfwWindowShouldClose( [gWindow os_window]))
      {
         glClearColor( 0.7, 0.0, 0.0, 0.0);
         glClear( GL_COLOR_BUFFER_BIT);
         glFlush();

         [gWindow os_swapBuffers];

         glClearColor( 0.0, 0.0, 0.7, 0.0);
         glClear( GL_COLOR_BUFFER_BIT);
         glFlush();

         [gWindow os_swapBuffers];
         glfwPollEvents();
      }
   }
   return( 0);
}

//! [code]

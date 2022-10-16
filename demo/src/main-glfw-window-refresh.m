#define _GNU_SOURCE

#define GL_GLEXT_PROTOTYPES
#ifdef __APPLE__
# include <OpenGL/gl.h>
# include <OpenGL/glext.h>
#else
# include <GL/gl.h>
# include <GL/glext.h>
#endif

#define GLFW_INCLUDE_NONE
#include <GLFW/glfw3.h>

//#import "import.h"

#include <string.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

uintptr_t    counter;
char         buf[ 64] = { ' ', ' ', ' ', ' ', '0', 0 };

#define RGBA( r, g, b, a)    { r, g, b, a }
#define GRAYA( gray,a)       RGBA( gray, gray, gray, a )
#define GRAY( gray)          RGBA( gray, gray, gray, 1.0f )

#define W   GRAY( 0.8f)
#define B   GRAY( 0.0f)
#define _   GRAYA( 0.0f, 0.0f)


static float   space[ 9 * 8][ 4]  =
{
   _, _, _, _,  _, _, _, _,
   _, _, _, _,  _, _, _, _,
   _, _, _, _,  _, _, _, _,
   _, _, _, _,  _, _, _, _,
   _, _, _, _,  _, _, _, _,

   _, _, _, _,  _, _, _, _,
   _, _, _, _,  _, _, _, _,
   _, _, _, _,  _, _, _, _,
   _, _, _, _,  _, _, _, _
};


static float   zero[ 9 * 8][ 4]  =
{
   _, _, _, _,  _, _, _, _,
   _, _, _, W,  W, _, _, _,
   _, _, W, _,  _, W, _, _,
   _, _, W, _,  _, W, _, _,
   _, _, W, _,  _, W, _, _,

   _, _, W, _,  _, W, _, _,
   _, _, W, _,  _, W, _, _,
   _, _, _, W,  W, _, _, _,
   _, _, _, _,  _, _, _, _
};


static float   one[ 9 * 8][ 4]  =
{
   _, _, _, _,  _, _, _, _,
   _, _, _, W,  W, _, _, _,
   _, _, W, _,  W, _, _, _,
   _, _, _, _,  W, _, _, _,
   _, _, _, _,  W, _, _, _,

   _, _, _, _,  W, _, _, _,
   _, _, _, _,  W, _, _, _,
   _, _, W, W,  W, W, _, _,
   _, _, _, _,  _, _, _, _
};


static float   two[ 9 * 8][ 4]  =
{
   _, _, _, _,  _, _, _, _,
   _, _, _, W,  W, _, _, _,
   _, _, W, _,  _, W, _, _,
   _, _, _, _,  _, W, _, _,
   _, _, _, _,  W, _, _, _,

   _, _, _, W,  _, _, _, _,
   _, _, W, _,  _, _, _, _,
   _, _, W, W,  W, W, _, _,
   _, _, _, _,  _, _, _, _
};

static float   three[ 9 * 8][ 4]  =
{
   _, _, _, _,  _, _, _, _,
   _, _, _, W,  W, _, _, _,
   _, _, W, _,  _, W, _, _,
   _, _, _, _,  _, W, _, _,
   _, _, _, W,  W, _, _, _,

   _, _, _, _,  _, W, _, _,
   _, _, W, _,  _, W, _, _,
   _, _, _, W,  W, _, _, _,
   _, _, _, _,  _, _, _, _
};


static float   four[ 9 * 8][ 4]  =
{
   _, _, _, _,  _, _, _, _,
   _, _, W, _,  _, _, _, _,
   _, _, W, _,  _, W, _, _,
   _, _, W, _,  _, W, _, _,
   _, _, W, W,  _, W, _, _,

   _, _, _, W,  W, W, _, _,
   _, _, _, _,  _, W, _, _,
   _, _, _, _,  _, W, _, _,
   _, _, _, _,  _, _, _, _
};


static float   five[ 9 * 8][ 4]  =
{
   _, _, _, _,  _, _, _, _,
   _, _, W, W,  W, W, _, _,
   _, _, W, _,  _, _, _, _,
   _, _, W, _,  _, _, _, _,
   _, _, _, W,  W, _, _, _,

   _, _, _, _,  _, W, _, _,
   _, _, W, _,  _, W, _, _,
   _, _, _, W,  W, _, _, _,
   _, _, _, _,  _, _, _, _
};


static float   six[ 9 * 8][ 4]  =
{
   _, _, _, _,  _, _, _, _,
   _, _, _, W,  W, _, _, _,
   _, _, W, _,  _, W, _, _,
   _, _, W, _,  _, _, _, _,
   _, _, W, W,  W, _, _, _,

   _, _, W, _,  _, W, _, _,
   _, _, W, _,  _, W, _, _,
   _, _, _, W,  W, _, _, _,
   _, _, _, _,  _, _, _, _
};


static float   seven[ 9 * 8][ 4]  =
{
   _, _, _, _,  _, _, _, _,
   _, _, W, W,  W, W, _, _,
   _, _, _, _,  _, W, _, _,
   _, _, _, _,  W, _, _, _,
   _, _, _, _,  W, _, _, _,

   _, _, _, W,  _, _, _, _,
   _, _, _, W,  _, _, _, _,
   _, _, _, W,  _, _, _, _,
   _, _, _, _,  _, _, _, _
};


static float   eight[ 9 * 8][ 4]  =
{
   _, _, _, _,  _, _, _, _,
   _, _, _, W,  W, _, _, _,
   _, _, W, _,  _, W, _, _,
   _, _, W, _,  _, W, _, _,
   _, _, _, W,  W, _, _, _,

   _, _, W, _,  _, W, _, _,
   _, _, W, _,  _, W, _, _,
   _, _, _, W,  W, _, _, _,
   _, _, _, _,  _, _, _, _
};


static float   nine[ 9 * 8][ 4]  =
{
   _, _, _, _,  _, _, _, _,
   _, _, _, W,  W, _, _, _,
   _, _, W, _,  _, W, _, _,
   _, _, W, _,  _, W, _, _,
   _, _, _, W,  W, W, _, _,

   _, _, _, _,  _, W, _, _,
   _, _, W, _,  _, W, _, _,
   _, _, _, W,  W, _, _, _,
   _, _, _, _,  _, _, _, _
};


static void   flipV( float *texture)
{
   float   tmp[ 8][ 4];
   int     y;

   for( y = 0; y < 9; y++)
   {
      memcpy( tmp, &texture[ y * 8 * 4], sizeof( float) * 4 * 8);
      memcpy( &texture[ y * 8 * 4], &texture[ (8 - y) * 8 * 4], sizeof( float) * 4 * 8);
      memcpy( &texture[ (8 - y) * 8 * 4], tmp, sizeof( float) * 4 * 8);
   }
}


static float   *digits[ 10] =
{
   (float *) zero,  (float *) one,   (float *) two,
   (float *) three, (float *) four,  (float *) five,
   (float *) six,   (float *) seven, (float *) eight,
   (float *) nine
};

static GLuint  textures[ 11];


GLuint   init_texture( void *texture)
{
   GLuint   textureName;

   glGenTextures( 1, &textureName);
   glBindTexture( GL_TEXTURE_2D, textureName);

   glTexParameterf( GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
   glTexParameterf( GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
   glTexParameterf( GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
   glTexParameterf( GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);

   //glTexEnvf( GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_REPLACE);

   glTexImage2D( GL_TEXTURE_2D, 0,                // One resolution (i.e. level 0)
                                GL_RGBA,
                                8,                 // Width
                                9,                 // Height
                                0,                 // Border width
                                GL_RGBA,           // Format
                                GL_FLOAT,          // Data type of the texels
                                texture);

   glEnable( GL_TEXTURE_2D);
   return( textureName);
}


static void   draw_texture( size_t position, GLuint handle)
{
   GLfloat vertices[ 4][ 3];

   glBindTexture( GL_TEXTURE_2D, handle);

   // use position for 'x'
   vertices[ 0][ 0] = -1.0 + position * 0.2;
   vertices[ 1][ 0] = vertices[ 0][ 0] + 0.2;
   vertices[ 2][ 0] = vertices[ 1][ 0];
   vertices[ 3][ 0] = vertices[ 0][ 0];

   // use middle for 'y'
   vertices[ 0][ 1] = -0.1;
   vertices[ 1][ 1] = vertices[ 0][ 1];
   vertices[ 2][ 1] = 0.1;
   vertices[ 3][ 1] = vertices[ 2][ 1];

   vertices[ 0][ 2] = 1.0;
   vertices[ 1][ 2] = 1.0;
   vertices[ 2][ 2] = 1.0;
   vertices[ 3][ 2] = 1.0;

   glBegin( GL_POLYGON);

   glTexCoord2f( 0.0, 1.0);
   glVertex3fv( vertices[0]);

   glTexCoord2f( 1.0, 1.0);
   glVertex3fv( vertices[1]);

   glTexCoord2f( 1.0, 0.0);
   glVertex3fv( vertices[2]);

   glTexCoord2f( 0.0, 0.0);
   glVertex3fv( vertices[3]);

   glEnd();
}

static void   draw_scene( int width, int height)
{
   void     *texture;
   size_t   i, n;
   GLuint   handle;
   int      index;
   float    *bitmap;

   glViewport( 0, 0, width, height);
   glClearColor( 0.33f, 0.33f, 0.33f, 1.0f);
   glClear(  GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
   glEnable( GL_BLEND);
   glBlendFunc( GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

   n = strlen( buf);
   for( i = 0; i < n; i++)
   {
      index = 10; // space
      if( buf[ i] >= '0' && buf[ i] <= '9')
         index = buf[ i] - '0';

      handle = textures[ index];
      if( ! handle)
      {
         bitmap           = index == 10 ? (float *) space : digits[ index];
         flipV( bitmap);
         handle           = init_texture( bitmap);
         textures[ index] = handle;
      }

      draw_texture( i, handle);
   }
}


static void   print_counter( uintptr_t counter)
{
   char     tmp[ 64];
   size_t   i, n;

   sprintf( tmp, "%tu", counter);
   n = strlen( tmp);
   for( i = 0; i < (10 - n + 1) / 2; i++)
      buf[ i] = ' ';
   strcpy( &buf[ i], tmp);
}

static int   needsRedraw = 1;

static void   windowRefreshCallback( GLFWwindow* os_window)
{
   fprintf( stderr, "%.6f %s\n", glfwGetTime(), __PRETTY_FUNCTION__);
   print_counter( ++counter);
   needsRedraw = 1;
}


static void   framebufferSizeCallback( GLFWwindow* os_window, int width, int height)
{
   fprintf( stderr, "%.6f %s\n", glfwGetTime(), __PRETTY_FUNCTION__);
}
static void   windowSizeCallback( GLFWwindow* os_window, int width, int height)
{
   fprintf( stderr, "%.6f %s\n", glfwGetTime(), __PRETTY_FUNCTION__);
}
static void   windowFocusCallback( GLFWwindow* os_window, int whatever)
{
   fprintf( stderr, "%.6f %s\n", glfwGetTime(), __PRETTY_FUNCTION__);
}


static void   error_callback( int error, const char* description)
{
    fprintf( stderr, "Error %d: %s\n", error, description);
}

static void  draw( GLFWwindow *window)
{
   int   width, height;

   fprintf( stderr, "%.6f %s\n", glfwGetTime(), __PRETTY_FUNCTION__);
   glfwGetFramebufferSize( window, &width, &height);
   draw_scene( width, height);
   glfwSwapBuffers( window);
}


int main(int argc, char* argv[])
{
    GLFWwindow  *window;

    glfwSetErrorCallback( error_callback);

    if( ! glfwInit())
        exit( EXIT_FAILURE);

   glfwWindowHint( GLFW_RESIZABLE, GLFW_TRUE);
   glfwWindowHint( GLFW_DECORATED, GLFW_TRUE);

    window = glfwCreateWindow( 500, 500, "Demo", NULL, NULL);
    if( ! window)
    {
        glfwTerminate();
        exit( EXIT_FAILURE);
    }

    glfwSetFramebufferSizeCallback( window, framebufferSizeCallback);
    glfwSetWindowRefreshCallback( window, windowRefreshCallback);
    glfwSetWindowSizeCallback( window, windowSizeCallback);
    glfwSetWindowFocusCallback( window, windowFocusCallback);

    glfwMakeContextCurrent( window);

    fprintf( stderr, "Vendor           : %s\n", glGetString( GL_VENDOR));
    fprintf( stderr, "Version          : %s\n", glGetString( GL_VERSION));
    fprintf( stderr, "Renderer         : %s\n", glGetString( GL_RENDERER));
    fprintf( stderr, "Shading Language : %s\n", glGetString( GL_SHADING_LANGUAGE_VERSION));
    fprintf( stderr, "Extensions       : %s\n", glGetString( GL_EXTENSIONS));

    glfwSwapInterval( 0);

    while( ! glfwWindowShouldClose( window))
    {
      if( needsRedraw)
      {
         draw( window);
         needsRedraw = 0;
      }
      glfwWaitEvents();
    }

    glfwTerminate();
    exit( EXIT_SUCCESS);
}



#if 0
static int   frameCallback( GLFWOSWindow *window)
{
   struct MulleIntegerSize   framebufferSize;

   framebufferSize = [window os_framebufferSize];
   draw_scene( framebufferSize.width, framebufferSize.height);
   return( 0);
}


static void   windowRefreshCallback( GLFWwindow* os_window)
{
   GLFWOSWindow   *self;

   self = glfwGetWindowUserPointer( os_window);

   print_counter( ++counter);
   [self setNeedsRefresh];
   [UIEvent sendEmptyEvent];
}


int   main( int argc, char *argv[])
{
   UIApplication         *app;
   id <UIScreen>         screen;
   NSUInteger            i;
   struct UIScreenInfo   info;
   GLFWOSWindow          *window;

   print_counter( 0);

   app = [UIApplication sharedInstance];

   @autoreleasepool
   {
      window = [[[GLFWOSWindow alloc] initWithFrame:CGRectMake( 0.0, 0.0, 500.0, 500.0)
                                    titleUTF8String:"Demo"
                                          styleMask:UIWindowStyleResizable // UIWindowOpenGLDeprecated
                                      graphicsHints:0] autorelease];
      assert( window);
      [window setFrameRate:UIWindowFrameRateAsync];
      [window setFrameCallback:frameCallback];
      glfwSetWindowRefreshCallback( [window os_window], windowRefreshCallback);

      [app addWindow:window];
   }
   return( [app run]);
}

#endif

//
//                           ,╓≤æKª╨╙╙▓█D"╙╙╙*╨¥W▄╓,
//                      ╓▄ª╙└╧▓        █           ⁿ▓▓ª╦w
//                  ╓#╜^*█⌐   `╕       █           ╓▌    `╙%w
//               ╓ΦΓ      █    ╙⌐     ,█,,,Φ      ╓▌         ╙¥▄
//            ,▄▀ █▄       █µ,╓╝,╓≤╗≡≡ª╨╨╨¥≡∞╗w╓,ª█,  ,       ]▄▀V,
//          ,Φ└   ║"▀▄     ,▄▀╨"                 "╙¥▓▓       ▄▀  º▄¥,
//        ,#▌Φ▓▄╓  Φ `█Q▄M╙                           ╙¥▄ ,▄▀ ╙▄⌐`  `Φ
//       ▄▀   `V,"▀▀¼╓╩└                                 ╙¥▓╗ ,       ╙▄
//      Φ       `¥═▄▀                            ╒          ▀▄          ▓
//    .▓         ╓▓]V▄H       ▓                 ,Å            ▀,         ▀
//    █      ,-ª▓╛  `██▀½      "▄  ,╓╓╓╓;╓▄▄▄▄╗▄█,             ╙▄         ▀
//   █  `██▄   ▓. - Φ█═.~     ,≤█▄▀-      `   █└"▀▀▀▀▄╓╓╓╓       ▌    ██▄, █
//  ║⌐  " ▀   ▓╨⌐   }▀`      ,█  `           █      .█▀▄▄███▄     ▌  ` ▀    ▌
//  ▌        ▐M A   '┴      ▌                ▀        ╙█▌████▌    ╙▄        ║⌐
// ║⌐        █⌐'║▄ Γr2«    ║▀                 ▄▄▄      ╙▌▄███      █         ▌
// █]     ,▄▐H  ██████═ª  ╓` ▄█▀▀▀▀█▄        ████     ╓███` `╙╙║█  ▐H        █
// █ "% ,▄▀ ║░╠K█═╣███^   ╛╓█▀      ▐█         ,╓╓═ª╙└   █      ╙█▄▐▌▓######▌╫
// █║▄▄▄█▄▄▄║H:  "╙▀███▄╓▄,█▌╓▄,,▄∩  ██p$ΦΦ▀▀▀▀▀ΦΦΦR≡≥▄╓ ║▄       ╙j▌` ▄▀╙╗ `╫
// █"      ╙▐H-═M ▄███████¥█H "^╙    '█, ,«^``     `     ║▌        ▐M▄▀    "Φ█
// ║        !█▄▄████≤═^`╓█ █▌╓▀╦▄▀█   ╙█⌐               ╓█▌        ▓ `       █
//  ▌      ,▄██╫██ ▄█═╜" █▌▐█╣Hj⌐ █    █▌╙¥w,           ██▄       ╓▌        ▐M
//  ╢"▄▄#▀▀╙╟█Ü███▀`▀█  ║██J█▄▌jH █    ██    ╙▀W▄;    ,██  `╙w,   █▄     ,╓ █
//   █╙     ▐███▌▀█w ▀█ ╠██████j▌║█▌   ▀██▄       `╙▓██▀w,     ╙╗█'`"▀█▀╙"`║`
//   ╙▌     Φ████████▄██ ███████████    ═██▀W▄,   ╓█▀└         ╓▀ "    ╙▄ ╓▀
//    ╙▄     ╙▀███╙█▄▐██▄,╙▀█████▄▀▄▀▄   ,█M╗ ▀▄██▀╙""*ⁿ═─≈-,,▄▌,        ▄▀
//     `▌╙µ,▄Φ▀x███▄██████████▀V███▀╙└ ,▄#▌████▀`"*«,      .█▀▄▀▄,      ▄╛
//       ▀Ö█  ;▓████████▄▄█▀▄╙W "V▄██▀▀│▄███▀└ ▀╦     "*═╥▄▀ ║,  ║▀▄  ,▓
//        ╙W▀ '█████╨▀▀█████████   "▀▀████└      ╙▄   ,▄▀'   `▀▀╣H ▐▀▄▀
//          ╙▄  ▀▀Γ╓▌  ▄▀ⁿ`╙▀███      ██▌         ╓█R▀▄A█        ▀▀▄▀
//            ╙W,Φ╙  ║█        ▄╙╙ª%≡╦██≤≤╗╗≡≡╜▀▀   ╣▌   █╕     ,▄▀
//              `▀▄M█┘        ║▀▌   ╫"    *Φ▄  █       Φ` ▀▌, ▄M╙
//                 "▀╦,       M ╙▌  ▀       `█W▐▌       wæQ▄▀╙
//                     ╙▀W╥,╓╣   ╙█║        ╫M  █    ,╓▄╝╙`
//                          ╙╙▀%▄▄▄▌,≤▄_▄≡,▐▓▓▄▄#ª▀"`


#import "import.h"

#include <math.h>


//#define GLAD_GL_IMPLEMENTATION
//#include <glad/gl.h>
#define GLFW_INCLUDE_NONE
#include <GLFW/glfw3.h>


// GLFW_INCLUDE_... keep undefined for OpenGL3
// see: https://www.glfw.org/docs/latest/build_guide.html
#define GL_GLEXT_PROTOTYPES
#ifdef __APPLE__
# include <OpenGL/gl.h>
# include <OpenGL/glext.h>
#else
# include <GL/gl.h>
# include <GL/glext.h>
#endif



/*
 * This demo is an original GLUT demo converted to MulleUICore with
 * minimal changes. There is no immediate advantage got by doing so, but it
 * is a first step.
 *
 * The major changes are mostly event related. And of course the whole
 * window setup is done with MulleUI.
 *
 * This demo does not use UIWindow but GLFWOSWindow, because we do not want
 * to have nanovg involved. This means that everything like CAAnimation,
 * CALayer, UIView is not available. Even CGContext is not available, since
 * it's tied to nanovg. Also you can not have retained/buffered output.
 *
 */

/**
 * An application that displays a rotating cube with a
 * texture mapped image.
 *
 * @author  Prof. David Bernstein, James Madison University
 */

static GLuint    textureName;
static GLfloat   angle[] = {0.0, 0.0, 0.0};
static GLint     axis = 2;
static GLint     delay = 20;


/**

 * OpenGL Initialization.

 */
#define R  { 0xFF, 0x00, 0x00, 0xFF }
#define G  { 0x00, 0xFF, 0x00, 0xFF }
#define B  { 0x00, 0x00, 0xFF, 0xFF }
#define Y  { 0xFF, 0xFF, 0x00, 0xFF }

static char   texture[ 8 * 8][ 4] =
{
   R, R, R, R,   Y, Y, Y, Y,
   R, R, R, R,   Y, Y, Y, Y,
   R, R, Y, G,   B, R, Y, Y,
   R, R, B, R,   Y, G, Y, Y,

   B, B, R, B,   G, B, G, G,
   B, B, Y, G,   R, Y, G, G,
   B, B, B, B,   G, G, G, G,
   B, B, B, B,   G, G, G, G
};


// this hasn't changed
static void   init_texture()
{
   glClearColor( 0.0, 0.0, 0.0, 0.0);

   glGenTextures( 1, &textureName);
   glBindTexture( GL_TEXTURE_2D, textureName);

   glTexParameterf( GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
   glTexParameterf( GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
   glTexParameterf( GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
   glTexParameterf( GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);

   glTexEnvf( GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_REPLACE);

   glTexImage2D( GL_TEXTURE_2D, 0,                 // One resolution (i.e. level 0)
                                GL_RGBA,
                                8,                 // Width
                                8,                 // Height
                                0,                 // Border width
                                GL_RGBA,           // Format
                                GL_UNSIGNED_BYTE,  // Data type of the texels
                                texture);

   glEnable( GL_TEXTURE_2D);
}


//
// pretty much unchanged.
//
static UIWindowDisplayBits   display( id <UIOSWindow> window_in)
{
   GLFWOSWindow  *window = MULLE_OBJC_CLASS_CAST( GLFWOSWindow, window_in);

   static GLint faces[][4] = {{4,5,6,7},
                              {1,2,6,5},
                              {0,1,5,4},
                              {0,3,2,1},
                              {0,4,7,3},
                              {2,3,7,6}
                             };

// Vertices
   static GLfloat vertices[][3] = {{-1.0,-1.0,-1.0},
                                   { 1.0,-1.0,-1.0},
                                   { 1.0, 1.0,-1.0},
                                   {-1.0, 1.0,-1.0},
                                   {-1.0,-1.0, 1.0},
                                   { 1.0,-1.0, 1.0},
                                   { 1.0, 1.0, 1.0},
                                   {-1.0, 1.0, 1.0}};

   glClear( GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
   glBindTexture( GL_TEXTURE_2D, textureName);

   // Draw the cube

   for(int f = 0; f < 6; f++)
   {
      glBegin(GL_POLYGON);

      int v;

      v = faces[f][0];

      glTexCoord2f(0.0, 0.0);  // Map to the bottom left texel
      glVertex3fv(vertices[v]);

      v = faces[f][1];

      glTexCoord2f(0.0, 1.0);  // Map to the bottom right texel
      glVertex3fv(vertices[v]);

      v = faces[f][2];

      glTexCoord2f(1.0, 1.0);  // Map to the top right texel
      glVertex3fv(vertices[v]);

      v = faces[f][3];

      glTexCoord2f(1.0, 0.0);  // Map to the top left texel
      glVertex3fv(vertices[v]);

      glEnd();
   }
   glFlush();

   return( 1);
}


// this hasn't changed
static void   reshape( int width, int height)
{
   GLfloat aspect;

   glViewport( 0, 0, (GLsizei) width, (GLsizei) height);
   glMatrixMode(GL_PROJECTION);
   glLoadIdentity();

   if( width <= height)
   {
      aspect = (GLfloat) height / (GLfloat) width;
      glOrtho(-2.0, 2.0, -2.0 * aspect, 2.0 * aspect, -10.0, 10.0);
   }
   else
   {
      aspect = (GLfloat) width / (GLfloat) height;
      glOrtho(-2.0 * aspect, 2.0 * aspect, -2.0, 2.0, -10.0, 10.0);
   }
}


// this hasn't changed
void   update()
{
   angle[axis] += 2.0;
   if (angle[axis] > 360.0)
      angle[axis] -= 360.0;

   glMatrixMode(GL_MODELVIEW);
   glLoadIdentity();

   glRotatef(angle[0], 1.0, 0.0, 0.0);
   glRotatef(angle[1], 0.0, 1.0, 0.0);
   glRotatef(angle[2], 0.0, 0.0, 1.0);
}

// this loses some functions, also the signature is different
static void   timerCallback( NSTimer *timer, id userInfo)
{
   update();
//
//  glutPostRedisplay();
//  glutTimerFunc(delay, timer, 0);
}

// This is new.
static void   receiveWindowEvents( GLFWOSWindow *window, UIWindowEvent *event)
{
   CGPixelSize   size;

   switch( [event windowEventType])
   {
   case UIWindowEventTypeClose             :
      return;

   case UIWindowEventTypeRefresh           :
   case UIWindowEventTypeMove              :
      break;

   case UIWindowEventTypeResize            :
   case UIWindowEventTypeFramebufferResize :
      size = [window os_framebufferSize];
      reshape( size.width, size.height);
   }

   [window displayFrameIfNeeded:mulle_absolutetime_now()];
}


int   main( int argc, char *argv[])
{
   GLFWOSWindow    *window;
   UIApplication   *app;
   NSTimer         *timer;

   app = [UIApplication sharedInstance];
//   glutInit( &argc, argv);
   {
      //
      // we are using an GLFWOSWindow here because we just want to do OpenGL
      //
      window = [[[GLFWOSWindow alloc] initWithFrame:CGRectMake( 0.0, 0.0, 500.0, 500.0)
                                    titleUTF8String:"Demo"
                                          styleMask:UIWindowStyleResizable] autorelease];

//    glutInitDisplayMode(GLUT_DOUBLE | GLUT_RGB | GLUT_DEPTH);
//    glutInitWindowSize(500, 500);
//    glutCreateWindow("Demo");
      assert( window);
      [app addWindow:window];

      [window setWindowEventsCallback:receiveWindowEvents];
//    glutReshapeFunc(reshape);
      timer = [[[NSTimer alloc] mulleInitWithRelativeTimeInterval:0.0
                                                   repeatInterval:delay/1000.0
                                                         callback:timerCallback
                                                         userInfo:nil] autorelease];
      [app addTimer:timer
   forTimerReceiver:app];   

//    glutTimerFunc(delay, timer, 0);

      [window os_activateGraphicsContext];
      {
         init_texture();
      }
      [window os_deactivateGraphicsContext];

      [window setFrameCallback:display];
//    glutDisplayFunc(display);

      [window setFrameRateHz:100.0];
//    glutMainLoop();
   }
   return( [app runApp]);
}



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


#define _GNU_SOURCE
#define MULLE_GLFW_EXPOSE_OPEN_GL
#define GLFW_INCLUDE_GLEXT

#import "import.h"

#include <string.h>
#include <stdio.h>
#include <ctype.h>

static int   log_enabled;

/*
 * This demo just creates a window and nothing else.
 * The frameRate by default should be async. That means the windows ought
 * to be quiet, unless events come in. You can pass options on the commandline
 * to enjoy "synced" and "async" as well.
 *
 * The only interesting thing happening is the output of the fprintf.
 */
static UIWindowDisplayBits   frameCallback( id <UIOSWindow> window_in)
{
   GLFWOSWindow  *window = MULLE_OBJC_CLASS_CAST( GLFWOSWindow, window_in);
   CGPixelSize   framebufferSize;

   framebufferSize = [window os_framebufferSize];

   if( log_enabled)
      MulleUICLog( "%#@ %d %d", window, framebufferSize.width, framebufferSize.height);

   glViewport( 0, 0, framebufferSize.width, framebufferSize.height);
   glClearColor( 0.33f, 0.66f, 0.33f, 0.0f);
   glClear( GL_COLOR_BUFFER_BIT);
   return( 0);
}


static void   windowMoveCallback( GLFWwindow* window, int xpos, int ypos)
{
   GLFWOSWindow   *self;

   self = glfwGetWindowUserPointer( window);
   if( log_enabled)
      MulleUICLog( "%#@ %d %d", self, xpos, ypos);
}


static void   windowResizeCallback( GLFWwindow* window, int width, int height)
{
   GLFWOSWindow   *self;

   self = glfwGetWindowUserPointer( window);
   if( log_enabled)
      MulleUICLog( "%#@ %d %d", self, width, height);

   // if we don't do this in wayland, then the resize doesn't happen
   [self setNeedsRefresh];
}


static void   usage( char *argv0)
{
   char   *s;

   s = strrchr( argv0, '/');
   s = s ? s + 1 : argv0;

   mulle_fprintf( stderr, "%s [framerate]\n"
"\n"
"Framerate:\n"
"   --synced            : redraw synced to monitor\n"
"   --async             : redraw on events (default)\n"
"   --unsynced          : redraw in busy loop\n"
"   --styleMask <mask>  : styleMask to use for window\n"
   , s);
      exit( 1);
}


int   main( int argc, char *argv[])
{
   mulle_relativetime_t  frameRate;
   UIApplication         *app;
   id <UIScreen>         screen;
   NSUInteger            i;
   struct UIScreenInfo   info;
   GLFWOSWindow          *window;
   NSUInteger            styleMask;

   app       = [UIApplication sharedInstance];

   frameRate = UIWindowFrameRateAsync;
   styleMask = 0;

   for( i = 1; i < argc; i++)
   {
      if( ! strcmp( argv[ i], "--log"))
      {
         log_enabled = 1;
         continue;
      }
      if( ! strcmp( argv[ i], "--async"))
      {
         frameRate = UIWindowFrameRateAsync;
         continue;
      }
      if( ! strcmp( argv[ i], "--synced"))
      {
         frameRate = UIWindowFrameRateSynced;
         continue;
      }
      if( ! strcmp( argv[ i], "--unsynced"))
      {
         frameRate = UIWindowFrameRateUnsynced;
         continue;
      }
      if( ! strcmp( argv[ i], "--styleMask"))
      {
         if( ++i >= argc)
            usage( argv[ 0]);

         styleMask = UIWindowStyleParseUTF8String( argv[ i]);
         fprintf( stderr, "parsed: %s\n", UIWindowStyleUTF8String( styleMask));
         continue;
      }

      if( isdigit( argv[ i][ 0]))
      {
         frameRate = atof( argv[ i]);
         ++i;
         break;
      }

      mulle_fprintf( stderr, "error: unknown \"%s\"\n", argv[ i]);
      usage( argv[ 0]);
   }

   if( i != argc)
      usage( argv[ 0]);

   for( i = 0; screen = [app screenAtIndex:i]; i++)
   {
      [screen getScreenInfo:&info];

      mulle_printf( "#%td\n", i);
      mulle_printf( "\tname         : \"%s\"\n",          [screen nameUTF8String]);
      mulle_printf( "\trefreshRate  : %.6fs (%.3f Hz)\n", info.refreshRate, info.refreshRate > 0.0 ? 1.0 / info.refreshRate : 0.0);
      mulle_printf( "\tframe        : %.3f %.3f %.3f %.3f\n",
                                                    info.frame.origin.x,
                                                    info.frame.origin.y,
                                                    info.frame.size.width,
                                                    info.frame.size.height);
      mulle_printf( "\tcanvas       : %.3f %.3f %.3f %.3f\n",
                                                    info.canvas.origin.x,
                                                    info.canvas.origin.y,
                                                    info.canvas.size.width,
                                                    info.canvas.size.height);
      mulle_printf( "\tcontentScale : %.3f %.3f\n",       info.contentScale.dx, info.contentScale.dy);
      mulle_printf( "\tphysicalSize : %.3f m %.3f m\n",   info.physicalSize.width, info.physicalSize.height);
      mulle_printf( "\tdpi          : %.3f\n",            info.dpi);
      mulle_printf( "\tred          : %d bit\n",          info.colorBits[ 0]);
      mulle_printf( "\tgreen        : %d bit\n",          info.colorBits[ 1]);
      mulle_printf( "\tblue         : %d bit\n",          info.colorBits[ 2]);
      mulle_printf( "\talpha        : %d bit\n",          info.colorBits[ 3]);
   }

   window = [[[GLFWOSWindow alloc] initWithFrame:CGRectMake( 0.0, 0.0, 500.0, 500.0)
                                 titleUTF8String:"Demo"
                                       styleMask:styleMask // UIWindowOpenGLDeprecated
                                   graphicsHints:GLFW_DEFAULT_CONTEXT] autorelease];
   assert( window);
   [window setFrameRate:frameRate];
   [window setFrameCallback:frameCallback];
   glfwSetWindowSizeCallback( [window os_window], windowResizeCallback);
   glfwSetWindowPosCallback( [window os_window], windowMoveCallback);

   return( [app runWindow:window]);
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


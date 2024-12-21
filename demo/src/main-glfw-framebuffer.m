#define _GNU_SOURCE
#define MULLE_GLFW_EXPOSE_OPEN_GL
#define GLFW_INCLUDE_GLEXT

#import "import.h"

#include <string.h>
#include <stdio.h>


/*
 * This demo just creates a window and nothing else.
 * The frameRate by default should be async. That means the windows ought
 * to be quiet, unless events come in. You can pass options on the commandline
 * to enjoy "synced" and "async" as well.
 *
 * The only interesting thing happening is the output of the fprintf.
 */
static float   colors[ 16][ 3] =
{
   { 0.33f, 0.33f, 0.33f  },
   { 0.33f, 0.33f, 0.00f  },
   { 0.33f, 0.00f, 0.33f  },
   { 0.00f, 0.33f, 0.33f  },

   { 0.66f, 0.33f, 0.33f  },
   { 0.33f, 0.66f, 0.33f  },
   { 0.33f, 0.33f, 0.66f  },
   { 0.66f, 0.66f, 0.33f  },

   { 0.33f, 0.66f, 0.66f  },
   { 0.66f, 0.33f, 0.66f  },
   { 0.00f, 0.66f, 0.33f  },
   { 0.33f, 0.66f, 0.00f  },

   { 0.66f, 0.00f, 0.33f  },
   { 0.66f, 0.33f, 0.00f  },
   { 0.66f, 0.00f, 0.66f  },
   { 0.66f, 0.66f, 0.00f  }
};


static int   frameCallback( GLFWOSWindow *window)
{
   CGPixelSize   framebufferSize;
   static int                i;

   framebufferSize = [window os_framebufferSize];

   glViewport( 0, 0, framebufferSize.width, framebufferSize.height);
//   glColorMask (GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
   glClearColor( colors[ i][ 0], colors[ i][ 1], colors[ i][ 2], 1.0f);
   i = (i + 1) & 0xF;
   glClear( GL_COLOR_BUFFER_BIT);
//   glFlush();
//   [window os_swapBuffers];
   MulleUICLog( "%#@ @%.4f\n", window, mulle_absolutetime_now());
   return( 0);
}


static void   usage( char *argv0)
{
   char   *s;

   s = strrchr( argv0, '/');
   s = s ? s + 1 : argv0;

   fprintf( stderr, "%s [options]\n"
"\n"
"Options:\n"
"   --single   : single buffered\n"
"   --double   : double buffered (default)\n"
"   --fast     : set frameRate to 60 Hz\n"
"   --unsynced : unsynced"
   , s);
      exit( 1);
}


int   main( int argc, char *argv[])
{
   mulle_relativetime_t  frameRate;
   NSUInteger            i;
   GLFWOSWindow          *window;
   NSUInteger            styleMask;

   // get glfw started
   [UIApplication os_initialize];

   styleMask = GLFWOSWindowStyleMaskDefault | UIWindowStyleResizable;
   frameRate = 0.5;

   for( i = 1; i < argc; i++)
   {
      if( ! strcmp( argv[ i], "--single"))
      {
         styleMask |= UIWindowStyleSingleBuffer;
         continue;
      }

      if( ! strcmp( argv[ i], "--double"))
      {
         styleMask &= ~UIWindowStyleSingleBuffer;
         continue;
      }

      if( ! strcmp( argv[ i], "--fast"))
      {
         frameRate = 1 / 60.0;
         continue;
      }

      if( ! strcmp( argv[ i], "--unsynced"))
      {
         frameRate = UIWindowFrameRateUnsynced;
         continue;
      }

      usage( argv[ 0]);
   }

   if( i != argc)
      usage( argv[ 0]);

   window = [[[GLFWOSWindow alloc] initWithFrame:CGRectMake( 0.0, 0.0, 500.0, 500.0)
                                 titleUTF8String:"Demo"
                                       styleMask:styleMask // UIWindowOpenGLDeprecated
                                   graphicsHints:0] autorelease];
   assert( window);
   [window setFrameRate:frameRate];
   [window setFrameCallback:frameCallback];

   return( UIApplicationRunWindow( window));
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


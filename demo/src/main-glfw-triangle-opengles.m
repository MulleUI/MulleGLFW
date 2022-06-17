//========================================================================
// OpenGL ES 2.0 triangle example
// Copyright (c) Camilla Löwy <elmindreda@glfw.org>
//
// This software is provided 'as-is', without any express or implied
// warranty. In no event will the authors be held liable for any damages
// arising from the use of this software.
//
// Permission is granted to anyone to use this software for any purpose,
// including commercial applications, and to alter it and redistribute it
// freely, subject to the following restrictions:
//
// 1. The origin of this software must not be misrepresented; you must not
//    claim that you wrote the original software. If you use this software
//    in a product, an acknowledgment in the product documentation would
//    be appreciated but is not required.
//
// 2. Altered source versions must be plainly marked as such, and must not
//    be misrepresented as being the original software.
//
// 3. This notice may not be removed or altered from any source
//    distribution.
//
//========================================================================
#define _GNU_SOURCE

#import "import.h"

//#define GLAD_GLES2_IMPLEMENTATION
//#include <glad/gles2.h>
#define GLFW_INCLUDE_NONE
#include <GLFW/glfw3.h>

#include "linmath.h"


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

#include <stdlib.h>
#include <stddef.h>
#include <stdio.h>

typedef struct Vertex
{
    vec2 pos;
    vec3 col;
} Vertex;

static const Vertex vertices[3] =
{
    { { -0.6f, -0.4f }, { 1.f, 0.f, 0.f } },
    { {  0.6f, -0.4f }, { 0.f, 1.f, 0.f } },
    { {   0.f,  0.6f }, { 0.f, 0.f, 1.f } }
};

#ifdef USE_GL

static const char* vertex_shader_text =
"#version 330\n"
"uniform mat4 MVP;\n"
"in vec3 vCol;\n"
"in vec2 vPos;\n"
"out vec3 color;\n"
"void main()\n"
"{\n"
"    gl_Position = MVP * vec4(vPos, 0.0, 1.0);\n"
"    color = vCol;\n"
"}\n";

static const char* fragment_shader_text =
"#version 330\n"
"in vec3 color;\n"
"out vec4 fragment;\n"
"void main()\n"
"{\n"
"    fragment = vec4(color, 1.0);\n"
"}\n";

#else

static const char* vertex_shader_text =
"#version 100\n"
"precision mediump float;\n"
"uniform mat4 MVP;\n"
"attribute vec3 vCol;\n"
"attribute vec2 vPos;\n"
"varying vec3 color;\n"
"void main()\n"
"{\n"
"    gl_Position = MVP * vec4(vPos, 0.0, 1.0);\n"
"    color = vCol;\n"
"}\n";

static const char* fragment_shader_text =
"#version 100\n"
"precision mediump float;\n"
"varying vec3 color;\n"
"void main()\n"
"{\n"
"    gl_FragColor = vec4(color, 1.0);\n"
"}\n";

#endif


static void error_callback(int error, const char* description)
{
    fprintf(stderr, "GLFW Error: %s\n", description);
}

static void key_callback(GLFWwindow* window, int key, int scancode, int action, int mods)
{
    if (key == GLFW_KEY_ESCAPE && action == GLFW_PRESS)
        glfwSetWindowShouldClose(window, GLFW_TRUE);
}

GLuint program;
GLint  mvp_location;
GLuint vertex_array;

static void   init_scene( void)
{
    GLuint vertex_buffer;
    glGenBuffers(1, &vertex_buffer);
    glBindBuffer(GL_ARRAY_BUFFER, vertex_buffer);
    glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);

    const GLuint vertex_shader = glCreateShader(GL_VERTEX_SHADER);
    glShaderSource(vertex_shader, 1, &vertex_shader_text, NULL);
    glCompileShader(vertex_shader);

    const GLuint fragment_shader = glCreateShader(GL_FRAGMENT_SHADER);
    glShaderSource(fragment_shader, 1, &fragment_shader_text, NULL);
    glCompileShader(fragment_shader);

    program = glCreateProgram();
    glAttachShader(program, vertex_shader);
    glAttachShader(program, fragment_shader);
    glLinkProgram(program);

    mvp_location = glGetUniformLocation(program, "MVP");

    const GLint vpos_location = glGetAttribLocation(program, "vPos");
    const GLint vcol_location = glGetAttribLocation(program, "vCol");

    glGenVertexArrays(1, &vertex_array);
    glBindVertexArray(vertex_array);

    glEnableVertexAttribArray(vpos_location);
    glEnableVertexAttribArray(vcol_location);
    glVertexAttribPointer(vpos_location, 2, GL_FLOAT, GL_FALSE,
                          sizeof(Vertex), (void*) offsetof(Vertex, pos));
    glVertexAttribPointer(vcol_location, 3, GL_FLOAT, GL_FALSE,
                          sizeof(Vertex), (void*) offsetof(Vertex, col));
}


static void   display( GLFWOSWindow *gWindow)
{
   struct CGBitmapSize    framebufferSize;
   float                  ratio;
   mulle_absolutetime_t   now;

//   printf( "%s %g\n", __FUNCTION__, now);
//   fflush( stdout);

   framebufferSize = [gWindow os_framebufferSize];
   ratio           = framebufferSize.width / (float) framebufferSize.height;

   glViewport(0, 0, framebufferSize.width, framebufferSize.height);
   glClear(GL_COLOR_BUFFER_BIT);

   mat4x4 m, p, mvp;
   mat4x4_identity(m);

   //
   // fix float overflow
   //
   now = mulle_absolutetime_now();
   mat4x4_rotate_Z(m, m, -(float) fmod( now, M_PI * 2.0));
   mat4x4_ortho(p, -ratio , ratio, -1.f, 1.f, 1.f, -1.f);
   mat4x4_mul(mvp, p, m);

   glUseProgram(program);
   glUniformMatrix4fv(mvp_location, 1, GL_FALSE, (const GLfloat*) &mvp);
   glBindVertexArray(vertex_array);
   glDrawArrays(GL_TRIANGLES, 0, 3);

// not needed
   glFlush();
}


static void   usage( char *argv0)
{
   char   *s;

   s = strrchr( argv0, '/');
   s = s ? s + 1 : argv0;

   fprintf( stderr, "%s [api] [options]\n"
"\n"
"Api:\n"
#ifdef USE_GL
"   --gl3        :\n"
"   --gl3_2      :\n"
#else
"   --gles2      :\n"
"   --gles3      :\n"
#endif
"\n"
"Options:\n"
"   --any        :\n"
"   --core       :\n"
"   --compat     :\n"
"\n"
"   --no-forward :\n"
"   --forward    :\n"
"\n"
"   --native     :\n"
"   --egl        :\n"
"   --mesa       :\n", s);
      exit( 1);
}

int   main( int argc, char *argv[])
{
   UIApplication    *app;
   GLFWOSWindow     *gWindow;
   GLFWwindow       *window;
   NSUInteger       styleMask;
   int              i;
   int              api;
   int              vendor;
   int              profile;
   int              hints;

#ifdef USE_GL
   hints   = GLFW_GL3_2_CONTEXT;
#else
   hints   = GLFW_GLES2_CONTEXT;
#endif
   api     = -1;
   vendor  = -1;
   profile = -1;

   for( i = 1; i < argc; i++)
   {
      if( ! strcmp( argv[ i], "--gl3"))
      {
         hints = GLFW_GL3_CONTEXT;
         continue;
      }
      if( ! strcmp( argv[ i], "--gl3_2"))
      {
         hints = GLFW_GL3_2_CONTEXT;
         continue;
      }
      if( ! strcmp( argv[ i], "--gles2"))
      {
         hints = GLFW_GLES2_CONTEXT;
         continue;
      }
      if( ! strcmp( argv[ i], "--gles3"))
      {
         hints = GLFW_GLES3_CONTEXT;
         continue;
      }

      // (0=any, 1=core, 2=compat)
      if( ! strcmp( argv[ i], "--any"))
      {
         hints = GLFWGraphicsHintsBySettingProfile( hints, 0);
         continue;
      }
      if( ! strcmp( argv[ i], "--core"))
      {
         hints = GLFWGraphicsHintsBySettingProfile( hints, 1);
         continue;
      }
      if( ! strcmp( argv[ i], "--compat"))
      {
         hints = GLFWGraphicsHintsBySettingProfile( hints, 2);
         continue;
      }

      // forward : GLFW_OPENGL_FORWARD_COMPAT   (0=NO, 1=YES)
      if( ! strcmp( argv[ i], "--no-forward"))
      {
         hints = GLFWGraphicsHintsBySettingForward( hints, 0);
         continue;
      }
      if( ! strcmp( argv[ i], "--forward"))
      {
         hints = GLFWGraphicsHintsBySettingForward( hints, 1);
         continue;
      }

      // lib     : GLFW_CONTEXT_CREATION_API    (0=native,1=egl,2=mesa)
      if( ! strcmp( argv[ i], "--native"))
      {
         hints = GLFWGraphicsHintsBySettingAPILibrary( hints, 0);
         continue;
      }
      if( ! strcmp( argv[ i], "--egl"))
      {
         hints = GLFWGraphicsHintsBySettingAPILibrary( hints, 1);
         continue;
      }
      if( ! strcmp( argv[ i], "--mesa"))
      {
         hints = GLFWGraphicsHintsBySettingAPILibrary( hints, 2);
         continue;
      }

      usage( argv[ 0]);
   }

   if( i != argc)
      usage( argv[ 0]);

   fprintf( stderr, "hints : 0x%x\n", hints);

   app = [UIApplication sharedInstance];
   @autoreleasepool
   {
      /*
       * It's tricky to get the flags right, so that macOS doesn't complain.
       * UIWindowOpenGLCoreProfile|UIWindowOpenGLForward is needed.
       * Which has GL 4.1.0 core forward (native) or GL2 for deprecated.
       */
      styleMask = UIWindowStyleResizable
                  ;

      if( argc == 1)
        styleMask |= UIWindowOpenGLCoreProfile
                  |  UIWindowOpenGLForward
                  ;

      gWindow = [GLFWOSWindow windowWithFrame:CGRectMake( 0, 0, 640, 480)
                              titleUTF8String:"Demo"
                                    styleMask:styleMask
                                graphicsHints:hints];

      fprintf( stdout, "%s\n", [gWindow os_contextInfoUTF8String]);
      fflush( stdout);

      [app addWindow:gWindow];

      window = [gWindow os_window];

      glfwSetKeyCallback(window, key_callback);

      [gWindow os_activateGraphicsContext];
      {
        [gWindow os_setSwapInterval:1];

        init_scene();
      }
      [gWindow os_deactivateGraphicsContext];

      [gWindow setFrameCallback:display];

      // as we have set os_setSwapInterval to 1, we are tied to the sync
      // so the Hz here don't really matter.
      [gWindow setFrameRate: 1 / 1000.0];
   }
   return( [app run]);
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


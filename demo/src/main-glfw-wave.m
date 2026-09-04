/*****************************************************************************
 * Wave Simulation in OpenGL
 * (C) 2002 Jakob Thomsen
 * http://home.in.tum.de/~thomsen
 * Modified for GLFW by Sylvain Hellegouarch - sh@programmationworld.com
 * Modified for variable frame rate by Marcus Geelnard
 * 2003-Jan-31: Minor cleanups and speedups / MG
 * 2010-10-24: Formatting and cleanup - Camilla Löwy
 * 2021-11-24: Adapted to MulleGLFW
 *****************************************************************************/
#define _GNU_SOURCE

#import "import.h"

#if defined(_MSC_VER)
 // Make MS math.h define M_PI
 #define _USE_MATH_DEFINES
#endif

#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#ifndef M_PI
# define M_PI 3.14159265358979323846264338327950288
#endif

//#define GLAD_GL_IMPLEMENTATION
//#include <glad/gl.h>
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

// Maximum delta T to allow for differential calculations
#define MAX_DELTA_T 0.01

// Animation speed (10.0 looks good)
#define ANIMATION_SPEED 10.0

GLfloat alpha = 210.f, beta = -70.f;
GLfloat zoom = 2.f;

double cursorX;
double cursorY;

struct Vertex
{
    GLfloat x, y, z;
    GLfloat r, g, b;
};

#define GRIDW 50
#define GRIDH 50
#define VERTEXNUM (GRIDW*GRIDH)

#define QUADW (GRIDW - 1)
#define QUADH (GRIDH - 1)
#define QUADNUM (QUADW*QUADH)

GLuint quad[4 * QUADNUM];
struct Vertex vertex[VERTEXNUM];

/* The grid will look like this:
 *
 *      3   4   5
 *      *---*---*
 *      |   |   |
 *      | 0 | 1 |
 *      |   |   |
 *      *---*---*
 *      0   1   2
 */

//========================================================================
// Initialize grid geometry
//========================================================================

void init_vertices(void)
{
    int x, y, p;

    // Place the vertices in a grid
    for (y = 0;  y < GRIDH;  y++)
    {
        for (x = 0;  x < GRIDW;  x++)
        {
            p = y * GRIDW + x;

            vertex[p].x = (GLfloat) (x - GRIDW / 2) / (GLfloat) (GRIDW / 2);
            vertex[p].y = (GLfloat) (y - GRIDH / 2) / (GLfloat) (GRIDH / 2);
            vertex[p].z = 0;

            if ((x % 4 < 2) ^ (y % 4 < 2))
                vertex[p].r = 0.0;
            else
                vertex[p].r = 1.0;

            vertex[p].g = (GLfloat) y / (GLfloat) GRIDH;
            vertex[p].b = 1.f - ((GLfloat) x / (GLfloat) GRIDW + (GLfloat) y / (GLfloat) GRIDH) / 2.f;
        }
    }

    for (y = 0;  y < QUADH;  y++)
    {
        for (x = 0;  x < QUADW;  x++)
        {
            p = 4 * (y * QUADW + x);

            quad[p + 0] = y       * GRIDW + x;     // Some point
            quad[p + 1] = y       * GRIDW + x + 1; // Neighbor at the right side
            quad[p + 2] = (y + 1) * GRIDW + x + 1; // Upper right neighbor
            quad[p + 3] = (y + 1) * GRIDW + x;     // Upper neighbor
        }
    }
}

double dt;
double p[GRIDW][GRIDH];
double vx[GRIDW][GRIDH], vy[GRIDW][GRIDH];
double ax[GRIDW][GRIDH], ay[GRIDW][GRIDH];

//========================================================================
// Initialize grid
//========================================================================

void init_grid(void)
{
    int x, y;
    double dx, dy, d;

    for (y = 0; y < GRIDH;  y++)
    {
        for (x = 0; x < GRIDW;  x++)
        {
            dx = (double) (x - GRIDW / 2);
            dy = (double) (y - GRIDH / 2);
            d = sqrt(dx * dx + dy * dy);
            if (d < 0.1 * (double) (GRIDW / 2))
            {
                d = d * 10.0;
                p[x][y] = -cos(d * (M_PI / (double)(GRIDW * 4))) * 100.0;
            }
            else
                p[x][y] = 0.0;

            vx[x][y] = 0.0;
            vy[x][y] = 0.0;
        }
    }
}


//========================================================================
// Modify the height of each vertex according to the pressure
//========================================================================

void adjust_grid(void)
{
    int pos;
    int x, y;

    for (y = 0; y < GRIDH;  y++)
    {
        for (x = 0;  x < GRIDW;  x++)
        {
            pos = y * GRIDW + x;
            vertex[pos].z = (float) (p[x][y] * (1.0 / 50.0));
        }
    }
}


//========================================================================
// Calculate wave propagation
//========================================================================

void calc_grid(void)
{
    int x, y, x2, y2;
    double time_step = dt * ANIMATION_SPEED;

    // Compute accelerations
    for (x = 0;  x < GRIDW;  x++)
    {
        x2 = (x + 1) % GRIDW;
        for(y = 0; y < GRIDH; y++)
            ax[x][y] = p[x][y] - p[x2][y];
    }

    for (y = 0;  y < GRIDH;  y++)
    {
        y2 = (y + 1) % GRIDH;
        for(x = 0; x < GRIDW; x++)
            ay[x][y] = p[x][y] - p[x][y2];
    }

    // Compute speeds
    for (x = 0;  x < GRIDW;  x++)
    {
        for (y = 0;  y < GRIDH;  y++)
        {
            vx[x][y] = vx[x][y] + ax[x][y] * time_step;
            vy[x][y] = vy[x][y] + ay[x][y] * time_step;
        }
    }

    // Compute pressure
    for (x = 1;  x < GRIDW;  x++)
    {
        x2 = x - 1;
        for (y = 1;  y < GRIDH;  y++)
        {
            y2 = y - 1;
            p[x][y] = p[x][y] + (vx[x2][y] - vx[x][y] + vy[x][y2] - vy[x][y]) * time_step;
        }
    }
}



static void   timer_callback( NSTimer *timer, id userInfo)
{
   mulle_relativetime_t         dt_total;
   mulle_absolutetime_t         t;
   mulle_absolutetime_t         now;
   static mulle_absolutetime_t  t_old;

   now = mulle_absolutetime_now();
   if( ! t_old)
       t_old = now - 0.01;

   t        = now;
   dt_total = t - t_old;
   t_old    = t;

   // Safety - iterate if dt_total is too large
   while( dt_total > 0.f)
   {
      // printf( "%s %g\n", __FUNCTION__, dt_total);
      // fflush( stdout);

         // Select iteration time step
      dt = dt_total > MAX_DELTA_T ? MAX_DELTA_T : dt_total;
      dt_total -= dt;
       // Calculate wave propagation
      calc_grid();
   }
}



////========================================================================
//// Print errors
////========================================================================
//
//static void error_callback(int error, const char* description)
//{
//    fprintf(stderr, "Error: %s\n", description);
//}


//========================================================================
// Handle key strokes
//========================================================================

void key_callback(GLFWwindow* window, int key, int scancode, int action, int mods)
{
    if (action != GLFW_PRESS)
        return;

    switch (key)
    {
        case GLFW_KEY_ESCAPE:
            glfwSetWindowShouldClose(window, GLFW_TRUE);
            break;
        case GLFW_KEY_SPACE:
            init_grid();
            break;
        case GLFW_KEY_LEFT:
            alpha += 5;
            break;
        case GLFW_KEY_RIGHT:
            alpha -= 5;
            break;
        case GLFW_KEY_UP:
            beta -= 5;
            break;
        case GLFW_KEY_DOWN:
            beta += 5;
            break;
        case GLFW_KEY_PAGE_UP:
            zoom -= 0.25f;
            if (zoom < 0.f)
                zoom = 0.f;
            break;
        case GLFW_KEY_PAGE_DOWN:
            zoom += 0.25f;
            break;
        default:
            break;
    }
}


//========================================================================
// Callback function for mouse button events
//========================================================================

void mouse_button_callback(GLFWwindow* window, int button, int action, int mods)
{
    if (button != GLFW_MOUSE_BUTTON_LEFT)
        return;

    if (action == GLFW_PRESS)
    {
        glfwSetInputMode(window, GLFW_CURSOR, GLFW_CURSOR_DISABLED);
        glfwGetCursorPos(window, &cursorX, &cursorY);
    }
    else
        glfwSetInputMode(window, GLFW_CURSOR, GLFW_CURSOR_NORMAL);
}


//========================================================================
// Callback function for cursor motion events
//========================================================================

void cursor_position_callback(GLFWwindow* window, double x, double y)
{
    if (glfwGetInputMode(window, GLFW_CURSOR) == GLFW_CURSOR_DISABLED)
    {
        alpha += (GLfloat) (x - cursorX) / 10.f;
        beta += (GLfloat) (y - cursorY) / 10.f;

        cursorX = x;
        cursorY = y;
    }
}


//========================================================================
// Callback function for scroll events
//========================================================================

void scroll_callback(GLFWwindow* window, double x, double y)
{
    zoom += (float) y / 4.f;
    if (zoom < 0)
        zoom = 0;
}


//========================================================================
// Callback function for framebuffer resize events
//========================================================================

void framebuffer_size_callback(GLFWwindow* window, int width, int height)
{
    float ratio = 1.f;
    mat4x4 projection;

    if (height > 0)
        ratio = (float) width / (float) height;

    // Setup viewport
    glViewport(0, 0, width, height);

    // Change to the projection matrix and set our viewing volume
    glMatrixMode(GL_PROJECTION);
    mat4x4_perspective(projection,
                       60.f * (float) M_PI / 180.f,
                       ratio,
                       1.f, 1024.f);
    glLoadMatrixf((const GLfloat*) projection);
}


static void   receiveWindowEvents( GLFWOSWindow *window, UIWindowEvent *event)
{
   CGPixelSize   size;

   switch( [event eventType])
   {
   default  :
      break;

   case UIWindowEventTypeFramebufferResize :
      size = [(UIWindowFramebufferResizeEvent *) event size];
      [window os_activateGraphicsContext];
      framebuffer_size_callback( [window os_window], size.width, size.height);
      [window os_deactivateGraphicsContext];
   }
}


static void   receiveOtherEvents( GLFWOSWindow *gWindow, UIEvent *event)
{
   CGPoint   scrollOffset;
   CGPoint   position;

   switch( [event eventType])
   {
   case UIEventTypePresses :
      key_callback( [gWindow os_window],
                    [(UIKeyboardEvent *) event key],
                    [(UIKeyboardEvent *) event scanCode],
                    [(UIKeyboardEvent *) event action],
                    [(UIKeyboardEvent *) event keyModifiers]);
      break;

   case UIEventTypeMotion  :
      position = [(UIInputEvent *) event locationInWindow];
      cursor_position_callback( [gWindow os_window],
                                position.x,
                                position.y);
      break;

   case UIEventTypeTouches :
      mouse_button_callback( [gWindow os_window],
                             [(UIMouseButtonEvent *) event button],
                             [(UIMouseButtonEvent *) event action],
                             [(UIMouseButtonEvent *) event keyModifiers]);
      break;

   case UIEventTypeScroll  :
      scrollOffset = [(UIMouseScrollEvent *) event scrollOffset];
      scroll_callback( [gWindow os_window], scrollOffset.x, scrollOffset.y);
      break;

   default  : break;
   }
}


/*
 * Open GL part
 */

//========================================================================
// Draw scene
//========================================================================

void draw_scene()
{
    // Clear the color and depth buffers
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    // We don't want to modify the projection matrix
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();

    // Move back
    glTranslatef(0.0, 0.0, -zoom);
    // Rotate the view
    glRotatef(beta, 1.0, 0.0, 0.0);
    glRotatef(alpha, 0.0, 0.0, 1.0);

    glDrawElements(GL_QUADS, 4 * QUADNUM, GL_UNSIGNED_INT, quad);

// don't do this, GLFWOSWindow will do it
//    glfwSwapBuffers(window);
}


//========================================================================
// Initialize Miscellaneous OpenGL state
//========================================================================

void init_opengl(void)
{
    // Use Gouraud (smooth) shading
    glShadeModel(GL_SMOOTH);

    // Switch on the z-buffer
    glEnable(GL_DEPTH_TEST);

    glEnableClientState(GL_VERTEX_ARRAY);
    glEnableClientState(GL_COLOR_ARRAY);
    glVertexPointer(3, GL_FLOAT, sizeof(struct Vertex), vertex);
    glColorPointer(3, GL_FLOAT, sizeof(struct Vertex), &vertex[0].r); // Pointer to the first color

    glPointSize(2.0);

    // Background color is black
    glClearColor(0, 0, 0, 0);
}


static UIWindowDisplayBits   display( id <UIOSWindow> window_in)
{
    //GLFWOSWindow  *window = MULLE_OBJC_CLASS_CAST( GLFWOSWindow, window_in);{
    // Compute height of each vertex
    adjust_grid();
    // Draw wave grid to OpenGL display
    draw_scene();
    return( 0);
}


//========================================================================
// main
//========================================================================

int main(int argc, char* argv[])
{
//    double t, dt_total, t_old;
//    int width, height;
   UIApplication         *app;
   GLFWOSWindow          *gWindow;
   NSTimer               *timer;
   CGPixelSize   framebufferSize;

//    glfwSetErrorCallback(error_callback);
//
//    if (!glfwInit())
//        exit(EXIT_FAILURE);
   app = [UIApplication sharedInstance];

   @autoreleasepool
   {
//    window = glfwCreateWindow(640, 480, "Wave Simulation", NULL, NULL);
//    if (!window)
//    {
//        glfwTerminate();
//        exit(EXIT_FAILURE);
//    }

   gWindow = [GLFWOSWindow windowWithFrame:CGRectMake( 0, 0, 640, 480)
                          titleUTF8String:"Wave Simulation"
                                styleMask:UIWindowStyleResizable
                            graphicsHints:GLFWGraphicsHintsDefault];
   [app addWindow:gWindow];

//   glfwSetKeyCallback(window, key_callback);
//   glfwSetFramebufferSizeCallback(window, framebuffer_size_callback);
//   glfwSetMouseButtonCallback(window, mouse_button_callback);
//   glfwSetCursorPosCallback(window, cursor_position_callback);
//   glfwSetScrollCallback(window, scroll_callback);

   // default of GLFWindow is 20
   [gWindow setScrollWheelSensitivity:1.0];
   [gWindow setWindowEventsCallback:receiveWindowEvents];
   [gWindow setOtherRetainedEventsCallback:receiveOtherEvents];

    // Initialize simulation
    init_vertices();
    init_grid();
    adjust_grid();
//    glfwGetFramebufferSize(window, &width, &height);

//
//    while (!glfwWindowShouldClose(window))
//    {
// moved to display
//        t = glfwGetTime();
//        dt_total = t - t_old;
//        t_old = t;
//
//        // Safety - iterate if dt_total is too large
//        while (dt_total > 0.f)
//        {
//            // Select iteration time step
//            dt = dt_total > MAX_DELTA_T ? MAX_DELTA_T : dt_total;
//            dt_total -= dt;
//
//            // Calculate wave propagation
//            calc_grid();
//        }
// moved to timer()
    // Initialize timer
    timer = [[[NSTimer alloc] mulleInitWithRelativeTimeInterval:0.0
                                         repeatInterval:MAX_DELTA_T / 10.0
                                               callback:timer_callback
                                               userInfo:nil] autorelease];
      [app addTimer:timer
   forTimerReceiver:app];
 //
//        // Compute height of each vertex
//        adjust_grid();
//
//        // Draw wave grid to OpenGL display
//        draw_scene(window);
//        glfwPollEvents();
// moved to display
//    glfwMakeContextCurrent(window);
    [gWindow os_activateGraphicsContext];
    {
    // gladLoadGL(glfwGetProcAddress);
//    glfwSwapInterval(1);
      [gWindow os_setSwapInterval:1];

      [gWindow setFrameCallback:display];

      framebufferSize = [gWindow os_framebufferSize];
      framebuffer_size_callback( [gWindow os_window], framebufferSize.width, framebufferSize.height);

      // Initialize OpenGL
      init_opengl();
    }
    [gWindow os_deactivateGraphicsContext];
    [gWindow setFrameRateHz:60.0];

//    }
//    glfwTerminate();
//    exit(EXIT_SUCCESS);
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


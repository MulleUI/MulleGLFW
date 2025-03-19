//========================================================================
// Context sharing example
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
#define _DEFAULT_SOURCE

#import "import.h"

#include <assert.h>
#include <string.h>
#include <time.h>


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


#define N_WINDOWS          3
#define TEXTURE_CREATOR    0

static const GLfloat   vertices[4][2] =
{
    { -1.0f, -1.0f },
    { -1.0f,  1.0f },
    {  1.0f,  1.0f },
    {  1.0f, -1.0f }
};

#define Z   { 0x0,  0x0,  0x0,  0xFF }
#define W   { 0xFF, 0xFF, 0xFF, 0xFF }
#define R   { 0xFF, 0, 0,       0xFF }
#define R   { 0xFF, 0, 0,       0xFF }
#define G   { 0,    0xFF, 0,       0xFF }
#define B   { 0,    0, 0xFF,       0xFF }
#define Y   { 0xFF, 0xFF, 0x0, 0xFF  }
#define O   { 0xFF, 0x7F, 0x0, 0xFF  }

static unsigned char   stupidtex1[ 8][ 8][ 4] = 
{
   { Y, Y, Y, Y,   Y, Y, Y, Y },
   { Y, Y, B, B,   G, G, Y, Y },
   { Y, Y, B, B,   G, G, Y, Y },
   { Y, B, B, B,   G, G, G, Y },

   { Y, B, B, B,   G, G, G, Y },
   { Y, Y, B, B,   G, G, Y, Y },
   { Y, Y, B, B,   G, G, Y, Y },
   { Y, Y, Y, Y,   Y, Y, Y, Y }
};


static unsigned char   stupidtex2[ 8][ 8][ 4] = 
{
   { O, O, O, O,   O, O, O, O },
   { O, O, B, B,   G, G, O, O },
   { O, O, B, B,   G, G, O, O },
   { O, B, B, B,   G, G, G, O },

   { O, B, B, B,   G, G, G, O },
   { O, O, B, B,   G, G, O, O },
   { O, O, B, B,   G, G, O, O },
   { O, O, O, O,   O, O, O, O }
};


static unsigned char   stupidtex3[ 8][ 8][ 4] = 
{
   { R, R, R, R,   R, R, R, R },
   { R, R, B, B,   G, G, R, R },
   { R, R, B, B,   G, G, R, R },
   { R, B, B, B,   G, G, G, R },

   { R, B, B, B,   G, G, G, R },
   { R, R, B, B,   G, G, R, R },
   { R, R, B, B,   G, G, R, R },
   { R, R, R, R,   R, R, R, R }
};



static unsigned char   bwtex[ 16][ 16][ 4] = 
{
   { Z, Z, Z, Z,   W, W, W, W,  Z, Z, Z, Z,   W, W, W, W },
   { Z, Z, Z, Z,   W, W, W, W,  Z, Z, Z, Z,   W, W, W, W },
   { Z, Z, Z, Z,   W, W, W, W,  Z, Z, Z, Z,   W, W, W, W },
   { Z, Z, Z, Z,   W, W, W, W,  Z, Z, Z, Z,   W, W, W, W },
   { W, W, W, W,   Z, Z, Z, Z,  W, W, W, W,   Z, Z, Z, Z },
   { W, W, W, W,   Z, Z, Z, Z,  W, W, W, W,   Z, Z, Z, Z },
   { W, W, W, W,   Z, Z, Z, Z,  W, W, W, W,   Z, Z, Z, Z },
   { W, W, W, W,   Z, Z, Z, Z,  W, W, W, W,   Z, Z, Z, Z },  

   { Z, Z, Z, Z,   W, W, W, W,  Z, Z, Z, Z,   W, W, W, W },
   { Z, Z, Z, Z,   W, W, W, W,  Z, Z, Z, Z,   W, W, W, W },
   { Z, Z, Z, Z,   W, W, W, W,  Z, Z, Z, Z,   W, W, W, W },
   { Z, Z, Z, Z,   W, W, W, W,  Z, Z, Z, Z,   W, W, W, W },
   { W, W, W, W,   Z, Z, Z, Z,  W, W, W, W,   Z, Z, Z, Z },
   { W, W, W, W,   Z, Z, Z, Z,  W, W, W, W,   Z, Z, Z, Z },
   { W, W, W, W,   Z, Z, Z, Z,  W, W, W, W,   Z, Z, Z, Z },
   { W, W, W, W,   Z, Z, Z, Z,  W, W, W, W,   Z, Z, Z, Z }  
};




static void   *get_stupidtex_with_index( int  i)
{
   if( i == 0)
      return( stupidtex1);
   if( i == 1)
      return( stupidtex2);
   return( stupidtex3);
}



static void error_callback(int error, const char* description)
{
    fprintf(stderr, "Error: %s\n", description);
}

static void key_callback(GLFWwindow* window, int key, int scancode, int action, int mods)
{
    if (action == GLFW_PRESS && key == GLFW_KEY_ESCAPE)
        glfwSetWindowShouldClose(window, GLFW_TRUE);
}

static void   create_texture( GLuint *texture, void *bitmap, int w, int h)
{
   glGenTextures(1, texture);
   fprintf( stderr, "glGenTextures ->: %d\n", *texture);
   glBindTexture(GL_TEXTURE_2D, *texture);

          // Create the texture object
   glTexImage2D(GL_TEXTURE_2D, 
               0,                // One resolution (i.e. level 0)
               4,                // 3 components (i.e., RGB)
               w,                // Width
               h,                // Height
               0,                // Border width
               GL_RGBA,           // Format
               GL_UNSIGNED_BYTE,  // Data type of the texels
               bitmap);
// needed otherwise no texture to be seen.
   glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
   glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
}


int main(int argc, char** argv)
{
    GLFWwindow   *windows[3];
    GLuint       texture[ 3];
    GLuint       junk;
    int          i;
    char         buf[ 64];

    glfwSetErrorCallback(error_callback);

    if (!glfwInit())
        exit(EXIT_FAILURE);

    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 2);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 0);

    windows[0] = glfwCreateWindow(400, 400, "Demo", NULL, NULL);
    if (!windows[0])
    {
        glfwTerminate();
        exit(EXIT_FAILURE);
    }

    glfwSetKeyCallback(windows[0], key_callback);

    glfwMakeContextCurrent(windows[0]);

    // Only enable vsync for the first of the windows to be swapped to
    // avoid waiting out the interval for each window
    glfwSwapInterval(1);


    // we can share with windows[ 0] in a "star" configuration or we can
    // daisy chain windows, it makes no difference apparenly (with OpenGL) 
    for( i = 1; i < N_WINDOWS; i++)
    {
       sprintf( buf, "Demo%d", i);
       windows[ i] = glfwCreateWindow(400, 400, buf, NULL, windows[i-1]);
       if (!windows[i])
       {
           glfwTerminate();
           exit(EXIT_FAILURE);
       }

       // Place the window to the right of the previous
       {
           int xpos, ypos, left, right, width;

           glfwGetWindowSize(windows[i-1], &width, NULL);
           glfwGetWindowFrameSize(windows[i-1], &left, NULL, &right, NULL);
           glfwGetWindowPos(windows[i-1], &xpos, &ypos);

           glfwSetWindowPos(windows[i], xpos + width + left + right, ypos);
       }

       glfwSetKeyCallback(windows[i], key_callback);
    }

    // While objects are shared, the global context state is not and will
    // need to be set up for each context
    for( i = 0; i < N_WINDOWS; i++)
    {
       // each context creates a texture
       glfwMakeContextCurrent(windows[i]);
       glEnable(GL_TEXTURE_2D);
       create_texture( &texture[ i], get_stupidtex_with_index( i), 8, 8);
    }

    for( i = 0; i < N_WINDOWS; i++)
    {
       glfwMakeContextCurrent(windows[i]);
       glBindTexture( GL_TEXTURE_2D, texture[ 1]);
    }
// If you remove sharing, you can see how a texture ids appears twice
// in each context. With sharing texture ids are unique (shareable)

//    glGenTextures(1, &junk);
//    fprintf( stderr, "1: %d\n", junk);
//
//    glfwMakeContextCurrent(windows[0]);
//
//    glGenTextures(1, &junk);
//    fprintf( stderr, "0 : %d\n", junk);


    //
    // this code removes the middle texture. But as the other textures remain
    // visible, it proves that textures are "reference counted", or that 
    // deleting a texture in one context does not affect the texture in 
    // another.
    //
#if 0
    glfwMakeContextCurrent( windows[1]);
    glDeleteTextures( 1, &texture[ 1]);
//    create_texture( &texture[ 1], bwtex);
//    fprintf( stderr, "W#%d: %d\n", 0, texture[ 1]);
#else 
    glfwMakeContextCurrent(windows[1]);
    glBindTexture( GL_TEXTURE_2D, texture[ 1]);
    glTexImage2D(GL_TEXTURE_2D, 
                  0,                // One resolution (i.e. level 0)
                  4,                // 3 components (i.e., RGB)
                  16,                // Width
                  16,                // Height
                  0,                // Border width
                  GL_RGBA,           // Format
                  GL_UNSIGNED_BYTE,  // Data type of the texels
                  bwtex);
#endif                     
    while (!glfwWindowShouldClose(windows[0])) // &&  !glfwWindowShouldClose(windows[1]))
    {

        for (i = 0;  i < N_WINDOWS;  i++)
        {
            int width, height;

            glfwGetFramebufferSize(windows[i], &width, &height);
            glfwMakeContextCurrent(windows[i]);

            glViewport(0, 0, width, height);
            glBindTexture( GL_TEXTURE_2D, texture[ 1]);

            glBegin(GL_QUADS);

             glTexCoord2f(0.0, 0.0);  // Use bottom left texel
             glVertex2fv(vertices[0]);

             glTexCoord2f(0.0, 1.0);  // Use bottom right texel
             glVertex2fv(vertices[1]);

             glTexCoord2f(1.0, 1.0);  // Use top right texel
             glVertex2fv(vertices[2]);

             glTexCoord2f(1.0, 0.0);  // Use top left texel
             glVertex2fv(vertices[3]);

             glEnd(); 

            glfwSwapBuffers(windows[i]);
        }

        glfwPollEvents();
        {
           struct timespec  delay;

           delay.tv_sec  = 0;
           delay.tv_nsec = 1000 * 1000 * 1000 / 2;
           nanosleep( &delay, NULL);
        }
    }

    glfwTerminate();
    exit(EXIT_SUCCESS);
}


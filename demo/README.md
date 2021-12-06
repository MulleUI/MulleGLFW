# demos

Demos of MulleGLFW.

```
TODO:  Fullscreen demo
       Multiple Monitor demo
```


### glfw-wave

Based on glfw-wave-original.

Shows UIEvents being accepted. The draw code has been moved to a render loop. Animations has been moved to a timer.
Window creation is done with GLFWWindows. Overall, setup is simplified. Event
handling is more complicated, but UIEvents will be a win starting when we
distribute them to individual UIViews in later projects.


![Screenshot of glfw-wavegears](glfw-wave.png)

[src/main-glfw-wave.m](src/main-glfw-wave.m)


### glfw-wave-original

Stolen demo from [glfw](//glfw.org) examples. Minimal changes to accomodate
not having "Glad". This is meant as a reference for



### glfw-texture

Most basic OpenGL texture mapping demo. **UIApplication** is used to
initialize GLFW. Then a GLFWWindows is created and a render callback installed.
Finally UIEvent handles event processing and sets a fixed framerate.

![Screenshot of glfw-texture](glfw-texture.png)

[src/main-glfw-texture.m](src/main-glfw-texture.m)

### glfw-triangle-opengles / glfw-triangle-opengl

Stolen demo from [glfw](//glfw.org) examples. Demonstrates how to specify a
certain API for drawing. This demo accepts a lot of options, to change the
OpenGL API to be used. Use `glfw-triangle-opengles -h` to see whats available.

![Screenshot of glfw-triangle-opengles](glfw-triangle-opengles.png)

[src/main-glfw-triangle-opengles.m](src/main-glfw-triangle-opengles.m)

[src/main-glfw-triangle-opengl.m](src/main-glfw-triangle-opengl.m)


### glfw-gears

Stolen demo from [glfw](//glfw.org) examples. Demonstrates how to remove
window adornments and to draw with transparencey.

![Screenshot of glfw-gears](glfw-gears.png)

[src/main-glfw-gears.m](src/main-glfw-gears.m)


## Build

This is a [mulle-sde](https://mulle-sde.github.io/) project.

It comes with its own virtual environment and list of dependencies.
To fetch and build everything say:

```
mulle-sde craft --[release|debug]
```

The resultant demos will be in `kitchen/{Release/Debug}`.

# MulleGLFW

#### 🌐 MulleGLFW provides platform windows and events

This is an Objective-C wrapper around GLFW3 to provide windows and events.
It provides the meat and potatoes code for **UIEvent** and **UIApplication**
through categories. **UIWindow** owns one more more **GLFWOSWindows**.

The GLFW3 window object is **GLFWOSWindow**. Each GLFWOSWindow has an implicit
graphics context, that will be later used by a CGContext.


### You are here

![Overview](overview.dot.svg)


### Platform notes

MulleGLFW is a dual-sourcetree project. You can choose between X11 (default)
and Wayland (wayland). See [Compiling GLFW](https://www.glfw.org/docs/latest/compile_guide.html) for an up-to-date list of platform requirements and
dependencies.


#### Linux X11

On Linux (X11) the following libraries are linked, but most of the
headers are included by glfw so they are maked `no-header` as to not create
duplicate include directives by `reflect`:

Library  | Header          |
---------|-----------------|---------
GL       | `GL/glext.h`    |
GLU      |                 | `apt-get install freeglut3-dev`
X11      |                 | `apt install libx11-dev libxi-dev`
Xrandr   |                 | `apt install libxrandr-dev`
Xxf86vm  |                 | `apt install libxxf86vm-dev`
Xinerama |                 | `apt install libxinerama-dev`
Xcursor  |                 | `apt install libxcursor-dev`
m        |                 |


#### Linux Wayland

On Linux (Wayland) the following libraries are linked, but most of the
headers are included by glfw so they are maked `no-header` as to not create
duplicate include directives by `reflect`:

Library           | Header          |
------------------|-----------------|---------
GL                | `GL/glext.h`    |
GLU               |                 | `apt-get install freeglut3-dev`
wayland_client    |                 | `apt install libwayland-dev`
wayland-protocols |                 | `apt install wayland-protocols`
libxkbcommon-dev  |                 | `apt install libxkbcommon-dev`
m                 |                 |


====
At the moment (glfw 3.3), there is a bug in `glfwSwapBuffers` that makes the
system always vsync (block). This leads to severe problems during resize.
====


#### macOS

On macOS, glfw needs to link with

Framework      | Header
---------------|------------------------
Cocoa          |
IOKit          |
CoreFoundation |
CoreGraphics   |
CoreServices   |
AppKit         |
Foundation     |

The header files of these frameworks are Apple Objective-C and not mulle-objc
compatible, so they aren't available (See the `no-header` mark with
`mulle-sde lib`). glfw doesn't expose them either.



## mulle-sde

This is a [mulle-sde](//github.com/mulle-sde) project. mulle-sde combines
recursive package management with cross-platform builds via **cmake**:

Action  | Command                               | Description
--------|---------------------------------------|---------------
Build   | `mulle-sde craft [--release|--debug]` | Builds into local `kitchen` folder
Add     | `mulle-sde dependency add --c --github MulleUI MulleGLFW` | Add MulleGLFW to another mulle-sde project as a dependency
Choose  | `mulle-sde config switch MulleGLFW wayland | Use wayland as the backend
Install | `mulle-sde install --prefix /usr/local https://github.com/MulleUI/MulleGLFW.git` | Like `make install`


### Manual Installation


Install the requirements:

Requirements                                      | Description
--------------------------------------------------|-----------------------
[some-requirement](//github.com/some/requirement) | Some requirement

Install into `/usr/local`:

``` sh
cmake -B build \
      -DCMAKE_INSTALL_PREFIX=/usr/local \
      -DCMAKE_PREFIX_PATH=/usr/local \
      -DCMAKE_BUILD_TYPE=Release &&
cmake --build build --config Release &&
cmake --install build --config Release
```


<!--
extension : mulle-sde/sde
directory : demo/library
template  : .../README.md
Suppress this comment with `export MULLE_SDE_GENERATE_FILE_COMMENTS=NO`
-->

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
Add     | `mulle-sde dependency add --c --github <|GITHUB_USER|> MulleGLFW` | Add MulleGLFW to another mulle-sde project as a dependency
Install | `mulle-sde install --prefix /usr/local https://github.com/<|GITHUB_USER|>/MulleGLFW.git` | Like `make install`


### Manual Installation


Install the requirements:

Requirements                                      | Description
--------------------------------------------------|-----------------------
[some-requirement](//github.com/some/requirement) | Some requirement

Install into `/usr/local`:

``` sh
mkdir build 2> /dev/null
(
   cd build ;
   cmake -DCMAKE_INSTALL_PREFIX=/usr/local \
         -DCMAKE_PREFIX_PATH=/usr/local \
         -DCMAKE_BUILD_TYPE=Release .. ;
   make install
)
```


<!--
extension : mulle-sde/sde
directory : demo/library
template  : .../README.md
Suppress this comment with `export MULLE_SDE_GENERATE_FILE_COMMENTS=NO`
-->

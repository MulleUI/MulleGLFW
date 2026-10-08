# MulleGLFW

#### Part of [MulleUI](https://github.com/MulleUI) — UIKit-shaped modular GUI libraries for mulle-objc.


This is an Objective-C wrapper around GLFW3 to provide windows and events.
It provides the meat and potatoes code for **UIEvent** and **UIApplication**
through categories. **UIWindow** owns one or more **GLFWOSWindows**.

The GLFW3 window object is **GLFWOSWindow**. Each GLFWOSWindow has an implicit
graphics context, that will be later used by a CGContext.





| Release Version                                       | Release Notes  | AI Documentation
|-------------------------------------------------------|----------------|---------------
| ![Mulle kybernetiK tag](https://img.shields.io/github/tag/MulleUI/MulleGLFW.svg) [![Build Status](https://github.com/MulleUI/MulleGLFW/workflows/CI/badge.svg)](//github.com/MulleUI/MulleGLFW/actions) | [RELEASENOTES](RELEASENOTES.md) | [DeepWiki for MulleGLFW](https://deepwiki.com/MulleUI/MulleGLFW)




## Documentation & Guides

* [API Summary](asset/dox/api/toc)
* [Coder Guide](asset/howto/coder/mulle-glfw)
* [Debugger Guide](asset/howto/debugger/mulle-glfw)
* [Verifier Guide](asset/howto/verifier/mulle-glfw)

## Usage

`GLFWOSWindow` is the concrete OS window: it wraps a native GLFW window and
gives you low-level access to it:

``` objc
#import <MulleGLFW/MulleGLFW.h>

int  main( void)
{
   GLFWOSWindow  *window;

   window = [GLFWOSWindow windowWithFrame:CGRectMake( 0.0, 0.0, 320.0, 240.0)
                          titleUTF8String:"Hello, MulleGLFW"
                                styleMask:UIWindowStyleResizable];

   [window os_show];
   [window os_setSwapInterval:1];            // sync buffer swaps to the monitor
   [window os_setTitleUTF8String:"A better title"];

   fprintf( stderr, "framebuffer %tdx%td\n",
                   [window os_framebufferSize].width,
                   [window os_framebufferSize].height);

   [window os_destroyWindow];
   return( 0);
}
```

Normally you won't talk to a `GLFWOSWindow` directly. A `UIWindow` owns one
(or more) and hands its events to the responder chain through `UIEvent`.
MulleUIOS selects the window system, renderer and backend at build time; see
its [sourcetree configs](//github.com/MulleUI/MulleUIOS).

## Build the demo

The `demo/` folder is a [mulle-sde](//github.com/mulle-sde) project:

``` sh
cd demo
mulle-sde craft
```


### You are here

![Overview](overview.dot.svg)





## Add





### Add MulleGLFW as a cmake subproject

In your code include its header:

``` c
#include <MulleGLFW/MulleGLFW.h>
```

Add MulleGLFW and dependencies as git submodules and link against
them:

``` bash
git submodule add -f --name "MulleGLFW" \
                        "https://github.com/MulleUI/MulleGLFW" \
                        "stash/MulleGLFW"
git submodule update --init --recursive
```

``` cmake
include_directories( SYSTEM "${CMAKE_BINARY_DIR}/include")

add_subdirectory( stash/)
add_subdirectory( stash/MulleGLFW)

target_link_libraries( ${PROJECT_NAME} PUBLIC )
target_link_libraries( ${PROJECT_NAME} PUBLIC MulleGLFW)
```

Or let [mulle-sde](//github.com/mulle-sde) do it:

``` sh
mulle-sde add github:MulleUI/MulleGLFW
```

## Install

Use [mulle-sde](//github.com/mulle-sde) to build and install MulleGLFW and all dependencies:

``` sh
mulle-sde install --prefix /usr/local \
   https://github.com/MulleUI/MulleGLFW/archive/latest.tar.gz
```

### Legacy Installation

Install the requirements:

| Requirements                                 | Description
|----------------------------------------------|-----------------------
| [glfw](https://github.com/glfw/glfw)             | 
| [MulleUIApplication](https://github.com/MulleUI/MulleUIApplication)             | 🛖 MulleUIApplication provides abstract classes like UIApplication and UIEvent
| [mulle-objc-tools](https://github.com/mulle-objc/mulle-objc-tools)             | 📒 Lists mulle-objc runtime information contained in executables.

Download the latest [tar](https://github.com/MulleUI/MulleGLFW/archive/refs/tags/latest.tar.gz) or [zip](https://github.com/MulleUI/MulleGLFW/archive/refs/tags/latest.zip) archive and unpack it.

Install **MulleGLFW** into `/usr/local` with [cmake](https://cmake.org):

``` sh
PREFIX_DIR="/usr/local"
cmake -B build                               \
      -DMULLE_SDK_PATH="${PREFIX_DIR}"       \
      -DCMAKE_INSTALL_PREFIX="${PREFIX_DIR}" \
      -DCMAKE_PREFIX_PATH="${PREFIX_DIR}"    \
      -DCMAKE_BUILD_TYPE=Release &&
cmake --build build --config Release &&
cmake --install build --config Release
```


## Author

[Nat!](https://mulle-kybernetik.com/weblog) for Mulle kybernetiK  




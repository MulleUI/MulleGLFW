#
# You rarely need to edit this file. To add or remove files to your
# project edit the "src" folders contents and run `mulle-sde reflect`
#
#
# A convenient way to add a new source fils is:
#    mulle-sde add src/foo.m
#
cmake_minimum_required( VERSION 3.16...99.99)

project( MulleGLFW VERSION 0.1.1 LANGUAGES C)


set( MULLE_PROJECT_TYPE "Library")


### mulle-sde environment

set( MULLE_SDE_REFLECT_DIR "reflect")

if( NOT MULLE_SOURCETREE_CONFIG_NAME)
   set( MULLE_SOURCETREE_CONFIG_NAME "$ENV{MULLE_SOURCETREE_CONFIG_NAME}")
endif()
if( MULLE_SOURCETREE_CONFIG_NAME)
   set( MULLE_SDE_REFLECT_DIR "reflect.${MULLE_SOURCETREE_CONFIG_NAME}")
endif()

# add cmake module paths to search path
list( INSERT CMAKE_MODULE_PATH 0 "${PROJECT_SOURCE_DIR}/cmake/share")
list( INSERT CMAKE_MODULE_PATH 0 "${PROJECT_SOURCE_DIR}/cmake/${MULLE_SDE_REFLECT_DIR}")
list( INSERT CMAKE_MODULE_PATH 0 "${PROJECT_SOURCE_DIR}/cmake")

include( Environment)

include( Files)

include( IDESupport OPTIONAL)


# ---------------------------------------------------------------------------
# Apple Metal surface shim (system clang, Apple runtime — NOT mulle-clang)
#
# src/GLFWMetalLayer-apple.m touches Apple AppKit/QuartzCore/Metal ObjC objects
# and uses the system Objective-C runtime + system SDK headers (which require
# blocks). mulle-clang cannot compile these, so we must NOT let CMake compile
# this TU with the project toolchain. Instead we compile it to an object file
# with the *system* clang via a custom command, and inject that object into the
# library through OTHER_<IDENTIFIER>_OBJECT_FILES (see cmake/share/Library.cmake).
# ---------------------------------------------------------------------------
list( REMOVE_ITEM SOURCES "src/GLFWMetalLayer-apple.m")

if( APPLE)
   # Locate the system clang (Xcode toolchain), explicitly avoiding mulle-clang.
   find_program( SYSTEM_CLANG
      NAMES clang
      PATHS /usr/bin
      NO_DEFAULT_PATH
   )
   if( NOT SYSTEM_CLANG)
      set( SYSTEM_CLANG "/usr/bin/clang")
   endif()

   execute_process(
      COMMAND xcrun --show-sdk-path
      OUTPUT_VARIABLE MULLE_GLFW_MACOS_SDK
      OUTPUT_STRIP_TRAILING_WHITESPACE
   )

   set( MULLE_GLFW_METAL_SHIM_SRC "${PROJECT_SOURCE_DIR}/src/GLFWMetalLayer-apple.m")
   set( MULLE_GLFW_METAL_SHIM_OBJ "${CMAKE_CURRENT_BINARY_DIR}/GLFWMetalLayer-apple.o")

   add_custom_command(
      OUTPUT "${MULLE_GLFW_METAL_SHIM_OBJ}"
      COMMAND "${SYSTEM_CLANG}"
              -isysroot "${MULLE_GLFW_MACOS_SDK}"
              -fobjc-arc
              -fmodules
              -g -O0 -fPIC
              -c "${MULLE_GLFW_METAL_SHIM_SRC}"
              -o "${MULLE_GLFW_METAL_SHIM_OBJ}"
      DEPENDS "${MULLE_GLFW_METAL_SHIM_SRC}"
              "${PROJECT_SOURCE_DIR}/src/GLFWMetalLayer-apple.h"
      COMMENT "Compiling Apple Metal shim with system clang (${SYSTEM_CLANG})"
      VERBATIM
   )
   add_custom_target( MulleGLFWMetalShim
      DEPENDS "${MULLE_GLFW_METAL_SHIM_OBJ}"
   )

   set( OTHER_MULLE_GLFW_OBJECT_FILES
      "${MULLE_GLFW_METAL_SHIM_OBJ}"
   )
endif()


### Library

if( HEADER_PHASE)
   install( FILES ${INSTALL_PUBLIC_HEADERS}  DESTINATION "include/${PROJECT_NAME}")
   install( FILES ${INSTALL_PRIVATE_HEADERS} DESTINATION "include/${PROJECT_NAME}")
   install( FILES ${INSTALL_CMAKE_INCLUDES}  DESTINATION "include/${PROJECT_NAME}/cmake")

   # short cut out
   if( NOT COMPILE_PHASE AND NOT LINK_PHASE)
      return()
   endif()
endif()

if( LINK_PHASE)
   include( Dependencies OPTIONAL)
endif()

include( Library)

# use LIBRARY_COMPILE_TARGET for compiler options
target_compile_definitions( "${LIBRARY_COMPILE_TARGET}" PUBLIC)
target_compile_options( "${LIBRARY_COMPILE_TARGET}" PUBLIC -Wall)
# use LIBRARY_LINK_TARGET for linker options
if( LINK_PHASE)
   target_link_options( "${LIBRARY_LINK_TARGET}" PUBLIC)
endif()

# Frameworks needed by the Apple Metal surface shim (src/GLFWMetalLayer-apple.m)
if( APPLE AND LINK_PHASE)
   target_link_libraries( "${LIBRARY_LINK_TARGET}" PUBLIC
      "-framework Metal"
      "-framework QuartzCore"
      "-framework AppKit"
   )
endif()

# ---------------------------------------------------------------------------
# TODO: OSMesa off-screen blit support — needs proper implementation
#
# Note: Library.cmake uses the plain (no-keyword) target_link_libraries
# signature.  Any calls added here must use PUBLIC so that cmake/share/
# Library.cmake is fixed to use PUBLIC first, otherwise cmake complains
# about mixing plain and keyword signatures on the same target.
#
# if( PkgConfig_FOUND)
#    pkg_check_modules( OSMESA QUIET osmesa)
#    pkg_check_modules( X11    QUIET x11)
#    pkg_check_modules( WAYLAND_CLIENT QUIET wayland-client)
# endif()
#
# if( OSMESA_FOUND)
#    message( STATUS "MulleGLFW: OSMesa found — enabling OSMesa blit path")
#    target_compile_definitions( "${LIBRARY_COMPILE_TARGET}" PRIVATE MULLE_GLFW_OSMESA=1)
#    if( LINK_PHASE)
#       target_link_libraries( "${LIBRARY_LINK_TARGET}" PUBLIC ${OSMESA_LIBRARIES})
#       target_include_directories( "${LIBRARY_COMPILE_TARGET}" PRIVATE ${OSMESA_INCLUDE_DIRS})
#    endif()
#
#    if( X11_FOUND)
#       message( STATUS "MulleGLFW: X11 found — enabling X11 blit backend")
#       target_compile_definitions( "${LIBRARY_COMPILE_TARGET}" PRIVATE MULLE_GLFW_X11=1)
#       if( LINK_PHASE)
#          target_link_libraries( "${LIBRARY_LINK_TARGET}" PUBLIC ${X11_LIBRARIES})
#          target_include_directories( "${LIBRARY_COMPILE_TARGET}" PRIVATE ${X11_INCLUDE_DIRS})
#       endif()
#    endif()
#
#    if( WAYLAND_CLIENT_FOUND)
#       message( STATUS "MulleGLFW: wayland-client found — enabling Wayland blit backend")
#       target_compile_definitions( "${LIBRARY_COMPILE_TARGET}" PRIVATE MULLE_GLFW_WAYLAND=1)
#       if( LINK_PHASE)
#          target_link_libraries( "${LIBRARY_LINK_TARGET}" PUBLIC ${WAYLAND_CLIENT_LIBRARIES})
#          target_include_directories( "${LIBRARY_COMPILE_TARGET}" PRIVATE ${WAYLAND_CLIENT_INCLUDE_DIRS})
#       endif()
#    endif()
# endif()
# ---------------------------------------------------------------------------

include( InstallLibrary)


include( FinalOutput OPTIONAL)


# extension : mulle-sde/cmake
# directory : project/library
# template  : .../CMakeLists.txt
# Suppress this comment with `export MULLE_SDE_GENERATE_FILE_COMMENTS=NO`

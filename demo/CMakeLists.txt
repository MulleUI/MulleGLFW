cmake_minimum_required( VERSION 3.15...99.99)

project( demo C)

#
# Turn an "Executable" into a "Library"
# * mulle-sde test init
# * mv src/main.m test/10_test/test.m
# Then set MULLE_PROJECT_TYPE to "Library".
# * mulle-sde reflect
# * mulle-sde test
#
set( MULLE_PROJECT_TYPE "Executable")

### mulle-sde environment

# add cmake module paths to search path
list( INSERT CMAKE_MODULE_PATH 0 "${PROJECT_SOURCE_DIR}/cmake/share")
list( INSERT CMAKE_MODULE_PATH 0 "${PROJECT_SOURCE_DIR}/cmake/reflect")
list( INSERT CMAKE_MODULE_PATH 0 "${PROJECT_SOURCE_DIR}/cmake")

include( Environment)

include( Files)

include( Dependencies OPTIONAL)

# Check if system has wayland-client (libMulleGLFW.a may need it as transitive dep)
find_library( HAVE_WAYLAND_CLIENT wayland-client)
find_library( HAVE_OSMESA OSMesa)
find_library( HAVE_X11 X11)

foreach( MAIN_SOURCE ${SOURCES})
   # get rid off src/main- prefix and .m suffix
   #             offset 9  length -9 - 2
   string( LENGTH "${MAIN_SOURCE}" MAIN_SOURCE_LENGTH)
   math( EXPR MAIN_SOURCE_LENGTH "${MAIN_SOURCE_LENGTH} - 11")
   string( SUBSTRING "${MAIN_SOURCE}" 9 ${MAIN_SOURCE_LENGTH} EXECUTABLE_NAME)

   set( SOURCES ${MAIN_SOURCE})
#   set( OTHER_EXECUTABLE_OBJECT_FILES $<TARGET_OBJECTS:MulleUI>)

   include( Executable)

   # use EXECUTABLE_COMPILE_TARGET for compiler options
   if( EXECUTABLE_NAME STREQUAL "two-x-two-windows")
      target_compile_definitions( "${EXECUTABLE_COMPILE_TARGET}" PUBLIC HAVE_GLAD)
      target_include_directories( "${EXECUTABLE_COMPILE_TARGET}" PUBLIC "${PROJECT_SOURCE_DIR}/src")
   elseif( EXECUTABLE_NAME STREQUAL "two-x-two-windows-ordered")
      target_compile_definitions( "${EXECUTABLE_COMPILE_TARGET}" PUBLIC HAVE_GLAD)
      target_include_directories( "${EXECUTABLE_COMPILE_TARGET}" PUBLIC "${PROJECT_SOURCE_DIR}/src")
   elseif( EXECUTABLE_NAME STREQUAL "x11-osmesa")
      target_compile_definitions( "${EXECUTABLE_COMPILE_TARGET}" PUBLIC)
      target_include_directories( "${EXECUTABLE_COMPILE_TARGET}" PUBLIC "${PROJECT_SOURCE_DIR}/src")
   else()
      target_compile_definitions( "${EXECUTABLE_COMPILE_TARGET}" PUBLIC)
   endif()
   target_compile_options( "${EXECUTABLE_COMPILE_TARGET}" PUBLIC)
   # use EXECUTABLE_LINK_TARGET for linker options
   if( LINK_PHASE)
      if( NOT APPLE)
         if( EXECUTABLE_NAME STREQUAL "x11-osmesa" OR EXECUTABLE_NAME STREQUAL "glfw-x11-osmesa" OR EXECUTABLE_NAME STREQUAL "glfw-x11-osmesa-grok")
            target_link_libraries( "${EXECUTABLE_LINK_TARGET}" OSMesa X11)
         elseif( EXECUTABLE_NAME STREQUAL "glfw-wayland-osmesa")
            target_link_libraries( "${EXECUTABLE_LINK_TARGET}" OSMesa wayland-client rt)
         elseif( EXECUTABLE_NAME STREQUAL "glfw-osmesa-triangle")
            target_link_libraries( "${EXECUTABLE_LINK_TARGET}" OSMesa)
         else()
            target_link_options( "${EXECUTABLE_LINK_TARGET}" PUBLIC -lEGL)
         endif()
         # libMulleGLFW.a pulls in wayland symbols when the system has
         # wayland-client installed. Add transitive dep for all targets
         # except glfw-wayland-osmesa which already links it explicitly.
         if( MULLE_DEMO_WAYLAND_FOUND AND NOT EXECUTABLE_NAME STREQUAL "glfw-wayland-osmesa")
            target_link_libraries( "${EXECUTABLE_LINK_TARGET}" wayland-client)
         endif()
      endif()
   endif()

   include( InstallExecutable)
   include( FinalOutput OPTIONAL)
# only for Executable
   include( Motd OPTIONAL)
endforeach()


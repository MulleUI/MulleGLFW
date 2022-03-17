//
// Copyright (c) 2021 Nat!, Mulle kybernetiK
//
// prefer a local GLFWOSWindow over one in import.h
#ifdef __has_include
# if __has_include( "GLFWOSWindow.h")
#  import "GLFWOSWindow.h"
# endif
#endif

// we want "import.h" always anyway
#import "import.h"


@interface GLFWOSWindow( UIEvent)

// convenience for os_initWindowEvents and os_initInputEvents
- (void) os_initEvents;

- (void) os_initWindowEvents;
- (void) os_initInputEvents;

@end

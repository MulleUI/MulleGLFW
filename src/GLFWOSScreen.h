//
//  GLFWOSScreen.m
//  MulleGLFW
//
//  Copyright (c) 2022 Nat! - Mulle kybernetiK.
//  Copyright (c) 2022 Codeon GmbH.
//  All rights reserved.
//
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are met:
//
//  Redistributions of source code must retain the above copyright notice, this
//  list of conditions and the following disclaimer.
//
//  Redistributions in binary form must reproduce the above copyright notice,
//  this list of conditions and the following disclaimer in the documentation
//  and/or other materials provided with the distribution.
//
//  Neither the name of Mulle kybernetiK nor the names of its contributors
//  may be used to endorse or promote products derived from this software
//  without specific prior written permission.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
//  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
//  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
//  ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
//  LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
//  CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
//  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
//  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
//  CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
//  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
//  POSSIBILITY OF SUCH DAMAGE.
//
#ifdef __has_include
# if __has_include( "NSObject.h")
#  import "NSObject.h"
# endif
#endif

#import "import.h"


@interface GLFWOSScreen : NSObject < UIScreen>
{
   void                  *_monitor;   // GLFWmonitor handle

// if we copy all the values into the local area, we can then access this
// information from non-mainthread threads
   struct UIScreenInfo   _info;
   NSLock                *_infoLock;
}

+ (NSUInteger) numberOfScreens;
+ (id <UIScreen>) screenAtIndex:(NSUInteger) i;

- (instancetype) initWithGLFWMonitor:(void *) monitor;

// this is thread safe
@property( readonly) char   *nameUTF8String ;

- (void) getScreenInfo:(struct UIScreenInfo *) info   MULLE_OBJC_THREADSAFE_METHOD;

// MEMO: marking these threadsafe messes up the non-threadsafe method types
- (CGRect) frame                                MULLE_OBJC_THREADSAFE_METHOD;
- (CGRect) canvas                               MULLE_OBJC_THREADSAFE_METHOD;
- (mulle_relativetime_t) refreshRate            MULLE_OBJC_THREADSAFE_METHOD;

- (char *) os_nameUTF8String;
- (CGVector) os_contentScale;
- (CGSize) os_physicalSize;
- (CGFloat) os_dpi;
- (CGPixelRect) os_canvas;
- (CGPixelPoint) os_position;

- (BOOL) os_isPrimaryScreen;

@end

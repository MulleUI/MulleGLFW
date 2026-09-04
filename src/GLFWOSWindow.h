//
//  GLFWOSWindow.h
//  MulleGLFW
//
//  Copyright (c) 2022 Nat! - Mulle kybernetiK.
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


@class UIEvent;
@class UIWindowEvent;
@class CGContext;
@class GLFWOSWindow;


// MEMO: osmesa and mesa are two different things!


//   3         2         1         0
//  10987654321098765432109876543210
//
//  ppfaaallMMMMMMMMmmmmmmmmmmmmmmmm
//  77776666555544443333222211110000
//
// profile : GLFW_OPENGL_PROFILE          (0=default, 1=any, 2=core, 3=compat)
// forward : GLFW_OPENGL_FORWARD_COMPAT   (0=NO, 1=YES)
// api     : GLFW_CLIENT_API              (0=default, 1=NONE, 2=OpenGLES, 3=OpenGL) // vulkan, metal...
// lib     : GLFW_CONTEXT_CREATION_API    (0=default, 1=native, 2=egl, 3=osmesa)
// major   : GLFW_CONTEXT_VERSION_MAJOR
// minor   : GLFW_CONTEXT_VERSION_MINOR

typedef UIOSWindowGraphicsHints GLFWGraphicsHints;



//
// Preset initialisers — use as base for struct literals:
//   GLFWGraphicsHints hints = GLFWGraphicsHintsGL3_2;
//   hints.forward = 1;
//   hints.glx_vendor = "mesa";
//
#define GLFWGraphicsHintsDefault   ((GLFWGraphicsHints){ 0 })
#define GLFWGraphicsHintsNone      ((GLFWGraphicsHints){ .api = 1 })
#define GLFWGraphicsHintsGL3       ((GLFWGraphicsHints){ .profile = 1, .api = 3, .major = 3, .minor = 0 })
#define GLFWGraphicsHintsGL3_2     ((GLFWGraphicsHints){ .profile = 1, .api = 3, .major = 3, .minor = 2 })
#define GLFWGraphicsHintsGLES2     ((GLFWGraphicsHints){ .profile = 1, .api = 2, .major = 2, .minor = 0 })
#define GLFWGraphicsHintsGLES3     ((GLFWGraphicsHints){ .profile = 1, .api = 2, .major = 3, .minor = 0 })
#define GLFWGraphicsHintsGLES3_2   ((GLFWGraphicsHints){ .profile = 1, .api = 2, .major = 3, .minor = 2 })

// Apply driver-selection env vars from hints fields before glfwInit().
// Sets __GLX_VENDOR_LIBRARY_NAME, MESA_LOADER_DRIVER_OVERRIDE,
// LD_LIBRARY_PATH, LIBGL_DRIVERS_PATH, __EGL_VENDOR_LIBRARY_FILENAMES,
// LIBGL_ALWAYS_SOFTWARE, DRI_PRIME as needed.
// Must be called before [UIApplication sharedInstance].
void   GLFWGraphicsHintsApplyDriverEnv( GLFWGraphicsHints hints);


#define GLFWOSWindowStyleMaskDefault  0


//
// The GLFWOSWindow has the GLFW window handle and implicitly the
// drawing context. A UIWindow will have possibly two GLFWOSWindows
// associated with it. One for drawing offscreen and one for display onscreen.
// Events for the window are forwarded from here.
//
// If you create GLFWOSWindow manually, be sure to finalize them before
// -[UIApplication terminate], otherwise the context is gone and finalization
// may not be able to finish.
//
// In most cases the methods of this class can only be called from the
// main thread
//
@interface GLFWOSWindow : NSObject < UIWindow, UIOSWindow>
{
   void                     *_window;   // GLFWwindow handle

   NSLock                   *_contextLock;
   GLFWOSWindow             *_sharingWindow;
   NSInteger                _shareID;

   mulle_absolutetime_t     _lastSwapBuffersTimestamp;
   mulle_atomic_pointer_t   _needsRefresh;
   mulle_atomic_pointer_t   _discardEventsMask;

   NSLock                   *_windowInfoLock;
   struct UIOSWindowInfo    _windowInfo;

   void                     *_osmesaBlitState;  // struct mulle__osmesa_blit_state*

#ifdef __APPLE__
   // Opaque CAMetalLayer * (retained) attached to the cocoa content view when
   // the window is created with GLFW_NO_API on macOS; NULL otherwise. Created
   // and released through the system-runtime shim (GLFWMetalLayer-apple.m).
   // Vended as void * via -backendMetalLayer for the Metal CG backend.
   void                     *_metalLayer;
#endif

@private
   // _activeThread is not retained(!) if -haveGraphicsContext returns NO
   // then this will always be nil
   mulle_atomic_pointer_t   _atomicActiveThread;

   NSLock                   *_inputStateLock;

   mulle_absolutetime_t     _lastMouseButtonPressTime;
   NSUInteger               _mouseButtonClickCount;
   CGPoint                  _lastMouseButtonPressLocation;
   mulle_relativetime_t     _doubleClickInterval;
}

// NONE OF THESE PROPERTIES are thread safe, except those which are readonly

// window events are called via -handleEvent:
// event is autoreleased
@property( assign) id <UIEventReceiver>                windowEventsReceiver;

// window events are called via -receiveRetainedEvent:
// event must be released by receiver!
@property( assign) id <UIEventReceiver>                eventsReceiver;

// if you chose to overwrite events callbacks, the eventsReceiver
// and the windowEventsReceiver will not get anything. Setting either will
// also enable OS events for windowEvents or other

// default: GLFWOSWindowEventDefaultCallback
@property( assign) UIOSWindowEventCallback_t           windowEventsCallback;
// default: GLFWOSWindowRetainedEventDefaultCallback
@property( assign) UIOSWindowRetainedEventCallback_t   otherRetainedEventsCallback;
//
// very basic rendering and event support. Does not use CGContext!
// view port is not setup and framebuffer is not cleared!
@property( assign) UIOSWindowFrameCallback_t           frameCallback;

@property( assign, readonly) BOOL                      haveGraphicsContext;
@property( assign, readonly) NSUInteger                styleMask;
@property( dynamic, assign) mulle_relativetime_t       frameRate           MULLE_OBJC_THREADSAFE_PROPERTY;


@property( dynamic, assign) NSUInteger                 discardEventsMask   MULLE_OBJC_THREADSAFE_PROPERTY;
@property( assign) CGFloat                             scrollWheelSensitivity;
@property( assign, getter=isScrollWheelNatural) BOOL   scrollWheelNatural;


// renderGraphicsContext  is always nil! glfw has no drawing functionality
@property( assign, readonly) id <UIGraphicsContext>    renderGraphicsContext;
@property( assign) id <UIWindow>                       parentWindow;

// this just pertains to the window context, not the nvg context
// which may be antialiasing as a fallback
@property( readonly, getter=isAntiAliasing) BOOL       antiAliasing;

@property( assign, readonly) struct UIInputState       inputState       MULLE_OBJC_THREADSAFE_PROPERTY;
@property( assign, readonly) UIGraphicsBackend         backend;

@property( assign) NSUInteger                          debuggingFlags   MULLE_OBJC_THREADSAFE_PROPERTY;

@property( assign) BOOL                                uninitializedFramebuffer;


//
// window creation must be done on the main thread only
//
//
+ (instancetype) windowWithFrame:(CGRect) frame
                 titleUTF8String:(char *) title
                       styleMask:(NSUInteger) styleMask
                   graphicsHints:(GLFWGraphicsHints) graphicsHints;

+ (instancetype) windowWithFrame:(CGRect) frame
                 titleUTF8String:(char *) title
                       styleMask:(NSUInteger) styleMask;

// sharingWindow is retained. We will be able to share textures with it
+ (instancetype) windowWithFrame:(CGRect) frame
                 titleUTF8String:(char *) title
                       styleMask:(NSUInteger) styleMask
                   graphicsHints:(GLFWGraphicsHints) graphicsHints
                   sharingWindow:(id <UIOSWindow>) sharingWindow;

- (instancetype) initWithFrame:(CGRect) frame
               titleUTF8String:(char *) title
                     styleMask:(NSUInteger) styleMask
                 graphicsHints:(GLFWGraphicsHints) graphicsHints;

- (instancetype) initWithFrame:(CGRect) frame
               titleUTF8String:(char *) title
                     styleMask:(NSUInteger) styleMask;

// sharingWindow is retained. We will be able to share textures with it
- (instancetype) initWithFrame:(CGRect) frame
               titleUTF8String:(char *) title
                     styleMask:(NSUInteger) styleMask
                 graphicsHints:(GLFWGraphicsHints) graphicsHints
                 sharingWindow:(id <UIOSWindow>) sharingWindow;

//
// The frame,framebufferSize is usually the same as
// os_windowFrame/os_framebufferSize. But during resize there will be a
// disparity, when events tell us the new size and the value is seemingly
// not update in glfw (X ?) yet. So these values are updated by events.
//
//
// these values get updated by the OS events, they are
// more up to date than os_windowFrame, during resize
//
// This method can be called from any thread
//
- (void) getOSWindowInfo:(struct UIOSWindowInfo *) info  MULLE_OBJC_THREADSAFE_METHOD;

//
// screen the windows is on (either fully or for the most part)
// if the window has been moved outside of any screens, this may return nil
// This method can be called from any thread
//
- (id <UIScreen>) screen                                 MULLE_OBJC_THREADSAFE_METHOD;
- (id <UIScreen>) screenOrPrimaryScreen:(BOOL) flag      MULLE_OBJC_THREADSAFE_METHOD;

// The shareID never changes for a Window
// This method can be called from any thread
// 0 means, no sharing
- (NSInteger) shareID      MULLE_OBJC_THREADSAFE_METHOD;

// This method can be called from any thread
- (BOOL) shouldClose       MULLE_OBJC_THREADSAFE_METHOD;



- (void *) os_window                               MULLE_OBJC_THREADSAFE_METHOD;         // GLFW window, use this for glfw functions

// On macOS, for a GLFW_NO_API window, returns the attached CAMetalLayer * as
// an opaque void * (for the Metal CG backend / nvgCreateMTL). NULL otherwise.
- (void *) backendMetalLayer                       MULLE_OBJC_THREADSAFE_METHOD;- (void) os_setSwapInterval:(NSUInteger) value     MULLE_OBJC_THREADSAFE_METHOD;
- (void) os_swapBuffers                            MULLE_OBJC_THREADSAFE_METHOD;

// bind GL context of the window to the current thread
// synonymous with activate. These methods do not call mulleGainAccess or
// mulleRelinquishAccess
//
- (void) os_activateGraphicsContext                MULLE_OBJC_THREADSAFE_METHOD;
- (void) os_deactivateGraphicsContext              MULLE_OBJC_THREADSAFE_METHOD;
- (BOOL) os_tryActivateGraphicsContext             MULLE_OBJC_THREADSAFE_METHOD;


// This method can be called from any thread
- (void) os_requestClose                           MULLE_OBJC_THREADSAFE_METHOD;

// This method can be called from any thread
- (BOOL) os_windowShouldClose                      MULLE_OBJC_THREADSAFE_METHOD;

//
// All defined in the protocol already
// All must be called from the mainThread unless specifically noted
//
- (struct CGPixelSize) os_framebufferSize          MULLE_UI_MAIN_THREAD_ONLY;

- (CGPoint) os_windowPosition                      MULLE_UI_MAIN_THREAD_ONLY;
- (CGSize) os_windowSize                           MULLE_UI_MAIN_THREAD_ONLY;
- (CGRect) os_windowFrame                          MULLE_UI_MAIN_THREAD_ONLY;
- (CGVector) os_UIScale                            MULLE_UI_MAIN_THREAD_ONLY;

- (void) os_setWindowPosition:(CGPoint) position   MULLE_UI_MAIN_THREAD_ONLY;
- (void) os_setWindowSize:(CGSize) size            MULLE_UI_MAIN_THREAD_ONLY;
- (void) os_setWindowFrame:(CGRect) rect           MULLE_UI_MAIN_THREAD_ONLY;


- (void) os_show                                   MULLE_UI_MAIN_THREAD_ONLY;
- (void) os_hide                                   MULLE_UI_MAIN_THREAD_ONLY;
- (void) os_destroyWindow                          MULLE_UI_MAIN_THREAD_ONLY;

// query function to check what context we got
// there must be an active context for these methods to work
- (char *) os_contextInfoUTF8String                MULLE_UI_MAIN_THREAD_ONLY;
- (char *) os_windowInfoUTF8String                 MULLE_UI_MAIN_THREAD_ONLY;

- (void) os_setTitleUTF8String:(char *) s          MULLE_UI_MAIN_THREAD_ONLY;


- (void) os_setCursor:(void *) cursor              MULLE_UI_MAIN_THREAD_ONLY;

// Capture the cursor for gameplay (GLFW_CURSOR_DISABLED: hidden, unlimited
// virtual movement). Pass NO to restore normal cursor behaviour.
// Note: while captured, locationInWindow in motion events is an unbounded
// virtual position, not a window-relative pixel coordinate. Use deltas
// between frames, not absolute values.
- (void) os_setCursorCaptured:(BOOL) captured      MULLE_UI_MAIN_THREAD_ONLY;

// if the (OpenGL) OS thread is active, then this will return the thread
// who called os_(try)activateGraphicsContext. If he window has no
// graphics context, this will return nil
//
- (NSThread *) activeThread                        MULLE_OBJC_THREADSAFE_METHOD;

//
// OS Pasteboard (Might need to be moved to UIApplication)
// prefix with os ?
- (char *) pasteboardCString                       MULLE_UI_MAIN_THREAD_ONLY;
- (void) setPasteboardCString:(char *) s           MULLE_UI_MAIN_THREAD_ONLY;

//
// this checks "needsRefresh", if set to yes it unconditionally refreshes
// if no, it refrehes if the frameRate is not 0.0 or Async and refresh has
// been reached
//
- (mulle_relativetime_t) displayFrameIfNeeded:(mulle_absolutetime_t) now;

@end

void   GLFWOSWindowEventDefaultCallback( id <UIOSWindow> window, UIWindowEvent *event);
void   GLFWOSWindowRetainedEventDefaultCallback( id <UIOSWindow> window, UIEvent *retainedEvent);


//
// Why is it relative time ? For animation purposes its more useful
// to use CLOCK_MONOTONIC:
// https://stackoverflow.com/questions/3523442/difference-between-clock-realtime-and-clock-monotonic
//

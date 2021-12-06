//
// Copyright (c) 2021 Nat!, Mulle kybernetiK
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
@class GLFWWindow;

//   3         2         1         0
//  10987654321098765432109876543210
//
//  ppfaallMMMMMMMMmmmmmmmmmmmmmmmmm
//  77776666555544443333222211110000
//
// profile : GLFW_OPENGL_PROFILE          (0=any, 1=core, 2=compat)
// forward : GLFW_OPENGL_FORWARD_COMPAT   (0=NO, 1=YES)
// api     : GLFW_CLIENT_API              (0=NONE, 1=OpenGLES, 2=OpenGL)
// lib     : GLFW_CONTEXT_CREATION_API    (0=native,1=egl,2=mesa)
// major   : GLFW_CONTEXT_VERSION_MAJOR
// minor   : GLFW_CONTEXT_VERSION_MINOR

#define GLFWGraphicsHintsMake( profile, forward, api, lib, major, minor) \
  ((((profile) & 0x3) << 30)    | \
   (((forward) & 0x1) << 29) | \
   (((api) & 0x3) << 27) | \
   (((lib) & 0x3) << 25) | \
   (((major) & 0xFF) << 17)  | \
   ((minor) & 0x01FFFF))

//
enum GLFWGraphicsHints
{
   GLFW_DEFAULT_CONTEXT = 0,
   GLFW_GL3_CONTEXT     = GLFWGraphicsHintsMake( 0, 0, 2, 0, 3, 0),
   GLFW_GL3_2_CONTEXT   = GLFWGraphicsHintsMake( 0, 0, 2, 0, 3, 2),
   GLFW_GLES2_CONTEXT   = GLFWGraphicsHintsMake( 0, 0, 1, 0, 2, 0),
   GLFW_GLES3_CONTEXT   = GLFWGraphicsHintsMake( 0, 0, 1, 0, 3, 0)
};


static int GLFWGraphicsHintsGetProfile( enum GLFWGraphicsHints t)
{
   return( (t >> 30) & 0x3);
}

static int GLFWGraphicsHintsGetForward( enum GLFWGraphicsHints t)
{
   return( (t >> 29) & 0x1);
}

static int GLFWGraphicsHintsGetAPI( enum GLFWGraphicsHints t)
{
   return( (t >> 27) & 0x3);
}

static int GLFWGraphicsHintsGetAPILibrary( enum GLFWGraphicsHints t)
{
   return( (t >> 25) & 0x3);
}

static int GLFWGraphicsHintsGetMajor( enum GLFWGraphicsHints t)
{
   return( (t >> 17) & 0xFF);
}

static int GLFWGraphicsHintsGetMinor( enum GLFWGraphicsHints t)
{
   return( t & 0x01FFFF);
}


static int GLFWGraphicsHintsBySettingProfile( enum GLFWGraphicsHints t, int profile)
{
   return( GLFWGraphicsHintsMake( profile,
                                  GLFWGraphicsHintsGetForward( t),
                                  GLFWGraphicsHintsGetAPI( t),
                                  GLFWGraphicsHintsGetAPILibrary( t),
                                  GLFWGraphicsHintsGetMajor( t),
                                  GLFWGraphicsHintsGetMinor( t)));
}


static int   GLFWGraphicsHintsBySettingForward( enum GLFWGraphicsHints t, int forward)
{
   return( GLFWGraphicsHintsMake( GLFWGraphicsHintsGetProfile( t),
                                  forward,
                                  GLFWGraphicsHintsGetAPI( t),
                                  GLFWGraphicsHintsGetAPILibrary( t),
                                  GLFWGraphicsHintsGetMajor( t),
                                  GLFWGraphicsHintsGetMinor( t)));
}

static int   GLFWGraphicsHintsBySettingAPI( enum GLFWGraphicsHints t, int api)
{
   return( GLFWGraphicsHintsMake( GLFWGraphicsHintsGetProfile( t),
                                  GLFWGraphicsHintsGetForward( t),
                                  api,
                                  GLFWGraphicsHintsGetAPILibrary( t),
                                  GLFWGraphicsHintsGetMajor( t),
                                  GLFWGraphicsHintsGetMinor( t)));
}

static int   GLFWGraphicsHintsBySettingAPILibrary( enum GLFWGraphicsHints t, int library)
{
   return( GLFWGraphicsHintsMake( GLFWGraphicsHintsGetProfile( t),
                                  GLFWGraphicsHintsGetForward( t),
                                  GLFWGraphicsHintsGetAPI( t),
                                  library,
                                  GLFWGraphicsHintsGetMajor( t),
                                  GLFWGraphicsHintsGetMinor( t)));
}




@protocol GLFWWindowEventReceiver

- (void) handleWindowEvent:(UIEvent *) event;
- (void) queueRetainedEvent:(UIEvent *) event;

@end

//
// Why is it relative time ? For animation purposes its more useful
// to use CLOCK_MONOTONIC:
// https://stackoverflow.com/questions/3523442/difference-between-clock-realtime-and-clock-monotonic
//
typedef void   (*GLFWWindowEventCallback_t)( GLFWWindow *window, UIWindowEvent *event);
typedef void   (*GLFWWindowRetainedEventCallback_t)( GLFWWindow *window, UIEvent *retainedEvent);
typedef void   (*GLFWWindowRenderCallback_t)( GLFWWindow *window, CARelativeTime now);
typedef void   (*GLFWTimerCallback_t)( GLFWWindow *window, CARelativeTime now, id userInfo);

//
// The GLFWWindow has the GLFW window handle and implicitly the
// drawing context. A UIWindow will have possibly two GLFWWindows
// associated with it. One for drawing offscreen and one for display onscreen.
// Events for the window are forwarded from here.
//
// If you create GLFWWindow manually, be sure to finalize them before
// -[UIApplication terminate], otherwise the context is gone and finalization
// may not be able to finish.
//
@interface GLFWWindow : NSObject < UIWindow>
{
   void                  *_window;   // GLFWwindow handle

   NSLock                *_contextLock;

   CGPoint               _mouseLocation;
   uint64_t              _mouseButtonStates;
   uint64_t              _modifiers;

   GLFWWindow            *_sharingWindow;
   NSInteger             _shareId;

   GLFWTimerCallback_t   _timerCallback;
   CARelativeTime        _lastTimerCall;
   CARelativeTime        _timerDelay;
   id                    _timerUserInfo;
}

// window events are called via -handleEvent:
// event is autoreleased
@property( assign) id <GLFWWindowEventReceiver>        windowEventsReceiver;

// window events are called via -queueRetainedEvent:
// event must be released by receiver!
@property( assign) id <GLFWWindowEventReceiver>        eventsReceiver;

// if you chose to overwrite eventsCallback, the eventsReceiver
// and the windowEventsReceiver will not get anything. Setting either will
// also enable OS events for windowEvents or other

// default: GLFWWindowEventDefaultCallback
@property( assign) GLFWWindowEventCallback_t           windowEventsCallback;
// default: GLFWWindowRetainedEventDefaultCallback
@property( assign) GLFWWindowRetainedEventCallback_t   otherEventsCallback;
//
// very basic rendering and event support. Does not use CGContext!
// view port is not setup and framebuffer is not cleared!
@property( assign) GLFWWindowRenderCallback_t          renderCallback;

@property( assign) NSUInteger                          discardEventsMask;
@property( assign) CGFloat                             scrollWheelSensitivity;
@property( assign, getter=isScrollWheelNatural) BOOL   scrollWheelNatural;

@property( assign, readonly) NSUInteger                styleMask;


- (NSInteger) shareId;

+ (CGFloat) os_primaryMonitorPPI;
+ (CGFloat) os_primaryMonitorRefreshRate;


+ (instancetype) windowWithFrame:(CGRect) frame
                 titleUTF8String:(char *) title
                       styleMask:(NSUInteger) styleMask
                   graphicsHints:(enum GLFWGraphicsHints) graphicsHints;

// sharingWindow is retained. We will be able to share textures with it
+ (instancetype) windowWithFrame:(CGRect) frame
                 titleUTF8String:(char *) title
                       styleMask:(NSUInteger) styleMask
                   graphicsHints:(enum GLFWGraphicsHints) graphicsHints
                   sharingWindow:(GLFWWindow *) sharingWindow;

- (instancetype) initWithFrame:(CGRect) frame
               titleUTF8String:(char *) title
                     styleMask:(NSUInteger) styleMask
                 graphicsHints:(enum GLFWGraphicsHints) graphicsHints;

// sharingWindow is retained. We will be able to share textures with it
- (instancetype) initWithFrame:(CGRect) frame
               titleUTF8String:(char *) title
                     styleMask:(NSUInteger) styleMask
                 graphicsHints:(enum GLFWGraphicsHints) graphicsHints
                 sharingWindow:(GLFWWindow *) sharingWindow;

- (void) os_destroyWindow;

- (void *) os_window;         // GLFW window, use this for glfw functions

- (CGSize) os_windowSize;
- (CGRect) os_windowFrame;
- (void) os_setSwapInterval:(NSUInteger) value;

// bind GL context of the window to the current thread
// synonymous with activate
- (void) os_activateContext;
- (void) os_deactivateContext;
- (struct CGBitmapSize) os_framebufferSize;
- (void) os_swapBuffers;

- (void) os_requestClose;
- (BOOL) os_windowShouldClose;

- (void) os_show;
- (void) os_hide;

// query function to check what context we got
- (char *) os_contextInfoUTF8String;

//
// OS Pasteboard
// prefix with os ?
- (char *) pasteboardCString;
- (void) setPasteboardCString:(char *) s;

- (void) renderLoopHz:(CGFloat) frameRate;
- (void) renderFrame:(CAAbsoluteTime) now;

// CLOCK_MONOTONIC
- (CARelativeTime) os_getRelativeTime;

//
// this is to simulate glutTimerFunc
// NSTimer it is not...
//
- (void) setTimerCallback:(GLFWTimerCallback_t) timer
                    delay:(CARelativeTime) delay
                 userInfo:(id) userinfo;
@end


void   GLFWWindowEventDefaultCallback( GLFWWindow *window, UIWindowEvent *event);
void   GLFWWindowRetainedEventDefaultCallback( GLFWWindow *window, UIEvent *retainedEvent);

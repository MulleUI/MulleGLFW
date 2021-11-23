//
// Copyright (c) 2021 Nat!, Mulle kybernetiK
//
#ifdef __has_include
# if __has_include( "NSObject.h")
#  import "NSObject.h"
# endif
#endif

#import "import.h"

#import "UIWindowTypes.h"


@class UIEvent;
@class UIWindowEvent;
@class CGContext;
@class GLFWWindow;
//   3         2         1         0
//  10987654321098765432109876543210
//
//  cMMMMMMMMmmmmmmmmmmmmmmmmmmmmmmm
//  77776666555544443333222211110000
#define GLFWGraphicsHintsMake( core, major, minor) \
  (((core & 0x1) << 31) | ((major & 0xFF) << 23) | ((minor) & 0x7FFFFF))


enum GLFWGraphicsHints
{
   GLFW_DEFAULT_CONTEXT = 0,
   GLFW_GL3_CONTEXT     = GLFWGraphicsHintsMake( 1, 3, 2),
   GLFW_GLES2_CONTEXT   = GLFWGraphicsHintsMake( 0, 2, 0),
   GLFW_GLES3_CONTEXT   = GLFWGraphicsHintsMake( 1, 3, 0)
};

static int GLFWGraphicsHintsGetCore( enum GLFWGraphicsHints t)
{
  return( (t >> 31) & 0x1);
}

static int GLFWGraphicsHintsGetMajor( enum GLFWGraphicsHints t)
{
  return( (t >> 23) & 0xFF);
}

static int GLFWGraphicsHintsGetMinor( enum GLFWGraphicsHints t)
{
  return( t & 0x7FFFFF);
}



@protocol GLFWWindowEventReceiver

- (void) handleWindowEvent:(UIEvent *) event;
- (void) queueRetainedEvent:(UIEvent *) event;

@end

typedef void   (*GLFWWindowEventCallback_t)( GLFWWindow *window, UIWindowEvent *event);
typedef void   (*GLFWWindowRetainedEventCallback_t)( GLFWWindow *window, UIEvent *retainedEvent);

typedef void   (*GLFWTimerCallback_t)( GLFWWindow *window, CAAbsoluteTime now, id userInfo);

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
   CAAbsoluteTime        _lastTimerCall;
   CARelativeTime        _timerDelay;
   id                    _timerUserInfo;
}

// window events are called via -handleEvent:
// event is autoreleased
@property( assign) id <GLFWWindowEventReceiver>  windowEventsReceiver;

// window events are called via -queueRetainedEvent:
// event must be released by receiver!
@property( assign) id <GLFWWindowEventReceiver>  eventsReceiver;

// if you chose to overwrite eventsCallback, the eventsReceiver
// and the windowEventsReceiver will not get anything. Setting either will
// also enable OS events for windowEvents or other

// default: GLFWWindowEventDefaultCallback
@property( assign) GLFWWindowEventCallback_t           windowEventsCallback;
// default: GLFWWindowRetainedEventDefaultCallback
@property( assign) GLFWWindowRetainedEventCallback_t   otherEventsCallback;

@property( assign) NSUInteger  discardEventsMask;
@property( assign) CGFloat     scrollWheelSensitivity;
@property( assign, getter=isScrollWheelNatural) BOOL scrollWheelNatural;

//
// very basic rendering and event support. Does not use CGContext!
// view port is not setup and framebuffer is not cleared!
@property void   (*renderCallback)( GLFWWindow *window,
                                    struct CGFrameInfo *info);

- (NSInteger) shareId;

+ (CGFloat) os_primaryMonitorPPI;
+ (CGFloat) os_primaryMonitorRefreshRate;

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


//
// OS Pasteboard
// prefix with os ?
- (char *) pasteboardCString;
- (void) setPasteboardCString:(char *) s;



- (void) renderLoopHz:(CGFloat) frameRate;
- (void) renderFrame;

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

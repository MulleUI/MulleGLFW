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
@class GLFWOSWindow;


#define  GLFWOSWindowStyleMaskDefault (0)

//   3         2         1         0
//  10987654321098765432109876543210
//
//  ppfaallMMMMMMMMmmmmmmmmmmmmmmmmm
//  77776666555544443333222211110000
//
// profile : GLFW_OPENGL_PROFILE          (0=any, 1=core, 2=compat)
// forward : GLFW_OPENGL_FORWARD_COMPAT   (0=NO, 1=YES)
// api     : GLFW_CLIENT_API              (0=default, 1=NONE, 2=OpenGLES, 3=OpenGL)
// lib     : GLFW_CONTEXT_CREATION_API    (0=native,1=egl,2=mesa)
// major   : GLFW_CONTEXT_VERSION_MAJOR
// minor   : GLFW_CONTEXT_VERSION_MINOR

#define GLFWGraphicsHintsMake( profile, forward, api, lib, major, minor) \
  ((((profile) & 0x3) << 30)  | \
   (((forward) & 0x1) << 29)  | \
   (((api)     & 0x3) << 27)  | \
   (((lib)     & 0x3) << 25)  | \
   (((major)   & 0xFF) << 17) | \
    ((minor)   & 0x01FFFF))

//
// GLFW_DEFAULT_CONTEXT is often the best choice
//
enum GLFWGraphicsHints
{
   GLFW_DEFAULT_CONTEXT = 0,
   GLFW_NO_CONTEXT      = GLFWGraphicsHintsMake( 0, 0, 1, 0, 0, 0),
   GLFW_GL3_CONTEXT     = GLFWGraphicsHintsMake( 0, 0, 3, 0, 3, 0),
   GLFW_GL3_2_CONTEXT   = GLFWGraphicsHintsMake( 0, 0, 3, 0, 3, 2),
   GLFW_GLES2_CONTEXT   = GLFWGraphicsHintsMake( 0, 0, 2, 0, 2, 0),
   GLFW_GLES3_CONTEXT   = GLFWGraphicsHintsMake( 0, 0, 2, 0, 3, 0)
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




//
// Why is it relative time ? For animation purposes its more useful
// to use CLOCK_MONOTONIC:
// https://stackoverflow.com/questions/3523442/difference-between-clock-realtime-and-clock-monotonic
//
typedef void   (*GLFWOSWindowEventCallback_t)( GLFWOSWindow *window, UIWindowEvent *event);
typedef void   (*GLFWOSWindowRetainedEventCallback_t)( GLFWOSWindow *window, UIEvent *retainedEvent);
typedef void   (*GLFWOSWindowFrameCallback_t)( GLFWOSWindow *window);

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
@interface GLFWOSWindow : NSObject < UIWindow>
{
   void                     *_window;   // GLFWwindow handle

   NSLock                   *_contextLock;

   CGPoint                  _mouseLocation;
   uint64_t                 _mouseButtonStates;
   uint64_t                 _modifiers;

   GLFWOSWindow             *_sharingWindow;
   NSInteger                _shareId;

   mulle_absolutetime_t     _lastSwapBuffersTimestamp;
   mulle_atomic_pointer_t   _needsRefresh;
   struct CGWindowInfo      _windowInfo;
}


// window events are called via -handleEvent:
// event is autoreleased
@property( assign) id <UIEventReceiver>        windowEventsReceiver;

// window events are called via -handleRetainedEvent:
// event must be released by receiver!
@property( assign) id <UIEventReceiver>        eventsReceiver;

// if you chose to overwrite eventsCallback, the eventsReceiver
// and the windowEventsReceiver will not get anything. Setting either will
// also enable OS events for windowEvents or other

// default: GLFWOSWindowEventDefaultCallback
@property( assign) GLFWOSWindowEventCallback_t           windowEventsCallback;
// default: GLFWOSWindowRetainedEventDefaultCallback
@property( assign) GLFWOSWindowRetainedEventCallback_t   otherRetainedEventsCallback;
//
// very basic rendering and event support. Does not use CGContext!
// view port is not setup and framebuffer is not cleared!
@property( assign) GLFWOSWindowFrameCallback_t         frameCallback;

@property( assign) NSUInteger                          discardEventsMask;
@property( assign) CGFloat                             scrollWheelSensitivity;
@property( assign, getter=isScrollWheelNatural) BOOL   scrollWheelNatural;

@property( assign, readonly) NSUInteger                styleMask;
@property( assign) double                              frameRate;
@property( assign, readonly) BOOL                      haveGraphicsContext;
@property( assign) id <UIWindow>                       parentWindow;


+ (instancetype) windowWithFrame:(CGRect) frame
                 titleUTF8String:(char *) title
                       styleMask:(NSUInteger) styleMask
                   graphicsHints:(enum GLFWGraphicsHints) graphicsHints;

+ (instancetype) windowWithFrame:(CGRect) frame
                 titleUTF8String:(char *) title
                       styleMask:(NSUInteger) styleMask;

// sharingWindow is retained. We will be able to share textures with it
+ (instancetype) windowWithFrame:(CGRect) frame
                 titleUTF8String:(char *) title
                       styleMask:(NSUInteger) styleMask
                   graphicsHints:(enum GLFWGraphicsHints) graphicsHints
                   sharingWindow:(id <UIOSWindow>) sharingWindow;

- (instancetype) initWithFrame:(CGRect) frame
               titleUTF8String:(char *) title
                     styleMask:(NSUInteger) styleMask
                 graphicsHints:(enum GLFWGraphicsHints) graphicsHints;

- (instancetype) initWithFrame:(CGRect) frame
               titleUTF8String:(char *) title
                     styleMask:(NSUInteger) styleMask;

// sharingWindow is retained. We will be able to share textures with it
- (instancetype) initWithFrame:(CGRect) frame
               titleUTF8String:(char *) title
                     styleMask:(NSUInteger) styleMask
                 graphicsHints:(enum GLFWGraphicsHints) graphicsHints
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
- (void) getWindowInfo:(struct CGWindowInfo *) info;


- (NSInteger) shareId;

// all defined in the protocol already

- (double) os_primaryMonitorPPI;
- (double) os_primaryMonitorRefreshRate;
- (double) os_monitorRefreshRate;


- (void) os_destroyWindow;

- (void *) os_window;         // GLFW window, use this for glfw functions

- (CGPoint) os_windowPosition;
- (void) os_setWindowPosition:(CGPoint) position;
- (CGSize) os_windowSize;
- (void) os_setWindowSize:(CGSize) size;
- (CGRect) os_windowFrame;
- (void) os_setWindowFrame:(CGRect) rect;
- (void) os_setWindowSize:(CGSize) size;
- (void) os_setSwapInterval:(NSUInteger) value;

- (struct CGBitmapSize) os_framebufferSize;

// bind GL context of the window to the current thread
// synonymous with activate
- (void) os_activateGraphicsContext;
- (void) os_deactivateGraphicsContext;
- (void) os_swapBuffers;

- (void) os_requestClose;
- (BOOL) os_windowShouldClose;

- (BOOL) shouldClose;

- (void) os_show;
- (void) os_hide;

// query function to check what context we got
- (char *) os_contextInfoUTF8String;
- (char *) os_windowInfoUTF8String;

- (void) os_setTitleUTF8String:(char *) s;


//
// OS Pasteboard
// prefix with os ?
- (char *) pasteboardCString;
- (void) setPasteboardCString:(char *) s;

//
// this checks "needsRefresh", if set to yes it unconditionally refreshes
// if no, it refrehes if the frameRate is not 0.0 or Async and refresh has
// been reached
//
- (mulle_relativetime_t) displayFrameIfNeeded:(mulle_absolutetime_t) now;

// CLOCK_MONOTONIC
- (mulle_absolutetime_t) os_getAbsoluteTime;

@end


void   GLFWOSWindowEventDefaultCallback( GLFWOSWindow *window, UIWindowEvent *event);
void   GLFWOSWindowRetainedEventDefaultCallback( GLFWOSWindow *window, UIEvent *retainedEvent);

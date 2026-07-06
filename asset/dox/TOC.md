# MulleGLFW Library Documentation for AI
<!-- Keywords: GLFW, window, events, Objective-C, OpenGL, platform -->

## 1. Introduction & Purpose

MulleGLFW provides platform windows and event handling for the MulleUI framework through an Objective-C wrapper around GLFW3. It serves as the foundational layer for **UIEvent** and **UIApplication** through categories, handling OS-level window management, input events, screen/monitor management, and gamepad support. The library provides the meat and potatoes code for creating platform-specific windows (**GLFWOSWindow**) with OpenGL contexts, managing multiple screens (**GLFWOSScreen**), and handling gamepads (**GLFWOSGamepad**). It is a core dependency within the MulleUI ecosystem and forms the bridge between GLFW's C API and mulle-objc's Objective-C runtime.

MulleGLFW supports multiple platform backends: X11 (Linux default), Wayland (Linux alternative), and macOS. It provides flexible OpenGL context creation with support for various OpenGL versions (3.x, ES2, ES3) and profiles (core, compatibility, forward-compatible).

## 2. Key Concepts & Design Philosophy

### Dual Sourcetree Architecture
MulleGLFW is a dual-sourcetree project allowing selection between X11 and Wayland backends on Linux using `mulle-sde config switch MulleGLFW [x11|wayland]`.

### Threading Model
- **Main Thread Only**: Most window operations, event initialization, and GLFW API calls must execute on the main thread
- **Thread-Safe Methods**: Explicitly marked with `MULLE_OBJC_THREADSAFE_METHOD` - these include context activation, window info queries, and state getters
- **Graphics Context Binding**: OpenGL contexts can be bound to different threads via `os_activateGraphicsContext`/`os_deactivateGraphicsContext`
- **Atomic Operations**: Critical shared state uses `mulle_atomic_pointer_t` for thread-safe access

### Event Handling Architecture
MulleGLFW provides multiple event callback mechanisms:
- **windowEventsCallback**: For window-specific events (resize, move, close, refresh) - calls receiver's `-handleWindowEvent:`
- **otherRetainedEventsCallback**: For retained events (keyboard, mouse, gamepad) - calls receiver's `-receiveRetainedEvent:` (event must be released by receiver)
- **frameCallback**: For rendering frames - does not use CGContext, provides raw OpenGL access
- **Default Callbacks**: `GLFWOSWindowEventDefaultCallback` and `GLFWOSWindowRetainedEventDefaultCallback` forward to receivers

### Graphics Context Management
- **Implicit Contexts**: Each GLFWOSWindow has an implicit OpenGL context
- **Context Sharing**: Windows can share textures via `sharingWindow` parameter (assigned a common `shareID`)
- **Multiple Backends**: Supports OpenGL, OpenGL ES, and NO_API configurations
- **Fallback Strategy**: Can attempt multiple context creation libraries (native, EGL, Mesa) via `UIWindowOpenGLLibraryFallback`

### Style Masks & Hints
Window behavior configured via `NSUInteger` style masks and `GLFWGraphicsHints` enums:
- Style masks control window decoration, resizability, transparency, anti-aliasing
- Graphics hints specify OpenGL version, profile, and API type
- Hints are encoded as bit-packed integers for efficient storage

## 3. Core API & Data Structures

### 3.1. `GLFWOSWindow.h`

#### `@interface GLFWOSWindow : NSObject <UIWindow, UIOSWindow>`
The primary window class wrapping a GLFW window handle.

**Purpose:** Represents a platform window with an OpenGL graphics context. Manages window lifecycle, events, and rendering.

**Key Fields:**
- `void *_window` - GLFW window handle (GLFWwindow*)
- `NSLock *_contextLock` - Protects graphics context operations
- `GLFWOSWindow *_sharingWindow` - Window this window shares textures with (retained)
- `NSInteger _shareID` - Unique ID for texture sharing group (0 = no sharing)
- `mulle_absolutetime_t _lastSwapBuffersTimestamp` - Timing for frame rate control
- `mulle_atomic_pointer_t _needsRefresh` - Flag for refresh requests (thread-safe)
- `mulle_atomic_pointer_t _discardEventsMask` - Mask for filtering events (thread-safe)
- `struct UIOSWindowInfo _windowInfo` - Cached window dimensions and state

**Lifecycle Functions:**

Creation (Main Thread Only):
```objective-c
+ (instancetype) windowWithFrame:(CGRect) frame
                 titleUTF8String:(char *) title
                       styleMask:(NSUInteger) styleMask;

+ (instancetype) windowWithFrame:(CGRect) frame
                 titleUTF8String:(char *) title
                       styleMask:(NSUInteger) styleMask
                   graphicsHints:(GLFWGraphicsHints) graphicsHints;

+ (instancetype) windowWithFrame:(CGRect) frame
                 titleUTF8String:(char *) title
                       styleMask:(NSUInteger) styleMask
                   graphicsHints:(GLFWGraphicsHints) graphicsHints
                   sharingWindow:(id <UIOSWindow>) sharingWindow;

- (instancetype) initWithFrame:(CGRect) frame
               titleUTF8String:(char *) title
                     styleMask:(NSUInteger) styleMask
                 graphicsHints:(GLFWGraphicsHints) graphicsHints
                 sharingWindow:(id <UIOSWindow>) sharingWindow;
```

**Style Mask Constants:**
- `GLFWOSWindowStyleMaskDefault` - Default window style (0)
- Combined with `UIWindowStyle*` flags: `UIWindowStyleBare`, `UIWindowStyleResizable`, `UIWindowStyleFloating`, `UIWindowStyleTransparent`, `UIWindowStyleAntiAlias`, `UIWindowStyleSingleBuffer`, `UIWindowStyleHidden`, `UIWindowOpenGLDeprecated`, `UIWindowOpenGLForward`, `UIWindowOpenGLCoreProfile`, `UIWindowOpenGLLibraryFallback`

**Graphics Hints:**
- `GLFWGraphicsHints` - Bit-packed enum encoding profile, forward-compat, API, library, major, minor
- Predefined: `GLFWGraphicsHintsDefault`, `GLFWGraphicsHintsNone`, `GLFWGraphicsHintsGL3`, `GLFWGraphicsHintsGL3_2`, `GLFWGraphicsHintsGLES2`, `GLFWGraphicsHintsGLES3`, `GLFWGraphicsHintsGLES3_2`
- Helper functions: `GLFWGraphicsHintsMake()`, `GLFWGraphicsHintsGetProfile()`, `GLFWGraphicsHintsGetForward()`, `GLFWGraphicsHintsGetAPI()`, `GLFWGraphicsHintsGetAPILibrary()`, `GLFWGraphicsHintsGetMajor()`, `GLFWGraphicsHintsGetMinor()`, `GLFWGraphicsHintsBySettingProfile()`, etc.

**Properties:**

Event Receivers:
- `id <UIEventReceiver> windowEventsReceiver` - Receives window events via `-handleWindowEvent:` (event is autoreleased)
- `id <UIEventReceiver> eventsReceiver` - Receives retained events via `-receiveRetainedEvent:` (event must be released by receiver)

Callbacks:
- `UIOSWindowEventCallback_t windowEventsCallback` - Default: `GLFWOSWindowEventDefaultCallback`
- `UIOSWindowRetainedEventCallback_t otherRetainedEventsCallback` - Default: `GLFWOSWindowRetainedEventDefaultCallback`
- `UIOSWindowFrameCallback_t frameCallback` - Custom rendering callback (no CGContext)

State (readonly):
- `BOOL haveGraphicsContext` - Whether window has an OpenGL context
- `NSUInteger styleMask` - Window style flags used at creation
- `id <UIGraphicsContext> renderGraphicsContext` - Always nil (GLFW has no drawing functionality)
- `BOOL antiAliasing` - Whether MSAA is enabled
- `struct UIInputState inputState` - Current keyboard/mouse state
- `UIGraphicsBackend backend` - OpenGL version detected (e.g., `UIGraphicsBackendGL3_2Forward`)

Configuration:
- `mulle_relativetime_t frameRate` (thread-safe) - Target frame rate (0.0 = on-demand)
- `NSUInteger discardEventsMask` (thread-safe) - Mask to filter unwanted events
- `CGFloat scrollWheelSensitivity` - Multiplier for scroll events
- `BOOL scrollWheelNatural` - Natural scrolling direction
- `id <UIWindow> parentWindow` - Parent window reference
- `NSUInteger debuggingFlags` (thread-safe) - Debug output control
- `BOOL uninitializedFramebuffer` - Whether framebuffer needs initial clear

**Window Information (Thread-Safe):**
```objective-c
- (void) getOSWindowInfo:(struct UIOSWindowInfo *) info;
- (id <UIScreen>) screen;
- (id <UIScreen>) screenOrPrimaryScreen:(BOOL) flag;
- (NSInteger) shareID;
- (BOOL) shouldClose;
```

**Graphics Context Operations (Thread-Safe):**
```objective-c
- (void) os_activateGraphicsContext;      // Bind GL context to current thread
- (void) os_deactivateGraphicsContext;    // Unbind GL context from current thread
- (BOOL) os_tryActivateGraphicsContext;   // Non-blocking activation attempt
- (void) os_swapBuffers;                  // Present rendered frame
- (void) os_setSwapInterval:(NSUInteger) value;  // Set vsync (0=off, 1=on)
- (void *) os_window;                     // Get raw GLFW window handle
- (NSThread *) activeThread;              // Thread that activated context (nil if none)
```

**Window Management (Main Thread Only):**
```objective-c
- (struct CGPixelSize) os_framebufferSize;
- (CGPoint) os_windowPosition;
- (CGSize) os_windowSize;
- (CGRect) os_windowFrame;
- (CGVector) os_UIScale;

- (void) os_setWindowPosition:(CGPoint) position;
- (void) os_setWindowSize:(CGSize) size;
- (void) os_setWindowFrame:(CGRect) rect;
- (void) os_setTitleUTF8String:(char *) s;
- (void) os_setCursor:(void *) cursor;

- (void) os_show;
- (void) os_hide;
- (void) os_destroyWindow;
- (void) os_requestClose;
- (BOOL) os_windowShouldClose;
```

**Inspection (Main Thread Only):**
```objective-c
- (char *) os_contextInfoUTF8String;  // OpenGL version info
- (char *) os_windowInfoUTF8String;   // Window properties
```

**Pasteboard (Main Thread Only):**
```objective-c
- (char *) pasteboardCString;
- (void) setPasteboardCString:(char *) s;
```

**Frame Display:**
```objective-c
- (mulle_relativetime_t) displayFrameIfNeeded:(mulle_absolutetime_t) now;
```
Checks `needsRefresh` flag and frame rate to determine if rendering should occur.

**Default Callback Functions:**
```c
void GLFWOSWindowEventDefaultCallback( id <UIOSWindow> window, UIWindowEvent *event);
void GLFWOSWindowRetainedEventDefaultCallback( id <UIOSWindow> window, UIEvent *retainedEvent);
```

### 3.2. `GLFWOSWindow+UIEvent.h`

#### `@interface GLFWOSWindow (UIEvent)`
Category providing event system initialization.

**Purpose:** Initialize GLFW callbacks for window and input events.

**Core Methods:**
```objective-c
- (void) os_initEvents;             // Initialize both window and input events
- (void) os_initWindowEvents;       // Initialize window callbacks (move, resize, close, refresh)
- (void) os_initInputEvents;        // Initialize input callbacks (keyboard, mouse, scroll)
- (void) updateWindowInfo;          // Update cached window info
- (void) os_pollInputState:(struct UIInputState *) state;  // Query current input state
```

### 3.3. `GLFWOSScreen.h`

#### `@interface GLFWOSScreen : NSObject <UIScreen>`
Represents a physical monitor/display.

**Purpose:** Wraps GLFW monitor handles to provide screen information and management.

**Key Fields:**
- `void *_monitor` - GLFW monitor handle (GLFWmonitor*)
- `struct UIScreenInfo _info` - Cached screen properties (frame, DPI, refresh rate)
- `NSLock *_infoLock` - Protects screen info

**Lifecycle Functions:**
```objective-c
+ (NSUInteger) numberOfScreens;
+ (id <UIScreen>) screenAtIndex:(NSUInteger) i;
- (instancetype) initWithGLFWMonitor:(void *) monitor;
```

**Properties:**
```objective-c
@property (readonly) char *nameUTF8String;  // Thread-safe
```

**Screen Information (Thread-Safe):**
```objective-c
- (void) getScreenInfo:(struct UIScreenInfo *) info;
- (CGRect) frame;                     // Screen bounds in points
- (CGRect) canvas;                    // Usable area (excludes taskbar)
- (mulle_relativetime_t) refreshRate; // Monitor refresh rate in Hz
```

**OS Queries (Main Thread):**
```objective-c
- (char *) os_nameUTF8String;         // Monitor name
- (CGVector) os_contentScale;         // DPI scaling factor
- (CGSize) os_physicalSize;           // Physical size in millimeters
- (CGFloat) os_dpi;                   // Dots per inch
- (CGPixelRect) os_canvas;            // Canvas in pixels
- (CGPixelPoint) os_position;         // Position in virtual desktop
- (BOOL) os_isPrimaryScreen;          // Is this the primary monitor
```

### 3.4. `GLFWOSGamepad.h`

#### `@interface GLFWOSGamepad : NSObject <UIGamepad>`
Represents a gamepad/joystick device.

**Purpose:** Wraps GLFW joystick handles to provide gamepad state and information.

**Key Fields:**
- `int _handle` - GLFW joystick ID (GLFW_JOYSTICK_1..GLFW_JOYSTICK_LAST)
- `struct UIGamepadInfo _info` - Current gamepad state (buttons, axes)
- `struct UIGamepadInfo _previousInfo` - Previous state for delta detection
- `NSLock *_infoLock` - Protects gamepad info

**Lifecycle Functions:**
```objective-c
+ (NSUInteger) numberOfGamepads;
+ (id <UIGamepad>) gamepadAtOSIndex:(NSUInteger) i;
+ (NSRange) osIndexRange;              // Range of valid joystick indices
- (instancetype) initWithOSGamepad:(void *) handle;
```

**Properties:**
```objective-c
@property (readonly) char *nameUTF8String;       // Thread-safe
@property (readonly) char *guidUTF8String;       // Thread-safe
@property (readonly, dynamic) BOOL isJoystick;   // vs gamepad
@property (readonly, dynamic) NSInteger osIndex; // GLFW joystick index
```

**Gamepad State (Thread-Safe):**
```objective-c
- (void) getGamepadInfo:(struct UIGamepadInfo *) info;
```

**Polling (Main Thread Only):**
```objective-c
- (void) os_pollGamepadInfo;  // Update gamepad state from GLFW
```

**OS Queries (Main Thread Only):**
```objective-c
- (char *) os_nameUTF8String;  // Device name
- (char *) os_guidUTF8String;  // Device GUID
```

### 3.5. `MulleObjCDeps+MulleGLFW.h`

#### `@interface MulleObjCDeps (MulleGLFW)`
Dependency declaration for mulle-objc runtime.

**Purpose:** Declares library dependencies for proper load order.

**Core Method:**
```objective-c
+ (struct _mulle_objc_dependency *) dependencies;
```

### 3.6. `UIApplication+GLFW.m` (Category - no public header)

#### `@interface UIApplication (GLFW)`
Private category extending UIApplication with GLFW initialization and event handling.

**Purpose:** Initializes GLFW library, sets up monitor and joystick callbacks, integrates with UIApplication event system.

**Key Methods:**
```objective-c
+ (void) os_initialize;  // Called by UIApplication to init GLFW
```

**Monitor Callbacks:**
- Handles `GLFW_CONNECTED`/`GLFW_DISCONNECTED` events
- Creates `UIScreenEvent` objects
- Forwards to `[UIApp handleScreenEvent:]`

**Gamepad Callbacks:**
- Handles joystick connection/disconnection
- Creates `UIGamepadEvent` objects
- Forwards to `[UIApp handleGamepadEvent:]`

## 4. Performance Characteristics

### Window Creation
- **O(1) per window** - GLFW handles platform-specific creation
- **Context creation can fail** - Library fallback mechanism (native → EGL → Mesa) can retry
- **Thread restriction** - Must be on main thread due to GLFW limitations

### Graphics Context Switching
- **Not negligible** - Context activation has measurable overhead (see test/15-glfw/activate.m)
- **Lock-based synchronization** - `_contextLock` serializes context operations
- **Per-thread binding** - Context can only be active on one thread at a time

### Event Handling
- **Polling-based** - GLFW uses `glfwPollEvents()` called from main thread
- **Callback-driven** - Events invoke Objective-C callbacks synchronously
- **Lock-free flags** - `_needsRefresh` and `_discardEventsMask` use atomic operations

### Screen/Gamepad Queries
- **Cached info** - Screen and gamepad info cached in structs protected by locks
- **Lock overhead** - Thread-safe getters acquire lock briefly
- **Polling required** - Gamepad state must be explicitly polled

### Frame Rate Control
- **Time-based** - Uses `mulle_absolutetime_t` for precise timing
- **Conditional refresh** - `displayFrameIfNeeded:` checks flags and timing
- **VSync support** - `os_setSwapInterval:` controls buffer swapping

### Thread Safety
- **Most operations: Main thread only** - GLFW API restriction
- **Atomic operations: Lock-free** - Flags use `mulle_atomic_pointer_t`
- **Context operations: Lock-based** - `_contextLock` protects activation
- **Info getters: Lock-based** - `_infoLock` protects cached state

## 5. AI Usage Recommendations & Patterns

### Best Practices

1. **Always initialize UIApplication first**: GLFW is initialized via `[UIApplication os_initialize]`
   ```objective-c
   UIApplication *app = [UIApplication sharedInstance];  // Initializes GLFW
   ```

2. **Create windows on main thread**: Never create windows from background threads
   ```objective-c
   assert( [NSThread mulleIsMainThread]);
   GLFWOSWindow *window = [GLFWOSWindow windowWithFrame:frame
                                        titleUTF8String:"Title"
                                              styleMask:styleMask];
   ```

3. **Wrap windows in autorelease pools**: Ensures proper cleanup before `[app terminate]`
   ```objective-c
   @autoreleasepool
   {
      window = [[[GLFWOSWindow alloc] initWithFrame:frame
                                    titleUTF8String:title
                                          styleMask:mask] autorelease];
      // Use window
   }
   [app terminate];  // Windows finalized before GLFW termination
   ```

4. **Set frameCallback before rendering**: Every window needs a frame callback
   ```objective-c
   [window setFrameCallback:myFrameCallback];
   ```

5. **Use thread-safe methods from background threads**: Check method signatures
   ```objective-c
   // Safe from any thread:
   [window os_activateGraphicsContext];
   [window getOSWindowInfo:&info];
   NSInteger shareID = [window shareID];
   
   // Main thread only:
   CGRect frame = [window os_windowFrame];
   [window os_show];
   ```

6. **Initialize events after window creation**:
   ```objective-c
   [window os_initEvents];
   ```

7. **Share contexts for texture sharing**:
   ```objective-c
   GLFWOSWindow *window1 = [GLFWOSWindow windowWithFrame:frame1 ...];
   GLFWOSWindow *window2 = [GLFWOSWindow windowWithFrame:frame2
                                         titleUTF8String:"Window 2"
                                               styleMask:mask
                                           graphicsHints:hints
                                           sharingWindow:window1];
   // window1 and window2 can now share textures
   ```

### Common Pitfalls

1. **Don't create windows off main thread**: Will crash or fail
2. **Don't forget to finalize windows before app terminate**: Context will be gone
3. **Don't assume immediate GLFW state updates**: During resize, cached info may lag
4. **Don't mix retained and non-retained event callbacks**: Choose one pattern
5. **Don't free retained events in default callback**: Receiver owns the event
6. **Don't call os_* methods from wrong thread**: Check `MULLE_OBJC_THREADSAFE_METHOD` markers
7. **Don't use alloc/init directly**: Use provided class methods that call autorelease
8. **Don't rely on OpenGL < 3.0 with forward-compatible**: Forward compat removes deprecated APIs

### Idiomatic Usage

**Pattern 1: Basic Window Setup**
```objective-c
UIApplication   *app = [UIApplication sharedInstance];

@autoreleasepool
{
   GLFWOSWindow   *window;
   
   window = [GLFWOSWindow windowWithFrame:CGRectMake( 0, 0, 800, 600)
                          titleUTF8String:"My Application"
                                styleMask:UIWindowStyleBare];
   [window os_initEvents];
   [window setFrameCallback:frameCallback];
   [window setWindowEventsReceiver:myReceiver];
   [window os_show];
   
   [app run];  // Main event loop
}
[app terminate];
```

**Pattern 2: OpenGL Context Selection**
```objective-c
// Request OpenGL 3.2 Core Profile
GLFWGraphicsHints hints = GLFWGraphicsHintsGL3_2;
hints = GLFWGraphicsHintsBySettingProfile( hints, 2);  // Core profile

GLFWOSWindow *window = [GLFWOSWindow windowWithFrame:frame
                                     titleUTF8String:"OpenGL 3.2"
                                           styleMask:UIWindowStyleBare
                                       graphicsHints:hints];
```

**Pattern 3: Multi-threaded Rendering**
```objective-c
// Main thread creates window
GLFWOSWindow *window = [GLFWOSWindow windowWithFrame:frame
                                     titleUTF8String:"Title"
                                           styleMask:mask];

// Render thread
dispatch_async( renderQueue, ^{
   [window os_activateGraphicsContext];
   
   // Render loop
   while( ![window shouldClose])
   {
      // OpenGL calls here
      [window os_swapBuffers];
   }
   
   [window os_deactivateGraphicsContext];
});
```

**Pattern 4: Event Receiver Setup**
```objective-c
@interface MyWindowController : NSObject <UIEventReceiver>
@end

@implementation MyWindowController

- (void) handleWindowEvent:(UIWindowEvent *) event
{
   // Event is autoreleased, don't release it
   switch( [event windowEventType])
   {
      case UIWindowEventTypeResize:
         // Handle resize
         break;
      case UIWindowEventTypeClose:
         // Handle close
         break;
   }
}

- (void) receiveRetainedEvent:(NS_CONSUMED UIEvent *) event
{
   // Event is retained, you MUST release it
   @try
   {
      // Handle mouse/keyboard events
   }
   @finally
   {
      [event release];
   }
}

@end

// Usage:
MyWindowController *controller = [[MyWindowController alloc] init];
[window setWindowEventsReceiver:controller];
[window setEventsReceiver:controller];
```

## 6. Integration Examples

### Example 1: Creating a Basic Window with OpenGL 3.2

```c
#import <MulleGLFW/MulleGLFW.h>

static UIWindowDisplayBits   frameCallback( id <UIOSWindow> window)
{
   GLFWOSWindow      *glfwWindow;
   struct CGPixelSize   framebufferSize;
   
   glfwWindow       = (GLFWOSWindow *) window;
   framebufferSize  = [glfwWindow os_framebufferSize];
   
   // Setup viewport
   glViewport( 0, 0, framebufferSize.width, framebufferSize.height);
   
   // Clear to black
   glClearColor( 0.0, 0.0, 0.0, 1.0);
   glClear( GL_COLOR_BUFFER_BIT);
   
   // Draw something
   // ... your OpenGL code here ...
   
   return( 0);  // 0 = no animation, 1 = continuous animation
}


int   main( void)
{
   UIApplication   *app;
   GLFWOSWindow    *window;
   
   app = [UIApplication sharedInstance];
   
   @autoreleasepool
   {
      window = [GLFWOSWindow windowWithFrame:CGRectMake( 100, 100, 640, 480)
                             titleUTF8String:"OpenGL Window"
                                   styleMask:UIWindowStyleBare
                               graphicsHints:GLFWGraphicsHintsGL3_2];
      if( ! window)
      {
         fprintf( stderr, "Failed to create window\n");
         return( 1);
      }
      
      [window os_initEvents];
      [window setFrameCallback:frameCallback];
      [window os_show];
      
      [app run];
   }
   [app terminate];
   
   return( 0);
}
```

### Example 2: Multiple Windows with Texture Sharing

```c
#import <MulleGLFW/MulleGLFW.h>

int   main( void)
{
   UIApplication   *app;
   GLFWOSWindow    *window1;
   GLFWOSWindow    *window2;
   NSInteger       shareID;
   
   app = [UIApplication sharedInstance];
   
   @autoreleasepool
   {
      // Create first window
      window1 = [[[GLFWOSWindow alloc] initWithFrame:CGRectMake( 0, 0, 320, 240)
                                     titleUTF8String:"Window 1"
                                           styleMask:UIWindowStyleBare
                                       graphicsHints:GLFWGraphicsHintsDefault] autorelease];
      
      // Create second window that shares textures with first
      window2 = [[[GLFWOSWindow alloc] initWithFrame:CGRectMake( 330, 0, 320, 240)
                                     titleUTF8String:"Window 2"
                                           styleMask:UIWindowStyleBare
                                       graphicsHints:GLFWGraphicsHintsDefault
                                       sharingWindow:window1] autorelease];
      
      if( ! window2)
      {
         fprintf( stderr, "Failed to create sharing window\n");
         return( 1);
      }
      
      // Both windows have same shareID
      shareID = [window1 shareID];
      assert( shareID == [window2 shareID]);
      assert( shareID != 0);
      
      [window1 os_initEvents];
      [window2 os_initEvents];
      
      // Setup frame callbacks for both
      [window1 setFrameCallback:frameCallback];
      [window2 setFrameCallback:frameCallback];
      
      [window1 os_show];
      [window2 os_show];
      
      [app run];
   }
   [app terminate];
   
   return( 0);
}
```

### Example 3: Multi-threaded Rendering with Context Switching

```c
#import <MulleGLFW/MulleGLFW.h>
#import <mulle-thread/mulle-thread.h>

static mulle_atomic_pointer_t   shouldStop;

static mulle_thread_rval_t   renderThread( void *arg)
{
   GLFWOSWindow      *window;
   struct CGPixelSize   size;
   
   window = (GLFWOSWindow *) arg;
   
   // Activate context on this thread
   [window os_activateGraphicsContext];
   [window os_setSwapInterval:1];  // Enable vsync
   
   while( ! _mulle_atomic_pointer_read( &shouldStop))
   {
      size = [window os_framebufferSize];
      
      glViewport( 0, 0, size.width, size.height);
      glClearColor( 0.0, 0.0, 0.5, 1.0);
      glClear( GL_COLOR_BUFFER_BIT);
      
      // Render scene
      // ... OpenGL drawing code ...
      
      [window os_swapBuffers];
      
      if( [window shouldClose])
         _mulle_atomic_pointer_write( &shouldStop, (void *) 1);
   }
   
   [window os_deactivateGraphicsContext];
   
   return( 0);
}


int   main( void)
{
   UIApplication   *app;
   GLFWOSWindow    *window;
   mulle_thread_t  thread;
   
   app = [UIApplication sharedInstance];
   
   _mulle_atomic_pointer_write( &shouldStop, (void *) 0);
   
   @autoreleasepool
   {
      window = [GLFWOSWindow windowWithFrame:CGRectMake( 0, 0, 800, 600)
                             titleUTF8String:"Multi-threaded"
                                   styleMask:UIWindowStyleBare];
      
      [window os_initEvents];
      [window os_show];
      
      // Start render thread
      mulle_thread_create( renderThread, window, &thread);
      
      // Main thread handles events
      while( ! _mulle_atomic_pointer_read( &shouldStop))
      {
         [app os_pollEvents];
         mulle_thread_yield();
      }
      
      mulle_thread_join( thread);
   }
   [app terminate];
   
   return( 0);
}
```

### Example 4: Querying Screens and Gamepads

```c
#import <MulleGLFW/MulleGLFW.h>

int   main( void)
{
   UIApplication         *app;
   NSUInteger            i;
   NSUInteger            n;
   id <UIScreen>         screen;
   id <UIGamepad>        gamepad;
   struct UIScreenInfo   screenInfo;
   struct UIGamepadInfo  gamepadInfo;
   
   app = [UIApplication sharedInstance];
   
   // Query screens
   n = [GLFWOSScreen numberOfScreens];
   printf( "Found %lu screen(s)\n", (unsigned long) n);
   
   for( i = 0; i < n; i++)
   {
      screen = [GLFWOSScreen screenAtIndex:i];
      [screen getScreenInfo:&screenInfo];
      
      printf( "Screen %lu: %s\n", (unsigned long) i, [screen nameUTF8String]);
      printf( "  Frame: %.0fx%.0f at %.0f,%.0f\n",
             screenInfo.frame.size.width,
             screenInfo.frame.size.height,
             screenInfo.frame.origin.x,
             screenInfo.frame.origin.y);
      printf( "  DPI: %.1f\n", screenInfo.dpi);
      printf( "  Refresh: %.1f Hz\n", screenInfo.refreshRate);
   }
   
   // Query gamepads
   n = [GLFWOSGamepad numberOfGamepads];
   printf( "\nFound %lu gamepad(s)\n", (unsigned long) n);
   
   for( i = 0; i < n; i++)
   {
      gamepad = [GLFWOSGamepad gamepadAtOSIndex:i];
      if( gamepad)
      {
         printf( "Gamepad %lu: %s\n", (unsigned long) i, [gamepad nameUTF8String]);
         printf( "  GUID: %s\n", [gamepad guidUTF8String]);
         printf( "  Type: %s\n", [gamepad isJoystick] ? "Joystick" : "Gamepad");
         
         [gamepad getGamepadInfo:&gamepadInfo];
         printf( "  Buttons: %d\n", gamepadInfo.buttonCount);
         printf( "  Axes: %d\n", gamepadInfo.axisCount);
      }
   }
   
   [app terminate];
   return( 0);
}
```

### Example 5: Custom Event Receiver with Event Filtering

```c
#import <MulleGLFW/MulleGLFW.h>

@interface MyEventReceiver : NSObject <UIEventReceiver>
{
   int   _frameCount;
}
@end

@implementation MyEventReceiver

- (void) handleWindowEvent:(UIWindowEvent *) event
{
   switch( [event windowEventType])
   {
      case UIWindowEventTypeResize:
         printf( "Window resized\n");
         break;
         
      case UIWindowEventTypeMove:
         printf( "Window moved\n");
         break;
         
      case UIWindowEventTypeClose:
         printf( "Window close requested\n");
         break;
         
      case UIWindowEventTypeRefresh:
         _frameCount++;
         if( _frameCount % 60 == 0)
            printf( "Frame %d\n", _frameCount);
         break;
   }
}

- (void) receiveRetainedEvent:(NS_CONSUMED UIEvent *) event
{
   @try
   {
      switch( [event eventType])
      {
         case UIEventTypeKeyboard:
            printf( "Key event\n");
            break;
            
         case UIEventTypeMouse:
            printf( "Mouse event\n");
            break;
      }
   }
   @finally
   {
      [event release];
   }
}

@end


int   main( void)
{
   UIApplication     *app;
   GLFWOSWindow      *window;
   MyEventReceiver   *receiver;
   
   app = [UIApplication sharedInstance];
   
   @autoreleasepool
   {
      window   = [GLFWOSWindow windowWithFrame:CGRectMake( 0, 0, 400, 300)
                               titleUTF8String:"Event Demo"
                                     styleMask:UIWindowStyleBare];
      
      receiver = [[[MyEventReceiver alloc] init] autorelease];
      
      [window setWindowEventsReceiver:receiver];
      [window setEventsReceiver:receiver];
      [window os_initEvents];
      [window setFrameCallback:myFrameCallback];
      
      // Filter out mouse move events (reduce noise)
      [window setDiscardEventsMask:UIEventTypeMouse];
      
      [window os_show];
      [app run];
   }
   [app terminate];
   
   return( 0);
}
```

## 7. Dependencies

Direct mulle-sde dependencies:
- **glfw** - GLFW 3.4 library (tar archive from GitHub)
- **MulleUIApplication** - Provides UIApplication, UIEvent, UIWindow protocols and base classes
- **mulle-objc-list** (no-header, no-link) - Build tool dependency for reflection

Platform-specific OS libraries (X11 backend):
- **GL** - OpenGL
- **GLU** - OpenGL Utility Library
- **X11** - X Window System
- **Xrandr** - X Resize and Rotate extension
- **Xxf86vm** - XFree86 Video Mode extension
- **Xinerama** - Multi-screen support
- **Xcursor** - X Cursor management
- **m** - Math library

Platform-specific OS libraries (Wayland backend):
- **GL** - OpenGL
- **GLU** - OpenGL Utility Library
- **wayland-client** - Wayland client library
- **wayland-protocols** - Wayland protocol definitions
- **libxkbcommon** - Keyboard handling
- **m** - Math library

Platform-specific frameworks (macOS):
- **Cocoa** - macOS UI framework
- **IOKit** - I/O Kit framework
- **CoreFoundation** - Core Foundation
- **CoreGraphics** - Graphics primitives
- **CoreServices** - Core Services
- **AppKit** - Application Kit
- **Foundation** - Foundation framework

Note: All OS libraries and frameworks are marked `no-header` as GLFW provides necessary header wrapping.

# MulleGLFW Library Documentation for AI
<!-- Keywords: GLFW, window, events, Objective-C, OpenGL, Metal, platform -->

## 1. Introduction & Purpose

MulleGLFW provides platform windows and event handling for the MulleUI framework through an Objective-C wrapper around GLFW3. It serves as the foundational layer for **UIEvent** and **UIApplication** through categories, handling OS-level window management, input events, screen/monitor management, and gamepad support. The library provides the platform-specific window (**GLFWOSWindow**) with OpenGL contexts (or a macOS Metal layer), manages multiple screens (**GLFWOSScreen**), and handles gamepads (**GLFWOSGamepad**). It is a core dependency within the MulleUI ecosystem and forms the bridge between GLFW's C API and mulle-objc's Objective-C runtime.

MulleGLFW supports multiple platform backends: X11 (Linux default), Wayland (Linux alternative), and macOS (OpenGL or Metal). It provides flexible OpenGL context creation with support for various OpenGL versions (3.x, ES2, ES3) and profiles (core, compatibility, forward-compatible). The GLFW3 window object is **GLFWOSWindow**; each GLFWOSWindow has an implicit graphics context that is later used by a CGContext.

## 2. Key Concepts & Design Philosophy

### Dual Sourcetree Architecture
MulleGLFW is a dual-sourcetree project allowing selection between X11 and Wayland backends on Linux using `mulle-sde config switch MulleGLFW [x11|wayland]`. Other available configs are `macos` and `x11-mesa`.

### Threading Model
- **Main Thread Only**: Most window operations, event initialization, and GLFW API calls must execute on the main thread.
- **Thread-Safe Methods**: Explicitly marked with `MULLE_OBJC_THREADSAFE_METHOD` - these include context activation, window info queries, and state getters.
- **Graphics Context Binding**: OpenGL contexts can be bound to different threads via `os_activateGraphicsContext`/`os_deactivateGraphicsContext`.
- **Atomic Operations**: Critical shared state uses `mulle_atomic_pointer_t` for thread-safe access.

### Event Handling Architecture
MulleGLFW provides multiple event callback mechanisms:
- **windowEventsCallback**: For window-specific events (resize, move, close, refresh) - calls receiver's `-handleWindowEvent:` (event is autoreleased).
- **otherRetainedEventsCallback**: For retained events (keyboard, mouse, gamepad) - calls receiver's `-receiveRetainedEvent:` (event must be released by receiver).
- **frameCallback**: For rendering frames - does not use CGContext, provides raw OpenGL access.
- **Default Callbacks**: `GLFWOSWindowEventDefaultCallback` and `GLFWOSWindowRetainedEventDefaultCallback` forward to receivers.

If you chose to overwrite event callbacks, the eventsReceiver and the windowEventsReceiver will not get anything. Setting either callback also enables the OS events for the respective channel.

### Graphics Context Management
- **Implicit Contexts**: Each GLFWOSWindow has an implicit graphics context (`haveGraphicsContext`).
- **Context Sharing**: Windows can share textures via `sharingWindow` parameter (assigned a common `shareID`). The sharing window is retained.
- **Multiple Backends**: Supports OpenGL, OpenGL ES, and NO_API configurations.
- **Fallback Strategy**: Can retry multiple context creation libraries (native → OSMesa → EGL, order depends on the first library requested) via `UIWindowOpenGLLibraryFallback`.
- **OSMesa blitting**: For `GLFW_OSMESA_CONTEXT_API` contexts, `glfwSwapBuffers` is a no-op; MuileGLFW performs a manual RGBA→XRGB blit into the native X11/Wayland window.
- **Metal (macOS)**: A `GLFW_NO_API` window on macOS gets a `CAMetalLayer` (via the pure-C shim in `GLFWMetalLayer-apple.h`) so the Metal CG backend has a surface; the backend is then reported as `UIGraphicsBackendMetal2`.

### Style Masks & Hints
Window behavior is configured via `NSUInteger` style masks and `GLFWGraphicsHints`:
- Style masks control window decoration (`UIWindowStyleBare`), resizability, transparency, anti-aliasing (MSAA), single/double buffering, floating, hidden, and OpenGL deprecation/forward/core-profile/fallback flags.
- Graphics hints specify OpenGL version, profile, API type, and context-creation library, plus driver-selection environment overrides.

## 3. Core API & Data Structures

### 3.1. `GLFWOSWindow.h`

#### `@interface GLFWOSWindow : NSObject <UIWindow, UIOSWindow>`
The primary window class wrapping a GLFW window handle.

**Purpose:** Represents a platform window with a graphics context (`_window` is the `GLFWwindow*`). Manages window lifecycle, events, and rendering. Most methods may only be called from the main thread, unless marked thread-safe. If you create `GLFWOSWindow` manually, finalize it before `-[UIApplication terminate]`, otherwise the context is gone and finalization may not complete.

**Key Fields:**
- `void *_window` - GLFW window handle (GLFWwindow*).
- `NSLock *_contextLock` - Protects graphics context operations.
- `GLFWOSWindow *_sharingWindow` - Window this window shares textures with (retained).
- `NSInteger _shareID` - Unique ID for texture sharing group (0 = no sharing; `shareID` delegates to the sharing window's ID).
- `mulle_absolutetime_t _lastSwapBuffersTimestamp` - Timing for frame rate control.
- `mulle_atomic_pointer_t _needsRefresh` - Flag for refresh requests (thread-safe).
- `mulle_atomic_pointer_t _discardEventsMask` - Mask for filtering events (thread-safe).
- `NSLock *_windowInfoLock` + `struct UIOSWindowInfo _windowInfo` - Cached window dimensions and state.
- `NSLock *_inputStateLock` - Protects cached input state.
- `void *_osmesaBlitState` - Opaque OSMesa blit state (struct `mulle__osmesa_blit_state*`).
- `void *_metalLayer` (macOS only) - Opaque `CAMetalLayer*` attached for `GLFW_NO_API` windows; vended via `-backendMetalLayer`.
- `mulle_atomic_pointer_t _atomicActiveThread` - Thread that currently owns the (active) context.

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

// sharingWindow is retained. We will be able to share textures with it
+ (instancetype) windowWithFrame:(CGRect) frame
                 titleUTF8String:(char *) title
                       styleMask:(NSUInteger) styleMask
                   graphicsHints:(GLFWGraphicsHints) graphicsHints
                   sharingWindow:(id <UIOSWindow>) sharingWindow;

- (instancetype) initWithFrame:(CGRect) frame
               titleUTF8String:(char *) title
                     styleMask:(NSUInteger) styleMask;

- (instancetype) initWithFrame:(CGRect) frame
               titleUTF8String:(char *) title
                     styleMask:(NSUInteger) styleMask
                 graphicsHints:(GLFWGraphicsHints) graphicsHints;

// sharingWindow is retained. We will be able to share textures with it
- (instancetype) initWithFrame:(CGRect) frame
               titleUTF8String:(char *) title
                     styleMask:(NSUInteger) styleMask
                 graphicsHints:(GLFWGraphicsHints) graphicsHints
                 sharingWindow:(id <UIOSWindow>) sharingWindow;
```

The `+windowWithFrame:` class methods `alloc`/`init`/`autorelease` in one step; use them unless you manage an `@autoreleasepool`.

**Style Mask Constants:**
- `GLFWOSWindowStyleMaskDefault` - Default window style (0).
- Combined with `UIWindowStyle*` flags: `UIWindowStyleBare`, `UIWindowStyleResizable`, `UIWindowStyleFloating`, `UIWindowStyleTransparent`, `UIWindowStyleAntiAlias`, `UIWindowStyleSingleBuffer`, `UIWindowStyleHidden`, `UIWindowOpenGLDeprecated`, `UIWindowOpenGLForward`, `UIWindowOpenGLCoreProfile`, `UIWindowOpenGLLibraryFallback`.

**Graphics Hints:**
- `GLFWGraphicsHints` - `typedef UIOSWindowGraphicsHints GLFWGraphicsHints;` (from MulleUIApplication). It is a struct encoding profile (0=default, 1=any, 2=core, 3=compat), forward-compat (0/1), API (0=default, 1=NONE, 2=OpenGLES, 3=OpenGL), context-creation library (0=default, 1=native, 2=egl, 3=osmesa), major/minor GLFW context version, and driver-override fields (`glx_vendor`, `driver`, `lib_path`, `egl_vendor`, `software`, `dri_prime`).
- Predefined literal initializers: `GLFWGraphicsHintsDefault`, `GLFWGraphicsHintsNone`, `GLFWGraphicsHintsGL3`, `GLFWGraphicsHintsGL3_2`, `GLFWGraphicsHintsGLES2`, `GLFWGraphicsHintsGLES3`, `GLFWGraphicsHintsGLES3_2`.

```c
MULLE_GLFW_GLOBAL
void   GLFWGraphicsHintsApplyDriverEnv( GLFWGraphicsHints hints);
```
Applies driver-selection environment variables derived from the hints fields (`__GLX_VENDOR_LIBRARY_NAME`, `MESA_LOADER_DRIVER_OVERRIDE`, `LD_LIBRARY_PATH`, `LIBGL_DRIVERS_PATH`, `__EGL_VENDOR_LIBRARY_FILENAMES`, `LIBGL_ALWAYS_SOFTWARE`, `DRI_PRIME`). Must be called before `[UIApplication sharedInstance]`.

**Properties:**

Event Receivers:
- `id <UIEventReceiver> windowEventsReceiver` (assign) - Receives window events via `-handleWindowEvent:` (event is autoreleased).
- `id <UIEventReceiver> eventsReceiver` (assign) - Receives retained events via `-receiveRetainedEvent:` (event must be released by receiver).

Callbacks (overwriting the callback disables the corresponding receiver):
- `UIOSWindowEventCallback_t windowEventsCallback` (assign) - Default: `GLFWOSWindowEventDefaultCallback`.
- `UIOSWindowRetainedEventCallback_t otherRetainedEventsCallback` (assign) - Default: `GLFWOSWindowRetainedEventDefaultCallback`.
- `UIOSWindowFrameCallback_t frameCallback` (assign) - Custom rendering callback (no CGContext). Glorified default prints a hint and aborts.

State (readonly):
- `BOOL haveGraphicsContext` - Whether the window has a graphics context.
- `NSUInteger styleMask` - Window style flags used at creation.
- `id <UIGraphicsContext> renderGraphicsContext` - Always nil (GLFW has no drawing functionality).
- `BOOL antiAliasing` - Whether MSAA is enabled (GLFW_SAMPLES == 4).
- `struct UIInputState inputState` - Current keyboard/mouse state (cached, thread-safe).
- `UIGraphicsBackend backend` - Detected graphics backend (e.g., `UIGraphicsBackendGL3_2Forward`, `UIGraphicsBackendMetal2`, `UIGraphicsBackendNone`).

Configuration:
- `mulle_relativetime_t frameRate` (thread-safe) - Target frame period (0.0 = on-demand/async). `frameRateHz`/`setFrameRateHz:` convert between Hz and period.
- `NSUInteger discardEventsMask` (thread-safe) - Mask to filter unwanted events (`UIEventType*`).
- `CGFloat scrollWheelSensitivity` - Multiplier for scroll events (default 20.0).
- `BOOL scrollWheelNatural` - Natural scrolling direction (requires explicit getter/setter via `isScrollWheelNatural`).
- `id <UIWindow> parentWindow` - Parent window reference.
- `NSUInteger debuggingFlags` (thread-safe) - Debug output control.
- `BOOL uninitializedFramebuffer` - Whether the framebuffer needs an initial clear.

**Window Information (Thread-Safe):**
```objective-c
- (void) getOSWindowInfo:(struct UIOSWindowInfo *) info;

// screen the window is on (either fully or for the most part)
- (id <UIScreen>) screen;
- (id <UIScreen>) screenOrPrimaryScreen:(BOOL) flag;

// The shareID never changes for a Window; 0 means no sharing
- (NSInteger) shareID;
- (BOOL) shouldClose;
```

**Raw Handle & Metal Access (Thread-Safe):**
```objective-c
- (void *) os_window;                    // GLFW window, use this for glfw functions

// On macOS, for a GLFW_NO_API window, returns the attached CAMetalLayer * as
// an opaque void * (for the Metal CG backend / nvgCreateMTL). NULL otherwise.
- (void *) backendMetalLayer;
```

**Graphics Context Operations (Thread-Safe):**
```objective-c
- (void) os_activateGraphicsContext;      // Bind GL context to current thread
- (void) os_deactivateGraphicsContext;    // Unbind GL context from current thread
- (BOOL) os_tryActivateGraphicsContext;   // Non-blocking activation attempt
- (void) os_swapBuffers;                  // Present rendered frame
- (void) os_setSwapInterval:(NSUInteger) value;  // Vsync interval (0=off, 1=on)
- (NSThread *) activeThread;              // Thread that activated context (nil if none)
```
These methods do not call `mulleGainAccess`/`mulleRelinquishAccess`.

**Close Request (Thread-Safe):**
```objective-c
- (void) os_requestClose;
- (BOOL) os_windowShouldClose;
```

**Window Management (Main Thread Only):**
```objective-c
- (struct CGPixelSize) os_framebufferSize;
- (CGPoint) os_windowPosition;
- (CGSize) os_windowSize;
- (CGRect) os_windowFrame;
- (CGVector) os_UIScale;                 // currently always (1.0, 1.0)

- (void) os_setWindowPosition:(CGPoint) position;
- (void) os_setWindowSize:(CGSize) size;
- (void) os_setWindowFrame:(CGRect) rect;
- (void) os_setTitleUTF8String:(char *) s;
- (void) os_setCursor:(void *) cursor;

// Capture the cursor for gameplay (GLFW_CURSOR_DISABLED: hidden, unlimited
// virtual movement). Pass NO to restore normal cursor behaviour. While
// captured, locationInWindow in motion events is an unbounded virtual
// position — use deltas between frames, not absolute values.
- (void) os_setCursorCaptured:(BOOL) captured;

- (void) os_show;
- (void) os_hide;
- (void) os_destroyWindow;
```

**Inspection (Main Thread Only):**
```objective-c
- (char *) os_contextInfoUTF8String;  // e.g. "GL 3.2.0 (...) MSAA4 (mesa) [renderer] - GLFW v3.4"
- (char *) os_windowInfoUTF8String;   // e.g. "visible,resizable,decorated,opaque,double"
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
Checks the `needsRefresh` atomic flag; if unset and the frameRate has not elapsed it returns the remaining time. Otherwise runs the frame callback, swaps buffers, and returns the frame period.

**Default Callback Functions (exported C globals):**
```c
MULLE_GLFW_GLOBAL
void   GLFWOSWindowEventDefaultCallback( id <UIOSWindow> window, UIWindowEvent *event);
MULLE_GLFW_GLOBAL
void   GLFWOSWindowRetainedEventDefaultCallback( id <UIOSWindow> window, UIEvent *retainedEvent);
```

### 3.2. `GLFWOSWindow+UIEvent.h`

#### `@interface GLFWOSWindow( UIEvent)`
Category providing event system initialization.

**Purpose:** Initialize GLFW callbacks for window and input events. All methods are main-thread only.

**Core Methods:**
```objective-c
// convenience for os_initWindowEvents and os_initInputEvents
- (void) os_initEvents;

- (void) os_initWindowEvents;   // resize, pos, framebuffer, refresh, close, focus callbacks
- (void) os_initInputEvents;    // mouse button, cursor pos, key, char, scroll callbacks

- (void) updateWindowInfo;      // re-read frame/framebuffer size and refresh rate
```
The header also declares (private category) `os_finalizeEvents` and `os_finalizeWindowEvents`/`os_finalizeInputEvents` in the implementation; these clear the GLFW callbacks. Window events dispatched by this category: `UIWindowMoveEvent`, `UIWindowResizeEvent`, `UIWindowFramebufferResizeEvent`, `UIWindowRefreshEvent`, `UIWindowFocusLostEvent`. Input events dispatched as retained events: `UIKeyboardEvent`, `UIUnicodeEvent`, `UIMouseButtonEvent` (with multi-click counting), `UIMouseMotionEvent`, `UIMouseScrollEvent`.

### 3.3. `GLFWOSScreen.h`

#### `@interface GLFWOSScreen : NSObject <UIScreen>`
Represents a physical monitor/display.

**Purpose:** Wraps GLFW monitor handles to provide screen information and management. Values are copied into a local `_info` area so they can be read from non-main-thread threads.

**Key Fields:**
- `void *_monitor` - GLFW monitor handle (GLFWmonitor*).
- `struct UIScreenInfo _info` - Cached screen properties (frame, canvas, DPI, refresh rate, content scale, physical size, color bits).
- `NSLock *_infoLock` - Protects screen info.

**Lifecycle Functions:**
```objective-c
+ (NSUInteger) numberOfScreens;
+ (id <UIScreen>) screenAtIndex:(NSUInteger) i;
- (instancetype) initWithGLFWMonitor:(void *) monitor;
```

**Properties:**
- `char *nameUTF8String` (readonly, thread-safe) - Monitor name (cached duplicated string).

**Screen Information (Thread-Safe):**
```objective-c
- (void) getScreenInfo:(struct UIScreenInfo *) info;
- (CGRect) frame;                     // Screen bounds in points
- (CGRect) canvas;                    // Usable area (workarea, excludes taskbar)
- (mulle_relativetime_t) refreshRate; // Monitor refresh period in seconds
```

**OS Queries (Main Thread Only):**
```objective-c
- (char *) os_nameUTF8String;         // Monitor name
- (CGVector) os_contentScale;         // DPI scaling factor
- (CGSize) os_physicalSize;           // Physical size in meters
- (CGFloat) os_dpi;                   // Dots per inch
- (CGPixelRect) os_canvas;            // Workarea in pixels
- (CGPixelPoint) os_position;         // Position in virtual desktop
- (BOOL) os_isPrimaryScreen;          // Is this the primary monitor
```

### 3.4. `GLFWOSGamepad.h`

#### `@interface GLFWOSGamepad : NSObject <UIGamepad>`
Represents a gamepad/joystick device.

**Purpose:** Wraps GLFW joystick handles to provide gamepad state and information. GLFW updates joystick states on demand; you do not need window or event processing for this (usually). New devices are sanity-checked (`+isValidJoystickInfo:`) to filter out junk devices like LED controllers or touchpads.

**Key Fields:**
- `int _handle` - GLFW joystick ID (GLFW_JOYSTICK_1 .. GLFW_JOYSTICK_LAST).
- `struct UIGamepadInfo _info` - Current gamepad state (buttons, sticks, axes).
- `struct UIGamepadInfo _previousInfo` - Previous state for delta detection.
- `NSLock *_infoLock` - Protects gamepad info.

**Lifecycle Functions:**
```objective-c
+ (NSUInteger) numberOfGamepads;
+ (id <UIGamepad>) gamepadAtOSIndex:(NSUInteger) i;

+ (NSRange) osIndexRange;              // Range of valid joystick indices

- (instancetype) initWithOSGamepad:(void *) handle;
```

**Properties:**
- `char *nameUTF8String` (readonly, thread-safe) - Device name.
- `char *guidUTF8String` (readonly, thread-safe) - Device GUID.
- `BOOL isJoystick` (readonly, dynamic) - YES for joystick vs gamepad.
- `NSInteger osIndex` (readonly, dynamic) - GLFW joystick index (the handle; `GLFW_JOYSTICK_1 == 1` makes osIndex 1-based).

**Gamepad State (Thread-Safe):**
```objective-c
- (void) getGamepadInfo:(struct UIGamepadInfo *) info;
```

**Polling (Main Thread Only):**
```objective-c
// to be called by pollGamepads
- (void) os_pollGamepadInfo;
```

**OS Queries (Main Thread Only):**
```objective-c
- (char *) os_nameUTF8String;  // Device name
- (char *) os_guidUTF8String;  // Device GUID
```

### 3.5. `GLFWMetalLayer-apple.h`

Pure C interface to the Apple-runtime Metal layer shim (`GLFWMetalLayer-apple.m`). Safe to include from mulle-objc translation units: it declares only C functions operating on opaque `void *` handles and references no Objective-C types. The shim is compiled with the *system* clang (Apple runtime) and linked in as an object file; ownership across the boundary uses CoreFoundation bridging (Create returns a +1 reference, Release balances it).

```c
MULLE_GLFW_GLOBAL
void   *MulleGLFWMetalLayerCreate( void *nsWindowPointer);
```
Create + attach a `CAMetalLayer` to the cocoa window (the `glfwGetCocoaWindow` result, passed as `void *`). Returns an opaque `CAMetalLayer *` (retained, +1 reference) or NULL. Release with `MulleGLFWMetalLayerRelease`.

```c
MULLE_GLFW_GLOBAL
void    MulleGLFWMetalLayerSetDrawableSize( void *layer, double width, double height);
```
Sync the layer's drawableSize to the framebuffer pixel size on resize.

```c
MULLE_GLFW_GLOBAL
void    MulleGLFWMetalLayerPresentClear( void *layer,
                                         double r, double g, double b, double a);
```
Acquire the layer's next drawable, clear it to the given RGBA color via a render pass, and present it. A minimal on-screen present path (for tests and reference).

```c
MULLE_GLFW_GLOBAL
void   *MulleGLFWMetalLayerDevice( void *layer);
```
Borrowed `id<MTLDevice>` as `void *` (not retained), or NULL.

```c
MULLE_GLFW_GLOBAL
void    MulleGLFWMetalLayerRelease( void *layer);
```
Release the reference from `MulleGLFWMetalLayerCreate`.

The implementation also provides `MulleGLFWMetalLayerPresentTwoContext( void *layer)` (a two-context reproduction helper; not declared in the header). All of these are compiled only on `__APPLE__`.

### 3.6. `MulleGLFW.h`

#### Umbrella Header
The main entry point for the library. Defines version information and controls GL header exposure.

**Purpose:** Provides the version macro and conditions whether GLFW headers expose OpenGL symbols.

**Core Macros:**
```c
#define MULLE_GLFW_VERSION  ((0UL << 20) | (1 << 8) | 1)
```
Version encoded as `((MAJOR << 20) | (MINOR << 8) | PATCH)` → 0.1.1.

```c
// do not expose any OpenGL stuff here, unless asked to
#ifndef MULLE_GLFW_EXPOSE_OPEN_GL
# define GLFW_INCLUDE_NONE
#endif
```
By default, GLFW does not include GL headers — your code must `#include` the OpenGL headers it needs. Define `MULLE_GLFW_EXPOSE_OPEN_GL` before including `MulleGLFW.h` to let GLFW expose them.

**Export Macro:** `MULLE_GLFW_GLOBAL` (and `MULLE_GLFW_GLOBAL_VAR`) is defined in `src/generic/import.h`: it expands to `MULLE_C_GLOBAL` when building (`MULLE_GLFW_BUILD`), `MULLE_C_EXTERN_GLOBAL` for dynamic inclusion, and `extern` otherwise. All exported C functions in this library carry this prefix.

### 3.7. `MulleObjCDeps+MulleGLFW.h`

#### `@interface MulleObjCDeps( MulleGLFW)`
Dependency declaration for the mulle-objc runtime, required to be public so that other libraries depending on this one can properly declare their load in their `MulleObjcLoader` class.

**Core Method:**
```objective-c
+ (struct _mulle_objc_dependency *) dependencies;
```
The implementation `#include`s the generated `objc-deps.inc`.

### 3.8. `UIApplication+GLFW.m` (Category - no public header)

#### `@interface UIApplication (GLFW)`
Private category extending UIApplication with GLFW initialization and event handling.

**Purpose:** Initializes GLFW, sets up monitor and joystick callbacks, integrates with UIApplication event system.

**Key Methods:**
```objective-c
+ (void) os_initialize;   // glfwInit() + init hints (GLFW_JOYSTICK_HAT_BUTTONS off)
+ (void) os_deinitialize; // glfwPollEvents() drain, then glfwTerminate() + clear error callback
- (void) os_init;         // enumerate screens/gamepads, set monitor+joystick callbacks
- (void) os_finalize;     // clear callbacks

- (void) os_waitEventsWithTimeout:(mulle_relativetime_t) timeout;
- (void) os_pollEvents;
- (void) os_sendEmptyEvent;   // glfwPostEmptyEvent; callable from any thread
- (void) os_pollGamepads;     // iterate joysticks, call -os_pollGamepadInfo

- (void *) os_createStandardCursor:(UICursorStandardShape) shape;
- (void *) os_createCursorWithBitmap:(struct CGBitmap) bitmap
                             hotSpot:(struct CGPixelPoint) hotSpot;
- (void) os_destroyCursor:(void *) cursor;
```

**Monitor Callbacks:**
- Handles `GLFW_CONNECTED`/`GLFW_DISCONNECTED` events.
- Creates `UIScreenEvent` objects and forwards to `[UIApp handleScreenEvent:]`.

**Gamepad Callbacks:**
- Handles joystick connection/disconnection.
- Creates `UIGamepadEvent` objects and forwards to `[UIApp handleGamepadEvent:]`.

## 4. Performance Characteristics

### Window Creation
- **O(1) per window** - GLFW handles platform-specific creation.
- **Context creation can fail** - Library fallback mechanism (native → OSMesa → EGL, or EGL → native → OSMesa, etc.) can retry when `UIWindowOpenGLLibraryFallback` is set.
- **Thread restriction** - Must be on main thread due to GLFW limitations.

### Graphics Context Switching
- **Not negligible** - Context activation/deactivation has measurable overhead (see `test/15-glfw/activate.m`, which benchmarks ~10k activation cycles).
- **Lock-based synchronization** - `_contextLock` serializes context operations.
- **Per-thread binding** - Context can only be active on one thread at a time.

### Event Handling
- **Polling-based** - GLFW uses `glfwPollEvents()`/`glfwWaitEvents*()` called from the main thread.
- **Callback-driven** - Events invoke Objective-C callbacks synchronously on the main thread.
- **Lock-free flags** - `_needsRefresh` and `_discardEventsMask` use atomic operations.
- **Discard filter** - `discardEventsMask` short-circuits event object creation (checked before allocation).

### Screen/Gamepad Queries
- **Cached info** - Screen and gamepad info cached in structs protected by locks.
- **Lock overhead** - Thread-safe getters briefly acquire a lock.
- **Polling required** - Gamepad state must be explicitly polled via `os_pollGamepadInfo`.

### Frame Rate Control
- **Time-based** - Uses `mulle_absolutetime_t` for precise timing.
- **Conditional refresh** - `displayFrameIfNeeded:` checks flags and timing; returns "time left to next frame" to the caller.
- **VSync support** - `os_setSwapInterval:` controls buffer swapping.

### Thread Safety
- **Most operations: Main thread only** - GLFW API restriction.
- **Atomic operations: Lock-free** - Flags use `mulle_atomic_pointer_t`.
- **Context operations: Lock-based** - `_contextLock` protects activation.
- **Info getters: Lock-based** - `_infoLock`/`_windowInfoLock`/`_inputStateLock` protect cached state.

## 5. AI Usage Recommendations & Patterns

### Best Practices

1. **Always initialize UIApplication first**: GLFW is initialized via `[UIApplication os_initialize]`.
   ```objective-c
   UIApplication *app = [UIApplication sharedInstance];  // Initializes GLFW
   ```

2. **Create windows on the main thread**: Never create windows from background threads.
   ```objective-c
   assert( [NSThread mulleIsMainThread]);
   GLFWOSWindow *window = [GLFWOSWindow windowWithFrame:frame
                                        titleUTF8String:"Title"
                                              styleMask:styleMask];
   ```

3. **Wrap windows in autorelease pools**: Ensures proper cleanup before `[app terminate]`. GLFW windows are not part of UIApplication; once the app terminates, windows can't be reaped, so either `mullePerformFinalize` them or wrap everything in an `@autoreleasepool`.
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

4. **Set a frameCallback before rendering**: Every window needs a frame callback; the default prints a hint and aborts.
   ```objective-c
   [window setFrameCallback:myFrameCallback];
   ```

5. **Use thread-safe methods from background threads**: Check method signatures.
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
   [window os_initEvents];   // window events + input events callbacks
   ```

7. **Share contexts for texture sharing**:
   ```objective-c
   GLFWOSWindow *window1 = [GLFWOSWindow windowWithFrame:frame1 ...];
   GLFWOSWindow *window2 = [GLFWOSWindow windowWithFrame:frame2
                                         titleUTF8String:"Window 2"
                                               styleMask:mask
                                           graphicsHints:hints
                                           sharingWindow:window1];
   // window1 and window2 can now share textures (same shareID)
   ```

8. **Apply driver env before UIApplication**: If you need a specific GL driver (e.g. Mesa), call `GLFWGraphicsHintsApplyDriverEnv( hints)` before `[UIApplication sharedInstance]`.

### Common Pitfalls

1. **Don't create windows off the main thread**: Will crash or fail.
2. **Don't forget to finalize windows before app terminate**: The context will be gone.
3. **Don't assume immediate GLFW state updates**: During resize, cached info (`os_windowFrame` vs event sizes) may lag; `getOSWindowInfo:` is updated by events and may be newer.
4. **Don't mix retained and non-retained event callbacks**: `windowEventsReceiver` gets autoreleased events; `eventsReceiver` gets retained events you must release.
5. **Don't free retained events in the default callback**: The receiver owns the event.
6. **Don't call `os_*` methods from the wrong thread**: Check `MULLE_OBJC_THREADSAFE_METHOD` markers.
7. **Don't use `alloc`/`init` directly without autorelease**: Use `+windowWithFrame:` or wrap in `@autoreleasepool`.
8. **Don't rely on OpenGL < 3.2 with core/forward profiles**: GLFW restricts those profiles to GL 3.2+.
9. **Don't use `os_contextInfoUTF8String:` on a NO_API (Metal) window**: There is no GL context; querying GL crashes. Check `haveGraphicsContext` first.
10. **Cursor capture note**: While captured, `locationInWindow` in motion events is an unbounded virtual position — use deltas between frames.
11. **Nothing renders with OSMesa unless you load GL functions**: With `GLFW_OSMESA_CONTEXT_API`, direct libGL calls do not route through OSMesa; you must load GL functions via `glfwGetProcAddress` or GLAD.

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

window = [GLFWOSWindow windowWithFrame:frame
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
   while( ! [window shouldClose])
   {
      // OpenGL calls here
      [window os_swapBuffers];
   }

   [window os_deactivateGraphicsContext];
});
```

**Pattern 4: Event Receiver Setup**
```objective-c
@implementation MyWindowController

- (void) handleWindowEvent:(UIWindowEvent *) event
{
   // Event is autoreleased, don't release it
   switch( [event windowEventType])
   {
   case UIWindowEventTypeResize : // Handle resize
                                 break;
   case UIWindowEventTypeClose  : // Handle close
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
```

## 6. Integration Examples

### Example 1: Creating a Basic Window with OpenGL 3.2

```c
#import <MulleGLFW/MulleGLFW.h>

static UIWindowDisplayBits   frameCallback( id <UIOSWindow> window)
{
   GLFWOSWindow      *glfwWindow;
   CGPixelSize       framebufferSize;

   glfwWindow       = (GLFWOSWindow *) window;
   framebufferSize  = [glfwWindow os_framebufferSize];

   // Setup viewport
   glViewport( 0, 0, framebufferSize.width, framebufferSize.height);

   // Clear to dark green
   glClearColor( 0.33f, 0.66f, 0.33f, 0.0f);
   glClear( GL_COLOR_BUFFER_BIT);

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
   GLFWOSWindow    *window[ 2];
   NSInteger       shareID;

   app = [UIApplication sharedInstance];

   @autoreleasepool
   {
      window[ 0] = [GLFWOSWindow windowWithFrame:CGRectMake( 0, 0, 320, 240)
                                 titleUTF8String:"Window 1"
                                       styleMask:UIWindowStyleBare
                                   graphicsHints:GLFWGraphicsHintsDefault];
      if( ! window[ 0])
      {
         fprintf( stderr, "initWithFrame: failed\n");
         exit( 1);
      }

      // Second window shares textures with the first
      window[ 1] = [GLFWOSWindow windowWithFrame:CGRectMake( 330, 0, 320, 240)
                                 titleUTF8String:"Window 2"
                                       styleMask:UIWindowStyleBare
                                   graphicsHints:GLFWGraphicsHintsDefault
                                   sharingWindow:window[ 0]];
      if( ! window[ 1])
      {
         fprintf( stderr, "sharingWindow: failed\n");
         exit( 1);
      }

      // Both windows have the same shareID (delegates to the sharing window)
      shareID = [window[ 0] shareID];
      assert( shareID == [window[ 1] shareID]);
      assert( shareID != 0);
   }
   [app terminate];

   return( 0);
}
```

### Example 3: Querying Screens and Gamepads

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
      printf( "  Refresh: %.1f Hz\n", 1.0 / screenInfo.refreshRate);
   }

   // Query gamepads (state is polled on demand)
   n = [GLFWOSGamepad numberOfGamepads];
   printf( "\nFound %lu gamepad(s)\n", (unsigned long) n);

   for( i = 0; i < n; i++)
   {
      gamepad = [GLFWOSGamepad gamepadAtOSIndex:i];
      if( gamepad)
         printf( "Gamepad: %s (%s)\n",
                 [gamepad nameUTF8String],
                 [gamepad isJoystick] ? "joystick" : "gamepad");
   }

   [app terminate];
   return( 0);
}
```

### Example 4: Applying Driver Environment Hints Before UIApplication

```c
#import <MulleGLFW/MulleGLFW.h>

int   main( void)
{
   UIApplication   *app;
   GLFWGraphicsHints hints;

   // Force a specific GLX vendor / Mesa driver selection
   hints            = GLFWGraphicsHintsGL3_2;
   hints.glx_vendor = "mesa";

   // Must run before [UIApplication sharedInstance]
   GLFWGraphicsHintsApplyDriverEnv( hints);

   app = [UIApplication sharedInstance];
   ...
}
```

### Example 5: Custom Event Receiver with Event Filtering

```c
#import <MulleGLFW/MulleGLFW.h>

@interface MyEventReceiver : NSObject <UIEventReceiver>
{
}
@end

@implementation MyEventReceiver

- (void) handleWindowEvent:(UIWindowEvent *) event
{
   // event is autoreleased here — do NOT release
   switch( [event windowEventType])
   {
   case UIWindowEventTypeResize : printf( "Window resized\n");
                                 break;

   case UIWindowEventTypeClose  : printf( "Window close requested\n");
                                 break;
   }
}

- (void) receiveRetainedEvent:(NS_CONSUMED UIEvent *) event
{
   @try
   {
      switch( [event eventType])
      {
      case UIEventTypeKeyboard : printf( "Key event\n");
                                break;

      case UIEventTypeMouse    : printf( "Mouse event\n");
                                break;
      }
   }
   @finally
   {
      [event release];   // retained events must be released
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

      // Filter out mouse motion events (reduce noise)
      [window setDiscardEventsMask:UIEventTypeMotion];

      [window os_show];
      [app run];
   }
   [app terminate];

   return( 0);
}
```

## 7. Dependencies

Direct mulle-sde dependencies (from `.mulle/etc/sourcetree/config`):
- **glfw** - GLFW 3.4 windowing library (tar archive from GitHub; header `GLFW/glfw3.h`).
- **MulleUIApplication** - Provides `UIApplication`, `UIEvent`, `UIWindow`, `UIOSWindow`, `UIScreen`, `UIGamepad` protocols and base classes, and the `UIOSWindowGraphicsHints`/`UIOSWindowInfo`/`UIScreenInfo`/`UIGamepadInfo` types used in the public API.
- **mulle-objc-tools** (no-header, no-link) - Build-time tooling for mulle-objc reflection.

Test/CI-only wiring:
- **craftinfo/glfw-craftinfo** (local, no-header, no-link) - GLFW craft info.

Note: `MulleObjC` itself is *not* a direct dependency; it is pulled in transitively via `MulleUIApplication`. Platform-specific OS libraries (GL, GLU, X11, Xrandr, wayland-client, Cocoa/QuartzCore/Metal on macOS, etc.) are handled by the GLFW craftinfo and the platform configs (`x11`, `wayland`, `macos`, `x11-mesa`).
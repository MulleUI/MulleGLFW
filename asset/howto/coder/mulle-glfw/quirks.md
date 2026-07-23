<!-- keywords: mulle-glfw, quirks, GLFWOSWindow, GLFWOSScreen, GLFWOSGamepad -->
# Quirks

## GLFWOSWindow

- Window creation is main-thread-only. In practice, so are `os_show`, `os_hide`, `os_destroyWindow`, geometry setters/getters, title/cursor updates, and pasteboard access. Only the methods and properties explicitly marked thread-safe in `src/GLFWOSWindow.h` are safe off the main thread.
- `frameCallback` is bare OpenGL. `src/GLFWOSWindow.h` and `demo/src/main-glfw-window.m` both assume you set the viewport, clear the buffer, and redraw everything yourself.
- `renderGraphicsContext` is always `nil`; a GLFW window may have a GL context, but it is not a CGContext-backed drawing surface.
- `getOSWindowInfo:` is intentionally more current than raw `os_windowFrame` during resize. `src/GLFWOSWindow.h` and `src/GLFWOSWindow+UIEvent.m` keep a cached `_windowInfo` because GLFW can lag while the window manager is mid-resize.
- Setting `windowEventsCallback` or `otherRetainedEventsCallback` auto-initializes the corresponding GLFW callbacks. If you replace those callbacks, the receiver properties are no longer the path that sees events.
- `GLFWOSWindowEventDefaultCallback` forwards an autoreleased `UIWindowEvent`; `GLFWOSWindowRetainedEventDefaultCallback` forwards a retained `UIEvent`. The retained one must be released by the receiver or callback. `demo/src/main-glfw-events.m` shows that explicitly.
- Manual windows must be finalized before `[UIApplication terminate]`. `src/GLFWOSWindow.h`, `test/15-glfw/share.m`, and `test/15-glfw/noshare.m` all treat an autorelease pool or `[window mullePerformFinalize]` as mandatory cleanup when the app does not own the window.
- Context switches are not cheap. `test/15-glfw/activate.m` exists specifically because `os_activateGraphicsContext` / `os_deactivateGraphicsContext` have measurable cost.
- A sharing window forces the new window onto the same GLFW context-creation API. Do not expect a shared window to use a different native/EGL/OSMesa backend.
- Automatic library fallback only happens when creation fails with no `sharingWindow`, no explicit `hints.lib`, and `UIWindowOpenGLLibraryFallback` set on the style mask.
- Apply `GLFWGraphicsHintsApplyDriverEnv` before `[UIApplication sharedInstance]`. The header says so, and `demo/src/main-glfw-triangle-opengles.m` does it in that order.
- OSMesa is special: GLFW can create the context, but direct libGL calls may still hit `NULL` dispatch. `src/GLFWOSWindow.m` and `demo/src/main-two-x-two-windows.m` both require loading functions through `glfwGetProcAddress` or GLAD for that path.
- The default `scrollWheelSensitivity` is `20.0`. `demo/src/main-glfw-wave.m` immediately lowers it to `1.0`.
- `os_setCursorCaptured:` disables the normal cursor boundary. While captured, `locationInWindow` in mouse motion events is an unbounded virtual position, not a window-relative coordinate. Always use deltas between consecutive motion events.
- `discardEventsMask` is a thread-safe property (`MULLE_OBJC_THREADSAFE_PROPERTY`) that filters retained events before they reach the callback or receiver. Inspect it before debugging "missing" input.
- `setFrameRateHz:` is a convenience setter that stores the value as `1.0 / hz`. The underlying `frameRate` property is `mulle_relativetime_t` (seconds per frame), not Hz.

## GLFWOSScreen

- The cached screen API is the portable path. `getScreenInfo:`, `frame`, `canvas`, and `refreshRate` read a lock-backed snapshot; `os_nameUTF8String`, `os_contentScale`, `os_physicalSize`, `os_dpi`, `os_canvas`, and `os_position` are main-thread OS queries.
- `refreshRate` is stored as seconds per frame, not Hertz. `demo/src/main-glfw-window.m` prints both by using `1.0 / info.refreshRate`.
- When GLFW does not report physical size, `src/GLFWOSScreen.m` falls back to hard-coded monitor dimensions and a `72.0` DPI default. Treat those values as best effort.

## GLFWOSGamepad

- Gamepad state is poll-on-demand. `src/GLFWOSGamepad.h` and `src/UIApplication+GLFW.m` do not rely on `glfwPollEvents()` for axis/button changes; they call `os_pollGamepadInfo`.
- GLFW joystick discovery is noisy. `src/GLFWOSGamepad.m` rejects some devices with no buttons/axes or suspicious names such as `LED`, `Mouse`, or `Touchpad`. Do not assume every GLFW joystick becomes a `GLFWOSGamepad`.
- `numberOfGamepads` is only a count of present devices; `gamepadAtOSIndex:` expects raw OS/GLFW joystick IDs from `osIndexRange`, not a dense `0 .. numberOfGamepads-1` loop.
- `UIApplication` owns connect/disconnect events through the joystick callback, but joystick callbacks can fire while GLFW joystick functions run. `src/UIApplication+GLFW.m` calls that out and keeps polling separate from event-array locking.

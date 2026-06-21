<!-- keywords: debugger, quirks, mulle-glfw, GLFWOSWindow, GLFWOSScreen, GLFWOSGamepad -->
# Quirks

## GLFWOSWindow

- Window creation is main-thread-only. Treat `os_show`, `os_hide`, `os_destroyWindow`, geometry setters/getters, title/cursor updates, and pasteboard access the same way unless the header explicitly marks a method thread-safe.
- `GLFWGraphicsHintsApplyDriverEnv` is only useful before `[UIApplication sharedInstance]`. After GLFW init, you are debugging the wrong phase.
- Explicit `hints.lib` turns off automatic native/EGL/OSMesa fallback. A `sharingWindow:` also suppresses backend freedom by forcing the creator API.
- `os_tryActivateGraphicsContext` failing means the context lock is busy, not that GLFW failed to create a context.
- `renderGraphicsContext` is always `nil`; `frameCallback` is bare OpenGL and must set viewport, clear, and draw everything itself.
- `getOSWindowInfo:` is intentionally fresher than raw `os_windowFrame` while resize events are in flight.
- `displayFrameIfNeeded:` uses `frameRate` as a relative time, not Hertz. Demo code prints Hertz by inverting the stored value.
- Manual windows must finalize before `[UIApplication terminate]`. `test/15-glfw/share.m` relies on autorelease-pool teardown; `test/15-glfw/noshare.m` calls `[window mullePerformFinalize]` explicitly.
- OSMesa is a special failure mode: `glfwCreateWindow` can succeed while `glGetString( GL_VERSION)` stays `NULL`. In this repo that usually means GL calls are not being loaded through `glfwGetProcAddress` or another loader.

## GLFWOSWindow (UIEvent)

- Setting `windowEventsCallback` or `otherRetainedEventsCallback` changes which path sees events. Debug the callback path or the receiver path, but do not assume both are active.
- Window events are autoreleased `UIWindowEvent` objects. Other input events are retained `UIEvent` objects and must be released by the receiver or callback.
- Missing input can be self-inflicted by `discardEventsMask`; inspect it before blaming GLFW.
- `src/GLFWOSWindow+UIEvent.m` assumes the main thread for window callbacks. If the repro violates that assumption, strange event ordering is expected.

## GLFWOSScreen

- `getScreenInfo:`, `frame`, `canvas`, and `refreshRate` come from a lock-backed snapshot. `os_nameUTF8String`, `os_contentScale`, `os_physicalSize`, `os_dpi`, `os_canvas`, and `os_position` are main-thread OS queries.
- `refreshRate` is stored as seconds per frame, not Hz.
- If screen refresh or frame matching looks wrong, debug `updateWindowInfo` and `_updateWindowRefreshRate` before digging into GLFW monitor geometry.

## GLFWOSGamepad

- GLFW joystick discovery is noisy. `GLFWOSGamepad` rejects some devices with no useful buttons/axes or suspicious names such as `LED`, `Mouse`, or `Touchpad`.
- `numberOfGamepads` is only a count of present devices. `gamepadAtOSIndex:` expects raw GLFW joystick IDs from `osIndexRange`, not a dense `0 .. numberOfGamepads - 1` loop.
- Button and axis state is poll-on-demand. `glfwPollEvents()` is not the whole story here; `os_pollGamepadInfo` and `os_pollGamepads` matter.
- `src/UIApplication+GLFW.m` notes that joystick callbacks can fire during joystick polling calls, so do not debug gamepad bugs assuming all events originate from the normal window-event loop.

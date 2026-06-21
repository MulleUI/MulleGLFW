<!-- keywords: mulle-glfw, GLFWOSWindow, GLFWOSScreen, GLFWOSGamepad, UIApplication -->
# mulle-glfw

Use this when changing the repo's GLFW-backed windowing layer, not generic GLFW code. The local public surfaces are `GLFWOSWindow`, `GLFWOSWindow (UIEvent)`, `GLFWOSScreen`, `GLFWOSGamepad`, and the `UIApplication` category that initializes GLFW and wires monitor and joystick callbacks.

## Understand first

```bash
mulle-sde api cat MulleUIApplication
mulle-sde code search GLFWOSWindow
mulle-sde code search GLFWOSScreen
mulle-sde code search GLFWOSGamepad
mulle-sde code search GLFWGraphicsHintsApplyDriverEnv
```

## Local references

- `README.md`
- `asset/dox/TOC.md`
- `src/GLFWOSWindow.h`
- `src/GLFWOSWindow+UIEvent.h`
- `src/GLFWOSScreen.h`
- `src/GLFWOSGamepad.h`
- `src/UIApplication+GLFW.m`
- `demo/src/main-glfw-window.m`
- `demo/src/main-glfw-events.m`
- `demo/src/main-glfw-events-objc.m`
- `demo/src/main-glfw-triangle-opengles.m`
- `demo/src/main-glfw-wave.m`
- `test/15-glfw/activate.m`
- `test/15-glfw/share.m`
- `test/15-glfw/noshare.m`
- `test/README.md`

## Main local surfaces

| Scenario | Start here | Local rule |
| --- | --- | --- |
| Create a platform window or GL context | `GLFWOSWindow` | Create on the main thread after `[UIApplication sharedInstance]`; rendering goes through `frameCallback`, not `CGContext`. |
| Bridge GLFW callbacks into MulleUI events | `GLFWOSWindow+UIEvent.h`, `demo/src/main-glfw-events.m`, `demo/src/main-glfw-wave.m` | Setting the window/input callbacks is the handoff point; retained events must be released by the receiver. |
| Choose native/EGL/OSMesa behavior | `GLFWGraphicsHintsApplyDriverEnv`, `demo/src/main-glfw-triangle-opengles.m` | Apply driver env before `[UIApplication sharedInstance]`; explicit context-library selection changes fallback behavior. |
| Query monitors, DPI, or refresh timing | `GLFWOSScreen`, `demo/src/main-glfw-window.m` | Prefer cached `getScreenInfo:` snapshots for cross-thread reads; raw `os_*` monitor queries stay on the main thread. |
| Enumerate or poll controllers | `GLFWOSGamepad`, `src/UIApplication+GLFW.m` | Connection events come from the app category, but button/axis state is still polled on demand. |

## Local workflow

1. Bootstrap with `[UIApplication sharedInstance]`. `src/UIApplication+GLFW.m` does the real `glfwInit`, installs monitor/gamepad callbacks, and owns the event wait/poll glue.
2. Build windows with `GLFWOSWindow`; if they belong to the app loop, add them to `UIApplication` or run them through `runWindow:` / `runApp`.
3. Do one-time GL setup inside `os_activateGraphicsContext` / `os_deactivateGraphicsContext`, then hand steady-state drawing to `frameCallback` plus `frameRate` or `frameRateHz`.
4. Treat `GLFWOSScreen` and `GLFWOSGamepad` as cached wrappers around GLFW handles: poll or refresh on the main thread, then read their snapshot structs wherever the API marks access thread-safe.

## Verify/report

- Window lifetime and shared-context regressions usually show up first in `test/15-glfw/share.m` and `test/15-glfw/noshare.m`.
- Context-lock or activation changes should be compared against `test/15-glfw/activate.m`.
- Backend and event-routing changes are easiest to explain against `demo/src/main-glfw-window.m`, `demo/src/main-glfw-events-objc.m`, `demo/src/main-glfw-events.m`, or `demo/src/main-glfw-triangle-opengles.m`.

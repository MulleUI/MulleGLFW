<!-- keywords: debugger, mulle-glfw, GLFWOSWindow, GLFWOSScreen, GLFWOSGamepad, UIApplication -->
# mulle-glfw

Use this when debugging the repo's GLFW-backed window, event, screen, or gamepad layer. The recurring local families are `GLFWOSWindow`, `GLFWOSWindow (UIEvent)`, `GLFWOSScreen`, `GLFWOSGamepad`, and `UIApplication (GLFW)`.

## Understand first

```bash
mulle-sde api apropos GLFWOSWindow
mulle-sde api cat GLFWOSWindow
mulle-sde api cat GLFWOSScreen
mulle-sde api cat GLFWOSGamepad
mulle-sde code search UIApplication+GLFW
mulle-sde code search os_activateGraphicsContext
```

## Local references

- `README.md`
- `asset/dox/TOC.md`
- `demo/README.md`
- `src/GLFWOSWindow.h`
- `src/GLFWOSWindow.m`
- `src/GLFWOSWindow+UIEvent.h`
- `src/GLFWOSWindow+UIEvent.m`
- `src/GLFWOSScreen.h`
- `src/GLFWOSScreen.m`
- `src/GLFWOSGamepad.h`
- `src/GLFWOSGamepad.m`
- `src/UIApplication+GLFW.m`
- `demo/src/main-glfw-window.m`
- `demo/src/main-glfw-events.m`
- `demo/src/main-glfw-events-objc.m`
- `demo/src/main-glfw-triangle-opengles.m`
- `test/15-glfw/activate.m`
- `test/15-glfw/share.m`
- `test/15-glfw/noshare.m`

## Main debugging surfaces

| If this is failing | Start here | Local check |
| --- | --- | --- |
| Window creation or wrong backend | `GLFWOSWindow`, `demo/src/main-glfw-triangle-opengles.m` | `GLFWGraphicsHintsApplyDriverEnv` must happen before `[UIApplication sharedInstance]`; explicit `hints.lib` disables automatic native/EGL/OSMesa retries. |
| Events missing or arriving on the wrong path | `GLFWOSWindow+UIEvent`, `demo/src/main-glfw-events.m`, `demo/src/main-glfw-events-objc.m` | Decide first whether the repro uses MulleUI event objects or raw GLFW callbacks; the repo ships both paths. |
| Resize or frame timing looks stale | `GLFWOSWindow`, `GLFWOSWindow+UIEvent`, `demo/src/main-glfw-window.m` | During resize, trust `getOSWindowInfo:` and the cached `_windowInfo` path before raw `os_windowFrame`. |
| Context activation, sharing, or teardown breaks | `GLFWOSWindow`, `test/15-glfw/activate.m`, `test/15-glfw/share.m`, `test/15-glfw/noshare.m` | Activation is lock-based, shared windows inherit the creator API, and non-app-owned windows must finalize before app termination. |
| Screen or gamepad state is wrong | `GLFWOSScreen`, `GLFWOSGamepad`, `UIApplication+GLFW` | Screens and gamepads are cached wrappers; update or poll on the main thread, then inspect copied structs. |

## Local workflow

1. Reproduce with the closest shipped sample first: `demo/src/main-glfw-window.m` for geometry/timing, `demo/src/main-glfw-events.m` for MulleUI events, `demo/src/main-glfw-events-objc.m` for raw GLFW callbacks, `demo/src/main-glfw-triangle-opengles.m` for backend selection, `test/15-glfw/*` for sharing/finalize/context activation.
2. Put the first breakpoint where ownership changes: `+[UIApplication sharedInstance]`, `+[UIApplication os_initialize]`, `-initWithFrame:titleUTF8String:styleMask:graphicsHints:sharingWindow:`, `-os_initEvents`, `-os_activateGraphicsContext`, `-displayFrameIfNeeded:`, `-applicationDidRemoveWindow:`.
3. If the window is not app-owned, verify `mullePerformFinalize` or autorelease-pool teardown happens before `[UIApplication terminate]`; the local tests depend on that order.

## Verify/report

- Always report whether the failing path is app-managed (`runApp`/`runWindow`) or a manual raw-GLFW loop.
- For backend failures include the requested hints, style mask, and whether `sharingWindow` or explicit `hints.lib` was involved.
- For input bugs say whether the failing callback got an autoreleased window event or a retained other event.

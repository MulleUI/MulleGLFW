<!-- keywords: GLFWOSWindow, GLFWOSScreen, GLFWOSGamepad, UIApplication, OpenGL, context sharing -->
# mulle-glfw

Use this when verifying app code that uses MulleGLFW windows, events, screen queries, gamepads, or backend/driver selection. The exported families worth checking first are `GLFWOSWindow`, `GLFWOSWindow (UIEvent)`, `GLFWOSScreen`, `GLFWOSGamepad`, and the `UIApplication` GLFW category.

## Understand first

```bash
mulle-sde api apropos GLFWOSWindow
mulle-sde api cat GLFWOSWindow
mulle-sde api cat GLFWOSScreen
mulle-sde api cat GLFWOSGamepad
mulle-sde code search UIApplication+GLFW
mulle-sde code search GLFWGraphicsHintsApplyDriverEnv
```

## Local references

- `README.md`
- `asset/dox/TOC.md`
- `demo/README.md`
- `src/GLFWOSWindow.h`
- `src/GLFWOSWindow.m`
- `src/GLFWOSWindow+UIEvent.h`
- `src/GLFWOSScreen.h`
- `src/GLFWOSGamepad.h`
- `src/UIApplication+GLFW.m`
- `demo/src/main-glfw-triangle-opengles.m`
- `test/15-glfw/activate.m`
- `test/15-glfw/share.m`
- `test/15-glfw/noshare.m`

## Main verification surfaces

| Symptom | Inspect | Local check |
| --- | --- | --- |
| Wrong GL backend, vendor, or renderer | `GLFWGraphicsHintsApplyDriverEnv`, `demo/README.md`, `demo/src/main-glfw-triangle-opengles.m` | Apply hints before `[UIApplication sharedInstance]`. The helper maps hints to `__GLX_VENDOR_LIBRARY_NAME`, `MESA_LOADER_DRIVER_OVERRIDE`, `LD_LIBRARY_PATH`, `LIBGL_DRIVERS_PATH`, `__EGL_VENDOR_LIBRARY_FILENAMES`, `LIBGL_ALWAYS_SOFTWARE`, and `DRI_PRIME`. Mesa runs in this repo also use `MESA_DEBUG=1`. |
| Blank window or bad context ownership | `GLFWOSWindow` | In `DEBUG` builds window creation requests `GLFW_OPENGL_DEBUG_CONTEXT` and logs `os_windowInfoUTF8String` plus `os_contextInfoUTF8String`. Use `haveGraphicsContext`, `activeThread`, `shareID`, and `os_tryActivateGraphicsContext` to see whether the context exists, who owns it, and whether sharing actually happened. |
| Missing, duplicated, or misrouted input | `GLFWOSWindow+UIEvent.h` | `windowEventsCallback` / `windowEventsReceiver` handle autoreleased `UIWindowEvent` objects. `otherRetainedEventsCallback` / `eventsReceiver` handle retained `UIEvent` objects. Setting callback paths changes who sees events. Check `discardEventsMask` before blaming GLFW. |
| Resize, screen, or gamepad state looks stale | `GLFWOSWindow`, `GLFWOSScreen`, `GLFWOSGamepad`, `src/UIApplication+GLFW.m` | During resize prefer `getOSWindowInfo:` over raw `os_windowFrame`. Screen snapshots are lock-backed; `os_*` monitor queries stay on the main thread. Gamepad buttons and axes are poll-on-demand, and joystick callbacks can also fire during polling. |

## Local workflow

1. Reproduce with the closest shipped case first: `demo/src/main-glfw-triangle-opengles.m` for backend selection, `test/15-glfw/activate.m` for activation and lock issues, `test/15-glfw/share.m` and `test/15-glfw/noshare.m` for sharing and teardown.
2. Build the reproducer with `mulle-sde craft --debug` when possible. In this repo, `DEBUG` is what turns on the GL debug context request and the immediate window/context info dump after creation.
3. If you need per-window debug bits, `GLFWOSWindow` seeds `debuggingFlags` from `GLFWOSWindowDebuggingFlags`, then `UIOSWindowDebuggingFlags`, then `UIDebuggingFlags` at class initialization.
4. For manual windows outside the app loop, verify finalization order. The local tests show the safe rule: non-app-owned windows must finalize before `[UIApplication terminate]`, and shared windows should report the same non-zero `shareID`.

## Verify/report

- Report the requested graphics hints, any driver env vars, and the exact `os_contextInfoUTF8String` / `os_windowInfoUTF8String` output.
- Say whether the failing path uses MulleUI events or raw GLFW callbacks, and whether the event object was autoreleased or retained.
- For context bugs include `haveGraphicsContext`, `activeThread`, `shareID`, and whether `os_tryActivateGraphicsContext` failed because the context lock was busy.
- For screen or gamepad bugs say whether the value came from a cached `get*Info:` snapshot or a main-thread `os_*` query or poll.

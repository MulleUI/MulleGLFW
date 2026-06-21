<!-- keywords: debugger, patterns, mulle-glfw, GLFWOSWindow, GLFWOSScreen, GLFWOSGamepad -->
# Patterns

## Start from the nearest shipped repro

- `demo/src/main-glfw-window.m` is the quickest app-managed repro for screen info, frame timing, and raw window-position/size callbacks.
- `demo/src/main-glfw-events.m` keeps the MulleUI event path alive.
- `demo/src/main-glfw-events-objc.m` keeps `GLFWOSWindow` but bypasses MulleUI and waits on raw GLFW callbacks.
- `demo/src/main-glfw-triangle-opengles.m` is the backend-selection repro; it prints the chosen hints and the created context.
- `test/15-glfw/share.m`, `test/15-glfw/noshare.m`, and `test/15-glfw/activate.m` are the smallest lifetime, sharing, and activation probes.

## Debug window bootstrap in repo order

Use the same sequence as `demo/src/main-glfw-triangle-opengles.m`:

```objective-c
GLFWGraphicsHintsApplyDriverEnv( hints);

app = [UIApplication sharedInstance];
gWindow = [GLFWOSWindow windowWithFrame:CGRectMake( 0, 0, 640, 480)
                        titleUTF8String:"Demo"
                              styleMask:styleMask
                          graphicsHints:hints];
[app addWindow:gWindow];

[gWindow os_activateGraphicsContext];
{
   [gWindow os_setSwapInterval:1];
   init_scene();
}
[gWindow os_deactivateGraphicsContext];

[gWindow setFrameCallback:display];
return( [app runApp]);
```

- If failure happens before `sharedInstance`, it is usually driver env or process setup.
- If creation fails inside `initWithFrame:...sharingWindow:`, inspect hint/style-mask translation and fallback conditions.
- If the window exists but the first frame is blank, debug `os_activateGraphicsContext`, `frameCallback`, and `displayFrameIfNeeded:`.

## Split MulleUI event bugs from raw GLFW bugs

The repo gives you both sides on purpose:

```objective-c
/* MulleUI path */
[app addWindow:window];
[window setWindowEventsCallback:receiveWindowEvents];
[window setOtherRetainedEventsCallback:otherRetainedEventsCallback];
return( [app runApp]);
```

```objective-c
/* Raw GLFW path */
gWindow = [GLFWOSWindow windowWithFrame:CGRectMake( 0, 0, 500, 500)
                        titleUTF8String:"Demo"
                              styleMask:UIWindowStyleResizable
                          graphicsHints:GLFW_NO_CONTEXT];
window = [gWindow os_window];
glfwSetKeyCallback( window, key_callback);
while( ! glfwWindowShouldClose( window))
   glfwWaitEvents();
```

- If the raw path works and the MulleUI path fails, stay in `src/GLFWOSWindow+UIEvent.m`.
- If both fail, debug below the wrapper in GLFW setup, thread usage, or the native callback source.

## Debug sharing and teardown with the tests

Use the three `test/15-glfw` programs as narrow probes:

- `share.m`: second window uses `sharingWindow:` and proves shared creation.
- `noshare.m`: non-app-owned window is explicitly finalized with `[window mullePerformFinalize]`.
- `activate.m`: activation/deactivation is exercised in a tight loop, so lock contention and context-switch cost show up quickly.

When a shared window fails, inspect the first window's creation API first. `GLFWOSWindow` forces the new window onto the same GLFW context-creation API before `glfwCreateWindow`.

## Debug cached monitor and gamepad state

For screens, follow `demo/src/main-glfw-window.m` and read the snapshot struct:

```objective-c
[screen getScreenInfo:&info];
mulle_printf( "\trefreshRate  : %.6fs (%.3f Hz)\n",
              info.refreshRate,
              info.refreshRate > 0.0 ? 1.0 / info.refreshRate : 0.0);
```

For gamepads, mirror `src/UIApplication+GLFW.m` and `src/GLFWOSGamepad.m`:

```objective-c
range = [GLFWOSGamepad osIndexRange];
for( i = range.location; i < NSMaxRange( range); i++)
{
   gamepad = [GLFWOSGamepad gamepadAtOSIndex:i];
   if( ! gamepad)
      continue;

   [gamepad os_pollGamepadInfo];
   [gamepad getGamepadInfo:&info];
}
```

- Screen and gamepad snapshots are the stable debugging surface.
- Raw `os_*` monitor/gamepad queries are main-thread-only and are a worse place to start when the bug is "state looks stale".

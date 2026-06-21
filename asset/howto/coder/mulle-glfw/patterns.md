<!-- keywords: mulle-glfw, patterns, GLFWOSWindow, GLFWOSScreen, GLFWOSGamepad -->
# Patterns

## Window + app lifecycle

Use the MulleUI app bootstrap first, then let the window own the GLFW handle:

```objective-c
UIApplication  *app;
GLFWOSWindow   *window;

app = [UIApplication sharedInstance];

window = [GLFWOSWindow windowWithFrame:CGRectMake( 0, 0, 640, 480)
                        titleUTF8String:"Demo"
                              styleMask:UIWindowStyleResizable
                          graphicsHints:GLFW_DEFAULT_CONTEXT];
[app addWindow:window];

[window setWindowEventsCallback:receiveWindowEvents];
[window setOtherRetainedEventsCallback:receiveOtherEvents];

[window os_activateGraphicsContext];
{
   [window os_setSwapInterval:1];
   [window setFrameCallback:display];
   init_opengl();
}
[window os_deactivateGraphicsContext];

[window setFrameRateHz:60.0];
return( [app runApp]);
```

- `demo/src/main-glfw-wave.m` is the clearest local "real app" shape.
- `demo/src/main-glfw-window.m` shows the lighter single-window version and prints screen info before entering the run loop.

## Event-only or raw-GLFW escape hatch

If you want `GLFWOSWindow` to own the native window but keep raw GLFW callbacks, create it with `GLFW_NO_CONTEXT` and use `os_window`:

```objective-c
GLFWOSWindow  *gWindow;
GLFWwindow    *window;

gWindow = [GLFWOSWindow windowWithFrame:CGRectMake( 0, 0, 500, 500)
                         titleUTF8String:"Demo"
                               styleMask:UIWindowStyleResizable
                           graphicsHints:GLFW_NO_CONTEXT];

window = [gWindow os_window];
glfwSetFramebufferSizeCallback( window, framebuffer_size_callback);
glfwSetKeyCallback( window, key_callback);

while( ! glfwWindowShouldClose( window))
   glfwWaitEvents();
```

- `demo/src/main-glfw-events-objc.m` uses this to keep the wrapper while bypassing MulleUI event objects.
- `demo/src/main-glfw-events.m` shows the opposite choice: keep `GLFWOSWindow`, but feed window events and retained input events back into MulleUI callbacks.

## Backend and graphics-hint setup

Use `GLFWGraphicsHints` as the local context description, and apply driver env before app startup:

```objective-c
GLFWGraphicsHints   hints;
GLFWOSWindow       *window;
NSUInteger          styleMask;

hints = GLFW_GLES2_CONTEXT;
hints.lib = 2;  /* EGL */

GLFWGraphicsHintsApplyDriverEnv( hints);

styleMask = UIWindowStyleResizable;
window = [GLFWOSWindow windowWithFrame:CGRectMake( 0, 0, 640, 480)
                        titleUTF8String:"Demo"
                              styleMask:styleMask
                          graphicsHints:hints];
```

- `demo/src/main-glfw-triangle-opengles.m` is the reference for switching API/profile/library combinations from argv.
- If you want automatic native/EGL/OSMesa retries, use `UIWindowOpenGLLibraryFallback` on the style mask and do **not** force `hints.lib`.

## Shared-context windows

Texture/resource sharing is expressed with `sharingWindow:`:

```objective-c
GLFWOSWindow   *master;
GLFWOSWindow   *slave;

master = [GLFWOSWindow windowWithFrame:CGRectMake( 0, 0, 128, 128)
                        titleUTF8String:"Foo"
                              styleMask:UIWindowStyleBare | UIWindowStyleHidden
                          graphicsHints:GLFW_DEFAULT_CONTEXT];

slave  = [GLFWOSWindow windowWithFrame:CGRectMake( 128, 0, 128, 128)
                        titleUTF8String:"Bar"
                              styleMask:UIWindowStyleBare | UIWindowStyleHidden
                          graphicsHints:GLFW_DEFAULT_CONTEXT
                          sharingWindow:master];
```

- `test/15-glfw/share.m` is the minimal local proof that shared creation works.
- `test/15-glfw/noshare.m` shows the matching manual-finalize path when there is no share partner.

## Screen snapshots

Use the cached `UIScreenInfo` snapshot for geometry, canvas, content scale, and refresh timing:

```objective-c
id <UIScreen>         screen;
struct UIScreenInfo   info;
NSUInteger            i;

for( i = 0; screen = [app screenAtIndex:i]; i++)
{
   [screen getScreenInfo:&info];
   mulle_printf( "%s %.3f %.3f\n",
                 [screen nameUTF8String],
                 info.contentScale.dx,
                 info.contentScale.dy);
}
```

- `demo/src/main-glfw-window.m` is the local example for printing monitor data.
- `src/GLFWOSScreen.m` shows that `frame`, `canvas`, and `refreshRate` are lock-backed cached reads, while the `os_*` monitor calls stay main-thread-only.

## Gamepad polling

There is no dedicated demo here; use the public wrapper directly and mirror what `src/UIApplication+GLFW.m` does:

```objective-c
id <UIGamepad>        gamepad;
struct UIGamepadInfo  info;
NSRange               range;
NSUInteger            i;
NSUInteger            max;

range = [GLFWOSGamepad osIndexRange];
max   = NSMaxRange( range);
for( i = range.location; i < max; i++)
{
   gamepad = [GLFWOSGamepad gamepadAtOSIndex:i];
   if( ! gamepad)
      continue;

   [gamepad os_pollGamepadInfo];
   [gamepad getGamepadInfo:&info];
}
```

- Poll on the main thread, then pass the copied `UIGamepadInfo` around.
- Let `UIApplication` own connect/disconnect events; use `GLFWOSGamepad` for per-frame state.

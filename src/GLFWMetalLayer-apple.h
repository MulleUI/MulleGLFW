//
//  GLFWMetalLayer-apple.h
//  MulleGLFW
//
//  Pure C interface to the Apple-runtime Metal layer shim
//  (GLFWMetalLayer-apple.m). Safe to include from mulle-objc translation
//  units: it declares only C functions operating on opaque void * handles and
//  references no Objective-C types.
//
#ifndef mulle_glfw_metal_layer_apple_h__
#define mulle_glfw_metal_layer_apple_h__

#ifdef __APPLE__

#if defined( __cplusplus)
extern "C" {
#endif

// Create + attach a CAMetalLayer to the cocoa window (glfwGetCocoaWindow
// result, passed as void *). Returns an opaque CAMetalLayer * (retained) or
// NULL. Release with MulleGLFWMetalLayerRelease.
void   *MulleGLFWMetalLayerCreate( void *nsWindowPointer);

// Sync the layer's drawableSize to the framebuffer pixel size on resize.
void    MulleGLFWMetalLayerSetDrawableSize( void *layer, double width, double height);

// Acquire the layer's next drawable, clear it to the given RGBA color via a
// render pass, and present it. Pure C boundary; all Metal ObjC messaging is
// contained in the shim. Intended as a minimal on-screen present for tests and
// as a reference present path.
void    MulleGLFWMetalLayerPresentClear( void *layer,
                                         double r, double g, double b, double a);

// Borrowed id<MTLDevice> as void * (not retained), or NULL.
void   *MulleGLFWMetalLayerDevice( void *layer);

// Release the reference from MulleGLFWMetalLayerCreate.
void    MulleGLFWMetalLayerRelease( void *layer);

#if defined( __cplusplus)
}
#endif

#endif // __APPLE__

#endif // mulle_glfw_metal_layer_apple_h__

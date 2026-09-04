//
//  GLFWMetalLayer-apple.m
//  MulleGLFW
//
//  Apple-runtime (system clang) translation unit — NOT compiled with
//  mulle-clang. It is removed from the mulle-objc SOURCES in the top-level
//  CMakeLists.txt and compiled to an object file by the *system* clang (with
//  ARC + the Apple ObjC runtime), then linked into the library. It is the ONLY
//  place that touches Apple Foundation/AppKit/QuartzCore/Metal ObjC objects.
//
//  Do NOT #import any mulle-objc headers here, and this file must never be sent
//  mulle-objc messages: the two runtimes cannot be mixed in one TU. The
//  interface to the rest of MulleGLFW is pure C (opaque void * handles only).
//
//  Ownership across the void * boundary uses CoreFoundation bridging:
//  MulleGLFWMetalLayerCreate returns a +1 reference (CFBridgingRetain), which
//  MulleGLFWMetalLayerRelease balances (CFBridgingRelease). This keeps ARC
//  correct while handing a plain pointer to the mulle-objc side.
//
#ifdef __APPLE__

#import <AppKit/AppKit.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>


void   *MulleGLFWMetalLayerCreate( void *nsWindowPointer)
{
   NSWindow        *nsWindow;
   NSView          *view;
   CAMetalLayer    *metalLayer;
   id <MTLDevice>   device;

   if( ! nsWindowPointer)
      return( NULL);

   // The NSWindow is owned by GLFW; treat as unretained (no ownership change).
   nsWindow = (__bridge NSWindow *) nsWindowPointer;

   // Share ONE MTLDevice process-wide. Each window used to call
   // MTLCreateSystemDefaultDevice() separately; textures created on one device
   // cannot be sampled by another. The two-context (offscreen->screen)
   // architecture shares the offscreen framebuffer texture with the screen
   // context, so they MUST be on the same device.
   static id <MTLDevice>   sharedDevice;
   if( ! sharedDevice)
      sharedDevice = MTLCreateSystemDefaultDevice();
   device = sharedDevice;
   if( ! device)
      return( NULL);

   view = [nsWindow contentView];
   if( ! view)
      return( NULL);

   metalLayer = [CAMetalLayer layer];
   [metalLayer setDevice:device];
   [metalLayer setPixelFormat:MTLPixelFormatBGRA8Unorm];
   [metalLayer setFramebufferOnly:YES];
   [metalLayer setOpaque:YES];

   // A freshly created CAMetalLayer has zero bounds. Setting drawableSize alone
   // makes nextDrawable return a valid texture, but the layer still occupies
   // zero area in the compositing tree -> valid present, blank window. Size the
   // layer to the view and set contentsScale so it actually occupies the view.
   CGSize   viewSize = [view bounds].size;
   CGFloat  scale    = [[nsWindow screen] backingScaleFactor];
   if( scale <= 0.0)
      scale = 1.0;
   [metalLayer setContentsScale:scale];
   [metalLayer setFrame:[view bounds]];
   [metalLayer setDrawableSize:CGSizeMake( viewSize.width * scale,
                                           viewSize.height * scale)];

   // Order matters: assign the layer to the view *before* setting wantsLayer.
   // Setting wantsLayer=YES first makes AppKit create and own its own backing
   // layer (layer-BACKED), and a later setLayer: on an already-backed view is
   // effectively ignored for display — you render into a CAMetalLayer that is
   // never composited (window shows blank). Assigning .layer first and then
   // wantsLayer=YES makes the view layer-HOSTING: it uses our CAMetalLayer as
   // the displayed layer. This matches the canonical GLFW+Metal setup.
   [view setLayer:metalLayer];
   [view setWantsLayer:YES];

   // Hand a +1 reference to the C world; balanced by MulleGLFWMetalLayerRelease.
   return( (void *) CFBridgingRetain( metalLayer));
}


void   MulleGLFWMetalLayerSetDrawableSize( void *layer, double width, double height)
{
   CAMetalLayer   *metalLayer;

   if( ! layer)
      return;

   metalLayer = (__bridge CAMetalLayer *) layer;
   [metalLayer setDrawableSize:CGSizeMake( width, height)];
}


void   MulleGLFWMetalLayerPresentClear( void *layer,
                                        double r, double g, double b, double a)
{
   CAMetalLayer   *metalLayer;

   if( ! layer)
      return;

   metalLayer = (__bridge CAMetalLayer *) layer;

   @autoreleasepool
   {
      // Cache one command queue per device (keyed trivially: the layer's device
      // is stable for the life of the layer here).
      static id <MTLCommandQueue>   queue;
      static id <MTLDevice>         queueDevice;

      id <MTLDevice>   device = [metalLayer device];
      if( ! device)
         return;
      if( queue == nil || queueDevice != device)
      {
         queue       = [device newCommandQueue];
         queueDevice = device;
      }

      id <CAMetalDrawable>   drawable = [metalLayer nextDrawable];
      if( ! drawable)
         return;

      MTLRenderPassDescriptor  *pass = [MTLRenderPassDescriptor renderPassDescriptor];
      pass.colorAttachments[0].texture     = drawable.texture;
      pass.colorAttachments[0].loadAction  = MTLLoadActionClear;
      pass.colorAttachments[0].storeAction = MTLStoreActionStore;
      pass.colorAttachments[0].clearColor  = MTLClearColorMake( r, g, b, a);

      id <MTLCommandBuffer>         buffer  = [queue commandBuffer];
      id <MTLRenderCommandEncoder>  encoder = [buffer renderCommandEncoderWithDescriptor:pass];
      [encoder endEncoding];
      [buffer presentDrawable:drawable];
      [buffer commit];
   }
}


//
//  Two-context reproduction helper.
//
//  This deliberately mirrors what the nanovg Metal backend does in the real
//  app, in isolation, to find where the on-screen result goes gray:
//
//    1. OFFSCREEN context: render a red/white/blue flag into a persistent
//       MTLTexture (analogous to nanovg's framebuffer fb!=0, drawable==0x0,
//       ncalls==3). Uses three scissored clears — no pipeline/shaders needed,
//       keeping the focus on the texture handoff, not on drawing.
//    2. SCREEN context: acquire the layer's nextDrawable and BLIT the offscreen
//       texture into it, then present (analogous to nanovg fb==0, ncalls==1,
//       then presentDrawable:).
//
//  Both contexts use the layer's device (the shared process-wide MTLDevice),
//  so the offscreen texture is valid on the screen context. If this shows the
//  flag, the two-context model is sound and the real gray is a wiring bug in
//  nanovg_mtl.m; if it goes gray, the model itself is suspect.
//
void   MulleGLFWMetalLayerPresentTwoContext( void *layer)
{
   CAMetalLayer   *metalLayer;

   if( ! layer)
      return;

   metalLayer = (__bridge CAMetalLayer *) layer;

   @autoreleasepool
   {
      id <MTLDevice>   device = [metalLayer device];
      if( ! device)
         return;

      // one persistent command queue + offscreen texture, keyed on device
      static id <MTLCommandQueue>   queue;
      static id <MTLDevice>         queueDevice;
      static id <MTLTexture>        offscreen;
      static NSUInteger             offW;
      static NSUInteger             offH;

      if( queue == nil || queueDevice != device)
      {
         queue       = [device newCommandQueue];
         queueDevice = device;
         offscreen   = nil;
      }

      CGSize      dsize = [metalLayer drawableSize];
      NSUInteger  w     = (NSUInteger) dsize.width;
      NSUInteger  h     = (NSUInteger) dsize.height;
      if( w == 0 || h == 0)
         return;

      // ---- 1. OFFSCREEN: build the flag in a texture ----
      //
      // The offscreen texture stands in for nanovg's framebuffer texture
      // (fb != 0). To keep this shader-free and unambiguously correct, we fill
      // the pixels on the CPU (three horizontal bands: blue / white / red) and
      // upload with -replaceRegion:. The texture uses MTLStorageModeManaged so
      // it is both CPU-writable and GPU-blit-readable on macOS. It must live on
      // the SAME device as the drawable (it does: metalLayer.device), which is
      // the invariant the real two-context path depends on.
      //
      // We rebuild only when the size changes.
      if( offscreen == nil || offW != w || offH != h)
      {
         MTLTextureDescriptor  *td;

         td = [MTLTextureDescriptor
                 texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                              width:w
                                             height:h
                                          mipmapped:NO];
         td.usage       = MTLTextureUsageShaderRead;
         td.storageMode = MTLStorageModeManaged;
         offscreen = [device newTextureWithDescriptor:td];
         offW      = w;
         offH      = h;

         if( offscreen)
         {
            NSUInteger  bytesPerRow = w * 4;
            uint8_t    *pixels      = malloc( bytesPerRow * h);
            if( pixels)
            {
               NSUInteger  third = h / 3;
               if( third == 0)
                  third = 1;

               for( NSUInteger y = 0; y < h; y++)
               {
                  uint8_t  r, g, b;
                  if( y < third)            { r = 0;   g = 77;  b = 179; } // blue  (top)
                  else if( y < 2 * third)   { r = 255; g = 255; b = 255; } // white (mid)
                  else                      { r = 217; g = 26;  b = 38;  } // red   (bottom)

                  uint8_t  *row = pixels + y * bytesPerRow;
                  for( NSUInteger x = 0; x < w; x++)
                  {
                     // BGRA8Unorm byte order: B, G, R, A
                     row[ x * 4 + 0] = b;
                     row[ x * 4 + 1] = g;
                     row[ x * 4 + 2] = r;
                     row[ x * 4 + 3] = 255;
                  }
               }

               [offscreen replaceRegion:MTLRegionMake2D( 0, 0, w, h)
                             mipmapLevel:0
                               withBytes:pixels
                             bytesPerRow:bytesPerRow];
               free( pixels);
            }
         }
      }
      if( ! offscreen)
         return;

      // ---- 2. SCREEN: blit the offscreen texture into the drawable ----
      // Mirrors nanovg's screen context (fb == 0, single blit call) then
      // presentDrawable:.
      id <CAMetalDrawable>   drawable = [metalLayer nextDrawable];
      if( ! drawable)
         return;

      id <MTLCommandBuffer>       cb   = [queue commandBuffer];
      id <MTLBlitCommandEncoder>  blit = [cb blitCommandEncoder];
      [blit copyFromTexture:offscreen
                sourceSlice:0
                sourceLevel:0
               sourceOrigin:MTLOriginMake( 0, 0, 0)
                 sourceSize:MTLSizeMake( w, h, 1)
                  toTexture:drawable.texture
           destinationSlice:0
           destinationLevel:0
          destinationOrigin:MTLOriginMake( 0, 0, 0)];
      [blit endEncoding];
      [cb presentDrawable:drawable];
      [cb commit];
   }
}


void   *MulleGLFWMetalLayerDevice( void *layer)
{
   CAMetalLayer     *metalLayer;
   id <MTLDevice>    device;

   if( ! layer)
      return( NULL);

   metalLayer = (__bridge CAMetalLayer *) layer;
   device     = [metalLayer device];
   // Borrowed (unretained) — caller must not release.
   return( (__bridge void *) device);
}


void   MulleGLFWMetalLayerRelease( void *layer)
{
   if( ! layer)
      return;

   // Balances the CFBridgingRetain in MulleGLFWMetalLayerCreate; ARC releases
   // the transferred object at the end of scope.
   CFBridgingRelease( layer);
}

#endif // __APPLE__

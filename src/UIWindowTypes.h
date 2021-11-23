//
// Copyright (c) 2021 Nat!, Mulle kybernetiK
//
// basically a future, but GLFWWindow also adopts it
// the only reason for this is a little type safety
@protocol UIWindow < NSObject>
@end



enum UIWindowStyleMask
{
//  UIWindowStyleClosable        = 0x1,
//  UIWindowStyleMiniaturizable  = 0x2,
  UIWindowStyleResizable             = 0x4,
  UIWindowStyleInvisible             = 0x8,
  UIWindowStyleNoEdgeAntialias       = 0x10,  // nanvg
  UIWindowStyleNoStencilStrokes      = 0x20,  // nanovg
  UIWindowStyleRenderNonRetainedOnly = 0x40,  // use UIWindowBackingStoreNonRetained
  UIWindowStyleOffscreen             = 0x80
};

typedef NSUInteger   UIWindowStyleMask;


enum UIWindowBackingStoreType
{
   UIWindowBackingStoreBuffered,        // safe default
   UIWindowBackingStoreNonRetained      // draws to "volatile" window framebuffer only
                                        // still dual buffered but needs fast code
                                        // to avoid ugliness during resize
};

typedef NSUInteger   UIWindowBackingStoreType;

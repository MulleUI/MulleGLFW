//
//  GLFWOSScreen.m
//  MulleGLFW
//
//  Copyright (c) 2022 Nat! - Mulle kybernetiK.
//  Copyright (c) 2022 Codeon GmbH.
//  All rights reserved.
//
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are met:
//
//  Redistributions of source code must retain the above copyright notice, this
//  list of conditions and the following disclaimer.
//
//  Redistributions in binary form must reproduce the above copyright notice,
//  this list of conditions and the following disclaimer in the documentation
//  and/or other materials provided with the distribution.
//
//  Neither the name of Mulle kybernetiK nor the names of its contributors
//  may be used to endorse or promote products derived from this software
//  without specific prior written permission.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
//  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
//  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
//  ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
//  LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
//  CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
//  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
//  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
//  CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
//  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
//  POSSIBILITY OF SUCH DAMAGE.
//
#import "GLFWOSScreen.h"

#import "import-private.h"



@implementation GLFWOSScreen

- (instancetype) initWithGLFWMonitor:(void *) monitor
{
   char   *name;

   if( ! monitor)
   {
      [self release];
      return( nil);
   }

   _infoLock = [NSLock new];
   _monitor  = monitor;

   glfwSetMonitorUserPointer( _monitor, self);

   [self updateScreenInfo];

   name = [self os_nameUTF8String];
   if( ! name)
      name = MulleObjC_asprintf( "Unnamed monitor %p", monitor);

   MulleObjCObjectSetDuplicatedUTF8String( self, &_nameUTF8String, name);

   return( self);
}


- (void) finalize
{
   glfwSetMonitorUserPointer( _monitor, NULL);
   [super finalize];
}


- (void) dealloc
{
   MulleObjCObjectSetDuplicatedUTF8String( self, &_nameUTF8String, NULL);

   [_infoLock release];
   [super dealloc];  // call at end
}


- (void) updateScreenInfo
{
   GLFWvidmode   *mode;

   assert( [NSThread mulleIsMainThread]);
   assert( _monitor);

   NSLockingDo( _infoLock)
   {
      mode                = (GLFWvidmode *) glfwGetVideoMode( _monitor);

      _info.frame.origin  = CGPointMakeWithPixelPoint( [self os_position]);
      _info.frame.size    = CGSizeMake( mode->width, mode->height);
      _info.canvas        = CGRectMakeWithPixelRect( [self os_canvas]);
      _info.contentScale  = [self os_contentScale];
      _info.physicalSize  = [self os_physicalSize];
      _info.dpi           = [self os_dpi];
      _info.colorBits[ 0] = mode->redBits;
      _info.colorBits[ 1] = mode->greenBits;
      _info.colorBits[ 2] = mode->blueBits;
      _info.colorBits[ 3] = -1;  // unknown
      _info.refreshRate   = mode->refreshRate != 0.0 ? 1.0 / mode->refreshRate : 0.0;
   }
}


- (void) getScreenInfo:(struct UIScreenInfo *) info
{
   NSLockingDo( _infoLock)
   {
      *info = _info;
   }
}


- (mulle_relativetime_t) refreshRate
{
   mulle_relativetime_t   refreshRate;

   NSLockingDo( _infoLock)
   {
      refreshRate = _info.refreshRate;
   }

   return( refreshRate);
}


- (CGRect) frame
{
   CGRect   rect;

   NSLockingDo( _infoLock)
   {
      rect = _info.frame;
   }

   return( rect);
}


- (CGRect) canvas
{
   CGRect   rect;

   NSLockingDo( _infoLock)
   {
      rect = _info.canvas;
   }

   return( rect);
}


+ (NSUInteger) numberOfScreens
{
   int   n;

   assert( [NSThread mulleIsMainThread]);

   n = 0;
   glfwGetMonitors( &n);
   return( n);
}


+ (id <UIScreen>) screenAtIndex:(NSUInteger) i
{
   int            n;
   GLFWmonitor    **monitors;
   GLFWmonitor    *monitor;
   id <UIScreen>  screen;

   assert( [NSThread mulleIsMainThread]);

   monitors = glfwGetMonitors( &n);
   if( i >= n)
      return( nil);

   monitor = monitors[ i];
   screen  = glfwGetMonitorUserPointer( monitor);
   if( ! screen)
      screen = [[[GLFWOSScreen alloc] initWithGLFWMonitor:monitor] autorelease];

   return( screen);
}


// example method
//- (id) method:(id) argument
//{
//   return( self);
//}
- (char *) os_nameUTF8String
{
   assert( [NSThread mulleIsMainThread]);
   assert( _monitor);

   return( (char *) glfwGetMonitorName( _monitor));
}


- (CGVector) os_contentScale;
{
   float   xscale, yscale;

   assert( [NSThread mulleIsMainThread]);
   assert( _monitor);

   xscale = yscale = 1.0;
   glfwGetMonitorContentScale( _monitor, &xscale, &yscale);
   return( CGVectorMake( xscale, yscale));
}


- (CGFloat) os_dpi
{
   int          w, h;
   CGFloat      hdpi, vdpi;
   GLFWvidmode  *mode;

   assert( [NSThread mulleIsMainThread]);
   assert( _monitor);

   mode = (GLFWvidmode *) glfwGetVideoMode( _monitor);
   if( ! mode)
      return( 72.0);

   w = h = 0;
   glfwGetMonitorPhysicalSize( _monitor, &w, &h);
   if( ! w || ! h)
      return( 72.0);

   // width height in mm
   hdpi = (mode->width / w) * 10.0 * 2.54;      // mm -> cm -> inch
   vdpi = (mode->height / h) * 10.0 * 2.54;
   return( hdpi < vdpi ? hdpi : vdpi);
}


- (CGSize) os_physicalSize
{
   int   w, h;

   assert( [NSThread mulleIsMainThread]);
   assert( _monitor);

   w = h = 0;
   glfwGetMonitorPhysicalSize( _monitor, &w, &h);
   if( ! w)
      w = 42000.0f; // 19" 
   if( ! h)
      h = 23600.0f; // 19"
   return( CGSizeMake( w / 1000.0, h / 1000.0));
}


- (CGPixelRect) os_canvas
{
   int   x, y, w, h;

   assert( [NSThread mulleIsMainThread]);
   assert( _monitor);

   x = y = w = h = 0;
   glfwGetMonitorWorkarea( _monitor, &x, &y, &w, &h);
   return( CGPixelRectMake( x, y, w, h));
}


- (CGPixelPoint) os_position
{
   int   x, y;

   assert( [NSThread mulleIsMainThread]);
   assert( _monitor);

   x = y = 0;
   glfwGetMonitorPos( _monitor, &x, &y);
   return( CGPixelPointMake( x, y));
}


- (BOOL) os_isPrimaryScreen
{
   assert( [NSThread mulleIsMainThread]);
   assert( _monitor);

   return( glfwGetPrimaryMonitor() == _monitor);
}

@end

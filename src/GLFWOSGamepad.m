//
//  GLFWOSGamepad.m
//  MulleGLFW
//
//  Copyright (c) 2024 Nat! - Mulle kybernetiK.
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
#import "GLFWOSGamepad.h"

#import "import-private.h"

#import <MulleObjC/NSDebug.h>


@implementation GLFWOSGamepad

// GLFW finds too much junk
// see: https://github.com/glfw/glfw/issues/2484
//
+ (BOOL) isValidJoystickInfo:(struct UIGamepadInfo *) info
                      osName:(char *) name
                      osGuid:(char *) guid
{
   if( ! name || ! guid)
      return( NO);

   if( ! info->isJoystick)  // gamepad is not suspicious
      return( YES);

   if( info->numberOfButtons == 0)
      return( NO);
   if( info->numberOfSticks == 0 && info->numberOfAxes == 0)
      return( NO);

//    if( strncmp( guid, "0300", 4))
//      return( NO);
   // unfortunately not good enough
   if( strstr( name, "LED")
       || strstr( name, "Mouse")
       || strstr( name, "Touchpad"))
      return( NO);

   return( YES); // MAYBE
}


- (instancetype) initWithOSGamepad:(void *) handle
{
   char   *osName;
   char   *osGuid;
   char   *name;

   _handle = (int) (intptr_t) handle;
   if( _handle < GLFW_JOYSTICK_1 || _handle > GLFW_JOYSTICK_LAST)
   {
      [self release];
      return( nil);
   }

   // if this is not the case then another joystick is still dangling
   assert( glfwGetJoystickUserPointer( _handle) == NULL);

   // some other devices are found as joysticks/gamepads, though they aren't
   // we do some sanity checks on the device (need at least a hat/axis and
   // one button)

   osGuid = [self os_guidUTF8String];
   osName = [self os_nameUTF8String];
   [self os_pollGamepadInfo];

   if( ! [[self class] isValidJoystickInfo:&_info
                                    osName:osName
                                    osGuid:osGuid])
   {
      if( NSDebugEnabled)
      {
         MulleUILog( "\"%s\" does not look like a valid joystick", osName ? osName : (osGuid ? osGuid : "???"));
      }
      [self release];
      return( nil);
   }

   name = osName ? osName : MulleObjC_asprintf( "Gamepad #%d", _handle);
   MulleObjCObjectSetDuplicatedUTF8String( self, &_nameUTF8String, name);
   if( osGuid)
      MulleObjCObjectSetDuplicatedUTF8String( self, &_guidUTF8String, osGuid);

   _infoLock = [NSLock new];
   glfwSetJoystickUserPointer( _handle, self);

   return( self);
}


- (void) finalize
{
   glfwSetJoystickUserPointer( _handle, NULL);
   [super finalize];
}


- (void) dealloc
{
   MulleObjCObjectSetDuplicatedUTF8String( self, &_guidUTF8String, NULL);
   MulleObjCObjectSetDuplicatedUTF8String( self, &_nameUTF8String, NULL);

   [_infoLock release];
   [super dealloc];  // call at end
}


static inline CADirection   CADirectionMakeWithGLFWHatDirection( unsigned int glfwHat)
{
    return ((glfwHat & 1) << 0) |   // Up
           ((glfwHat & 2) << 2) |   // Right
           ((glfwHat & 4) >> 1) |   // Down
           ((glfwHat & 8) >> 1);    // Left
}


// copy hats, from back to front (so we easily pick out the first)
static inline void   UIGamepadInfoMemcpyGLFWHats( unsigned char *dst, unsigned char *src, unsigned int n)
{
   unsigned char   *sentinel;
   unsigned char   *p;

   p        = dst;
   sentinel = &dst[ n];
   while( p < sentinel)
      *p++ = (unsigned char) CADirectionMakeWithGLFWHatDirection( *src++);
}


- (void) os_pollGamepadInfo
{
   assert( [NSThread mulleIsMainThread]);

   unsigned char      *hats;
   unsigned char      *buttons;
   float              *axes;
   GLFWgamepadstate   glfwState;
   int                n;

   NSLockingDo( _infoLock)
   {
      _previousInfo = _info;
      memset( &_info, 0, sizeof( _info));

      _info.isJoystick = ! glfwJoystickIsGamepad( _handle);

      // joystick is "legacy" :)
      if( _info.isJoystick)
      {
         buttons = (unsigned char *) glfwGetJoystickButtons( _handle, &n);
         if( n > UIGamepadInfoMaxButtons)
            n = UIGamepadInfoMaxButtons;
         _info.numberOfButtons = n;

         hats = (unsigned char *) glfwGetJoystickHats( _handle, &n);
         if( n > UIGamepadInfoMaxSticks)
            n = UIGamepadInfoMaxSticks;
         _info.numberOfSticks = n;

         axes = (float *) glfwGetJoystickAxes( _handle, &n);
         if( n > UIGamepadInfoMaxAxes)
            n = UIGamepadInfoMaxAxes;
         _info.numberOfAxes = n;

         memcpy( &_info.buttons, buttons, _info.numberOfButtons);
         UIGamepadInfoMemcpyGLFWHats( _info.sticks,
                                      hats,
                                      _info.numberOfSticks);
         memcpy( _info.axes, axes, _info.numberOfAxes * sizeof( float));
      }
      else
      {
         glfwGetGamepadState( _handle, (GLFWgamepadstate *) &glfwState);

         // copy button state, except dpad state( if there are buttons behind)
         // these are compatible
         memcpy( _info.buttons, glfwState.buttons, UIGamepadButtonRightThumb + 1);
         memcpy( _info.axes, glfwState.axes, 6);

         _info.sticks[ 0] = (glfwState.buttons[ GLFW_GAMEPAD_BUTTON_DPAD_UP] ? CADirectionUp : 0)
                                  | (glfwState.buttons[ GLFW_GAMEPAD_BUTTON_DPAD_DOWN] ? CADirectionDown : 0)
                                  | (glfwState.buttons[ GLFW_GAMEPAD_BUTTON_DPAD_LEFT] ? CADirectionLeft : 0)
                                  | (glfwState.buttons[ GLFW_GAMEPAD_BUTTON_DPAD_RIGHT] ? CADirectionRight : 0);

         _info.numberOfButtons = 14;
         _info.numberOfSticks  = 1;
         _info.numberOfAxes    = 6;
      }
   }
}


- (void) getGamepadInfo:(struct UIGamepadInfo *) info
{
   NSLockingDo( _infoLock)
   {
      *info = _info;
   }
}


+ (NSUInteger) numberOfGamepads
{
   int   i, n;

   assert( [NSThread mulleIsMainThread]);

   n = 0;
   for( i = GLFW_JOYSTICK_1; i <= GLFW_JOYSTICK_LAST; i++)
      if( glfwJoystickPresent( i))
         ++n;
   return( n);
}


+ (id <UIGamepad>) gamepadAtOSIndex:(NSUInteger) i
{
   id <UIGamepad>  gamepad;
   int             handle;

   assert( [NSThread mulleIsMainThread]);

   handle = (int) i;
   if( ! glfwJoystickPresent( handle))
      return( nil);

   gamepad = glfwGetJoystickUserPointer( handle);
   if( gamepad == NULL)
      gamepad = [[[GLFWOSGamepad alloc] initWithOSGamepad:(void *) (intptr_t) handle] autorelease];

   return( gamepad);
}


// example method
//- (id) method:(id) argument
//{
//   return( self);
//}
- (char *) os_nameUTF8String
{
   assert( [NSThread mulleIsMainThread]);

   if( glfwJoystickIsGamepad( _handle))
      return( (char *) glfwGetGamepadName( _handle));
   return( (char *) glfwGetJoystickName( _handle));
}


- (char *) os_guidUTF8String
{
   assert( [NSThread mulleIsMainThread]);

   return( (char *) glfwGetJoystickGUID( _handle));
}


+ (NSRange) osIndexRange
{
   return( NSRangeMake( GLFW_JOYSTICK_1, GLFW_JOYSTICK_LAST - GLFW_JOYSTICK_1 + 1));
}


- (NSInteger) osIndex
{
   return( (NSInteger) _handle);
}



- (BOOL) isJoystick
{
   BOOL   flag;

   NSLockingDo( _infoLock)
   {
      flag = _info.isJoystick;
   }
   return( flag);
}


- (BOOL) stateOfGamepadButton:(UIGamepadButton) button
{
   BOOL   flag;

   NSLockingDo( _infoLock)
   {
      flag = UIGamepadInfoGetButton( &_info, button);
   }
   return( flag);
}


- (CADirection) direction
{
   CADirection   direction;

   NSLockingDo( _infoLock)
   {
      direction = UIGamepadInfoGetDPad( &_info);
   }
   return( direction);
}


- (BOOL) getDigitalStickWithIndex:(NSUInteger) index
                        direction:(CADirection *) direction
{
   BOOL   flag;

   NSLockingDo( _infoLock)
   {
      flag = index < _info.numberOfSticks;
      if( flag)
         *direction = UIGamepadInfoGetDigitalStick( &_info, index);
   }
   return( flag);
}


- (BOOL) getAnalogStickWithIndex:(NSUInteger) index
                            axes:(float [ 3]) axes
{
   BOOL   flag;

   NSLockingDo( _infoLock)
   {
      flag = index < _info.numberOfAxes * 3;
      if( flag)
         UIGamepadInfoGetAnalogStick( &_info, index, axes);
   }
   return( flag);
}


- (char *) UTF8String
{
   char   *s;

   s = MulleObjC_asprintf( "<%s %p \"%s\">",
                           MulleObjCInstanceGetClassNameUTF8String( self),
                           self,
                           _nameUTF8String);
   return( s);
}


@end

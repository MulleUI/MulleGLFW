#import "UIEvent.h"


@implementation UIEvent
enum
{
   UIKeyboardEventIndex,  // Keyboard
   UIUnicodeEventIndex,  // Unicode char (interpreted Keyboard)
   UIMouseButtonEventIndex,  // Mouse click
   UIMouseMotionEventIndex,  // Mouse movemeent
   UIMouseScrollEventIndex   // Mouse Scrollwheel
};
#define N_UIEventIndexMax  (UIMouseScrollEventIndex + 1)

static struct
{
   struct mulle__pointerqueue   _reuseEventQueues[ N_UIEventIndexMax];
   BOOL                         _reuseEvents;
   BOOL                         _initialized;
} UIEventSelf;


+ (void) enableEventsReuse
{
   unsigned int   i;

   assert( ! UIEventSelf._reuseEvents);

   for( i = 0; i < N_UIEventIndexMax; i++)
      _mulle__pointerqueue_init( &UIEventSelf._reuseEventQueues[ i], 32, 4);
   UIEventSelf._reuseEvents = YES;
}


+ (void) initialize
{
   if( ! UIEventSelf._initialized)
   {
      if( mulle_objc_environment_get_yes_no_default( "MULLE_UI_REUSE_EVENTS", YES))
         [self enableEventsReuse];
      UIEventSelf._initialized = YES;
   }
}


static void   deallocateAllEventsInQueue( struct mulle__pointerqueue *p)
{
   struct mulle__pointerqueueenumerator  rover;
   UIEvent                               *event;

   rover = _mulle__pointerqueue_enumerate( p);
   while( _mulle__pointerqueueenumerator_next( &rover, (void **) &event))
      NSDeallocateObject( event);
   mulle__pointerqueueenumerator_done(&rover);
}


+ (void) disableEventsReuse
{
   unsigned int             i;
   struct mulle_allocator   *allocator;

   assert( UIEventSelf._reuseEvents);
   // dont't re-accumulate
   UIEventSelf._reuseEvents = NO;

   allocator = MulleObjCClassGetAllocator( self);
   for( i = 0; i < N_UIEventIndexMax; i++)
   {
      deallocateAllEventsInQueue( &UIEventSelf._reuseEventQueues[ i]);
      _mulle__pointerqueue_done( &UIEventSelf._reuseEventQueues[ i],
                                 allocator);
   }
}


+ (void) deinitialize
{
   if( UIEventSelf._reuseEvents)
      [self disableEventsReuse];
   UIEventSelf._initialized = NO;
}


+ (BOOL) reuseEvents
{
   return( UIEventSelf._reuseEvents);
}


+ (void) setReuseEvents:(BOOL) flag
{
   if( UIEventSelf._reuseEvents == flag)
      return;
   if( UIEventSelf._reuseEvents)
      [self disableEventsReuse];
   else
      [self enableEventsReuse];
}


static id   allocateEventWithIndex( Class self, unsigned int index)
{
   struct mulle__pointerqueue       *p;
   UIEvent                          *event;
   UIEvent                          *reuse;
   struct _mulle_objc_objectheader  *header;
   struct _mulle_objc_class         *cls;

   p     = &UIEventSelf._reuseEventQueues[ index];
   reuse = _mulle__pointerqueue_pop( p, MulleObjCClassGetAllocator( self));
   if( reuse)
   {
      // since the event is going to be overwritten completely we forego
      // zeroing it
      assert( [reuse class] == self);

      cls    = _mulle_objc_infraclass_as_class( self);
      header = _mulle_objc_object_get_objectheader( reuse);
      _mulle_objc_objectheader_init( header, cls, cls->headerextrasize, 0);
      event  = reuse;
   }
   else
      event = NSAllocateObject( self, 0, NULL);

   assert( [event retainCount] == 1);
   assert( [event class] == self);

   return( event);
}


static void   deallocateEventWithIndex( UIEvent *self, unsigned int index)
{
   struct mulle__pointerqueue   *p;

   if( ! UIEventSelf._reuseEvents)
   {
      NSDeallocateObject( self);
      return;
   }

   p = &UIEventSelf._reuseEventQueues[ index];
   _mulle__pointerqueue_push( p, self, MulleObjCInstanceGetAllocator( self));
}


- (instancetype) initWithMouseLocation:(CGPoint) pos
                             modifiers:(NSUInteger) mods
{
   _locationInWindow  = pos;
   _timestamp         = CAAbsoluteTimeNow();
   _modifiers         = mods;
   _translatedPoint.x = CGFLOAT_MIN; // not set
   return( self);
}

static int   UIEventIsFirstResponderPointSet( UIEvent *event)
{
   return( event->_translatedPoint.x != CGFLOAT_MIN);
}

+ (void) waitForEventsHz:(double) hz
{
   if( hz == 0.0)
      [self os_pollEvents];
   else
      [self os_waitEventsTimeout:1.0 / hz];
}


+ (void) sendEmptyEvent
{
   [self os_sendEmptyEvent];
}



- (char *) UTF8String
{
   char   *s;

   s = MulleObjC_asprintf( "<%p %s @%.1f %.1f t:%.6f>",
                  self,
                  MulleObjCClassGetNameUTF8String( NSClassFromObject( self)),
                  _locationInWindow.x,
                  _locationInWindow.y,
                  _timestamp);
   return( s);
}

@end


@implementation UIKeyboardEvent

+ (id) alloc
{
   return( allocateEventWithIndex( self, UIKeyboardEventIndex));
}


- (void) dealloc
{
   deallocateEventWithIndex( self, UIKeyboardEventIndex);
}



- (instancetype) initWithMouseLocation:(CGPoint) pos
                             modifiers:(NSUInteger) mods
                                   key:(NSUInteger) key
                              scanCode:(NSUInteger) scanCode
                                action:(NSUInteger) action
{
   self = [self initWithMouseLocation:pos
                            modifiers:mods];

   _key       = key;
   _scanCode  = scanCode;
   _action    = action;

   return( self);
}

- (UIEventType) eventType
{
   return( UIEventTypePresses);
}

@end



// Receive a OS unicode character (w/o key press)
@implementation UIUnicodeEvent

+ (id) alloc
{
   return(  allocateEventWithIndex( self, UIUnicodeEventIndex));
}

- (void) dealloc
{
   deallocateEventWithIndex( self, UIUnicodeEventIndex);
}


- (instancetype) initWithMouseLocation:(CGPoint) pos
                             modifiers:(NSUInteger) mods
                             character:(NSUInteger) character
{
   self = [self initWithMouseLocation:pos
                            modifiers:mods];

   _character = character;

   return( self);
}

- (UIEventType) eventType
{
   return( UIEventTypeUnicode);
}


@end


@implementation UIMouseMotionEvent


+ (id) alloc
{
   return(  allocateEventWithIndex( self, UIMouseMotionEventIndex));
}

- (void) dealloc
{
   deallocateEventWithIndex( self, UIMouseMotionEventIndex);
}


- (UIEventType) eventType
{
   return( UIEventTypeMotion);
}


- (instancetype) initWithMouseLocation:(CGPoint) pos
                             modifiers:(NSUInteger) mods
                          buttonStates:(NSUInteger) buttonStates
{
   self = [self initWithMouseLocation:pos
                            modifiers:mods];

   _buttonStates = buttonStates;

   return( self);
}

@end


@implementation UIMouseButtonEvent

+ (id) alloc
{
   return(  allocateEventWithIndex( self, UIMouseButtonEventIndex));
}

- (void) dealloc
{
   deallocateEventWithIndex( self, UIMouseButtonEventIndex);
}


- (instancetype) initWithMouseLocation:(CGPoint) pos
                             modifiers:(NSUInteger) mods
                                button:(NSUInteger) button
                                action:(NSUInteger) action
{
   self = [self initWithMouseLocation:pos
                            modifiers:mods];
   _button = button;
   _action = action;

   return( self);
}


- (UIEventType) eventType
{
   return( UIEventTypeTouches);
}


- (char *) UTF8String
{
   char   *s;

   s = MulleObjC_asprintf( "<%p %s @%.1f %.1f t:%.6f b:%d a:%d>",
                  self,
                  MulleObjCClassGetNameUTF8String( NSClassFromObject( self)),
                  _locationInWindow.x,
                  _locationInWindow.y,
                  _timestamp,
                  _button,
                  _action);
   return( s);
}

@end


@implementation UIMouseScrollEvent

+ (id) alloc
{
   return( allocateEventWithIndex( self, UIMouseScrollEventIndex));
}


- (void) dealloc
{
   deallocateEventWithIndex( self, UIMouseScrollEventIndex);
}

static struct
{
   CGFloat   _acceleration;
} Self =
{
   3.0
};


- (instancetype) initWithMouseLocation:(CGPoint) pos
                             modifiers:(NSUInteger) mods
                          scrollOffset:(CGPoint) scrollOffset
{
   self = [self initWithMouseLocation:pos
                            modifiers:mods];
   _scrollOffset = scrollOffset;

   return( self);
}


- (UIEventType) eventType
{
   return( UIEventTypeScroll);
}


+ (CGFloat) scrollWheelAcceleration
{
   return( Self._acceleration);
}


+ (void) setScrollWheelAcceleration:(CGFloat) value
{
   Self._acceleration = value;
}

- (CGPoint) acceleratedScrollOffset
{
   CGPoint   offset;

   offset.x = _scrollOffset.x * Self._acceleration;
   offset.y = _scrollOffset.y * Self._acceleration;

   return( offset);
}

@end


// 95% renderzeit
//  5% eventzeit
//  30 FPS
//
// Q: how many events do we need to queue ?
//
// Assumption is that event handling takes no time, so an infinite amount of
// events could be handled.
//
// 1s/30 = 0.033s
// 0.033 * 0.95 = queue time = 0.030  30ms
//
//
// Input frequency of mouse ?  lets say 2000Hz for a gaming mice
// Actually could basically drop/filter those ?
//
// 1s/2000 = 0.0005
//
// 8000 / 60 = 133 samples


@implementation UIWindowEvent

- (UIEventType) eventType
{
   return( UIEventTypeWindow);
}
@end


@implementation UIWindowCloseEvent

- (enum UIWindowEventType) windowEventType
{
   return( UIWindowEventTypeClose);
}

@end


@implementation UIWindowMoveEvent

- (instancetype) initWithMouseLocation:(CGPoint) pos
                             modifiers:(NSUInteger) mods
                                origin:(struct CGBitmapPoint) origin
{
   self = [self initWithMouseLocation:pos
                            modifiers:mods];
   _origin = origin;
   return( self);
}

- (enum UIWindowEventType) windowEventType
{
   return( UIWindowEventTypeMove);
}

@end


@implementation UIWindowResizeEvent : UIWindowEvent

- (instancetype) initWithMouseLocation:(CGPoint) pos
                             modifiers:(NSUInteger) mods
                                  size:(struct CGBitmapSize) size
{
   self  = [self initWithMouseLocation:pos
                             modifiers:mods];
   _size = size;
   return( self);
}

- (enum UIWindowEventType) windowEventType
{
   return( UIWindowEventTypeResize);
}

@end


@implementation UIWindowFramebufferResizeEvent

- (enum UIWindowEventType) windowEventType
{
   return( UIWindowEventTypeFramebufferResize);
}

@end


@implementation UIWindowRefreshEvent

- (enum UIWindowEventType) windowEventType
{
   return( UIWindowEventTypeRefresh);
}

@end

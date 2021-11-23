#import "import.h"


// bits suitable or bitmasking
enum
{                              // leave 0 to nil
   UIEventTypePresses = 0x01,  // Keyboard
   UIEventTypeUnicode = 0x02,  // Unicode char (interpreted Keyboard)
   UIEventTypeTouches = 0x04,  // Mouse click
   UIEventTypeMotion  = 0x08,  // Mouse movemeent
   UIEventTypeScroll  = 0x10,  // Mouse Scrollwheel
   UIEventTypeWindow  = 0x20   // Window event (close, resize, move etc)
};

typedef NSUInteger   UIEventType;
//
// As we are using glfw, the main object queue is in the main thread
// we retrieve objects from a central growing array of possibly used
// objects and reuse them. When we reclaim an object from a queue, we
// need to put up a memory barrier, so the receiver does not see stale
// data. An UIEvent is not read/only as _translatedPoint is used for
// storing by UIView for efficiency (temporarily used)
//
// You can turn off reuse by setting the environment variable
// MULLE_UI_REUSE_EVENTS to NO, which may come in handy for leak detection.
//
@interface UIEvent : NSObject
{
   CGPoint   _translatedPoint;
   id        _translatedView; // NOT READONLY!!
}

@property( assign, readonly) CGPoint   locationInWindow;

// clock() vs clock_gettime() tests on linux show, that that clock
// is 25% faster. That's IMO not enough to forego the convenience of
// CAAbsoluteTime here
@property( assign, readonly) CAAbsoluteTime   timestamp;

// current known state of modifier keys
@property( assign, readonly) NSUInteger  modifiers;

+ (BOOL) reuseEvents;
+ (void) setReuseEvents:(BOOL) flag;

+ (void) waitForEventsHz:(double) hz;
+ (void) sendEmptyEvent;

- (instancetype) initWithMouseLocation:(CGPoint) pos
                             modifiers:(NSUInteger) mods;
@end


@interface UIEvent( Subclasses)

- (UIEventType) eventType;

@end

/*
 * Subclasses
 */

@interface UIKeyboardEvent : UIEvent

@property( assign, readonly) NSUInteger   key;
@property( assign, readonly) NSUInteger   scanCode;
@property( assign, readonly) NSUInteger   action;

- (instancetype) initWithMouseLocation:(CGPoint) pos
                             modifiers:(NSUInteger) mods
                                   key:(NSUInteger) key
                              scanCode:(NSUInteger) scanCode
                                action:(NSUInteger) action;
@end


// Receive a OS unicode character (w/o key press)
@interface UIUnicodeEvent : UIEvent

@property( assign, readonly) NSUInteger   character;

- (instancetype) initWithMouseLocation:(CGPoint) pos
                             modifiers:(NSUInteger) mods
                             character:(NSUInteger) key;

@end


@interface UIMouseButtonEvent : UIEvent

@property( assign, readonly) NSUInteger   button;
@property( assign, readonly) NSUInteger   action;

- (instancetype) initWithMouseLocation:(CGPoint) pos
                             modifiers:(NSUInteger) mods
                                button:(NSUInteger) button
                                action:(NSUInteger) action;


@end


@interface UIMouseMotionEvent : UIEvent

- (instancetype) initWithMouseLocation:(CGPoint) pos
                             modifiers:(NSUInteger) mods
                          buttonStates:(NSUInteger) buttonStates;

@property( assign, readonly) NSUInteger   buttonStates;

@end


@interface UIMouseScrollEvent : UIEvent

- (instancetype) initWithMouseLocation:(CGPoint) pos
                             modifiers:(NSUInteger) mods
                          scrollOffset:(CGPoint) offset;

@property( assign, readonly) CGPoint   scrollOffset;

+ (CGFloat) scrollWheelAcceleration;
+ (void) setScrollWheelAcceleration:(CGFloat) value;

- (CGPoint) acceleratedScrollOffset;

@end


enum UIWindowEventType
{
   UIWindowEventTypeClose             = 0x01,
   UIWindowEventTypeRefresh           = 0x02,
   UIWindowEventTypeResize            = 0x04,
   UIWindowEventTypeMove              = 0x08,
   UIWindowEventTypeFramebufferResize = 0x10
};


@interface UIWindowEvent : UIEvent
@end


@interface UIWindowEvent( Subclasses)

- (enum UIWindowEventType) windowEventType;

@end


@interface UIWindowMoveEvent : UIWindowEvent

- (instancetype) initWithMouseLocation:(CGPoint) pos
                             modifiers:(NSUInteger) mods
                                origin:(struct CGBitmapPoint) pos;

@property( assign, readonly) struct CGBitmapPoint   origin;

@end


@interface UIWindowCloseEvent : UIWindowEvent
@end


@interface UIWindowRefreshEvent : UIWindowEvent
@end


@interface UIWindowResizeEvent : UIWindowEvent

- (instancetype) initWithMouseLocation:(CGPoint) pos
                             modifiers:(NSUInteger) mods
                                  size:(struct CGBitmapSize) size;

@property( assign, readonly) struct CGBitmapSize   size;

@end


@interface UIWindowFramebufferResizeEvent : UIWindowResizeEvent
@end


@interface UIEvent( OS)

+ (void) os_waitEventsTimeout:(CGFloat) seconds;
+ (void) os_pollEvents;
+ (void) os_sendEmptyEvent;

@end


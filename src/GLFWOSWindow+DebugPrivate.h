// use generic OSWindow for this and SDLOSWindow
enum
{
   UIOSWindowDebug                 = 0x000001,
   UIOSWindowDebugVerbose          = 0x001000,

   UIOSWindowDebugEvent            = 0x000002,
   UIOSWindowDebugEventVerbose     = 0x002000,

   UIOSWindowDebugMouseMotionEvent = 0x1000000
};



#if ! defined( UI_OS_WINDOW_DEBUG_DISABLED)

@interface NSObject ( UIOSWindow)

- (BOOL) __isUIOSWindow;

@end


#define UIOSWindowLog( format, ...)                                         \
do                                                                          \
{                                                                           \
   assert( [self __isUIOSWindow]);                                          \
   if( self->_debugEnabled & UIOSWindowDebug)                               \
      mulleui_log_object_method( self, (char *) __PRETTY_FUNCTION__,        \
                                       (char *) format, ## __VA_ARGS__);    \
}                                                                           \
while( 0)

#define UIOSWindowLogVerbose( format, ...)                                  \
do                                                                          \
{                                                                           \
   assert( [self __isUIOSWindow]);                                          \
   if( self->_debugEnabled & UIOSWindowDebugVerbose)                        \
      mulleui_log_object_method( self, (char *) __PRETTY_FUNCTION__,        \
                                       (char *) format, ## __VA_ARGS__);    \
}                                                                           \
while( 0)


#define UIOSWindowEventLog( format, ...)                                    \
do                                                                          \
{                                                                           \
   assert( [self __isUIOSWindow]);                                          \
   if( self->_debugEnabled & UIOSWindowDebugEvent)                          \
      mulleui_log_object_method( self, (char *) __PRETTY_FUNCTION__,        \
                                       (char *) format, ## __VA_ARGS__);    \
}                                                                           \
while( 0)


#define UIOSWindowEventLogVerbose( format, ...)                             \
{                                                                           \
   assert( [self __isUIOSWindow]);                                          \
   if( self->_debugEnabled & UIOSWindowDebugEventVerbose)                   \
      mulleui_log_object_method( self, (char *) __PRETTY_FUNCTION__,        \
                                       (char *) format, ## __VA_ARGS__);    \
}                                                                           \
while( 0)


#define UIOSWindowMouseMotionEventLog( format, ...)                         \
do                                                                          \
{                                                                           \
   assert( [self __isUIOSWindow]);                                          \
   if( self->_debugEnabled & UIOSWindowDebugMouseMotionEvent)               \
      mulleui_log_object_method( self, (char *) __PRETTY_FUNCTION__,        \
                                       (char *) format, ## __VA_ARGS__);    \
}                                                                           \
while( 0)


#else

#define UIOSWindowLog( format, ...)                  do {} while( 0)
#define UIOSWindowLogVerbose( format, ...)           do {} while( 0)
#define UIOSWindowEventLog( format, ...)             do {} while( 0)
#define UIOSWindowEventLogVerbose( format, ...)      do {} while( 0)
#define UIOSWindowMouseMotionEventLog( format, ...)  do {} while( 0)

#endif



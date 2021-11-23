#import "import.h"

#import "UIWindowTypes.h"

//
// MEMO: unhandled events, are they passed to the application ? If yes
//       it could be a problem. Application would needs its own queue,
//       which is managed by the main thread.
//
@interface UIApplication : NSObject <MulleObjCSingleton>
{
   struct mulle_array   _windows;   
}

@property( assign) id   delegate;      // unused so far
@property( assign) int  returnValue;
 
- (void) addWindow:(id <UIWindow>) window;
// does not call [UIWindow terminate]
- (void) removeWindow:(id<UIWindow>) window;


// call terminate on all windows and then remove all of them 
- (int) terminate;

// will never return, call terminate from somewhere to die
- (void) run;

- (NSUInteger) numberOfWindows;
- (NSUInteger) getWindows:(id<UIWindow> *) buf
                   length:(NSUInteger) length;

@end


@interface UIApplication( OS)

+ (void) os_initialize;
+ (void) os_terminate;

@end

int  UIApplicationMain( int argc, char **argv, Class appClass, id delegate);


#ifdef __MULLE_OBJC__

#import <MulleObjC/MulleObjC.h>

//
// This header file is required to be public, to enable other libraries that
// depend on this library to properly declare their load in their
// MulleObjcLoader class.
//
@interface MulleObjCDeps( MulleGLFW)

+ (struct _mulle_objc_dependency *) dependencies;

@end

#endif


/*
 * extension : mulle-objc/objc
 * directory : project-oneshot/library
 * template  : .../MulleObjCDeps+PROJECT_NAME.h
 * Suppress this comment with `export MULLE_SDE_GENERATE_FILE_COMMENTS=NO`
 */

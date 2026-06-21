cmake_minimum_required( VERSION 3.13...99.99)

project( MulleGLFW-craftinfo LANGUAGES NONE)


# install build script, if any into "${DEPENDENCY_DIR}/bin"

file( GLOB SCRIPTS
   bin/MulleGLFW-build
   bin/MulleGLFW-build.*
)

list( FILTER SCRIPTS EXCLUDE REGEX ".*[.]example")

if( SCRIPTS)
	install( FILES ${SCRIPTS} DESTINATION "bin"
	         PERMISSIONS OWNER_EXECUTE OWNER_WRITE OWNER_READ
	                     GROUP_EXECUTE GROUP_READ
	                     WORLD_EXECUTE WORLD_READ
	)
endif()

# install craftinfos

file( GLOB DEFINITION_DIRS
   definition*
)

if( DEFINITION_DIRS)
	foreach( DIR ${DEFINITION_DIRS} )
	   install( DIRECTORY "${DIR}" DESTINATION "share/mulle-craft/MulleGLFW"
	            USE_SOURCE_PERMISSIONS
	            PATTERN "*._DS_Store" EXCLUDE
	   )
	endforeach()
else()
   message( SEND_ERROR "Remove craftinfo \"MulleGLFW\" as it is empty with:\n   mulle-sourcetree remove craftinfo/MulleGLFW\n   rm -rf craftinfo/MulleGLFW")
endif()

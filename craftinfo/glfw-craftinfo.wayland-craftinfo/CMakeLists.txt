cmake_minimum_required( VERSION 3.15...99.99)

project( glfw-craftinfo NONE)


# install build script, if any into "${DEPENDENCY_DIR}/bin"

file( GLOB SCRIPTS
   bin/glfw-build
   bin/glfw-build.*
)

if( SCRIPTS)
	install( FILES "${SCRIPTS}" DESTINATION "bin"
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
	   install( DIRECTORY "${DIR}" DESTINATION "share/mulle-craft/glfw"
	            USE_SOURCE_PERMISSIONS
	            PATTERN "*._DS_Store" EXCLUDE
	   )
	endforeach()
else()
   message( FATAL_ERROR "Remove craftinfo \"glfw\" as it is empty with:\n   mulle-sourcetree remove craftinfo/glfw\n   rm -rf craftinfo/glfw")
endif()


# extension : mulle-sde/craftinfo
# directory : project/all
# template  : .../CMakeLists.txt
# Suppress this comment with `export MULLE_SDE_GENERATE_FILE_COMMENTS=NO`

cmake_minimum_required(VERSION 3.12)

if (NOT DEFINED TEST_DIRECTORY)
    message(FATAL_ERROR "TEST_DIRECTORY is required")
endif()

set(REAVEROS_BINARY_DIR "${TEST_DIRECTORY}")
file(MAKE_DIRECTORY "${TEST_DIRECTORY}")
include("${CMAKE_CURRENT_LIST_DIR}/../cmake/target_functions.cmake")

set(_patch "${TEST_DIRECTORY}/example.patch")
file(WRITE "${_patch}" "first revision\n")
reaveros_patch_dependency(_dependency example revision-a "${_patch}")
get_property(_configure_dependencies DIRECTORY PROPERTY CMAKE_CONFIGURE_DEPENDS)
if (NOT _patch IN_LIST _configure_dependencies)
    message(FATAL_ERROR "Patch files must trigger CMake regeneration")
endif()
file(READ "${_dependency}" _first_hash)
file(TIMESTAMP "${_dependency}" _first_timestamp "%s")

execute_process(COMMAND "${CMAKE_COMMAND}" -E sleep 1.1)
reaveros_patch_dependency(_same_dependency example revision-a "${_patch}")
file(TIMESTAMP "${_dependency}" _same_timestamp "%s")
if (NOT _same_dependency STREQUAL _dependency
    OR NOT _same_timestamp STREQUAL _first_timestamp)
    message(FATAL_ERROR "Unchanged patch contents invalidated the build")
endif()

execute_process(COMMAND "${CMAKE_COMMAND}" -E sleep 1.1)
file(WRITE "${_patch}" "second revision\n")
reaveros_patch_dependency(_changed_dependency example revision-a "${_patch}")
file(READ "${_dependency}" _second_hash)
file(TIMESTAMP "${_dependency}" _second_timestamp "%s")
if (_second_hash STREQUAL _first_hash
    OR NOT _second_timestamp GREATER _same_timestamp)
    message(FATAL_ERROR "Changed patch contents did not invalidate the build")
endif()

file(WRITE "${_patch}" "first revision\n")
reaveros_patch_dependency(_reverted_dependency example revision-a "${_patch}")
file(READ "${_dependency}" _reverted_hash)
if (NOT _reverted_hash STREQUAL _first_hash)
    message(FATAL_ERROR "Reverted patch contents did not invalidate the build")
endif()

reaveros_patch_dependency(_new_revision_dependency example revision-b "${_patch}")
file(READ "${_dependency}" _new_revision_hash)
if (_new_revision_hash STREQUAL _first_hash)
    message(FATAL_ERROR "Changed source revision did not invalidate the build")
endif()

message(STATUS "Toolchain patch dependency tests passed")

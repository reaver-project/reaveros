cmake_minimum_required(VERSION 3.12)
project(reaveros-meta C CXX)

set(REAVEROS_SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR})
set(REAVEROS_BINARY_DIR ${CMAKE_CURRENT_BINARY_DIR})

set(REAVEROS_C_STANDARD "11")
set(REAVEROS_CXX_STANDARD "20")

option(REAVEROS_USE_CACHE "Enable the use of a cache program in builds." ON)
set(REAVEROS_CACHE_PROGRAM "ccache" CACHE STRING "Name of the cache program to use (defaults to ccache).")

set(REAVEROS_CMAKE ${REAVEROS_BINARY_DIR}/install/toolchain/cmake/bin/cmake)
set(REAVEROS_CTEST ${REAVEROS_BINARY_DIR}/install/toolchain/cmake/bin/ctest)
set(REAVEROS_THORN ${REAVEROS_BINARY_DIR}/install/toolchain/thorn/bin/thorn)

if (REAVEROS_USE_CACHE)
    find_program(_cache_program ${REAVEROS_CACHE_PROGRAM})
    if (_cache_program)
        set(CMAKE_C_COMPILER_LAUNCHER ${_cache_program})
        set(CMAKE_CXX_COMPILER_LAUNCHER ${_cache_program})
    endif()
    mark_as_advanced(_cache_program)
endif()

if (NOT GIT_EXECUTABLE OR NOT GIT_VERSION_STRING)
    find_package(Git QUIET)
    if (NOT GIT_EXECUTABLE)
        message(FATAL_ERROR "error: could not find git")
    endif()
endif()

if (${CMAKE_VERSION} VERSION_GREATER_EQUAL 3.19)
    cmake_policy(SET CMP0113 NEW)
    cmake_policy(SET CMP0114 NEW)
endif()
include(ExternalProject)

if (${CMAKE_VERSION} VERSION_GREATER_EQUAL 3.20)
    set(_REAVEROS_CONFIGURE_HANDLED_BY_BUILD CONFIGURE_HANDLED_BY_BUILD TRUE)
else()
    set(_REAVEROS_CONFIGURE_HANDLED_BY_BUILD "")
endif()

set(REAVEROS_ARCHITECTURES "amd64" CACHE STRING "List of architectures to build for. Possible values: amd64.")
set(REAVEROS_LOADERS "uefi" CACHE STRING "List of loaders to build images with. Possible values: uefi (amd64 only).")

include(cmake/target_functions.cmake)

reaveros_add_aggregate_targets("")
add_custom_target(all-toolchain)

option(REAVEROS_ENABLE_UNIT_TESTS OFF)
if (REAVEROS_ENABLE_UNIT_TESTS)
    set(_REAVEROS_TEST_TARGET test)
endif()

reaveros_add_aggregate_targets(kernels)
reaveros_add_aggregate_targets_with_modes(libraries)

add_subdirectory(toolchain)

set(_saved "${CMAKE_CURRENT_BINARY_DIR}")
set(CMAKE_CURRENT_BINARY_DIR "${CMAKE_CURRENT_BINARY_DIR}/kernel")
reaveros_include_component(kernel "" kernels)
set(CMAKE_CURRENT_BINARY_DIR "${_saved}")

add_subdirectory(libraries)
add_subdirectory(loaders)
add_subdirectory(userspace)
add_subdirectory(images)

if (REAVEROS_ENABLE_UNIT_TESTS)
    enable_testing()

    set(_trampoline "${CMAKE_CURRENT_BINARY_DIR}/ctest_trampoline.cmake")

    get_property(components GLOBAL PROPERTY _REAVEROS_COMPONENTS)

    set(properties_for_trampoline "")
    foreach (component IN LISTS components)
        ExternalProject_Get_Property(${component} BINARY_DIR)
        get_property(labels TARGET ${component} PROPERTY _REAVEROS_COMPONENT_LABELS)
        get_property(display_name TARGET ${component} PROPERTY _REAVEROS_COMPONENT_TEST_NAME)

        set(properties_for_trampoline
"${properties_for_trampoline}
set(component_directory_${component} ${BINARY_DIR})
set(component_labels_${component} ${labels})
set(component_names_${component} ${display_name})
"
        )
    endforeach()

    configure_file(
        "${CMAKE_CURRENT_LIST_DIR}/cmake/ctest_trampoline.cmake.in"
        "${_trampoline}"
        @ONLY
    )
    set_property(
        DIRECTORY "${CMAKE_CURRENT_LIST_DIR}"
        PROPERTY
            TEST_INCLUDE_FILE "${_trampoline}"
    )

    add_custom_target(run-tests ctest .)
    add_dependencies(run-tests all-build-tests)
endif()

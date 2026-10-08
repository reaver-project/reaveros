cmake_minimum_required(VERSION 3.31)
if (NOT CMAKE_GENERATOR STREQUAL "Unix Makefiles")
    message(FATAL_ERROR "Unsupported CMake generator '${CMAKE_GENERATOR}'.\nReaverOS requires GNU Make. Configure with -G 'Unix Makefiles'.")
endif()
project(reaveros-meta LANGUAGES NONE)
execute_process(COMMAND "${CMAKE_MAKE_PROGRAM}" --version
    RESULT_VARIABLE _reaveros_make_result OUTPUT_VARIABLE _reaveros_make_version
    ERROR_QUIET TIMEOUT 10)
if (NOT _reaveros_make_result EQUAL 0 OR NOT _reaveros_make_version MATCHES "^GNU Make ")
    message(FATAL_ERROR "ReaverOS requires GNU Make; selected '${CMAKE_MAKE_PROGRAM}' is unsupported.")
endif()
enable_language(C CXX)

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
    # A reused build directory may have cached a different launcher.
    unset(_cache_program CACHE)
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

include(ExternalProject)
include(toolchain/targets.cmake)

set(_REAVEROS_CONFIGURE_HANDLED_BY_BUILD CONFIGURE_HANDLED_BY_BUILD TRUE)

set(REAVEROS_ARCHITECTURES "amd64" CACHE STRING "List of target CPU architectures to enable. Possible values: amd64.")
set(REAVEROS_LOADERS "uefi" CACHE STRING "List of bootloaders to enable. Possible values: uefi (amd64 only).")

function(_reaveros_validate_selection _name)
    set(_seen_values "")
    foreach (_value IN LISTS ${_name})
        if (NOT _value IN_LIST ARGN)
            message(FATAL_ERROR "Unsupported value '${_value}' for ${_name}. Supported values: ${ARGN}.")
        endif()
        if (_value IN_LIST _seen_values)
            message(FATAL_ERROR "Duplicate value '${_value}' in ${_name}.")
        endif()
        list(APPEND _seen_values "${_value}")
    endforeach()
endfunction()

if ("${REAVEROS_ARCHITECTURES}" STREQUAL "")
    message(FATAL_ERROR "REAVEROS_ARCHITECTURES must select at least one target CPU architecture.")
endif()
_reaveros_validate_selection(REAVEROS_ARCHITECTURES ${_reaveros_architectures})
_reaveros_validate_selection(REAVEROS_LOADERS uefi)

include(cmake/target_functions.cmake)
reaveros_require_host_python()
reaveros_require_host_tools("Toolchain helpers and kernel symbol extraction" bash tail grep awk)

reaveros_add_aggregate_targets("")
add_custom_target(all-toolchain)

option(REAVEROS_ENABLE_UNIT_TESTS "Enable unit tests for project components." OFF)

reaveros_add_aggregate_targets(kernels)
reaveros_add_aggregate_targets_with_modes(libraries)

add_subdirectory(toolchain)

# Dependencies can refer to these before their producers are registered after
# libraries. This preserves the existing hosted/freestanding bootstrap order.
foreach (_architecture IN LISTS REAVEROS_ARCHITECTURES)
    add_custom_target(kernel-interface-${_architecture})
    add_custom_target(kernel-bootinit-${_architecture})
endforeach()

reaveros_include_component(kernel
    BINARY_ROOT "${CMAKE_CURRENT_BINARY_DIR}/kernel"
    TAGS kernels
)

add_subdirectory(libraries)
include(kernel/components.cmake)
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
set(component_directory_${component} [==[${BINARY_DIR}]==])
set(component_labels_${component} [==[${labels}]==])
set(component_names_${component} [==[${display_name}]==])
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

    add_custom_target(run-tests
        COMMAND "${REAVEROS_CTEST}" --test-dir "${CMAKE_CURRENT_BINARY_DIR}"
        VERBATIM)
    add_dependencies(run-tests all-build-tests)
endif()

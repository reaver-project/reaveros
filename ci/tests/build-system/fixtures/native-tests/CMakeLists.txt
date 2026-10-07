cmake_minimum_required(VERSION 3.31)
project(native-test-superbuild LANGUAGES NONE)
include(ExternalProject)
enable_testing()

set(REAVEROS_SOURCE_DIR "${TEST_REPOSITORY}")
set(REAVEROS_CTEST "${CMAKE_CTEST_COMMAND}")
set(components alpha beta headers)
set(properties_for_trampoline "")
foreach (component IN LISTS components)
    ExternalProject_Add(${component}
        SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/child"
        DOWNLOAD_COMMAND "" INSTALL_COMMAND "" BUILD_ALWAYS TRUE
        CMAKE_ARGS "-DTEST_REPOSITORY=${TEST_REPOSITORY}"
            "-DTEST_COMPONENT=${component}" "-DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}"
            "-DTEST_HEADER_ONLY=$<STREQUAL:${component},headers>"
    )
    ExternalProject_Get_Property(${component} BINARY_DIR)
    string(APPEND properties_for_trampoline
        "set(component_directory_${component} [==[${BINARY_DIR}]==])\n"
        "set(component_names_${component} [==[${component}]==])\n"
        "set(component_labels_${component} [==[native;${component}]==])\n")
endforeach()
add_custom_target(all-build-tests DEPENDS ${components})
configure_file("${TEST_REPOSITORY}/cmake/ctest_trampoline.cmake.in"
    "${CMAKE_CURRENT_BINARY_DIR}/ctest_trampoline.cmake" @ONLY)
set_property(DIRECTORY PROPERTY TEST_INCLUDE_FILE "${CMAKE_CURRENT_BINARY_DIR}/ctest_trampoline.cmake")

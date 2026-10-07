cmake_minimum_required(VERSION 3.31)
project(registration-child LANGUAGES NONE)

get_filename_component(_component "${CMAKE_CURRENT_SOURCE_DIR}" NAME)
set(_prerequisites "common-${REAVEROS_ARCH}")
if (_component STREQUAL "alpha")
    list(APPEND _prerequisites
        "${REAVEROS_BUILD_MODE}-first-${REAVEROS_ARCH}"
        "${REAVEROS_BUILD_MODE}-second-${REAVEROS_ARCH}")
endif()
foreach (_prerequisite IN LISTS _prerequisites)
    if (NOT EXISTS "${REAVEROS_FIXTURE_ROOT}/${_prerequisite}")
        message(FATAL_ERROR "Missing configure prerequisite '${_prerequisite}'.")
    endif()
endforeach()
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/${_component}.txt" "${REAVEROS_BUILD_MODE}\n")
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/${_component}.txt" DESTINATION usr/include)

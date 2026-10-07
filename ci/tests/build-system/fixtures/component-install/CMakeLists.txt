cmake_minimum_required(VERSION 3.31)
project(component-install-test CXX)

include(ExternalProject)
include("${TEST_REPOSITORY}/cmake/target_functions.cmake")
set(REAVEROS_SOURCE_DIR "${TEST_REPOSITORY}")
set(REAVEROS_BINARY_DIR "${CMAKE_BINARY_DIR}")
set(REAVEROS_CMAKE "${CMAKE_COMMAND}")
set(_REAVEROS_CONFIGURE_HANDLED_BY_BUILD CONFIGURE_HANDLED_BY_BUILD TRUE)

configure_file(native-toolchain.cmake
    "${CMAKE_BINARY_DIR}/install/toolchain/files/amd64-freestanding.cmake" COPYONLY)
add_custom_target(toolchain-llvm-install)
reaveros_add_component(
    NAME alpha SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/alpha"
    BINARY_ROOT "${CMAKE_CURRENT_BINARY_DIR}"
    ARCHITECTURES amd64 MODES freestanding
    INSTALL_PATH [=[sysroots/${_architecture}-${_mode}]=]
)
set(_beta_dependencies "")
if (TEST_BETA_DEPENDS_ON_ALPHA)
    set(_beta_dependencies alpha-freestanding-amd64)
endif()
set(_beta_transfer "")
if (DEFINED TEST_BETA_INSTALL_TRANSFER_FROM)
    list(APPEND _beta_transfer INSTALL_TRANSFER_FROM "${TEST_BETA_INSTALL_TRANSFER_FROM}")
endif()
if (DEFINED TEST_BETA_INSTALL_TRANSFER_ROOTS)
    list(APPEND _beta_transfer INSTALL_TRANSFER_ROOTS ${TEST_BETA_INSTALL_TRANSFER_ROOTS})
endif()
reaveros_add_component(
    NAME beta SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/beta"
    BINARY_ROOT "${CMAKE_CURRENT_BINARY_DIR}"
    ARCHITECTURES amd64 MODES freestanding
    INSTALL_PATH [=[sysroots/${_architecture}-${_mode}]=]
    DEPENDS ${_beta_dependencies}
    ${_beta_transfer}
)
add_custom_target(components DEPENDS alpha-freestanding-amd64 beta-freestanding-amd64)

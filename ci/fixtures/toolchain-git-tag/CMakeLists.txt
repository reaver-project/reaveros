cmake_minimum_required(VERSION 3.28)
project(toolchain-git-tag-test NONE)

include(ExternalProject)
include("${REAVEROS_SOURCE_DIR}/cmake/target_functions.cmake")

set(REAVEROS_BINARY_DIR "${CMAKE_CURRENT_BINARY_DIR}")

ExternalProject_Add(example
    GIT_REPOSITORY "${TEST_REMOTE}"
    GIT_TAG "${TEST_TAG}"
    GIT_SHALLOW TRUE
    UPDATE_DISCONNECTED TRUE
    STEP_TARGETS install
    CONFIGURE_COMMAND ""
    BUILD_COMMAND ""
    INSTALL_COMMAND ""
)
reaveros_add_ep_fetch_tag_target(example "${TEST_REVISION}")

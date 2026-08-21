set(patch_files
    ${CMAKE_CURRENT_LIST_DIR}/cmake/patches/000-reaveros.patch
)

ExternalProject_Add(toolchain-cmake
    GIT_REPOSITORY ${REAVEROS_CMAKE_REPO}
    GIT_TAG ${REAVEROS_CMAKE_TAG}
    GIT_SHALLOW TRUE
    UPDATE_DISCONNECTED 1

    STEP_TARGETS install

    INSTALL_DIR ${REAVEROS_BINARY_DIR}/install/toolchain/cmake

    ${_REAVEROS_CONFIGURE_HANDLED_BY_BUILD}

    PATCH_COMMAND ""

    CMAKE_ARGS
        -DCMAKE_C_COMPILER_LAUNCHER=${CMAKE_C_COMPILER_LAUNCHER}
        -DCMAKE_CXX_COMPILER_LAUNCHER=${CMAKE_CXX_COMPILER_LAUNCHER}
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>
)
ExternalProject_Add_Step(toolchain-cmake
    apply-patches
    COMMAND git reset --hard
    COMMAND git clean -fxd
    COMMAND git apply ${patch_files}
    DEPENDEES set-to-tag
    DEPENDERS configure
    DEPENDS ${patch_files}
    WORKING_DIRECTORY <SOURCE_DIR>
)
reaveros_add_ep_prune_target(toolchain-cmake)
reaveros_add_ep_fetch_tag_target(toolchain-cmake)

reaveros_register_target(toolchain-cmake-install toolchain)

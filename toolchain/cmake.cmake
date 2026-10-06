set(patch_files
    ${CMAKE_CURRENT_LIST_DIR}/cmake/patches/000-reaveros.patch
)
reaveros_patch_dependency(
    patch_dependency toolchain-cmake ${REAVEROS_CMAKE_REVISION} ${patch_files}
)

_reaveros_ep_arguments(_cmake_args _cmake_separator
    "${CMAKE_CURRENT_SOURCE_DIR};${REAVEROS_BINARY_DIR};${CMAKE_COMMAND};${GIT_EXECUTABLE}"
    "-DCMAKE_MAKE_PROGRAM=${CMAKE_MAKE_PROGRAM}"
    "-DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}"
    "-DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}"
    ${_reaveros_host_compiler_args}
    "-DCMAKE_C_COMPILER_LAUNCHER=${CMAKE_C_COMPILER_LAUNCHER}"
    "-DCMAKE_CXX_COMPILER_LAUNCHER=${CMAKE_CXX_COMPILER_LAUNCHER}"
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>)
ExternalProject_Add(toolchain-cmake
    GIT_REPOSITORY ${REAVEROS_CMAKE_REPO}
    GIT_TAG ${REAVEROS_CMAKE_TAG}
    GIT_SHALLOW TRUE
    UPDATE_DISCONNECTED 1

    STEP_TARGETS install

    INSTALL_DIR ${REAVEROS_BINARY_DIR}/install/toolchain/cmake

    ${_REAVEROS_CONFIGURE_HANDLED_BY_BUILD}

    PATCH_COMMAND ""
    LIST_SEPARATOR "${_cmake_separator}"
    CMAKE_ARGS ${_cmake_args}
)
ExternalProject_Add_Step(toolchain-cmake
    apply-patches
    COMMAND "${GIT_EXECUTABLE}" reset --hard
    COMMAND "${GIT_EXECUTABLE}" clean -fxd
    COMMAND "${GIT_EXECUTABLE}" checkout --detach ${REAVEROS_CMAKE_REVISION}
    COMMAND "${GIT_EXECUTABLE}" apply ${patch_files}
    DEPENDEES set-to-tag
    DEPENDERS configure
    DEPENDS ${patch_dependency}
    WORKING_DIRECTORY <SOURCE_DIR>
)
reaveros_add_ep_prune_target(toolchain-cmake
    REQUIRED_INSTALLED_OUTPUTS bin/cmake bin/ctest bin/cpack)
reaveros_add_ep_fetch_tag_target(toolchain-cmake ${REAVEROS_CMAKE_REVISION})
reaveros_add_ep_source_identity_step(toolchain-cmake ${REAVEROS_CMAKE_REVISION}
    DEPENDEES set-to-tag)

reaveros_register_target(toolchain-cmake-install toolchain)

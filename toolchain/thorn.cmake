_reaveros_ep_arguments(_thorn_args _thorn_separator
    "${CMAKE_CURRENT_SOURCE_DIR};${REAVEROS_BINARY_DIR};${REAVEROS_CMAKE}"
    "-DCMAKE_MAKE_PROGRAM=${CMAKE_MAKE_PROGRAM}"
    "-DCMAKE_C_COMPILER=${CMAKE_C_COMPILER}"
    "-DCMAKE_CXX_COMPILER=${CMAKE_CXX_COMPILER}"
    "-DCMAKE_C_COMPILER_LAUNCHER=${CMAKE_C_COMPILER_LAUNCHER}"
    "-DCMAKE_CXX_COMPILER_LAUNCHER=${CMAKE_CXX_COMPILER_LAUNCHER}"
    "-DCMAKE_PROJECT_INCLUDE=${REAVEROS_BINARY_DIR}/install/toolchain/files/project-policy.cmake"
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>)
ExternalProject_Add(toolchain-thorn
    DOWNLOAD_COMMAND ""
    SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/thorn
    BUILD_ALWAYS 1

    STEP_TARGETS install

    DEPENDS toolchain-cmake-install

    INSTALL_DIR ${REAVEROS_BINARY_DIR}/install/toolchain/thorn

    ${_REAVEROS_CONFIGURE_HANDLED_BY_BUILD}

    CMAKE_COMMAND ${REAVEROS_CMAKE}
    LIST_SEPARATOR "${_thorn_separator}"
    CMAKE_ARGS ${_thorn_args}
)

reaveros_register_target(toolchain-thorn-install toolchain)

ExternalProject_Add(toolchain-dosfstools
    GIT_REPOSITORY ${REAVEROS_DOSFSTOOLS_REPO}
    GIT_TAG ${REAVEROS_DOSFSTOOLS_TAG}
    GIT_SHALLOW TRUE
    UPDATE_DISCONNECTED 1

    PATCH_COMMAND "${GIT_EXECUTABLE}" checkout --detach ${REAVEROS_DOSFSTOOLS_REVISION}

    STEP_TARGETS install

    INSTALL_DIR ${REAVEROS_BINARY_DIR}/install/toolchain/dosfstools

    ${_REAVEROS_CONFIGURE_HANDLED_BY_BUILD}

    CONFIGURE_COMMAND cd <SOURCE_DIR> && <SOURCE_DIR>/autogen.sh
    COMMAND <SOURCE_DIR>/configure --prefix=<INSTALL_DIR>
        "CC=${CMAKE_C_COMPILER_LAUNCHER} ${CMAKE_C_COMPILER}"
        "CXX=${CMAKE_CXX_COMPILER_LAUNCHER} ${CMAKE_CXX_COMPILER}"
    BUILD_COMMAND $(MAKE)
    INSTALL_COMMAND $(MAKE) install
)
reaveros_add_ep_prune_target(toolchain-dosfstools)
reaveros_add_ep_fetch_tag_target(toolchain-dosfstools ${REAVEROS_DOSFSTOOLS_REVISION})
reaveros_add_ep_source_identity_step(toolchain-dosfstools ${REAVEROS_DOSFSTOOLS_REVISION}
    DEPENDEES set-to-tag)

reaveros_register_target(toolchain-dosfstools-install toolchain)

ExternalProject_Add(toolchain-mtools
    URL ${REAVEROS_MTOOLS_DIR}/${REAVEROS_MTOOLS_VER}
    URL_HASH SHA256=${REAVEROS_MTOOLS_SHA256}
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
    UPDATE_DISCONNECTED 1

    STEP_TARGETS install

    INSTALL_DIR ${REAVEROS_BINARY_DIR}/install/toolchain/mtools

    ${_REAVEROS_CONFIGURE_HANDLED_BY_BUILD}

    CONFIGURE_COMMAND <SOURCE_DIR>/configure --prefix=<INSTALL_DIR>
        "CC=${CMAKE_C_COMPILER_LAUNCHER} ${CMAKE_C_COMPILER}"
        "CXX=${CMAKE_CXX_COMPILER_LAUNCHER} ${CMAKE_CXX_COMPILER}"
    BUILD_COMMAND $(MAKE)
    INSTALL_COMMAND $(MAKE) install
)
reaveros_add_ep_prune_target(toolchain-mtools)
reaveros_add_ep_source_identity_step(toolchain-mtools ${REAVEROS_MTOOLS_SHA256}
    DEPENDEES download update patch)

reaveros_register_target(toolchain-mtools-install toolchain)

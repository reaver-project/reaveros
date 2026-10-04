set(steps
    CONFIGURE_COMMAND "${CMAKE_COMMAND}" -E touch <BINARY_DIR>/configured
    BUILD_COMMAND "${CMAKE_COMMAND}" -E true
    INSTALL_COMMAND "${CMAKE_COMMAND}" -E touch <INSTALL_DIR>/installed
)

ExternalProject_Add(toolchain-git
    GIT_REPOSITORY "${TEST_REMOTE}"
    GIT_TAG fixture
    GIT_SHALLOW TRUE
    UPDATE_DISCONNECTED TRUE
    STEP_TARGETS install
    INSTALL_DIR "${REAVEROS_BINARY_DIR}/install/toolchain/git"
    ${steps}
)
reaveros_add_ep_prune_target(toolchain-git)
reaveros_add_ep_fetch_tag_target(toolchain-git "${TEST_REVISION}")
reaveros_add_ep_source_identity_step(toolchain-git "${TEST_REVISION}"
    DEPENDEES set-to-tag)

ExternalProject_Add(toolchain-archive
    URL "${TEST_ARCHIVE}"
    URL_HASH "SHA256=${TEST_ARCHIVE_HASH}"
    DOWNLOAD_NO_EXTRACT TRUE
    UPDATE_DISCONNECTED TRUE
    STEP_TARGETS install
    INSTALL_DIR "${REAVEROS_BINARY_DIR}/install/toolchain/archive"
    ${steps}
)
reaveros_file_dependency(hydration_dependency toolchain-archive-hydration-inputs
    "${TEST_REVISION}:${TEST_ARCHIVE_HASH}"
    "${REAVEROS_SOURCE_DIR}/toolchain/hydrate-git-archive")
_reaveros_add_ep_file_dependencies(toolchain-archive download ${hydration_dependency})
ExternalProject_Add_Step(toolchain-archive hydrate-source
    COMMAND bash "${REAVEROS_SOURCE_DIR}/toolchain/hydrate-git-archive"
        <SOURCE_DIR> "${TEST_REMOTE}" fixture "${TEST_REVISION}" <DOWNLOADED_FILE>
    DEPENDEES download update patch
    DEPENDERS configure
    DEPENDS ${hydration_dependency}
)
reaveros_add_ep_source_identity_step(toolchain-archive
    "${TEST_REVISION}:${TEST_ARCHIVE_HASH}" DEPENDEES hydrate-source)
reaveros_add_ep_prune_target(toolchain-archive
    SOURCE_STEP hydrate-source SOURCE_STEP_AFTER_PATCH REMOVE_DOWNLOADED_ARCHIVE)

ExternalProject_Add(toolchain-extract
    URL "${TEST_ARCHIVE}"
    URL_HASH "SHA256=${TEST_ARCHIVE_HASH}"
    UPDATE_DISCONNECTED TRUE
    STEP_TARGETS install
    INSTALL_DIR "${REAVEROS_BINARY_DIR}/install/toolchain/extract"
    ${steps}
)
reaveros_add_ep_source_identity_step(toolchain-extract "${TEST_ARCHIVE_HASH}"
    DEPENDEES download update patch)
reaveros_add_ep_prune_target(toolchain-extract SOURCE_STEP download)

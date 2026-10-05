reaveros_patch_dependency(_patch toolchain-example "${TEST_ARCHIVE_HASH}" "${TEST_PATCH_INPUT}")
ExternalProject_Add(toolchain-example
    URL "${TEST_ARCHIVE}" URL_HASH "SHA256=${TEST_ARCHIVE_HASH}"
    UPDATE_DISCONNECTED TRUE STEP_TARGETS install
    INSTALL_DIR "${CMAKE_BINARY_DIR}/install/toolchain/example"
    CMAKE_ARGS "-DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>" "-DTEST_VALUE=${TEST_VALUE}"
        "-DTEST_CONTROL=${CMAKE_BINARY_DIR}/control"
        "-DLLVM_PARALLEL_LINK_JOBS=${TEST_JOBS}"
)
ExternalProject_Add_Step(toolchain-example apply-patches
    COMMAND "${CMAKE_COMMAND}" -E true
    DEPENDEES patch DEPENDERS configure DEPENDS "${_patch}")
reaveros_add_ep_source_identity_step(toolchain-example "${TEST_ARCHIVE_HASH}"
    DEPENDEES download update patch)
reaveros_add_ep_prune_target(toolchain-example SOURCE_STEP download
    REQUIRED_INSTALLED_OUTPUTS bin/example)

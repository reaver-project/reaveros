set_directory_properties(
    PROPERTIES
        CLEAN_NO_CUSTOM 1
)

configure_file(targets.cmake "${REAVEROS_BINARY_DIR}/install/toolchain/files/targets.cmake" COPYONLY)
configure_file("${REAVEROS_SOURCE_DIR}/cmake/project_policy.cmake.in"
    "${REAVEROS_BINARY_DIR}/install/toolchain/files/project-policy.cmake" @ONLY)
configure_file("${REAVEROS_SOURCE_DIR}/cmake/linker_policy.cmake"
    "${REAVEROS_BINARY_DIR}/install/toolchain/files/linker-policy.cmake" COPYONLY)
configure_file("${REAVEROS_SOURCE_DIR}/cmake/native_tests.cmake"
    "${REAVEROS_BINARY_DIR}/install/toolchain/files/native-tests.cmake" COPYONLY)

file(GLOB toolchain_files
    RELATIVE ${CMAKE_CURRENT_SOURCE_DIR}/files
    CONFIGURE_DEPENDS
    ${CMAKE_CURRENT_SOURCE_DIR}/files/*.cmake.in
)

foreach (toolchain_file_in IN LISTS toolchain_files)
    string(REGEX
        REPLACE "\\.in$" ""
        toolchain_file
        ${toolchain_file_in}
    )

    configure_file(
        ${REAVEROS_SOURCE_DIR}/toolchain/files/${toolchain_file_in}
        ${REAVEROS_BINARY_DIR}/install/toolchain/files/${toolchain_file}
        @ONLY
    )
endforeach()

add_custom_target(all-toolchain-prune)

include(config.cmake)

include(cmake.cmake)
include(llvm.cmake)

if ("uefi" IN_LIST REAVEROS_LOADERS)
    include(fs-fat.cmake)
endif()

include(thorn.cmake)

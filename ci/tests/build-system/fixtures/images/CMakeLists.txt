cmake_minimum_required(VERSION 3.31)
project(image-rules-test NONE)

set(REAVEROS_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
set(REAVEROS_BINARY_DIR "${CMAKE_BINARY_DIR}")
set(REAVEROS_ARCHITECTURES amd64)
set(REAVEROS_LOADERS uefi)
include("${TEST_REPOSITORY}/cmake/aggregate_targets.cmake")

add_custom_target(all-amd64-userspace-services
    COMMAND "${CMAKE_COMMAND}" -E rm -rf "${CMAKE_BINARY_DIR}/install/userspace/services/amd64"
    COMMAND "${CMAKE_COMMAND}" -E copy_directory "${TEST_PAYLOAD}/services"
        "${CMAKE_BINARY_DIR}/install/userspace/services/amd64"
    COMMENT "Staging fixture services" VERBATIM)
foreach (_item IN ITEMS library-rosestd-hosted-amd64 loader-uefi-amd64 kernel-amd64)
    add_custom_target(${_item})
endforeach()
add_custom_target(toolchain-dosfstools-install)
add_custom_target(toolchain-mtools-install)
add_subdirectory("${TEST_REPOSITORY}/images" images)

# These are requests in one Make dependency graph, not separate root invocations.
add_custom_target(joint-images)
add_dependencies(joint-images image-initrd-amd64 image-uefi-efipart-amd64 all-images)

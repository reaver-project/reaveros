include("${CMAKE_CURRENT_LIST_DIR}/../cmake/host_tools.cmake")
reaveros_add_aggregate_targets(images)

# Reserved for a future root filesystem image; intentionally empty today.
include(rootfs.cmake)
include(initrd.cmake)
include(uefi.cmake)

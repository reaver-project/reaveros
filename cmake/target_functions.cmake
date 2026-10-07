# Compatibility entry point for existing superbuild and fixture callers.
include("${CMAKE_CURRENT_LIST_DIR}/../toolchain/targets.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/aggregate_targets.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/components.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/toolchain_lifecycle.cmake")

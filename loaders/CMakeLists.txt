reaveros_add_aggregate_targets(loaders)

if ("uefi" IN_LIST REAVEROS_LOADERS)
    reaveros_add_aggregate_targets(loaders-uefi)
endif()

foreach (loader IN LISTS REAVEROS_LOADERS)
    reaveros_include_component("${loader}" PREFIX loader TAGS loaders)
endforeach()

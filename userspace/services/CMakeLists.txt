reaveros_add_aggregate_targets(userspace-services)

set(services
    logger
)

foreach (service IN LISTS services)
    reaveros_include_component("${service}" PREFIX userspace-service TAGS userspace services)
endforeach()

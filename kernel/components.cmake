reaveros_include_component(kernel/vdso
    BINARY_ROOT "${REAVEROS_BINARY_DIR}/kernel"
)
reaveros_include_component(kernel/bootinit
    BINARY_ROOT "${REAVEROS_BINARY_DIR}/kernel"
)

foreach (_architecture IN LISTS REAVEROS_ARCHITECTURES)
    add_dependencies(kernel-interface-${_architecture} vdso-${_architecture})
    add_dependencies(kernel-bootinit-${_architecture} bootinit-${_architecture})
endforeach()

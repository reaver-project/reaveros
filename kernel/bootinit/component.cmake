set(REAVEROS_COMPONENT_ARCHITECTURES ${REAVEROS_ARCHITECTURES})
set(REAVEROS_COMPONENT_INSTALL_PATH [=[bootinit/${_architecture}]=])
set(REAVEROS_COMPONENT_MODES freestanding)
set(REAVEROS_COMPONENT_SKIP_MODE_NAME TRUE)
set(REAVEROS_COMPONENT_REGISTER_AGGREGATES FALSE)
set(REAVEROS_COMPONENT_DEPENDS
    [=[vdso-${_architecture}]=]
    [=[library-rosestd-freestanding-${_architecture}]=]
    [=[library-archive-freestanding-${_architecture}]=]
    [=[library-elf-freestanding-${_architecture}]=]
    [=[library-boot-protocol-freestanding-${_architecture}]=]
)
set(REAVEROS_COMPONENT_CMAKE_ARGS
    "-DREAVEROS_KERNEL_INTERFACE_ROOT:PATH=${REAVEROS_BINARY_DIR}/install/kernel-interface/\${_architecture}"
)

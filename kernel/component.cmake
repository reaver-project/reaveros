set(REAVEROS_COMPONENT_ARCHITECTURES ${REAVEROS_ARCHITECTURES})
set(REAVEROS_COMPONENT_INSTALL_PATH [=[kernels/${_architecture}]=])
set(REAVEROS_COMPONENT_MODES freestanding tests)
set(REAVEROS_COMPONENT_SKIP_MODE_NAME TRUE)
set(REAVEROS_COMPONENT_DEPENDS [=[all-${_architecture}-${_mode}-libraries]=])
set(REAVEROS_COMPONENT_DEPENDS_FREESTANDING
    [=[kernel-interface-${_architecture}]=]
    [=[kernel-bootinit-${_architecture}]=]
)
set(REAVEROS_COMPONENT_CMAKE_ARGS
    "-DREAVEROS_KERNEL_INTERFACE_ROOT:PATH=${REAVEROS_BINARY_DIR}/install/kernel-interface/\${_architecture}"
    "-DREAVEROS_KERNEL_VDSO_FILE:FILEPATH=${REAVEROS_BINARY_DIR}/install/sysroots/\${_architecture}-hosted/usr/lib/libvdso.so"
    "-DREAVEROS_BOOTINIT_FILE:FILEPATH=${REAVEROS_BINARY_DIR}/install/bootinit/\${_architecture}/bootinit"
)

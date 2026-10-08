set(REAVEROS_COMPONENT_ARCHITECTURES ${REAVEROS_ARCHITECTURES})
set(REAVEROS_COMPONENT_INSTALL_PATH [=[kernel-interface/${_architecture}]=])
set(REAVEROS_COMPONENT_MODES freestanding)
set(REAVEROS_COMPONENT_SKIP_MODE_NAME TRUE)
set(REAVEROS_COMPONENT_REGISTER_AGGREGATES FALSE)
set(REAVEROS_COMPONENT_DEPENDS
    toolchain-thorn-install
    [=[library-rosestd-freestanding-${_architecture}]=]
)
set(REAVEROS_COMPONENT_CMAKE_ARGS
    "-DREAVEROS_HOSTED_SYSROOT:PATH=${REAVEROS_BINARY_DIR}/install/sysroots/\${_architecture}-hosted"
)
set(REAVEROS_COMPONENT_INSTALL_TRANSFER_FROM [=[kernel-${_architecture}]=])
set(REAVEROS_COMPONENT_INSTALL_TRANSFER_ROOTS
    [=[sysroots/${_architecture}-hosted/usr/include/rose/syscall]=]
    [=[sysroots/${_architecture}-hosted/usr/lib/libvdso.so]=]
)

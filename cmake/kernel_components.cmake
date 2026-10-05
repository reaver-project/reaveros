# These producers have no native-test variant and join existing aggregates
# through their consumers. Their source directories and target flags stay local.
foreach (_architecture IN LISTS REAVEROS_ARCHITECTURES)
    set(_interface_root "${REAVEROS_BINARY_DIR}/install/kernel-interface/${_architecture}")
    set(_hosted_sysroot "${REAVEROS_BINARY_DIR}/install/sysroots/${_architecture}-hosted")
    reaveros_add_component(
        NAME vdso SOURCE_DIR "${REAVEROS_SOURCE_DIR}/kernel/vdso"
        BINARY_ROOT "${REAVEROS_BINARY_DIR}/kernel"
        ARCHITECTURES ${_architecture} MODES freestanding SKIP_MODE_NAME TRUE
        REGISTER_AGGREGATES FALSE INSTALL_PATH "kernel-interface/${_architecture}"
        DEPENDS toolchain-thorn-install library-rosestd-freestanding-${_architecture}
        CMAKE_ARGS "-DREAVEROS_HOSTED_SYSROOT:PATH=${_hosted_sysroot}"
        INSTALL_TRANSFER_FROM kernel-${_architecture}
        INSTALL_TRANSFER_ROOTS
            "sysroots/${_architecture}-hosted/usr/include/rose/syscall"
            "sysroots/${_architecture}-hosted/usr/lib/libvdso.so"
    )
    add_dependencies(kernel-interface-${_architecture} vdso-${_architecture})

    reaveros_add_component(
        NAME bootinit SOURCE_DIR "${REAVEROS_SOURCE_DIR}/kernel/bootinit"
        BINARY_ROOT "${REAVEROS_BINARY_DIR}/kernel"
        ARCHITECTURES ${_architecture} MODES freestanding SKIP_MODE_NAME TRUE
        REGISTER_AGGREGATES FALSE INSTALL_PATH "bootinit/${_architecture}"
        DEPENDS vdso-${_architecture}
            library-rosestd-freestanding-${_architecture}
            library-archive-freestanding-${_architecture}
            library-elf-freestanding-${_architecture}
            library-boot-protocol-freestanding-${_architecture}
        CMAKE_ARGS "-DREAVEROS_KERNEL_INTERFACE_ROOT:PATH=${_interface_root}"
    )
    add_dependencies(kernel-bootinit-${_architecture} bootinit-${_architecture})
endforeach()

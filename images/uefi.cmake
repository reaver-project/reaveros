function(_reaveros_add_uefi_image_target architecture)
    reaveros_require_host_tools("UEFI FAT images" fallocate)
    reaveros_require_host_python()
    set(_targetfs_contents "${REAVEROS_BINARY_DIR}/images/mount/uefi-efipart-${architecture}")
    set(_targetfs_path "${REAVEROS_BINARY_DIR}/install/images/uefi-efipart-${architecture}.img")
    set(_temporary_path "${_targetfs_path}.tmp")
    file(RELATIVE_PATH _temporary_relative "${_targetfs_contents}" "${_temporary_path}")

    # Preserve the existing floppy-sized FAT layout; these are internal geometry
    # constants, not configuration options. Validate usable capacity after mkfs.
    set(_sector_size 512)
    set(_image_sectors 2880)
    math(EXPR _image_size "${_sector_size} * ${_image_sectors}")

    # One always-run producer owns this staging tree and publishes only a
    # successfully populated filesystem. A failed attempt leaves the last image.
    add_custom_target(image-uefi-efipart-${architecture}
        COMMAND "${CMAKE_COMMAND}" -E rm -rf "${_targetfs_contents}"
        COMMAND "${CMAKE_COMMAND}" -E make_directory
            "${_targetfs_contents}/EFI/BOOT" "${_targetfs_contents}/reaver"
            "${REAVEROS_BINARY_DIR}/install/images"
        COMMAND "${CMAKE_COMMAND}" -E copy
            "${REAVEROS_BINARY_DIR}/install/loaders/uefi-${architecture}/loader-uefi"
            "${_targetfs_contents}/EFI/BOOT/BOOTX64.EFI"
        COMMAND "${CMAKE_COMMAND}" -E copy
            "${REAVEROS_SOURCE_DIR}/loaders/uefi/config/reaveros.conf"
            "${_targetfs_contents}/EFI/BOOT/reaveros.conf"

        COMMAND "${CMAKE_COMMAND}" -E copy
            "${REAVEROS_BINARY_DIR}/install/kernels/${architecture}/kernel"
            "${_targetfs_contents}/reaver/kernel.img"
        COMMAND "${CMAKE_COMMAND}" -E copy
            "${REAVEROS_BINARY_DIR}/install/images/initrd-${architecture}.img"
            "${_targetfs_contents}/reaver/initrd.img"

        COMMAND "${CMAKE_COMMAND}" -E rm -f "${_temporary_path}"
        COMMAND "${REAVEROS_HOST_FALLOCATE}" -l "${_image_size}" "${_temporary_path}"
        COMMAND "${REAVEROS_BINARY_DIR}/install/toolchain/dosfstools/sbin/mkfs.fat" "${_temporary_path}"
        COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/check-fat-capacity"
            "${_temporary_path}" "${_targetfs_contents}" "${_image_size}" "${_sector_size}"
        # mtools expands the -i argument itself. Relative layout paths avoid
        # interpreting quotes/dollars in the build root as expansion syntax.
        COMMAND "${CMAKE_COMMAND}" -E chdir "${_targetfs_contents}"
            "${REAVEROS_BINARY_DIR}/install/toolchain/mtools/bin/mcopy"
            -os -i "${_temporary_relative}" EFI reaver ::/
        COMMAND "${CMAKE_COMMAND}" -E rename "${_temporary_path}" "${_targetfs_path}"
        BYPRODUCTS "${_targetfs_path}"
        WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
        COMMENT "Packaging UEFI filesystem for ${architecture}"
        VERBATIM
    )
    add_dependencies(image-uefi-efipart-${architecture}
        toolchain-dosfstools-install toolchain-mtools-install
        loader-uefi-${architecture} kernel-${architecture} image-initrd-${architecture})

    reaveros_register_target(image-uefi-efipart-${architecture} ${architecture} images uefi-efipart)
endfunction()

if ("amd64" IN_LIST REAVEROS_ARCHITECTURES AND "uefi" IN_LIST REAVEROS_LOADERS)
    reaveros_add_aggregate_targets(images-uefi-efipart)

    _reaveros_add_uefi_image_target(amd64)
endif()

function(_reaveros_add_initrd_image_target architecture)
    reaveros_require_host_tools("Initrd images" bash find cpio)
    set(_working_path "${REAVEROS_BINARY_DIR}/images/initrd-${architecture}")
    set(_target_dir "${REAVEROS_BINARY_DIR}/install/images")
    set(_target_path "${_target_dir}/initrd-${architecture}.img")

    # Packaging intentionally runs on every request. The image is a byproduct
    # of this single producer, rather than an output with a fictitious sibling.
    add_custom_target(image-initrd-${architecture}
        COMMAND "${CMAKE_COMMAND}" -E rm -rf "${_working_path}"
        COMMAND "${CMAKE_COMMAND}" -E make_directory "${_working_path}" "${_target_dir}"
        COMMAND "${CMAKE_COMMAND}" -E copy_directory
            "${REAVEROS_BINARY_DIR}/install/userspace/services/${architecture}" "${_working_path}"
        COMMAND "${CMAKE_COMMAND}" -E copy
            "${REAVEROS_BINARY_DIR}/install/sysroots/${architecture}-hosted/usr/lib/librosestd.so" "${_working_path}"
        COMMAND "${CMAKE_COMMAND}" -E chdir "${_working_path}"
            "${REAVEROS_HOST_BASH}" "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/create-initrd"
            "${_target_path}" "${REAVEROS_HOST_FIND}" "${REAVEROS_HOST_CPIO}"
        BYPRODUCTS "${_target_path}"
        WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
        COMMENT "Packaging initrd for ${architecture}"
        VERBATIM
    )
    add_dependencies(image-initrd-${architecture}
        all-${architecture}-userspace-services library-rosestd-hosted-${architecture})

    reaveros_register_target(image-initrd-${architecture} ${architecture} images initrd)
endfunction()

reaveros_add_aggregate_targets(images-initrd)

foreach (architecture IN LISTS REAVEROS_ARCHITECTURES)
    _reaveros_add_initrd_image_target(${architecture})
endforeach()

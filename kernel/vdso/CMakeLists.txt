cmake_minimum_required(VERSION 3.31)
project(reaveros-kernel-interface CXX)

if (NOT IS_ABSOLUTE "${REAVEROS_HOSTED_SYSROOT}")
    message(FATAL_ERROR "The superbuild must provide REAVEROS_HOSTED_SYSROOT.")
endif()

file(GLOB thorn_files
    CONFIGURE_DEPENDS
    *.thorn
)

set(_thorn_user_files "${CMAKE_CURRENT_BINARY_DIR}/thorn/user/types.h")
set(_thorn_vdso_files)
set(_thorn_kernel_files "${CMAKE_CURRENT_BINARY_DIR}/thorn/kernel/meta.h")
set(_kernel_sources "")

foreach (abs_thorn_file IN LISTS thorn_files)
    file(RELATIVE_PATH thorn_file "${CMAKE_CURRENT_SOURCE_DIR}" "${abs_thorn_file}")
    string(REGEX REPLACE "\\.[^.]*$" "" base "${thorn_file}")

    list(APPEND _thorn_user_files "${CMAKE_CURRENT_BINARY_DIR}/thorn/user/${base}.h")
    list(APPEND _thorn_vdso_files "${CMAKE_CURRENT_BINARY_DIR}/thorn/vdso/${base}.cpp")
    list(APPEND _thorn_kernel_files "${CMAKE_CURRENT_BINARY_DIR}/thorn/kernel/${base}.cpp")
    list(APPEND _kernel_sources "generated/kernel/${base}.cpp")
endforeach()

add_custom_command(
    OUTPUT
        ${_thorn_user_files}
        ${_thorn_vdso_files}
        ${_thorn_kernel_files}

    COMMENT "Compiling syscall definitions from thorn files..."
    COMMAND "${REAVEROS_THORN}" -i "${CMAKE_CURRENT_SOURCE_DIR}" -o "${CMAKE_CURRENT_BINARY_DIR}/thorn" -s "rose::syscall" -a ${REAVEROS_ARCH}
    DEPENDS ${REAVEROS_THORN} ${thorn_files}
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    VERBATIM
)
add_custom_target(thorn-generation
    DEPENDS
        ${_thorn_user_files}
        ${_thorn_vdso_files}
        ${_thorn_kernel_files}
)

set_source_files_properties(
    FILES
        ${_thorn_user_files}
        ${_thorn_vdso_files}
        ${_thorn_kernel_files}
    PROPERTIES
        GENERATED TRUE
)

add_library(vdso SHARED
    ${_thorn_vdso_files}
)
add_dependencies(vdso thorn-generation)
target_include_directories(vdso PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/thorn")

target_link_options(vdso PRIVATE LINKER:-z,separate-loadable-segments)
reaveros_require_linker_dependencies(vdso CXX)

install(FILES ${_thorn_user_files}
    DESTINATION "${REAVEROS_HOSTED_SYSROOT}/usr/include/rose/syscall"
)

install(TARGETS vdso
    DESTINATION "${REAVEROS_HOSTED_SYSROOT}/usr/lib"
)

# Keep the generated kernel/user sibling layout required by Thorn's includes.
install(FILES ${_thorn_user_files} DESTINATION generated/user)
install(FILES ${_thorn_kernel_files} DESTINATION generated/kernel)
string(JOIN "\n" _kernel_sources ${_kernel_sources})
file(GENERATE OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/kernel-sources.txt"
    CONTENT "${_kernel_sources}\n")
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/kernel-sources.txt" DESTINATION .)

set(vdso_symbols_file "${CMAKE_CURRENT_BINARY_DIR}/vdso_symbols.lds")

add_custom_command(OUTPUT ${vdso_symbols_file}
    COMMAND bash -o pipefail -c
        "\"$1\" --dyn-syms \"$2\" | tail -n+4 | grep 'FUNC' | grep -v __rose_syscall | awk '{ printf \"%s = __vdso_base + 0x%s;\\n\", $8, $2; }' > \"$3\""
        bash "${CMAKE_READELF}" "$<TARGET_FILE:vdso>" "${vdso_symbols_file}"
    DEPENDS vdso
    VERBATIM
)

add_custom_target(vdso_symbols DEPENDS ${vdso_symbols_file})
add_custom_target(interface-artifacts ALL DEPENDS thorn-generation vdso_symbols)
install(FILES "${vdso_symbols_file}" DESTINATION .)

set(vdso_offsets_file "${CMAKE_CURRENT_BINARY_DIR}/vdso_offsets.lds")

add_custom_command(OUTPUT ${vdso_offsets_file}
    COMMAND bash -o pipefail -c
        "\"$1\" --dyn-syms \"$2\" | tail -n+4 | grep __rose_syscall | awk '{ printf \"%s = __vdso_base + 0x%s;\\n\", $8, $2; }' > \"$3\""
        bash "${CMAKE_READELF}" "$<TARGET_FILE:vdso>" "${vdso_offsets_file}"
    DEPENDS vdso
    VERBATIM
)

add_custom_target(vdso_offsets DEPENDS ${vdso_offsets_file})

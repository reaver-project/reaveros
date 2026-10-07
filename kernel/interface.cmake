foreach (_artifact
        "${REAVEROS_KERNEL_INTERFACE_ROOT}/kernel-sources.txt"
        "${REAVEROS_KERNEL_INTERFACE_ROOT}/vdso_symbols.lds"
        "${REAVEROS_KERNEL_VDSO_FILE}"
        "${REAVEROS_BOOTINIT_FILE}")
    if (NOT EXISTS "${_artifact}")
        message(FATAL_ERROR "The superbuild must install the kernel prerequisite '${_artifact}'.")
    endif()
endforeach()

set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    "${REAVEROS_KERNEL_INTERFACE_ROOT}/kernel-sources.txt")
file(STRINGS "${REAVEROS_KERNEL_INTERFACE_ROOT}/kernel-sources.txt" _syscall_sources)
list(TRANSFORM _syscall_sources PREPEND "${REAVEROS_KERNEL_INTERFACE_ROOT}/")
include_directories("${REAVEROS_KERNEL_INTERFACE_ROOT}/generated")
set(vdso_symbols_file "${REAVEROS_KERNEL_INTERFACE_ROOT}/vdso_symbols.lds")

add_library(syscall_table STATIC ${_syscall_sources})
target_include_directories(syscall_table PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_options(syscall_table PRIVATE -g -mcmodel=kernel)

file(CONFIGURE OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/incbin_vdso.asm" CONTENT [=[
    .section .vdso
    .globl begin_vdso
    .globl end_vdso
    begin_vdso:
    .incbin "@REAVEROS_KERNEL_VDSO_FILE@"
    end_vdso:
]=] @ONLY)
add_library(vdso-incbin STATIC "${CMAKE_CURRENT_BINARY_DIR}/incbin_vdso.asm")
set_source_files_properties("${CMAKE_CURRENT_BINARY_DIR}/incbin_vdso.asm"
    PROPERTIES OBJECT_DEPENDS "${REAVEROS_KERNEL_VDSO_FILE}")

file(CONFIGURE OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/incbin_bootinit.asm" CONTENT [=[
    .section .bootinit
    .globl begin_bootinit
    .globl end_bootinit
    begin_bootinit:
    .incbin "@REAVEROS_BOOTINIT_FILE@"
    end_bootinit:
]=] @ONLY)
add_library(bootinit-incbin STATIC "${CMAKE_CURRENT_BINARY_DIR}/incbin_bootinit.asm")
set_source_files_properties("${CMAKE_CURRENT_BINARY_DIR}/incbin_bootinit.asm"
    PROPERTIES OBJECT_DEPENDS "${REAVEROS_BOOTINIT_FILE}")

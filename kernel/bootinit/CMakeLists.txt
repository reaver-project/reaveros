cmake_minimum_required(VERSION 3.31)
project(reaveros-bootinit CXX)

if (NOT EXISTS "${REAVEROS_KERNEL_INTERFACE_ROOT}/generated/user/meta.h")
    message(FATAL_ERROR "The superbuild must install the syscall interface before bootinit.")
endif()
set(vdso_symbols_file "${REAVEROS_KERNEL_INTERFACE_ROOT}/vdso_symbols.lds")

add_executable(bootinit-elf
    main.cpp
    print.cpp
    process.cpp
)
target_include_directories(bootinit-elf PRIVATE "${REAVEROS_KERNEL_INTERFACE_ROOT}/generated")

target_link_libraries(bootinit-elf
    PRIVATE
    "${CMAKE_SYSROOT}/usr/lib/librosestd.a"
    "${CMAKE_SYSROOT}/usr/lib/libarchive.a"
    "${CMAKE_SYSROOT}/usr/lib/libelf.a"
)

set(linker_script_in ${CMAKE_CURRENT_SOURCE_DIR}/bootinit.lds.in)
set(linker_script ${CMAKE_CURRENT_BINARY_DIR}/bootinit.lds)

configure_file(${linker_script_in} ${linker_script} @ONLY)

target_compile_definitions(bootinit-elf PRIVATE REAVEROS_BOOTINIT_PRINT_IN_TREE)
target_compile_options(bootinit-elf PRIVATE -g -Wno-infinite-recursion)
target_link_options(bootinit-elf PRIVATE
    "LINKER:-T,${linker_script}" LINKER:-Map,bootinit.map -static -ffreestanding)
set_property(TARGET bootinit-elf PROPERTY LINK_DEPENDS "${linker_script}" "${vdso_symbols_file}")
reaveros_require_linker_dependencies(bootinit-elf CXX)

add_custom_command(OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/bootinit
    DEPENDS bootinit-elf

    COMMAND
        ${CMAKE_OBJCOPY} -O binary $<TARGET_FILE:bootinit-elf> ${CMAKE_CURRENT_BINARY_DIR}/bootinit
            --set-section-flags .data=alloc,load,contents
    VERBATIM
)

add_custom_target(bootinit-flat ALL DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/bootinit")
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/bootinit" DESTINATION .)

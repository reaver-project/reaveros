add_executable(bootinit-elf
    main.cpp
    print.cpp
    process.cpp
)

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
set_property(TARGET bootinit-elf PROPERTY LINK_DEPENDS "${linker_script}")
reaveros_require_linker_dependencies(bootinit-elf CXX)

add_dependencies(bootinit-elf
    vdso_symbols
)

add_custom_command(OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/bootinit
    DEPENDS bootinit-elf

    COMMAND
        ${CMAKE_OBJCOPY} -O binary $<TARGET_FILE:bootinit-elf> ${CMAKE_CURRENT_BINARY_DIR}/bootinit
            --set-section-flags .data=alloc,load,contents
    VERBATIM
)

file(CONFIGURE OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/incbin_bootinit.asm" CONTENT
    "
    .section .bootinit
    .globl begin_bootinit
    .globl end_bootinit
    begin_bootinit:
    .incbin \"${CMAKE_CURRENT_BINARY_DIR}/bootinit\"
    end_bootinit:
    "
    @ONLY
)

add_library(bootinit-incbin STATIC
    ${CMAKE_CURRENT_BINARY_DIR}/incbin_bootinit.asm
)

set_source_files_properties(
    ${CMAKE_CURRENT_BINARY_DIR}/incbin_bootinit.asm
    PROPERTIES
        OBJECT_DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/bootinit
)

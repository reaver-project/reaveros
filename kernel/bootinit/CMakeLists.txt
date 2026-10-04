add_definitions(
    -DREAVEROS_BOOTINIT_PRINT_IN_TREE
)

add_executable(bootinit-elf
    main.cpp
    print.cpp
    process.cpp
)

target_link_libraries(bootinit-elf
    ${CMAKE_SYSROOT}/usr/lib/librosestd.a
    ${CMAKE_SYSROOT}/usr/lib/libarchive.a
    ${CMAKE_SYSROOT}/usr/lib/libelf.a
)

set(linker_script_in ${CMAKE_CURRENT_SOURCE_DIR}/bootinit.lds.in)
set(linker_script ${CMAKE_CURRENT_BINARY_DIR}/bootinit.lds)

configure_file(${linker_script_in} ${linker_script} @ONLY)

set_target_properties(bootinit-elf
    PROPERTIES
        COMPILE_FLAGS "-g -Wno-infinite-recursion"
        LINK_FLAGS "-Wl,-T,'${linker_script}' -static -Wl,-Map=bootinit.map -ffreestanding"
        LINK_DEPENDS ${linker_script}
)

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

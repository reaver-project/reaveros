cmake_minimum_required(VERSION 3.31)
project(reaveros-kernel ASM CXX)

if (NOT REAVEROS_ENABLE_UNIT_TESTS)
    include(interface.cmake)

    file(GLOB_RECURSE sources
        CONFIGURE_DEPENDS
        boot/*.cpp
        memory/*.cpp
        time/*.cpp
        scheduler/*.cpp
        util/*.cpp
    )

    file(GLOB_RECURSE current_arch_sources
        CONFIGURE_DEPENDS
        arch/common/*.cpp
        arch/${REAVEROS_ARCH}/*.cpp
        arch/${REAVEROS_ARCH}/*.asm
    )

    add_executable(kernel-elf
        main.cpp
        ${sources}
        ${current_arch_sources}
    )

    target_link_libraries(kernel-elf
        PRIVATE
        bootinit-incbin
        vdso-incbin
        syscall_table
        rosestd
        clang_rt.builtins
    )

    set(linker_script_in ${CMAKE_CURRENT_SOURCE_DIR}/arch/${REAVEROS_ARCH}/kernel.lds.in)
    set(linker_script ${CMAKE_CURRENT_BINARY_DIR}/kernel.lds)

    configure_file(${linker_script_in} ${linker_script} @ONLY)

    target_compile_options(kernel-elf PRIVATE -g -mcmodel=kernel)
    target_compile_definitions(kernel-elf PRIVATE
        "$<$<COMPILE_LANGUAGE:CXX>:REAVEROS_KERNEL_SOURCE_ROOT=\"${CMAKE_SOURCE_DIR}\">")
    target_link_options(kernel-elf PRIVATE
        "LINKER:-T,${linker_script}" LINKER:-Map,kernel.map -static -ffreestanding)
    set_property(TARGET kernel-elf PROPERTY LINK_DEPENDS "${linker_script}" "${vdso_symbols_file}")
    reaveros_require_linker_dependencies(kernel-elf CXX)

    add_custom_command(OUTPUT ${CMAKE_BINARY_DIR}/kernel
        DEPENDS kernel-elf

        COMMAND
            ${CMAKE_OBJCOPY} -O binary $<TARGET_FILE:kernel-elf> ${CMAKE_BINARY_DIR}/kernel
                --set-section-flags .data=alloc,load,contents
        VERBATIM
    )

    add_custom_target(kernel-flat ALL DEPENDS ${CMAKE_BINARY_DIR}/kernel)

    install(FILES ${CMAKE_BINARY_DIR}/kernel
        DESTINATION .
    )
else()
    enable_testing()

    add_subdirectory(test)

    install(FILES)
endif()

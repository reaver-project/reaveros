cmake_minimum_required(VERSION 3.31)
project(reaveros-loader-uefi ASM CXX)

file(GLOB_RECURSE sources
    CONFIGURE_DEPENDS
    *.cpp
)

file(GLOB asm_sources
    CONFIGURE_DEPENDS
    *.asm
    cpu/${REAVEROS_ARCH}/*.asm
)

set_source_files_properties(
    ${asm_sources}
    PROPERTIES
        LANGUAGE ASM
        COMPILE_FLAGS -integrated-as
)

add_executable(loader-uefi
    ${asm_sources}
    ${sources}
)

target_link_libraries(loader-uefi
    ${CMAKE_SYSROOT}/usr/lib/librosestd.a
)

set_target_properties(loader-uefi
    PROPERTIES
        LINKER_LANGUAGE CXX
)

add_custom_target(loader-uefi-pe ALL DEPENDS ${CMAKE_BINARY_DIR}/loader-uefi)

install(FILES ${CMAKE_BINARY_DIR}/loader-uefi
    DESTINATION ${CMAKE_INSTALL_PREFIX}
)

if (REAVEROS_ENABLE_UNIT_TESTS)
    add_custom_target(build-tests)
endif()

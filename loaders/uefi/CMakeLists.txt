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

add_executable(loader-uefi
    ${asm_sources}
    ${sources}
)
target_compile_options(loader-uefi PRIVATE "$<$<COMPILE_LANGUAGE:ASM>:-integrated-as>")

target_link_libraries(loader-uefi
    PRIVATE "${CMAKE_SYSROOT}/usr/lib/librosestd.a"
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

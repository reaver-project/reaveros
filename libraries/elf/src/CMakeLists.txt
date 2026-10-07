file(GLOB sources CONFIGURE_DEPENDS *.cpp)

if (REAVEROS_IS_FREESTANDING)
    set(_library_type STATIC)
else()
    set(_library_type SHARED)
endif()

add_library(elf ${_library_type}
    ${sources}
)
target_compile_options(elf PRIVATE -g)
if (_library_type STREQUAL "SHARED")
    reaveros_require_linker_dependencies(elf CXX)
endif()

install(TARGETS elf
    DESTINATION usr/lib
)
